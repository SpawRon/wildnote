import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
void main() {
  runApp(const WildNoteApp());
}

class WildNoteApp extends StatelessWidget {
  const WildNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WildNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D7B79),
          surface: const Color(0xFFEBEAE0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      // Стартовый экран — окно логина
      home: const LoginScreen(),
    );
  }
}