import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:light_sensor/light_sensor.dart';
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

  /// Порог включения ультраконтраста.
  /// По справочным значениям прямой солнечный свет обычно сильно выше 30 000 lx,
  /// а тень в солнечный день часто около 10 000-20 000 lx, поэтому здесь
  /// используется гистерезис, чтобы тема не мигала около границы.
  static const double sunlightContrastOnLux = 35000;
  static const double sunlightContrastOffLux = 22000;

  StreamSubscription<dynamic>? _luxSubscription;

  bool _sensorAvailable = false;
  bool _sensorChecked = false;

  bool _autoBrightness = false;
  bool _autoContrast = false;
  bool _darkTheme = false;
  bool _sunlightContrast = false;

  double? _smoothedLux;
  double? _lastBrightness;
  DateTime? _lastBrightnessSetAt;
  DateTime? _lastContrastSwitchAt;

  void Function(bool active)? _onSunlightContrastChanged;
  void Function(AmbientLightSnapshot snapshot)? _onSnapshot;

  bool get enabled => _autoBrightness || (_autoContrast && !_darkTheme);
  bool get sunlightContrast => _sunlightContrast;
  double? get currentLux => _smoothedLux;
  double? get currentBrightness => _lastBrightness;
  bool get sensorAvailable => _sensorAvailable;

  Future<bool> applyAdaptiveSettings({
    required bool autoBrightness,
    required bool autoContrast,
    required bool darkTheme,
    void Function(bool active)? onSunlightContrastChanged,
    void Function(AmbientLightSnapshot snapshot)? onSnapshot,
  }) async {
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

    await _ensureSensorAvailability();

    if (!_sensorAvailable) {
      if (_autoBrightness) {
        // Без датчика света нельзя сделать честную автояркость.
        // Сбрасываем к системной яркости, чтобы не держать принудительный максимум.
        await _resetApplicationBrightness();
      }
      _emitSnapshot();
      return false;
    }

    _startListening();
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

  Future<void> _ensureSensorAvailability() async {
    if (_sensorChecked) return;

    try {
      _sensorAvailable = await LightSensor.hasSensor();
    } catch (error, stackTrace) {
      debugPrint('DeviceBrightnessService sensor check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _sensorAvailable = false;
    } finally {
      _sensorChecked = true;
    }
  }

  void _startListening() {
    if (_luxSubscription != null) return;

    _luxSubscription = LightSensor.luxStream().listen(
      _handleLux,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('DeviceBrightnessService lux stream failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
      cancelOnError: false,
    );
  }

  Future<void> _stopSensorAndResetBrightness() async {
    await _luxSubscription?.cancel();
    _luxSubscription = null;
    _smoothedLux = null;
    _lastBrightness = null;
    _lastBrightnessSetAt = null;
    _setSunlightContrast(false, force: true);
    await _resetApplicationBrightness();
  }

  void _handleLux(dynamic value) {
    final rawLux = _toFiniteLux(value);
    if (rawLux == null) return;

    _smoothedLux = _smoothedLux == null
        ? rawLux
        : (_smoothedLux! * 0.65) + (rawLux * 0.35);

    if (_autoBrightness) {
      unawaited(_applyBrightnessForLux(_smoothedLux!));
    }

    if (_autoContrast && !_darkTheme) {
      _updateSunlightContrast(_smoothedLux!);
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

  /// Плавная шкала под полевой режим:
  /// помещение/пасмурно — комфортная середина, улица — выше, прямое солнце — максимум.
  double _brightnessForLux(double lux) {
    const points = <({double lux, double brightness})>[
      (lux: 0, brightness: 0.46),
      (lux: 50, brightness: 0.50),
      (lux: 150, brightness: 0.56),
      (lux: 400, brightness: 0.62),
      (lux: 1000, brightness: 0.70),
      (lux: 3000, brightness: 0.80),
      (lux: 10000, brightness: 0.90),
      (lux: 22000, brightness: 0.96),
      (lux: 35000, brightness: 1.00),
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

    return 0.75;
  }

  Future<void> _applyBrightnessForLux(double lux) async {
    final next = _brightnessForLux(lux).clamp(0.0, 1.0).toDouble();
    final now = DateTime.now();

    if (_lastBrightness != null && (next - _lastBrightness!).abs() < 0.04) {
      return;
    }

    if (_lastBrightnessSetAt != null &&
        now.difference(_lastBrightnessSetAt!) < const Duration(milliseconds: 900)) {
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

  void _updateSunlightContrast(double lux) {
    final now = DateTime.now();

    if (_lastContrastSwitchAt != null &&
        now.difference(_lastContrastSwitchAt!) < const Duration(seconds: 5)) {
      return;
    }

    if (!_sunlightContrast && lux >= sunlightContrastOnLux) {
      _setSunlightContrast(true);
      return;
    }

    if (_sunlightContrast && lux <= sunlightContrastOffLux) {
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

  Future<void> _resetApplicationBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (error, stackTrace) {
      debugPrint('DeviceBrightnessService reset failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _emitSnapshot() {
    _onSnapshot?.call(
      AmbientLightSnapshot(
        enabled: enabled,
        sensorAvailable: _sensorAvailable,
        lux: _smoothedLux,
        brightness: _lastBrightness,
        sunlightContrast: _sunlightContrast,
      ),
    );
  }
}
