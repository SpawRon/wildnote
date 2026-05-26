import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/database_helper.dart';
import '../services/geoportal_api_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'main_home_screen.dart';

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
        title: Text('Доступ к системе'),
        content: Text(
          'Авторизация происходит через единую систему геопортала МАУ.\n\n'
              'Для получения логина и пароля обратитесь к руководителю практики или администратору кафедры ИТ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Понятно'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
        builder: (_) => const MainHomeScreen(isGuest: true, userLogin: 'guest'),
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
          builder: (_) => MainHomeScreen(isGuest: false, userLogin: resolvedLogin),
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
      backgroundColor: WildColors.of(context).background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 30),
              Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.7,
                  // 1. Уменьшили высоту до 15% от экрана, чтобы он не занимал полстраницы
                  height: MediaQuery.of(context).size.height * 0.15,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  // 2. Align прижимает рисунок к верхнему краю контейнера
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SvgPicture.asset(
                      'assets/mlogo.svg',
                      fit: BoxFit.contain,
                      colorFilter: ColorFilter.mode(
                        WildColors.of(context).primary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 28),
              Text(
                'Добро\nпожаловать',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  color: WildColors.of(context).primaryDark,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Полевые наблюдения редких растений и отправка данных на геопортал МАУ.',
                style: TextStyle(fontSize: 16, height: 1.35, color: WildColors.of(context).muted),
              ),
              SizedBox(height: 34),
              TextField(
                controller: _loginController,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Логин',
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Пароль',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showAccountInfoDialog(context),
                  icon: Icon(Icons.help_outline, size: 18),
                  label: Text('Доступ'),
                ),
              ),
              SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _login,
                icon: _isLoading
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : Icon(Icons.login),
                label: Text(_isLoading ? 'Вход...' : 'Войти'),
              ),
              SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _loginAsGuest,
                icon: Icon(Icons.cloud_off_outlined),
                label: Text('Гостевой режим'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
