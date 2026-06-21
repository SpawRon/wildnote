import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_appearance_settings.dart';
import '../services/location_accuracy_settings.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/wild_page_header.dart';
import 'login_screen.dart';

class _AccuracyPreset {
  final String title;
  final String subtitle;
  final double meters;

  const _AccuracyPreset({
    required this.title,
    required this.subtitle,
    required this.meters,
  });
}

const List<_AccuracyPreset> _accuracyPresets = <_AccuracyPreset>[
  _AccuracyPreset(
    title: 'Быстро',
    subtitle: 'Не рекомендуется, подходит для быстрого сохранения наблюдения.',
    meters: 30,
  ),
  _AccuracyPreset(
    title: 'Стандартно',
    subtitle: 'Основной режим для обычной полевой работы.',
    meters: 15,
  ),
  _AccuracyPreset(
    title: 'Точно',
    subtitle: 'Более строгая фиксация, ожидание может быть дольше.',
    meters: 7,
  ),
  _AccuracyPreset(
    title: 'Максимально точно',
    subtitle: 'Самый строгий режим для важных точек наблюдения.',
    meters: 5,
  ),
];

_AccuracyPreset? _accuracyPresetExactFor(double value) {
  final normalized = LocationAccuracySettings.normalize(value);

  for (final preset in _accuracyPresets) {
    if ((normalized - preset.meters).abs() < 0.05) {
      return preset;
    }
  }

  return null;
}

String _accuracyMetersLabel(double value) {
  return '±${LocationAccuracySettings.formatMeters(value)} м';
}

class SettingsScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;
  final AppAppearanceController? appearanceController;

  const SettingsScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
    this.appearanceController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppAppearanceController _appearanceController;
  late final bool _ownsAppearanceController;

  bool _autoContrast = false;
  bool _autoBrightness = false;
  bool _darkTheme = false;
  bool _sunlightContrast = false;
  bool _fieldMode = false;
  bool _largeButtons = false;
  Color _selectedAccent = AppAppearanceSettingsData.defaultAccent;
  double _targetAccuracyMeters =
      LocationAccuracySettings.defaultTargetAccuracyMeters;
  double _customAccuracyMeters =
      LocationAccuracySettings.defaultTargetAccuracyMeters;
  bool _accuracyExpanded = false;
  bool _customAccuracyMode = false;
  bool _customAccuracyEditorOpen = false;

  String _versionLabel = 'загрузка...';
  static const String _storeUrl =
      'https://www.rustore.ru/catalog/app/mauniver.ivt.ponarin.wildnote';

  @override
  void initState() {
    super.initState();

    _appearanceController =
        widget.appearanceController ?? AppAppearance.controller;
    _ownsAppearanceController = false;

    _appearanceController.addListener(_syncAppearanceFromController);
    _syncAppearanceFromController();

    if (!_appearanceController.loaded) {
      _appearanceController.load();
    }

    _loadLocationAccuracy();
    _loadAppVersion();
  }

  @override
  void dispose() {
    _appearanceController.removeListener(_syncAppearanceFromController);

    if (_ownsAppearanceController) {
      _appearanceController.dispose();
    }

    super.dispose();
  }

  void _syncAppearanceFromController() {
    final data = _appearanceController.data;

    if (!mounted) return;

    setState(() {
      _darkTheme = data.darkTheme;
      _autoContrast = data.autoContrast;
      _autoBrightness = data.autoBrightness;
      _sunlightContrast = data.sunlightContrast;
      _fieldMode = data.fieldMode;
      _largeButtons = data.largeButtons;
      _selectedAccent = data.accentColor;
    });
  }

  bool _sameColor(Color a, Color b) {
    return a.toARGB32() == b.toARGB32();
  }

  Future<void> _loadLocationAccuracy() async {
    final value = await LocationAccuracySettings.loadTargetAccuracyMeters();

    if (!mounted) return;

    setState(() {
      _targetAccuracyMeters = value;
      _customAccuracyMeters = value;
      _customAccuracyMode = _accuracyPresetExactFor(value) == null;
      _customAccuracyEditorOpen = false;
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final rawVersion = info.version.trim();
      final version = rawVersion.isEmpty ? 'не определена' : rawVersion;

      if (!mounted) return;

      setState(() {
        _versionLabel = version;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _versionLabel = 'не определена';
      });
    }
  }

  Future<void> _logout() async {
    await SessionManager.instance.clearSession();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }


  void _openLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  Future<void> _rateApp() async {
    final uri = Uri.parse(_storeUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ссылка на магазин будет доступна после публикации'),
        ),
      );
    }
  }

  String _currentAccuracyModeTitle() {
    if (_customAccuracyMode) {
      return 'Свой вариант';
    }

    return _accuracyPresetExactFor(_targetAccuracyMeters)?.title ??
        'Свой вариант';
  }

  Future<void> _saveLocationAccuracyFromUi(
      double value, {
        bool customMode = false,
        bool showMessage = true,
      }) async {
    final normalized = LocationAccuracySettings.normalize(value);

    await LocationAccuracySettings.saveTargetAccuracyMeters(normalized);

    if (!mounted) return;

    setState(() {
      _targetAccuracyMeters = normalized;
      _customAccuracyMeters = normalized;
      _customAccuracyMode =
          customMode || _accuracyPresetExactFor(normalized) == null;
      if (!customMode) {
        _customAccuracyEditorOpen = false;
      }
    });

    if (!showMessage) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Режим точности: ${_currentAccuracyModeTitle()} (${_accuracyMetersLabel(normalized)})',
        ),
      ),
    );
  }

  Future<void> _resetLocationAccuracyFromUi() async {
    await LocationAccuracySettings.resetTargetAccuracyMeters();

    final value = LocationAccuracySettings.defaultTargetAccuracyMeters;

    if (!mounted) return;

    setState(() {
      _targetAccuracyMeters = value;
      _customAccuracyMeters = value;
      _customAccuracyMode = false;
      _customAccuracyEditorOpen = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Режим точности сброшен: ${_currentAccuracyModeTitle()} (${_accuracyMetersLabel(value)})',
        ),
      ),
    );
  }

  Future<void> _confirmCustomAccuracyFromUi() async {
    final normalized = LocationAccuracySettings.normalize(_customAccuracyMeters);

    await LocationAccuracySettings.saveTargetAccuracyMeters(normalized);

    if (!mounted) return;

    setState(() {
      _targetAccuracyMeters = normalized;
      _customAccuracyMeters = normalized;
      _customAccuracyMode = true;
      _customAccuracyEditorOpen = false;
    });

    HapticFeedback.selectionClick();
  }

  Widget _accuracyOptionDivider() {
    final colors = WildColors.of(context);
    return Divider(height: 1, color: colors.border);
  }

  String _accuracyLeadingLabel(double value) {
    return '±${LocationAccuracySettings.formatMeters(value)}';
  }

  Widget _distanceLeading(String label, {required bool selected}) {
    final colors = WildColors.of(context);

    return SizedBox(
      width: 23,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: selected
              ? colors.primary
              : colors.primary.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _accuracyTrailingSlot({
    required bool selected,
    Widget? trailing,
  }) {
    final colors = WildColors.of(context);

    final child = trailing ??
        (selected
            ? Icon(
          Icons.check_rounded,
          size: 22,
          color: colors.primary,
        )
            : const SizedBox.shrink());

    return SizedBox(
      width: 34,
      height: 34,
      child: Center(child: child),
    );
  }

  Widget _accuracyOptionRow({
    required String leading,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final colors = WildColors.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _distanceLeading(leading, selected: selected),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            _accuracyTrailingSlot(selected: selected, trailing: trailing),
          ],
        ),
      ),
    );
  }

  Widget _accuracyPresetTile(_AccuracyPreset preset) {
    final isSelected =
        !_customAccuracyMode &&
            _accuracyPresetExactFor(_targetAccuracyMeters)?.meters == preset.meters;

    return _accuracyOptionRow(
      leading: _accuracyLeadingLabel(preset.meters),
      title: preset.title,
      subtitle: preset.subtitle,
      selected: isSelected,
      onTap: () async {
        HapticFeedback.selectionClick();
        await _saveLocationAccuracyFromUi(
          preset.meters,
          customMode: false,
          showMessage: false,
        );
      },
    );
  }

  Widget _customAccuracyTile() {
    final colors = WildColors.of(context);
    final isSavedCustom =
        _customAccuracyMode ||
            _accuracyPresetExactFor(_targetAccuracyMeters) == null;
    final isActive = isSavedCustom || _customAccuracyEditorOpen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accuracyOptionRow(
          leading: _accuracyLeadingLabel(_customAccuracyMeters),
          title: 'Свой вариант',
          subtitle: 'Ручная настройка цели от ±3 до ±60 м.',
          selected: isActive,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _customAccuracyEditorOpen = true;
              _customAccuracyMeters = _targetAccuracyMeters;
            });
          },
          trailing: _customAccuracyEditorOpen
              ? IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: 34,
              height: 34,
            ),
            tooltip: 'Сохранить точность',
            icon: Icon(
              Icons.check_rounded,
              size: 22,
              color: colors.primary,
            ),
            onPressed: _confirmCustomAccuracyFromUi,
          )
              : null,
        ),
        ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0.0,
              end: _customAccuracyEditorOpen ? 1.0 : 0.0,
            ),
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            builder: (context, factor, child) {
              return Align(
                alignment: Alignment.topCenter,
                heightFactor: factor,
                child: child,
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(35, 0, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: LocationAccuracySettings.normalize(
                      _customAccuracyMeters,
                    ),
                    min: LocationAccuracySettings.minTargetAccuracyMeters,
                    max: LocationAccuracySettings.maxTargetAccuracyMeters,
                    divisions: 57,
                    label: _accuracyMetersLabel(_customAccuracyMeters),
                    onChanged: (value) {
                      setState(() {
                        _customAccuracyMeters =
                            LocationAccuracySettings.normalize(value);
                      });
                    },
                  ),
                  Row(
                    children: [
                      Text(
                        '±3 м',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: colors.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '±60 м',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _accuracyInlineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accuracyOptionDivider(),
        for (final preset in _accuracyPresets) ...[
          _accuracyPresetTile(preset),
          _accuracyOptionDivider(),
        ],
        _customAccuracyTile(),
        _accuracyOptionDivider(),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _resetLocationAccuracyFromUi,
            child: const Text('Сбросить'),
          ),
        ),
      ],
    );
  }

  Future<void> _setDarkTheme(bool value) async {
    await _appearanceController.setDarkTheme(value);
  }

  Future<void> _setAutoContrast(bool value) async {
    if (_darkTheme) return;
    await _appearanceController.setAutoContrast(value);
  }

  Future<void> _setAutoBrightness(bool value) async {
    await _appearanceController.setAutoBrightness(value);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Автояркость будет подстраиваться по датчику освещённости'
              : 'Автояркость выключена',
        ),
      ),
    );
  }

  Future<void> _setFieldMode(bool value) async {
    await _appearanceController.setFieldMode(value);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Полевой режим включён'
              : 'Полевой режим выключен',
        ),
      ),
    );
  }

  Future<void> _setLargeButtons(bool value) async {
    await _appearanceController.setLargeButtons(value);
  }

  Future<void> _setAccent(Color color) async {
    final normalized = AppAppearanceSettings.normalizeAccent(color);
    await _appearanceController.setAccentColor(normalized);

    if (!mounted) return;

    HapticFeedback.selectionClick();
  }

  int _channel(Color color, int shift) {
    return (color.toARGB32() >> shift) & 0xFF;
  }

  Future<void> _showRgbAccentDialog() async {
    final original = _appearanceController.accentColor;
    var preview = original;

    double red = _channel(original, 16).toDouble();
    double green = _channel(original, 8).toDouble();
    double blue = _channel(original, 0).toDouble();

    Color fromChannels() {
      return Color.fromARGB(
        255,
        red.round().clamp(0, 255),
        green.round().clamp(0, 255),
        blue.round().clamp(0, 255),
      );
    }

    void applyPreview(StateSetter setDialogState) {
      preview = AppAppearanceSettings.normalizeAccent(fromChannels());
      _appearanceController.previewAccentColor(preview);
      setDialogState(() {});
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colors = WildColors.of(context);

            Widget slider({
              required String label,
              required double value,
              required Color color,
              required ValueChanged<double> onChanged,
            }) {
              return Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: colors.muted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: color,
                        thumbColor: color,
                      ),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: 255,
                        divisions: 255,
                        label: value.round().toString(),
                        onChanged: (next) {
                          onChanged(next);
                          applyPreview(setDialogState);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      value.round().toString(),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: colors.primaryDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              );
            }

            return Dialog(
              backgroundColor: colors.surface,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: preview,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Свой акцент',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: colors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      slider(
                        label: 'R',
                        value: red,
                        color: Colors.red,
                        onChanged: (value) => red = value,
                      ),
                      slider(
                        label: 'G',
                        value: green,
                        color: Colors.green,
                        onChanged: (value) => green = value,
                      ),
                      slider(
                        label: 'B',
                        value: blue,
                        color: Colors.blue,
                        onChanged: (value) => blue = value,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            preview.withValues(alpha: 0.16),
                            colors.surface,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          '#${(preview.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                          style: TextStyle(
                            color: colors.primaryDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              _appearanceController.previewAccentColor(original);
                              Navigator.of(context).pop(false);
                            },
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                            child: const Text('Сохранить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      await _appearanceController.setAccentColor(preview);
      if (!mounted) return;
      HapticFeedback.selectionClick();
    } else {
      _appearanceController.previewAccentColor(original);
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final colors = WildColors.of(context);

        return Dialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WildNote',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Приложение для регистрации полевых наблюдений редких растений и отправки данных на геопортал.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: colors.primaryDark,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Версия: $_versionLabel',
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Закрыть'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section({
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final colors = WildColors.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryDark,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _divider() {
    final colors = WildColors.of(context);
    return Divider(height: 1, color: colors.border);
  }

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? color,
  }) {
    final colors = WildColors.of(context);
    final effectiveColor = color ?? colors.primaryDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 23, color: color ?? colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: effectiveColor,
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return _row(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _accentPicker() {
    final colors = WildColors.of(context);

    final quickColors = AppAppearanceSettings.accentPalette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(35, 2, 0, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...quickColors.map((color) {
            final isSelected = _sameColor(color, _selectedAccent);

            return InkWell(
              onTap: () => _setAccent(color),
              customBorder: const CircleBorder(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
                child: isSelected
                    ? const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 18,
                )
                    : null,
              ),
            );
          }),
          InkWell(
            onTap: _showRgbAccentDialog,
            customBorder: const CircleBorder(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryDark.withValues(alpha: 0.06),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 17,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);
    final label = widget.isGuest ? 'Гость' : widget.userLogin;

    return ColoredBox(
      color: colors.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            20,
            AppSpacing.screen,
            116,
          ),
          children: [
            const WildPageHeader(
              title: 'Настройки',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 18),
            _section(
              title: 'Аккаунт',
              children: [
                _row(
                  icon: widget.isGuest
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_done_outlined,
                  title: label,
                  subtitle: widget.isGuest
                      ? 'Офлайн-режим'
                      : 'Аккаунт геопортала',
                ),
                _divider(),
                _row(
                  icon: widget.isGuest
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  title: widget.isGuest ? 'Войти' : 'Выйти',
                  subtitle: widget.isGuest
                      ? 'Перейти к авторизации на геопортале'
                      : null,
                  color: widget.isGuest ? colors.primary : colors.danger,
                  onTap: widget.isGuest ? _openLogin : _logout,
                ),
              ],
            ),
            _section(
              title: 'Внешний вид',
              children: [
                _switchRow(
                  icon: Icons.dark_mode_outlined,
                  title: 'Тёмная тема',
                  subtitle: 'Переключает светлое и тёмное оформление',
                  value: _darkTheme,
                  onChanged: _setDarkTheme,
                ),
                _divider(),
                _row(
                  icon: Icons.palette_outlined,
                  title: 'Акцент приложения',
                  subtitle: 'Цвет фона, кнопок, полей и нижнего меню',
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.muted,
                  ),
                  onTap: _showRgbAccentDialog,
                ),
                _accentPicker(),
              ],
            ),
            _section(
              title: 'Полевой режим',
              trailing: Switch(
                value: _fieldMode,
                onChanged: _setFieldMode,
              ),
              children: [
                _switchRow(
                  icon: Icons.touch_app_rounded,
                  title: 'Крупные кнопки',
                  subtitle: 'Увеличивает основные кнопки и нижнее меню для работы на улице',
                  value: _largeButtons,
                  onChanged: _setLargeButtons,
                ),
                _divider(),
                _row(
                  icon: Icons.gps_fixed_rounded,
                  title: 'Точность координат',
                  subtitle:
                  'Сейчас: ${_currentAccuracyModeTitle()} · ${_accuracyMetersLabel(_targetAccuracyMeters)}. Чем точнее режим, тем дольше ожидание.',
                  trailing: Icon(
                    _accuracyExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colors.muted,
                  ),
                  onTap: () {
                    setState(() {
                      _accuracyExpanded = !_accuracyExpanded;
                      if (!_accuracyExpanded) {
                        _customAccuracyEditorOpen = false;
                        _customAccuracyMeters = _targetAccuracyMeters;
                      }
                    });
                  },
                ),
                ClipRect(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0.0,
                      end: _accuracyExpanded ? 1.0 : 0.0,
                    ),
                    duration: const Duration(milliseconds: 190),
                    curve: Curves.easeOutCubic,
                    builder: (context, factor, child) {
                      return Align(
                        alignment: Alignment.topCenter,
                        heightFactor: factor,
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: _accuracyInlineSelector(),
                    ),
                  ),
                ),
                _divider(),
                _switchRow(
                  icon: Icons.contrast_rounded,
                  title: 'Автоконтрастность',
                  subtitle: _darkTheme
                      ? 'Недоступна в тёмной теме'
                      : (_sunlightContrast
                      ? 'Солнце на датчике: включена ультраконтрастность'
                      : 'Обычная тема в тени и ультраконтраст при прямом солнце'),
                  value: _darkTheme ? false : _autoContrast,
                  onChanged: _darkTheme ? null : _setAutoContrast,
                ),
                _divider(),
                _switchRow(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Автояркость',
                  subtitle:
                  'Экран подстраивается под любое освещение',
                  value: _autoBrightness,
                  onChanged: _setAutoBrightness,
                ),
              ],
            ),
            _section(
              title: 'Приложение',
              children: [
                _row(
                  icon: Icons.info_outline_rounded,
                  title: 'Справка и версия',
                  subtitle: 'Версия $_versionLabel',
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.muted,
                  ),
                  onTap: _showAbout,
                ),
                _divider(),
                _row(
                  icon: Icons.star_outline_rounded,
                  title: 'Оценить приложение',
                  trailing: Icon(
                    Icons.open_in_new_rounded,
                    color: colors.muted,
                  ),
                  onTap: _rateApp,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
