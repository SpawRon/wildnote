import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppAppearanceSettingsData {
  final bool darkTheme;

  /// Пользовательская настройка: включить автоматический режим контраста.
  /// Сам факт "солнце сейчас попало на датчик" не сохраняется.
  final bool autoContrast;

  /// Пользовательская настройка: включить автоматическую яркость от датчика света.
  final bool autoBrightness;

  /// Временное runtime-состояние от датчика света.
  /// true только когда autoContrast включён, тема светлая и датчик видит прямое солнце.
  final bool sunlightContrast;

  /// Общий переключатель "Полевой режим".
  /// Он включает набор полевых настроек, но отдельные пункты можно выключить вручную.
  final bool fieldMode;

  /// Отдельная настройка крупных кнопок.
  final bool largeButtons;

  final Color accentColor;

  const AppAppearanceSettingsData({
    required this.darkTheme,
    required this.autoContrast,
    required this.autoBrightness,
    required this.sunlightContrast,
    required this.fieldMode,
    required this.largeButtons,
    required this.accentColor,
  });

  static const Color defaultAccent = Color(0xFF6F8F77);

  static const AppAppearanceSettingsData defaults = AppAppearanceSettingsData(
    darkTheme: false,
    autoContrast: false,
    autoBrightness: false,
    sunlightContrast: false,
    fieldMode: false,
    largeButtons: false,
    accentColor: defaultAccent,
  );

  AppAppearanceSettingsData copyWith({
    bool? darkTheme,
    bool? autoContrast,
    bool? autoBrightness,
    bool? sunlightContrast,
    bool? fieldMode,
    bool? largeButtons,
    Color? accentColor,
  }) {
    return AppAppearanceSettingsData(
      darkTheme: darkTheme ?? this.darkTheme,
      autoContrast: autoContrast ?? this.autoContrast,
      autoBrightness: autoBrightness ?? this.autoBrightness,
      sunlightContrast: sunlightContrast ?? this.sunlightContrast,
      fieldMode: fieldMode ?? this.fieldMode,
      largeButtons: largeButtons ?? this.largeButtons,
      accentColor: accentColor ?? this.accentColor,
    );
  }

  bool get fieldModeSatisfied {
    final contrastOk = darkTheme ? true : autoContrast;
    return largeButtons && autoBrightness && contrastOk;
  }

  AppAppearanceSettingsData normalized() {
    final normalizedAutoContrast = darkTheme ? false : autoContrast;
    final normalizedFieldMode = fieldMode && fieldModeSatisfied;

    return copyWith(
      autoContrast: normalizedAutoContrast,
      sunlightContrast:
      darkTheme || !normalizedAutoContrast ? false : sunlightContrast,
      fieldMode: normalizedFieldMode,
      accentColor: AppAppearanceSettings.normalizeAccent(accentColor),
    );
  }
}

class AppAppearanceSettings {
  AppAppearanceSettings._();

  static const String darkThemeKey = 'app_dark_theme_enabled';
  static const String autoContrastKey = 'app_auto_contrast_enabled';
  static const String autoBrightnessKey = 'app_auto_brightness_enabled';
  static const String fieldModeKey = 'app_field_mode_enabled';
  static const String largeButtonsKey = 'app_large_buttons_enabled';
  static const String accentColorKey = 'app_accent_color_value';

  /// Красивый короткий ряд: 6 готовых цветов + отдельный круг "свой".
  static const List<Color> accentPalette = <Color>[
    Color(0xFF6F8F77), // мягкий зелёный
    Color(0xFF24863B), // насыщенный зелёный
    Color(0xFF00897B), // бирюза
    Color(0xFF1565C0), // синий
    Color(0xFF6A5AE0), // фиолетово-синий
    Color(0xFFE4772D), // тёплый оранжевый
  ];

  static Future<AppAppearanceSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();

    final darkTheme = prefs.getBool(darkThemeKey) ??
        AppAppearanceSettingsData.defaults.darkTheme;

    final autoContrast = darkTheme
        ? false
        : prefs.getBool(autoContrastKey) ??
        AppAppearanceSettingsData.defaults.autoContrast;

    final autoBrightness = prefs.getBool(autoBrightnessKey) ??
        AppAppearanceSettingsData.defaults.autoBrightness;

    final largeButtons = prefs.getBool(largeButtonsKey) ??
        AppAppearanceSettingsData.defaults.largeButtons;

    final savedFieldMode = prefs.getBool(fieldModeKey) ??
        AppAppearanceSettingsData.defaults.fieldMode;

    final accentValue = prefs.getInt(accentColorKey) ??
        AppAppearanceSettingsData.defaults.accentColor.toARGB32();

    final loaded = AppAppearanceSettingsData(
      darkTheme: darkTheme,
      autoContrast: autoContrast,
      autoBrightness: autoBrightness,
      sunlightContrast: false,
      fieldMode: savedFieldMode,
      largeButtons: largeButtons,
      accentColor: Color(accentValue),
    ).normalized();

    return loaded;
  }

  static Future<void> save(AppAppearanceSettingsData data) async {
    final normalized = data.normalized();
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(darkThemeKey, normalized.darkTheme);
    await prefs.setBool(autoContrastKey, normalized.autoContrast);
    await prefs.setBool(autoBrightnessKey, normalized.autoBrightness);
    await prefs.setBool(fieldModeKey, normalized.fieldMode);
    await prefs.setBool(largeButtonsKey, normalized.largeButtons);
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
  bool get sunlightContrast => _data.sunlightContrast;
  bool get fieldMode => _data.fieldMode;
  bool get largeButtons => _data.largeButtons;
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

  bool _fieldModeValue({
    required bool darkTheme,
    required bool autoContrast,
    required bool autoBrightness,
    required bool largeButtons,
  }) {
    final contrastOk = darkTheme ? true : autoContrast;
    return largeButtons && autoBrightness && contrastOk;
  }

  Future<void> setDarkTheme(bool value) async {
    final nextAutoContrast = value ? false : _data.autoContrast;
    final nextFieldMode = _fieldModeValue(
      darkTheme: value,
      autoContrast: nextAutoContrast,
      autoBrightness: _data.autoBrightness,
      largeButtons: _data.largeButtons,
    );

    await update(
      _data.copyWith(
        darkTheme: value,
        autoContrast: nextAutoContrast,
        sunlightContrast: false,
        fieldMode: nextFieldMode,
      ),
    );
  }

  Future<void> setAutoContrast(bool value) async {
    if (_data.darkTheme) {
      final nextFieldMode = _fieldModeValue(
        darkTheme: true,
        autoContrast: false,
        autoBrightness: _data.autoBrightness,
        largeButtons: _data.largeButtons,
      );

      await update(
        _data.copyWith(
          autoContrast: false,
          sunlightContrast: false,
          fieldMode: nextFieldMode,
        ),
      );
      return;
    }

    final nextFieldMode = _fieldModeValue(
      darkTheme: _data.darkTheme,
      autoContrast: value,
      autoBrightness: _data.autoBrightness,
      largeButtons: _data.largeButtons,
    );

    await update(
      _data.copyWith(
        autoContrast: value,
        // При включении автоконтрастности оставляем обычную тему.
        // Ультраконтраст включит только датчик освещенности.
        sunlightContrast: false,
        fieldMode: nextFieldMode,
      ),
    );
  }

  Future<void> setAutoBrightness(bool value) async {
    final nextFieldMode = _fieldModeValue(
      darkTheme: _data.darkTheme,
      autoContrast: _data.autoContrast,
      autoBrightness: value,
      largeButtons: _data.largeButtons,
    );

    await update(
      _data.copyWith(
        autoBrightness: value,
        fieldMode: nextFieldMode,
      ),
    );
  }

  Future<void> setLargeButtons(bool value) async {
    final nextFieldMode = _fieldModeValue(
      darkTheme: _data.darkTheme,
      autoContrast: _data.autoContrast,
      autoBrightness: _data.autoBrightness,
      largeButtons: value,
    );

    await update(
      _data.copyWith(
        largeButtons: value,
        fieldMode: nextFieldMode,
      ),
    );
  }

  Future<void> setFieldMode(bool value) async {
    await update(
      _data.copyWith(
        fieldMode: value,
        largeButtons: value,
        autoBrightness: value,
        autoContrast: value && !_data.darkTheme,
        sunlightContrast: false,
      ),
    );
  }

  Future<void> setAccentColor(Color color) async {
    await update(_data.copyWith(accentColor: color));
  }

  /// Runtime-переключатель от датчика света.
  /// не сохраняется в SharedPreferences чтобы приложение не просыпалось в ультраконтрасте без реального солнца
  void setSunlightContrast(bool value) {
    final next = _data.copyWith(sunlightContrast: value).normalized();
    if (next.sunlightContrast == _data.sunlightContrast) return;

    _data = next;
    notifyListeners();
  }

  Future<void> saveCurrent() async {
    await AppAppearanceSettings.save(_data);
  }
}

class AppAppearance {
  AppAppearance._();

  static final AppAppearanceController controller = AppAppearanceController();
}
