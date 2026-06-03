import 'package:flutter/material.dart';

import '../services/app_appearance_settings.dart';
import '../theme/app_theme.dart';
import 'add_plant_screen.dart' as add_screen;
import 'explorer_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class MainHomeScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;
  final AppAppearanceController? appearanceController;

  const MainHomeScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
    this.appearanceController,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final List<Widget?> _screenCache = List<Widget?>.filled(4, null);
  final GlobalKey<HistoryScreenState> _historyKey =
  GlobalKey<HistoryScreenState>();

  late final AppAppearanceController _appearanceController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _appearanceController =
        widget.appearanceController ?? AppAppearance.controller;
  }

  Widget _screenAt(int index) {
    final cached = _screenCache[index];
    if (cached != null) return cached;

    final created = switch (index) {
      0 => add_screen.AddPlantScreen(
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
        onSaved: () => _historyKey.currentState?.reload(),
      ),
      1 => HistoryScreen(
        key: _historyKey,
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
      ),
      2 => ExplorerScreen(
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
      ),
      3 => SettingsScreen(
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
        appearanceController: _appearanceController,
      ),
      _ => const SizedBox.shrink(),
    };

    _screenCache[index] = created;
    return created;
  }

  void _onTabTap(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: List.generate(
                4,
                    (index) => _screenCache[index] ??
                    (index == _currentIndex
                        ? _screenAt(index)
                        : const SizedBox.shrink()),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: bottomSafe + 8,
            child: _WildBottomIslandNav(
              selectedIndex: _currentIndex,
              onDestinationSelected: _onTabTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _WildBottomIslandNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _WildBottomIslandNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Row(
            children: [
              _WildNavItem(
                icon: Icons.local_florist_outlined,
                selectedIcon: Icons.local_florist_rounded,
                label: 'Добавить',
                selected: selectedIndex == 0,
                onTap: () => onDestinationSelected(0),
              ),
              _WildNavItem(
                icon: Icons.article_outlined,
                selectedIcon: Icons.article_rounded,
                label: 'История',
                selected: selectedIndex == 1,
                onTap: () => onDestinationSelected(1),
              ),
              _WildNavItem(
                icon: Icons.map_outlined,
                selectedIcon: Icons.map_rounded,
                label: 'Обзор',
                selected: selectedIndex == 2,
                onTap: () => onDestinationSelected(2),
              ),
              _WildNavItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: 'Настройки',
                selected: selectedIndex == 3,
                onTap: () => onDestinationSelected(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WildNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WildNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = WildColors.of(context);
    final fieldMode = colors.fieldMode;
    final color = selected ? colors.primary : colors.muted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: fieldMode ? Duration.zero : const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: fieldMode ? 58 : 50,
          decoration: BoxDecoration(
            color: selected ? colors.softGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: fieldMode ? (selected ? 25 : 23) : (selected ? 22 : 20),
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fieldMode ? 10.8 : 10,
                  height: 1,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected ? colors.primaryDark : colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
