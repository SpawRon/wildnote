import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wildnote/services/app_appearance_settings.dart';

void main() {
  group('AppAppearanceSettings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('normalizeAccent drops alpha and preserves RGB', () {
      final normalized = AppAppearanceSettings.normalizeAccent(
        const Color(0x802E7D32),
      );

      expect(normalized.toARGB32(), const Color(0xFF2E7D32).toARGB32());
    });

    test('normalizeAccent falls back to default when fully transparent', () {
      final normalized = AppAppearanceSettings.normalizeAccent(
        const Color(0x002E7D32),
      );

      expect(
        normalized.toARGB32(),
        AppAppearanceSettingsData.defaultAccent.toARGB32(),
      );
    });

    test('dark theme disables auto contrast in normalization', () {
      final data = const AppAppearanceSettingsData(
        darkTheme: true,
        autoContrast: true,
        autoBrightness: false,
        accentColor: Color(0xFF6A5AE0),
      ).normalized();

      expect(data.darkTheme, isTrue);
      expect(data.autoContrast, isFalse);
    });

    test('save and load returns normalized settings', () async {
      final saved = const AppAppearanceSettingsData(
        darkTheme: true,
        autoContrast: true,
        autoBrightness: true,
        accentColor: Color(0x80E85D75),
      );

      await AppAppearanceSettings.save(saved);
      final loaded = await AppAppearanceSettings.load();

      expect(loaded.darkTheme, isTrue);
      expect(loaded.autoContrast, isFalse);
      expect(loaded.autoBrightness, isTrue);
      expect(loaded.accentColor.toARGB32(), const Color(0xFFE85D75).toARGB32());
    });
  });
}
