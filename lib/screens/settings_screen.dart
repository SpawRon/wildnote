import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/location_accuracy_settings.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/wild_page_header.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;

  const SettingsScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoContrast = false;
  bool _autoBrightness = false;
  bool _darkTheme = false;
  Color _selectedAccent = AppColors.primary;
  double _targetAccuracyMeters =
      LocationAccuracySettings.defaultTargetAccuracyMeters;

  static const String _version = '0.1.0';
  static const String _storeUrl = 'https://www.rustore.ru/catalog/app/mauniver.ivt.ponarin.wildnote';

  @override
  void initState() {
    super.initState();
    _loadLocationAccuracy();
  }

  Future<void> _loadLocationAccuracy() async {
    final value = await LocationAccuracySettings.loadTargetAccuracyMeters();

    if (!mounted) return;

    setState(() {
      _targetAccuracyMeters = value;
    });
  }

  Future<void> _logout() async {
    await SessionManager.instance.clearSession();

    if (!mounted) return;

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
        const SnackBar(content: Text('Ссылка на магазин будет доступна после публикации')),
      );
    }
  }

  Future<void> _showLocationAccuracyDialog() async {
    var selected = _targetAccuracyMeters;

    final saved = await showDialog<double>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String label(double value) {
              return '${LocationAccuracySettings.formatMeters(value)} м';
            }

            Widget preset(double value) {
              final isSelected = (selected - value).abs() < 0.1;

              return ChoiceChip(
                label: Text(label(value)),
                selected: isSelected,
                showCheckmark: false,
                selectedColor: AppColors.softGreen,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isSelected ? AppColors.primary : AppColors.primaryDark,
                ),
                side: BorderSide.none,
                onSelected: (_) {
                  setDialogState(() => selected = value);
                },
              );
            }

            return Dialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Точность координат',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Чем меньше значение, тем дольше приложение будет уточнять координаты перед сохранением.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        '±${label(selected)}',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Slider(
                      value: selected,
                      min: LocationAccuracySettings.minTargetAccuracyMeters,
                      max: LocationAccuracySettings.maxTargetAccuracyMeters,
                      divisions: 57,
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.border,
                      label: label(selected),
                      onChanged: (value) {
                        setDialogState(() => selected = value.roundToDouble());
                      },
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        preset(5),
                        preset(10),
                        preset(15),
                        preset(25),
                        preset(35),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            await LocationAccuracySettings
                                .resetTargetAccuracyMeters();

                            if (!context.mounted) return;

                            Navigator.of(context).pop(
                              LocationAccuracySettings
                                  .defaultTargetAccuracyMeters,
                            );
                          },
                          child: const Text('Сбросить'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.surface,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop(selected);
                          },
                          child: const Text('Сохранить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == null) return;

    final normalized = LocationAccuracySettings.normalize(saved);
    await LocationAccuracySettings.saveTargetAccuracyMeters(normalized);

    if (!mounted) return;

    setState(() {
      _targetAccuracyMeters = normalized;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Требуемая точность: ±${LocationAccuracySettings.formatMeters(normalized)} м',
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WildNote',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Приложение для регистрации полевых наблюдений редких растений и отправки данных на геопортал.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Версия: $_version',
                  style: TextStyle(color: AppColors.muted),
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
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _divider() {
    return const Divider(height: 1, color: AppColors.border);
  }

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? AppColors.primaryDark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 23, color: color ?? AppColors.primary),
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
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
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
    required ValueChanged<bool> onChanged,
  }) {
    return _row(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        activeThumbColor: AppColors.primary,
        onChanged: onChanged,
      ),
    );
  }

  Widget _accentPicker() {
    const colors = <Color>[
      Color(0xFF5D7B79),
      Color(0xFF2E7D32),
      Color(0xFF1565C0),
      Color(0xFF6D4C41),
      Color(0xFF8E5A7A),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(35, 2, 0, 12),
      child: Row(
        children: colors.map((color) {
          final isSelected = color == _selectedAccent;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Semantics(
              selected: isSelected,
              child: InkWell(
                onTap: () => setState(() => _selectedAccent = color),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isGuest ? 'Гость' : widget.userLogin;

    return SafeArea(
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
                icon: Icons.logout_rounded,
                title: 'Выйти',
                color: AppColors.danger,
                onTap: _logout,
              ),
            ],
          ),
          _section(
            title: 'Внешний вид',
            children: [
              _switchRow(
                icon: Icons.dark_mode_outlined,
                title: 'Тёмная тема',
                subtitle: 'Заготовка для будущего переключения темы',
                value: _darkTheme,
                onChanged: (value) => setState(() => _darkTheme = value),
              ),
              _divider(),
              _row(
                icon: Icons.palette_outlined,
                title: 'Акцент приложения',
                subtitle: 'Выбранный цвет будет использоваться после подключения общей темы',
              ),
              _accentPicker(),
            ],
          ),
          _section(
            title: 'Полевой режим',
            children: [
              _row(
                icon: Icons.gps_fixed_rounded,
                title: 'Точность координат',
                subtitle:
                'Сейчас: ±${LocationAccuracySettings.formatMeters(_targetAccuracyMeters)} м. Чем точнее, тем дольше ожидание.',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                ),
                onTap: _showLocationAccuracyDialog,
              ),
              _divider(),
              _switchRow(
                icon: Icons.contrast_rounded,
                title: 'Автоконтрастность',
                subtitle: 'Будет повышать читаемость интерфейса на ярком солнце',
                value: _autoContrast,
                onChanged: (value) => setState(() => _autoContrast = value),
              ),
              _divider(),
              _switchRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Автояркость',
                subtitle: 'Заготовка для управления яркостью после реализации датчиков',
                value: _autoBrightness,
                onChanged: (value) => setState(() => _autoBrightness = value),
              ),
            ],
          ),
          _section(
            title: 'Приложение',
            children: [
              _row(
                icon: Icons.info_outline_rounded,
                title: 'Справка и версия',
                subtitle: 'Версия $_version',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                onTap: _showAbout,
              ),
              _divider(),
              _row(
                icon: Icons.star_outline_rounded,
                title: 'Оценить приложение',
                trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.muted),
                onTap: _rateApp,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
