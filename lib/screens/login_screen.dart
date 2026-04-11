import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'main_home_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _showAccountInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Доступ к системе'),
        content: const Text(
            'Авторизация происходит через единую систему геопортала МАУ.\n\n'
                'Для получения логина и пароля обратитесь к руководителю практики или администратору кафедры ИТ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  // Переход на главный экран (имитация входа)
  void _login(BuildContext context, bool isGuest) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MainHomeScreen(isGuest: isGuest)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              // ГОСТ Р ИСО 9241-110 - идентификация системы
              SvgPicture.asset(
                'assets/mlogo.svg',
                height: 60,
                colorFilter: const ColorFilter.mode(Color(0xFF5D7B79), BlendMode.srcIn),
              ),
              const SizedBox(height: 20),
              const Text(
                'Добро\nпожаловать!',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, height: 1.1),
              ),
              const SizedBox(height: 12),
              const Text(
                'WildNote - приложение для отправки данных редких растений на геопортал МАУ',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              const TextField(
                decoration: InputDecoration(hintText: 'Логин'),
              ),
              const SizedBox(height: 16),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  suffixIcon: Icon(Icons.visibility_off),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showAccountInfoDialog(context),
                  child: const Text('Нет аккаунта?'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF131D1C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _login(context, false), // Вход как студент/исследователь
                child: const Text('Войти', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: const BorderSide(color: Color(0xFF5D7B79), width: 1.5),
                ),
                onPressed: () => _login(context, true), // Гостевой режим
                child: const Text('Продолжить как гость (офлайн)', style: TextStyle(fontSize: 16),selectionColor: Color(0xFF131D1C)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}