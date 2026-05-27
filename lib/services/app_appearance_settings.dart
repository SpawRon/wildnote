import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppAppearanceSettingsData {
  final bool darkTheme;
  final bool autoContrast;
  final bool autoBrightness;
  final Color accentColor;

  const AppAppearanceSettingsData({
    required this.darkTheme,
    required this.autoContrast,
    required this.autoBrightness,
    required this.accentColor,
  });

  static const Color defaultAccent = Color(0xFF6F8F77);

  static const AppAppearanceSettingsData defaults = AppAppearanceSettingsData(
    darkTheme: false,
    autoContrast: false,
    autoBrightness: false,
    accentColor: defaultAccent,
  );

  AppAppearanceSettingsData copyWith({
    bool? darkTheme,
    bool? autoContrast,
    bool? autoBrightness,
    Color? accentColor,
  }) {
    return AppAppearanceSettingsData(
      darkTheme: darkTheme ?? this.darkTheme,
      autoContrast: autoContrast ?? this.autoContrast,
      autoBrightness: autoBrightness ?? this.autoBrightness,
      accentColor: accentColor ?? this.accentColor,
    );
  }

  AppAppearanceSettingsData normalized() {
    return copyWith(
      autoContrast: darkTheme ? false : autoContrast,
      accentColor: AppAppearanceSettings.normalizeAccent(accentColor),
    );
  }
}

class AppAppearanceSettings {
  AppAppearanceSettings._();

  static const String darkThemeKey = 'app_dark_theme_enabled';
  static const String autoContrastKey = 'app_auto_contrast_enabled';
  static const String autoBrightnessKey = 'app_auto_brightness_enabled';
  static const String accentColorKey = 'app_accent_color_value';

  static const List<Color> accentPalette = <Color>[
    Color(0xFF6F8F77),
    Color(0xFF2E7D32),
    Color(0xFF00897B),
    Color(0xFF1565C0),
    Color(0xFF6A5AE0),
    Color(0xFF8E44AD),
    Color(0xFFE85D75),
    Color(0xFFD77A2D),
  ];

  static Future<AppAppearanceSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();

    final darkTheme =
        prefs.getBool(darkThemeKey) ?? AppAppearanceSettingsData.defaults.darkTheme;

    final autoContrast = darkTheme
        ? false
        : prefs.getBool(autoContrastKey) ??
        AppAppearanceSettingsData.defaults.autoContrast;

    final autoBrightness = prefs.getBool(autoBrightnessKey) ??
        AppAppearanceSettingsData.defaults.autoBrightness;

    final accentValue = prefs.getInt(accentColorKey) ??
        AppAppearanceSettingsData.defaults.accentColor.toARGB32();

    return AppAppearanceSettingsData(
      darkTheme: darkTheme,
      autoContrast: autoContrast,
      autoBrightness: autoBrightness,
      accentColor: Color(accentValue),
    ).normalized();
  }

  static Future<void> save(AppAppearanceSettingsData data) async {
    final normalized = data.normalized();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(darkThemeKey, normalized.darkTheme);
    await prefs.setBool(autoContrastKey, normalized.autoContrast);
    await prefs.setBool(autoBrightnessKey, normalized.autoBrightness);
    await prefs.setInt(accentColorKey, normalized.accentColor.toARGB32());
  }

  static Color normalizeAccent(Color color) {
    final argb = color.toARGB32();
    final alpha = (argb >> 24) & 0xFF;

    if (alpha == 0) {
      return AppAppearanceSettingsData.defaultAccent;
    }

    return Color(0xFF000000 | (argb & 0x00FFFFFF));
  }
}

class AppAppearanceController extends ChangeNotifier {
  AppAppearanceSettingsData _data = AppAppearanceSettingsData.defaults;
  bool _loaded = false;

  AppAppearanceSettingsData get data => _data;
  bool get loaded => _loaded;

  bool get darkTheme => _data.darkTheme;
  bool get autoContrast => _data.autoContrast;
  bool get autoBrightness => _data.autoBrightness;
  Color get accentColor => _data.accentColor;

  Future<void> load() async {
    _data = await AppAppearanceSettings.load();
    _loaded = true;
    notifyListeners();
  }

  void preview(AppAppearanceSettingsData data) {
    _data = data.normalized();
    notifyListeners();
  }

  void previewAccentColor(Color color) {
    preview(_data.copyWith(accentColor: color));
  }

  Future<void> update(AppAppearanceSettingsData data) async {
    _data = data.normalized();
    notifyListeners();

    await AppAppearanceSettings.save(_data);
  }

  Future<void> setDarkTheme(bool value) async {
    await update(
      _data.copyWith(
        darkTheme: value,
        autoContrast: value ? false : _data.autoContrast,
      ),
    );
  }

  Future<void> setAutoContrast(bool value) async {
    if (_data.darkTheme) {
      await update(_data.copyWith(autoContrast: false));
      return;
    }

    await update(_data.copyWith(autoContrast: value));
  }

  Future<void> setAutoBrightness(bool value) async {
    await update(_data.copyWith(autoBrightness: value));
  }

  Future<void> setAccentColor(Color color) async {
    await update(_data.copyWith(accentColor: color));
  }

  Future<void> saveCurrent() async {
    await AppAppearanceSettings.save(_data);
  }
}

class AppAppearance {
  AppAppearance._();

  static final AppAppearanceController controller = AppAppearanceController();
}
