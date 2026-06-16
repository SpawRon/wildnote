import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

class AmbientLightSnapshot {
  final bool enabled;
  final bool sensorAvailable;
  final double? lux;
  final double? brightness;
  final bool sunlightContrast;

  const AmbientLightSnapshot({
    required this.enabled,
    required this.sensorAvailable,
    required this.lux,
    required this.brightness,
    required this.sunlightContrast,
  });
}

class DeviceBrightnessService {
  DeviceBrightnessService._();

  static final DeviceBrightnessService instance = DeviceBrightnessService._();

  static const EventChannel _ambientLightChannel =
  EventChannel('wildnote/ambient_light');

  /// До этого уровня приложение не трогает яркость вообще.
  /// В помещении должна работать системная автояркость.
  static const double _brightnessBoostOnLux = 5200;
  static const double _brightnessBoostOffLux = 2200;

  /// Контраст включается только при ярком внешнем освещении.
  /// Пороги разнесены, чтобы тема не мигала на границе света и тени.
  static const double _contrastOnLux = 6500;
  static const double _contrastOffLux = 2600;

  final StreamController<AmbientLightSnapshot> _snapshotController =
  StreamController<AmbientLightSnapshot>.broadcast();

  StreamSubscription<dynamic>? _luxSubscription;
  Timer? _sensorWatchdog;

  bool _sensorAvailable = false;
  bool _autoBrightness = false;
  bool _autoContrast = false;
  bool _darkTheme = false;
  bool _sunlightContrast = false;
  bool _brightnessBoostActive = false;

  double? _rawLux;
  double? _smoothedLux;
  double? _lastBrightness;
  DateTime? _lastBrightnessSetAt;
  DateTime? _lastBrightnessResetAt;
  DateTime? _lastContrastSwitchAt;
  AmbientLightSnapshot? _lastSnapshot;

  void Function(bool active)? _onSunlightContrastChanged;
  void Function(AmbientLightSnapshot snapshot)? _onSnapshot;

  bool get enabled => _autoBrightness || (_autoContrast && !_darkTheme);
  bool get sunlightContrast => _sunlightContrast;
  double? get currentLux => _smoothedLux;
  double? get currentBrightness => _lastBrightness;
  bool get sensorAvailable => _sensorAvailable;
  AmbientLightSnapshot? get lastSnapshot => _lastSnapshot;
  Stream<AmbientLightSnapshot> get snapshots => _snapshotController.stream;

  Future<bool> applyAdaptiveSettings({
    required bool autoBrightness,
    required bool autoContrast,
    required bool darkTheme,
    void Function(bool active)? onSunlightContrastChanged,
    void Function(AmbientLightSnapshot snapshot)? onSnapshot,
  }) async {
    final previousAutoBrightness = _autoBrightness;
    final previousAutoContrast = _autoContrast;
    final previousDarkTheme = _darkTheme;

    _autoBrightness = autoBrightness;
    _autoContrast = autoContrast;
    _darkTheme = darkTheme;
    _onSunlightContrastChanged = onSunlightContrastChanged;
    _onSnapshot = onSnapshot;

    if (_darkTheme || !_autoContrast) {
      _setSunlightContrast(false, force: true);
    }

    if (!enabled) {
      await _stopSensorAndResetBrightness();
      _emitSnapshot();
      return true;
    }

    _startListening();

    final lux = _smoothedLux;
    final rawLux = _rawLux ?? lux;

    if (lux == null || rawLux == null) {
      // Без реального значения с датчика не поднимаем яркость и не включаем контраст.
      if (_autoBrightness) {
        await _resetApplicationBrightnessIfNeeded();
      }
      _emitSnapshot();
      return true;
    }

    final brightnessSettingChanged = previousAutoBrightness != _autoBrightness;
    final contrastSettingChanged = previousAutoContrast != _autoContrast ||
        previousDarkTheme != _darkTheme;

    if (_autoBrightness) {
      unawaited(
        _updateBrightnessForLux(
          lux: lux,
          rawLux: rawLux,
          force: brightnessSettingChanged,
        ),
      );
    } else if (previousAutoBrightness) {
      unawaited(_resetApplicationBrightnessIfNeeded());
    }

    if (_autoContrast && !_darkTheme) {
      _updateSunlightContrast(
        lux: lux,
        rawLux: rawLux,
        force: contrastSettingChanged,
      );
    }

    _emitSnapshot();
    return true;
  }

  Future<void> stop() async {
    _autoBrightness = false;
    _autoContrast = false;
    _darkTheme = false;
    _onSunlightContrastChanged = null;
    _onSnapshot = null;
    await _stopSensorAndResetBrightness();
  }

  Future<void> resetForBackground() async {
    _brightnessBoostActive = false;
    await _resetApplicationBrightnessIfNeeded(force: true);
  }

  void _startListening() {
    if (_luxSubscription != null) {
      _startSensorWatchdog();
      return;
    }

    _sensorAvailable = false;

    try {
      _luxSubscription = _ambientLightChannel.receiveBroadcastStream().listen(
        _handleLux,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('DeviceBrightnessService native lux stream failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          _sensorAvailable = false;
          _emitSnapshot();
          if (_autoBrightness) {
            unawaited(_resetApplicationBrightnessIfNeeded(force: true));
          }
        },
        cancelOnError: false,
      );

      _startSensorWatchdog();
    } catch (error, stackTrace) {
      debugPrint('DeviceBrightnessService native lux start failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _sensorAvailable = false;
      _emitSnapshot();
      if (_autoBrightness) {
        unawaited(_resetApplicationBrightnessIfNeeded(force: true));
      }
    }
  }

  void _startSensorWatchdog() {
    _sensorWatchdog?.cancel();

    if (_smoothedLux != null || !enabled) return;

    _sensorWatchdog = Timer(const Duration(milliseconds: 1800), () {
      if (_smoothedLux == null && enabled) {
        _sensorAvailable = false;
        _emitSnapshot();
        if (_autoBrightness) {
          unawaited(_resetApplicationBrightnessIfNeeded(force: true));
        }
      }
    });
  }

  Future<void> _stopSensorAndResetBrightness() async {
    _sensorWatchdog?.cancel();
    _sensorWatchdog = null;

    await _luxSubscription?.cancel();
    _luxSubscription = null;

    _sensorAvailable = false;
    _rawLux = null;
    _smoothedLux = null;
    _lastBrightnessSetAt = null;
    _brightnessBoostActive = false;

    _setSunlightContrast(false, force: true);
    await _resetApplicationBrightnessIfNeeded(force: true);
  }

  void _handleLux(dynamic value) {
    final rawLux = _toFiniteLux(value);
    if (rawLux == null) return;

    _sensorWatchdog?.cancel();
    _sensorWatchdog = null;

    final isFirstValue = _smoothedLux == null;

    _sensorAvailable = true;
    _rawLux = rawLux;

    if (isFirstValue) {
      _smoothedLux = rawLux;
    } else if (rawLux > _smoothedLux!) {
      // Быстро реагируем на выход на свет.
      _smoothedLux = (_smoothedLux! * 0.30) + (rawLux * 0.70);
    } else {
      // Понижение должно тоже происходить быстро, иначе яркость зависает.
      _smoothedLux = (_smoothedLux! * 0.38) + (rawLux * 0.62);
    }

    final lux = _smoothedLux!;

    if (_autoBrightness) {
      unawaited(
        _updateBrightnessForLux(
          lux: lux,
          rawLux: rawLux,
          force: isFirstValue,
        ),
      );
    }

    if (_autoContrast && !_darkTheme) {
      _updateSunlightContrast(
        lux: lux,
        rawLux: rawLux,
        force: isFirstValue,
      );
    }

    _emitSnapshot();
  }

  double? _toFiniteLux(dynamic value) {
    double? parsed;

    if (value is num) {
      parsed = value.toDouble();
    } else {
      parsed = double.tryParse(value.toString());
    }

    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

  double _brightnessForOutdoorLux(double lux) {
    const points = <({double lux, double brightness})>[
      (lux: 2200, brightness: 0.48),
      (lux: 5200, brightness: 0.60),
      (lux: 9000, brightness: 0.70),
      (lux: 16000, brightness: 0.82),
      (lux: 28000, brightness: 0.94),
      (lux: 45000, brightness: 1.00),
    ];

    if (lux <= points.first.lux) return points.first.brightness;
    if (lux >= points.last.lux) return points.last.brightness;

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      if (lux >= a.lux && lux <= b.lux) {
        final t = (lux - a.lux) / (b.lux - a.lux);
        return a.brightness + ((b.brightness - a.brightness) * t);
      }
    }

    return 0.65;
  }

  Future<void> _updateBrightnessForLux({
    required double lux,
    required double rawLux,
    bool force = false,
  }) async {
    if (!_brightnessBoostActive) {
      if (lux < _brightnessBoostOnLux && rawLux < _brightnessBoostOnLux) {
        await _resetApplicationBrightnessIfNeeded();
        return;
      }
      _brightnessBoostActive = true;
    }

    if (_brightnessBoostActive &&
        lux <= _brightnessBoostOffLux &&
        rawLux <= _brightnessBoostOffLux) {
      _brightnessBoostActive = false;
      await _resetApplicationBrightnessIfNeeded(force: true);
      return;
    }

    final next = _brightnessForOutdoorLux(lux).clamp(0.0, 1.0).toDouble();
    final now = DateTime.now();
    final delta = _lastBrightness == null
        ? 1.0
        : (next - _lastBrightness!).abs();
    final isDecreasing = _lastBrightness != null && next < _lastBrightness!;

    if (!force && delta < 0.018) return;

    if (!force &&
        !isDecreasing &&
        _lastBrightnessSetAt != null &&
        now.difference(_lastBrightnessSetAt!) < const Duration(milliseconds: 700)) {
      return;
    }

    if (!force &&
        isDecreasing &&
        _lastBrightnessSetAt != null &&
        now.difference(_lastBrightnessSetAt!) < const Duration(milliseconds: 280)) {
      return;
    }

    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(next);
      _lastBrightness = next;
      _lastBrightnessSetAt = now;
    } catch (error, stackTrace) {
      debugPrint('DeviceBrightnessService brightness failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _updateSunlightContrast({
    required double lux,
    required double rawLux,
    bool force = false,
  }) {
    final now = DateTime.now();

    if (!force &&
        _lastContrastSwitchAt != null &&
        now.difference(_lastContrastSwitchAt!) < const Duration(milliseconds: 900)) {
      return;
    }

    final shouldEnable = lux >= _contrastOnLux || rawLux >= _contrastOnLux;
    final shouldDisable = lux <= _contrastOffLux && rawLux <= _contrastOffLux;

    if (!_sunlightContrast && shouldEnable) {
      _setSunlightContrast(true);
      return;
    }

    if (_sunlightContrast && shouldDisable) {
      _setSunlightContrast(false);
    }
  }

  void _setSunlightContrast(bool value, {bool force = false}) {
    if (!force && value == _sunlightContrast) return;

    _sunlightContrast = value;
    _lastContrastSwitchAt = DateTime.now();
    _onSunlightContrastChanged?.call(value);
    _emitSnapshot();
  }

  Future<void> _resetApplicationBrightnessIfNeeded({bool force = false}) async {
    final now = DateTime.now();

    if (!force && _lastBrightness == null) {
      return;
    }

    if (!force &&
        _lastBrightnessResetAt != null &&
        now.difference(_lastBrightnessResetAt!) < const Duration(seconds: 2)) {
      return;
    }

    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
      _lastBrightness = null;
      _lastBrightnessSetAt = null;
      _lastBrightnessResetAt = now;
    } catch (error, stackTrace) {
      debugPrint('DeviceBrightnessService reset failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _emitSnapshot() {
    final snapshot = AmbientLightSnapshot(
      enabled: enabled,
      sensorAvailable: _sensorAvailable,
      lux: _smoothedLux,
      brightness: _lastBrightness,
      sunlightContrast: _sunlightContrast,
    );

    _lastSnapshot = snapshot;
    _onSnapshot?.call(snapshot);

    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }
}
