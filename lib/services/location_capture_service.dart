import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import 'location_accuracy_settings.dart';

class PreciseLocationConfig {
  final double maxAcceptedAccuracyMeters;
  final double acceptableSaveAccuracyMeters;
  final double targetAccuracyMeters;
  final int minSamples;
  final int maxBestPointsUsed;
  final Duration requestTimeout;
  final Duration requestInterval;
  final Duration maxSessionDuration;
  final bool autoStopWhenTargetReached;

  /// Пространственный антискачок: после формирования кластера
  /// новая точка отклоняется, если она слишком далеко от основной группы
  /// даже если сама заявляет хорошую accuracy
  final bool rejectSpatialOutliers;

  /// Сколько уже принятых точек нужно накопить до включения антискачка.
  final int minSamplesBeforeSpatialFilter;

  /// допустимый радиус кластера для антискачка.
  final double minSpatialJumpMeters;

  /// допустимый радиус кластера для антискачка.
  final double maxSpatialJumpMeters;

  const PreciseLocationConfig({
    this.maxAcceptedAccuracyMeters = 60,
    this.acceptableSaveAccuracyMeters = LocationAccuracySettings.defaultTargetAccuracyMeters,
    this.targetAccuracyMeters = LocationAccuracySettings.defaultTargetAccuracyMeters,
    this.minSamples = 3,
    this.maxBestPointsUsed = 6,
    this.requestTimeout = const Duration(seconds: 3),
    this.requestInterval = const Duration(milliseconds: 600),
    this.maxSessionDuration = const Duration(seconds: 70),
    this.autoStopWhenTargetReached = true,
    this.rejectSpatialOutliers = true,
    this.minSamplesBeforeSpatialFilter = 4,
    this.minSpatialJumpMeters = 20,
    this.maxSpatialJumpMeters = 55,
  });
}

class PreciseLocationProgress {
  final double? latitude;
  final double? longitude;

  /// консервативная оценка итоговой точности агрегированной точки
  final double? accuracy;

  /// лучшая одиночная точка среди принятых.
  final double? bestSampleAccuracy;

  /// всего принятых точек.
  final int sampleCount;

  /// сколько лучших точек использовано в итоговом расчёте.
  final int usedSampleCount;

  /// сколько точек было отклонено пространственным антискачком.
  final int rejectedSpatialOutlierCount;

  /// Последнее расстояние отклонённой точки от текущего кластера.
  final double? lastRejectedSpatialDistanceMeters;

  final bool isUsable;
  final bool isTargetReached;
  final bool isRunning;
  final String message;

  const PreciseLocationProgress({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.bestSampleAccuracy,
    required this.sampleCount,
    required this.usedSampleCount,
    this.rejectedSpatialOutlierCount = 0,
    this.lastRejectedSpatialDistanceMeters,
    required this.isUsable,
    required this.isTargetReached,
    required this.isRunning,
    required this.message,
  });
}

class LocationCaptureException implements Exception {
  final String message;

  const LocationCaptureException(this.message);

  @override
  String toString() => message;
}

class LocationCaptureService {
  final StreamController<PreciseLocationProgress> _controller =
  StreamController<PreciseLocationProgress>.broadcast();

  final List<Position> _accepted = [];
  int _rejectedSpatialOutlierCount = 0;
  double? _lastRejectedSpatialDistanceMeters;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _sessionTimer;
  Timer? _statusTimer;

  bool _isRunning = false;
  bool _stopRequested = false;
  bool _disposed = false;

  DateTime? _lastAnyPositionAt;
  DateTime? _lastAcceptedAt;

  PreciseLocationProgress? _latestProgress;
  PreciseLocationConfig _activeConfig = const PreciseLocationConfig();

  Stream<PreciseLocationProgress> get progressStream => _controller.stream;
  bool get isRunning => _isRunning;
  PreciseLocationProgress? get latestProgress => _latestProgress;

  Future<PreciseLocationConfig> _configFromUserSettings() async {
    final targetAccuracy =
    await LocationAccuracySettings.loadTargetAccuracyMeters();

    final maxAcceptedAccuracy =
    math.max(30.0, targetAccuracy * 3.0).clamp(30.0, 90.0).toDouble();

    final minSamples = targetAccuracy <= 7
        ? 6
        : targetAccuracy <= 15
        ? 4
        : 3;

    final maxBestPointsUsed = targetAccuracy <= 7
        ? 10
        : targetAccuracy <= 15
        ? 8
        : 6;

    final maxSessionDuration = targetAccuracy <= 7
        ? const Duration(seconds: 180)
        : targetAccuracy <= 15
        ? const Duration(seconds: 120)
        : const Duration(seconds: 80);

    return PreciseLocationConfig(
      maxAcceptedAccuracyMeters: maxAcceptedAccuracy,
      acceptableSaveAccuracyMeters: targetAccuracy,
      targetAccuracyMeters: targetAccuracy,
      minSamples: minSamples,
      maxBestPointsUsed: maxBestPointsUsed,
      requestTimeout: const Duration(seconds: 3),
      requestInterval: const Duration(milliseconds: 600),
      maxSessionDuration: maxSessionDuration,
      autoStopWhenTargetReached: true,
      rejectSpatialOutliers: true,
      minSamplesBeforeSpatialFilter: minSamples,
      minSpatialJumpMeters: 20,
      maxSpatialJumpMeters: targetAccuracy <= 7 ? 35 : 55,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _stopRequested = true;
    _isRunning = false;
    _sessionTimer?.cancel();
    _statusTimer?.cancel();
    await _positionSubscription?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationCaptureException('Включите геолокацию');
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationCaptureException('Нет разрешения на геолокацию');
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationCaptureException(
        'Доступ к геолокации запрещён навсегда. Откройте настройки приложения.',
      );
    }

    final accuracyStatus = await Geolocator.getLocationAccuracy();
    if (accuracyStatus == LocationAccuracyStatus.reduced) {
      throw const LocationCaptureException(
        'На устройстве включена приблизительная геолокация. Включите точную геопозицию.',
      );
    }
  }

  void clearProgress() {
    _accepted.clear();
    _rejectedSpatialOutlierCount = 0;
    _lastRejectedSpatialDistanceMeters = null;
    _latestProgress = null;
    _lastAnyPositionAt = null;
    _lastAcceptedAt = null;
  }

  bool _isAccepted(Position p, PreciseLocationConfig config) {
    return p.accuracy > 0 && p.accuracy <= config.maxAcceptedAccuracyMeters;
  }


  ({double latitude, double longitude}) _weightedCenterOfBestPoints(
      List<Position> samples,
      PreciseLocationConfig config,
      ) {
    final sorted = [...samples]..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final bestPoints = sorted.take(config.maxBestPointsUsed).toList();

    double weightedLat = 0;
    double weightedLon = 0;
    double totalWeight = 0;

    for (final sample in bestPoints) {
      final sigma = sample.accuracy <= 0 ? 1.0 : sample.accuracy;
      final weight = 1 / (sigma * sigma);
      weightedLat += sample.latitude * weight;
      weightedLon += sample.longitude * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) {
      return (
      latitude: bestPoints.first.latitude,
      longitude: bestPoints.first.longitude,
      );
    }

    return (
    latitude: weightedLat / totalWeight,
    longitude: weightedLon / totalWeight,
    );
  }

  double _allowedSpatialJumpMeters(
      Position candidate,
      PreciseLocationConfig config,
      ) {
    final byTarget = config.targetAccuracyMeters * 1.8;
    final byCandidateAccuracy = candidate.accuracy * 2.4;

    return math.max(
      config.minSpatialJumpMeters,
      math.max(byTarget, byCandidateAccuracy),
    ).clamp(
      config.minSpatialJumpMeters,
      config.maxSpatialJumpMeters,
    ).toDouble();
  }

  bool _isSpatialOutlier(
      Position candidate,
      PreciseLocationConfig config,
      ) {
    if (!config.rejectSpatialOutliers) return false;
    if (_accepted.length < config.minSamplesBeforeSpatialFilter) return false;

    final center = _weightedCenterOfBestPoints(_accepted, config);
    final distance = _distanceMeters(
      lat1: center.latitude,
      lon1: center.longitude,
      lat2: candidate.latitude,
      lon2: candidate.longitude,
    );

    final allowed = _allowedSpatialJumpMeters(candidate, config);

    if (distance <= allowed) return false;

    _rejectedSpatialOutlierCount++;
    _lastRejectedSpatialDistanceMeters = distance;
    return true;
  }

  bool _isFresh(
      Position position, {
        Duration maxAge = const Duration(minutes: 3),
      }) {
    final age = DateTime.now().difference(position.timestamp);
    return !age.isNegative && age <= maxAge;
  }

  LocationSettings _buildLocationSettings(PreciseLocationConfig config) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: config.requestInterval,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  void _emit(PreciseLocationProgress progress) {
    _latestProgress = progress;
    if (!_controller.isClosed) {
      _controller.add(progress);
    }
  }

  double _distanceMeters({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const earthRadius = 6371000.0;
    final lat1Rad = lat1 * math.pi / 180.0;
    final lat2Rad = lat2 * math.pi / 180.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;

    final x = dLon * math.cos((lat1Rad + lat2Rad) / 2.0);
    final y = dLat;
    return math.sqrt((x * x) + (y * y)) * earthRadius;
  }

  PreciseLocationProgress _buildProgress({
    required PreciseLocationConfig config,
    required bool isRunning,
    String? messageOverride,
  }) {
    if (_accepted.isEmpty) {
      return PreciseLocationProgress(
        latitude: null,
        longitude: null,
        accuracy: null,
        bestSampleAccuracy: null,
        sampleCount: 0,
        usedSampleCount: 0,
        rejectedSpatialOutlierCount: _rejectedSpatialOutlierCount,
        lastRejectedSpatialDistanceMeters: _lastRejectedSpatialDistanceMeters,
        isUsable: false,
        isTargetReached: false,
        isRunning: isRunning,
        message: messageOverride ?? 'Ожидание пригодных точек...',
      );
    }

    final sorted = [..._accepted]..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final bestPoints = sorted.take(config.maxBestPointsUsed).toList();

    double weightedLat = 0;
    double weightedLon = 0;
    double totalWeight = 0;

    for (final sample in bestPoints) {
      final sigma = sample.accuracy <= 0 ? 1.0 : sample.accuracy;
      final variance = sigma * sigma;
      final weight = 1 / variance;

      weightedLat += sample.latitude * weight;
      weightedLon += sample.longitude * weight;
      totalWeight += weight;
    }

    final finalLat = weightedLat / totalWeight;
    final finalLon = weightedLon / totalWeight;
    final bestAccuracy = bestPoints.first.accuracy;

    final estimatedByWeights = math.sqrt(1 / totalWeight);

    double weightedDistanceSq = 0;
    for (final sample in bestPoints) {
      final sigma = sample.accuracy <= 0 ? 1.0 : sample.accuracy;
      final weight = 1 / (sigma * sigma);
      final distance = _distanceMeters(
        lat1: finalLat,
        lon1: finalLon,
        lat2: sample.latitude,
        lon2: sample.longitude,
      );
      weightedDistanceSq += weight * distance * distance;
    }

    final clusterRms = math.sqrt(weightedDistanceSq / totalWeight);

    final conservativeFloor = math.max(bestAccuracy * 0.7, 3.0);
    final estimatedAccuracy = [
      estimatedByWeights,
      clusterRms,
      conservativeFloor,
    ].reduce(math.max);

    final isUsable = _accepted.length >= config.minSamples &&
        estimatedAccuracy <= config.acceptableSaveAccuracyMeters;

    final isTargetReached = _accepted.length >= config.minSamples &&
        estimatedAccuracy <= config.targetAccuracyMeters;

    return PreciseLocationProgress(
      latitude: finalLat,
      longitude: finalLon,
      accuracy: estimatedAccuracy,
      bestSampleAccuracy: bestAccuracy,
      sampleCount: _accepted.length,
      usedSampleCount: bestPoints.length,
      rejectedSpatialOutlierCount: _rejectedSpatialOutlierCount,
      lastRejectedSpatialDistanceMeters: _lastRejectedSpatialDistanceMeters,
      isUsable: isUsable,
      isTargetReached: isTargetReached,
      isRunning: isRunning,
      message: messageOverride ??
          'Принято ${_accepted.length} точек, в расчёте ${bestPoints.length}. '
              'Итоговая ±${estimatedAccuracy.toStringAsFixed(1)} м, '
              'лучшая одиночная ±${bestAccuracy.toStringAsFixed(1)} м',
    );
  }

  Future<void> startCapture({
    PreciseLocationConfig? config,
    bool reset = false,
  }) async {
    if (_disposed) return;

    await ensureLocationReady();

    final effectiveConfig = config ?? await _configFromUserSettings();
    _activeConfig = effectiveConfig;

    if (reset) {
      clearProgress();
    }

    if (_isRunning) {
      if (_latestProgress != null) {
        _emit(
          PreciseLocationProgress(
            latitude: _latestProgress!.latitude,
            longitude: _latestProgress!.longitude,
            accuracy: _latestProgress!.accuracy,
            bestSampleAccuracy: _latestProgress!.bestSampleAccuracy,
            sampleCount: _latestProgress!.sampleCount,
            usedSampleCount: _latestProgress!.usedSampleCount,
            rejectedSpatialOutlierCount:
            _latestProgress!.rejectedSpatialOutlierCount,
            lastRejectedSpatialDistanceMeters:
            _latestProgress!.lastRejectedSpatialDistanceMeters,
            isUsable: _latestProgress!.isUsable,
            isTargetReached: _latestProgress!.isTargetReached,
            isRunning: true,
            message: 'Фиксация уже выполняется...',
          ),
        );
      }
      return;
    }

    _stopRequested = false;
    _isRunning = true;
    _lastAnyPositionAt = DateTime.now();

    _emit(
      _buildProgress(
        config: effectiveConfig,
        isRunning: true,
        messageOverride: 'Поиск спутников...',
      ),
    );

    try {
      final lastKnown = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: false,
      );

      if (lastKnown != null &&
          _isFresh(lastKnown) &&
          _isAccepted(lastKnown, effectiveConfig) &&
          !_isSpatialOutlier(lastKnown, effectiveConfig)) {
        _accepted.add(lastKnown);
        _lastAcceptedAt = DateTime.now();
        _emit(
          _buildProgress(
            config: effectiveConfig,
            isRunning: true,
            messageOverride:
            'Найдена свежая последняя позиция. Уточняем координаты...',
          ),
        );
      }
    } catch (_) {
      // прогрев не критичен.
    }

    await _positionSubscription?.cancel();

    final settings = _buildLocationSettings(effectiveConfig);
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
          (position) async {
        if (_disposed || _stopRequested || !_isRunning) return;

        _lastAnyPositionAt = DateTime.now();

        if (_isAccepted(position, effectiveConfig)) {
          if (_isSpatialOutlier(position, effectiveConfig)) {
            _emit(
              _buildProgress(
                config: effectiveConfig,
                isRunning: true,
                messageOverride:
                'Точка отклонена антискачком: ${_lastRejectedSpatialDistanceMeters!.toStringAsFixed(1)} м от основного кластера. Продолжаем уточнение...',
              ),
            );
            return;
          }

          _accepted.add(position);
          _lastAcceptedAt = DateTime.now();

          final progress = _buildProgress(
            config: effectiveConfig,
            isRunning: true,
          );
          _emit(progress);

          if (effectiveConfig.autoStopWhenTargetReached && progress.isTargetReached) {
            await stopAndKeepBest(
              reason: 'Достигнута целевая точность.',
            );
          }
        } else {
          _emit(
            _buildProgress(
              config: effectiveConfig,
              isRunning: true,
              messageOverride:
              'Текущая точка слишком грубая (${position.accuracy.toStringAsFixed(1)} м), продолжаем уточнение...',
            ),
          );
        }
      },
      onError: (Object error) {
        if (_disposed) return;
        _emit(
          _buildProgress(
            config: effectiveConfig,
            isRunning: true,
            messageOverride: 'Продолжаем поиск координат: $error',
          ),
        );
      },
      cancelOnError: false,
    );

    _sessionTimer?.cancel();
    _sessionTimer = Timer(effectiveConfig.maxSessionDuration, () {
      if (!_disposed && _isRunning) {
        stopAndKeepBest(
          reason: 'Сеанс фиксации завершён. Можно принять текущую точность.',
        );
      }
    });

    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(effectiveConfig.requestTimeout, (_) {
      if (_disposed || !_isRunning) return;

      if (_accepted.isEmpty) {
        _emit(
          _buildProgress(
            config: effectiveConfig,
            isRunning: true,
            messageOverride: 'Ищем спутники... продолжаем сбор.',
          ),
        );
        return;
      }

      final now = DateTime.now();
      final noNewAcceptedFor = _lastAcceptedAt == null
          ? null
          : now.difference(_lastAcceptedAt!);
      final noAnyUpdateFor = _lastAnyPositionAt == null
          ? null
          : now.difference(_lastAnyPositionAt!);

      final staleAcceptedLimit = Duration(
        milliseconds: effectiveConfig.requestTimeout.inMilliseconds * 2,
      );

      if (noAnyUpdateFor != null && noAnyUpdateFor >= effectiveConfig.requestTimeout) {
        _emit(
          _buildProgress(
            config: effectiveConfig,
            isRunning: true,
            messageOverride: 'Новых координат пока нет, продолжаем поиск...',
          ),
        );
      } else if (noNewAcceptedFor != null &&
          noNewAcceptedFor >= staleAcceptedLimit) {
        _emit(
          _buildProgress(
            config: effectiveConfig,
            isRunning: true,
            messageOverride:
            'Свежие точки идут, но качество пока не улучшается. Продолжаем уточнение...',
          ),
        );
      }
    });
  }

  Future<PreciseLocationProgress> stopAndKeepBest({
    String? reason,
  }) async {
    _stopRequested = true;
    _isRunning = false;

    _sessionTimer?.cancel();
    _statusTimer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final progress = _buildProgress(
      config: _activeConfig,
      isRunning: false,
      messageOverride: reason,
    );

    _emit(progress);
    return progress;
  }
}
