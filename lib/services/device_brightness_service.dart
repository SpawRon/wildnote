import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';

class DeviceBrightnessService {
  DeviceBrightnessService._();

  static final DeviceBrightnessService instance = DeviceBrightnessService._();

  bool _enabled = false;

  bool get enabled => _enabled;

  Future<bool> applyAutoBrightness(bool enabled) async {
    _enabled = enabled;

    try {
      if (enabled) {
        await ScreenBrightness().setScreenBrightness(1.0);
      } else {
        await ScreenBrightness().resetScreenBrightness();
      }

      return true;
    } catch (error, stackTrace) {
      debugPrint('DeviceBrightnessService failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
