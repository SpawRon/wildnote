import 'package:flutter/material.dart';

import 'add_plant_screen.dart';
import 'explorer_screen.dart';
import 'history_screen.dart';

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

  final GlobalKey<HistoryScreenState> _historyKey =
  GlobalKey<HistoryScreenState>();
  final GlobalKey<ExplorerScreenState> _explorerKey =
  GlobalKey<ExplorerScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      AddPlantScreen(
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
        onSaved: () {
          _historyKey.currentState?.reload();
          _explorerKey.currentState?.reload();
        },
      ),
      HistoryScreen(
        key: _historyKey,
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
      ),
      ExplorerScreen(
        key: _explorerKey,
        isGuest: widget.isGuest,
        userLogin: widget.userLogin,
      ),
    ];
  }

  void _onTabTap(int index) {
    setState(() => _currentIndex = index);

    if (index == 1) {
      _historyKey.currentState?.reload();
    } else if (index == 2) {
      _explorerKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
        selectedItemColor: const Color(0xFF5D7B79),
        unselectedItemColor: Colors.grey,
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.local_florist),
            label: 'Добавить',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'История',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Обзор',
          ),
        ],
      ),
    );
  }
}
