import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/geoportal_api_service.dart';
import '../services/session_manager.dart';
import 'main_home_screen.dart';
import '../data/database_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showAccountInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Доступ к системе'),
        content: const Text(
          'Авторизация происходит через единую систему геопортала МАУ.\n\n'
              'Для получения логина и пароля обратитесь к руководителю практики или администратору кафедры ИТ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _loginAsGuest() async {
    final session = const UserSession(
      userLogin: 'guest',
      isGuest: true,
      accessToken: null,
      remoteFolder: 'local_only',
      userFolderId: null,
      userLayerId: null,
      userStyleId: null,
      webMapId: null,
    );

    await SessionManager.instance.saveSession(session);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainHomeScreen(
          isGuest: true,
          userLogin: 'guest',
        ),
      ),
    );
  }

  Future<void> _login() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text.trim();

    if (login.isEmpty || password.isEmpty) {
      _showMessage('Введите логин и пароль');
      return;
    }

    setState(() => _isLoading = true);

    final loginResult = await GeoportalApiService.instance.login(
      login: login,
      password: password,
    );

    if (!mounted) return;

    if (!loginResult.success || loginResult.accessToken == null) {
      setState(() => _isLoading = false);
      _showMessage(loginResult.error ?? 'Ошибка входа');
      return;
    }

    final resolvedLogin = loginResult.userKeyname ?? login;

    try {
      final workspace = await GeoportalApiService.instance.ensureUserWorkspace(
        login: resolvedLogin,
        auth: loginResult.accessToken!,
      );

      final session = UserSession(
        userLogin: resolvedLogin,
        isGuest: false,
        accessToken: loginResult.accessToken,
        remoteFolder: workspace.folderPath,
        userFolderId: workspace.folderId,
        userLayerId: workspace.layerId,
        userStyleId: workspace.styleId,
        webMapId: workspace.webMapId,
      );

      await SessionManager.instance.saveSession(session);

      await DatabaseHelper.instance.saveUserResources(
        userLogin: resolvedLogin,
        userFolderId: workspace.folderId,
        userLayerId: workspace.layerId,
        userStyleId: workspace.styleId,
        webMapId: workspace.webMapId,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainHomeScreen(
            isGuest: false,
            userLogin: resolvedLogin,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Не удалось подготовить рабочее пространство: $e');
    }
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
              SvgPicture.asset(
                'assets/mlogo.svg',
                height: 60,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF5D7B79),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Добро\nпожаловать!',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'WildNote - приложение для отправки данных редких растений на геопортал МАУ',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _loginController,
                decoration: const InputDecoration(hintText: 'Логин'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Войти', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: const BorderSide(
                    color: Color(0xFF5D7B79),
                    width: 1.5,
                  ),
                ),
                onPressed: _isLoading ? null : _loginAsGuest,
                child: const Text(
                  'Продолжить как гость (офлайн)',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}