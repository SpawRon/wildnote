import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'add_plant_screen.dart';
import 'explorer_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class MainHomeScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;

  const MainHomeScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return AddPlantScreen(
          isGuest: widget.isGuest,
          userLogin: widget.userLogin,
        );
      case 1:
        return HistoryScreen(
          isGuest: widget.isGuest,
          userLogin: widget.userLogin,
        );
      case 2:
        return ExplorerScreen(
          isGuest: widget.isGuest,
          userLogin: widget.userLogin,
        );
      case 3:
        return SettingsScreen(
          isGuest: widget.isGuest,
          userLogin: widget.userLogin,
        );
      default:
        return AddPlantScreen(
          isGuest: widget.isGuest,
          userLogin: widget.userLogin,
        );
    }
  }

  void _onTabTap(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCurrentScreen()),
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
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
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
    final color = selected ? AppColors.primary : AppColors.muted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 50,
          decoration: BoxDecoration(
            color: selected ? AppColors.softGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: selected ? 22 : 20,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected ? AppColors.primaryDark : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
