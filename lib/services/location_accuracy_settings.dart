import 'package:shared_preferences/shared_preferences.dart';

class LocationAccuracySettings {
  LocationAccuracySettings._();

  static const String storageKey = 'location_target_accuracy_meters';
  static const double defaultTargetAccuracyMeters = 15;
  static const double minTargetAccuracyMeters = 3;
  static const double maxTargetAccuracyMeters = 60;

  static double normalize(double value) {
    if (value.isNaN || value.isInfinite) {
      return defaultTargetAccuracyMeters;
    }

    return value
        .clamp(minTargetAccuracyMeters, maxTargetAccuracyMeters)
        .toDouble();
  }

  static Future<double> loadTargetAccuracyMeters() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(storageKey);

    if (value == null) {
      return defaultTargetAccuracyMeters;
    }

    return normalize(value);
  }

  static Future<void> saveTargetAccuracyMeters(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(storageKey, normalize(value));
  }

  static Future<void> resetTargetAccuracyMeters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  static String formatMeters(double value) {
    final normalized = normalize(value);

    if (normalized.truncateToDouble() == normalized) {
      return normalized.toStringAsFixed(0);
    }

    return normalized.toStringAsFixed(1);
  }
}
