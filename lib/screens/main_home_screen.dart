import 'package:flutter/material.dart';
import 'add_plant_screen.dart';
import 'history_screen.dart';

class MainHomeScreen extends StatefulWidget {
  final bool isGuest;
  const MainHomeScreen({super.key, required this.isGuest});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      AddPlantScreen(isGuest: widget.isGuest),
      HistoryScreen(isGuest: widget.isGuest),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: const Color(0xFF5D7B79),
        unselectedItemColor: Colors.grey,
        backgroundColor: Theme.of(context).colorScheme.background,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.local_florist), label: 'Добавить'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'История'),
        ],
      ),
    );
  }
}