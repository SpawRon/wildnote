import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildnote/services/location_accuracy_settings.dart';

void main() {
  group('LocationAccuracySettings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('normalize keeps value within allowed bounds', () {
      expect(
        LocationAccuracySettings.normalize(20),
        20,
      );
      expect(
        LocationAccuracySettings.normalize(1),
        LocationAccuracySettings.minTargetAccuracyMeters,
      );
      expect(
        LocationAccuracySettings.normalize(100),
        LocationAccuracySettings.maxTargetAccuracyMeters,
      );
    });

    test('normalize falls back to default for NaN and infinity', () {
      expect(
        LocationAccuracySettings.normalize(double.nan),
        LocationAccuracySettings.defaultTargetAccuracyMeters,
      );
      expect(
        LocationAccuracySettings.normalize(double.infinity),
        LocationAccuracySettings.defaultTargetAccuracyMeters,
      );
    });

    test('load/save/reset roundtrip works with shared preferences', () async {
      expect(
        await LocationAccuracySettings.loadTargetAccuracyMeters(),
        LocationAccuracySettings.defaultTargetAccuracyMeters,
      );

      await LocationAccuracySettings.saveTargetAccuracyMeters(11.4);
      expect(
        await LocationAccuracySettings.loadTargetAccuracyMeters(),
        11.4,
      );

      await LocationAccuracySettings.saveTargetAccuracyMeters(0);
      expect(
        await LocationAccuracySettings.loadTargetAccuracyMeters(),
        LocationAccuracySettings.minTargetAccuracyMeters,
      );

      await LocationAccuracySettings.resetTargetAccuracyMeters();
      expect(
        await LocationAccuracySettings.loadTargetAccuracyMeters(),
        LocationAccuracySettings.defaultTargetAccuracyMeters,
      );
    });

    test('formatMeters renders integer and decimal values', () {
      expect(LocationAccuracySettings.formatMeters(12), '12');
      expect(LocationAccuracySettings.formatMeters(12.34), '12.3');
    });
  });
}
