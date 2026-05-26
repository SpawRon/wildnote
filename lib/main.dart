import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/main_home_screen.dart';
import 'services/app_appearance_settings.dart';
import 'services/app_logger.dart';
import 'services/device_brightness_service.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await AppLogger.instance.init().timeout(const Duration(seconds: 2));
  } catch (_) {
    // Логгер не должен блокировать запуск.
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.instance.error(
      'FlutterError',
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.error(
      'PlatformDispatcher',
      'Unhandled platform error',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  runZonedGuarded<void>(
        () {
      AppLogger.instance.info('Main', 'Application started');
      runApp(const WildNoteApp());
    },
        (Object error, StackTrace stack) {
      AppLogger.instance.error(
        'Zone',
        'Unhandled zone error',
        error: error,
        stackTrace: stack,
      );
    },
  );
}

class WildNoteApp extends StatefulWidget {
  const WildNoteApp({super.key});

  @override
  State<WildNoteApp> createState() => _WildNoteAppState();
}

class _WildNoteAppState extends State<WildNoteApp> {
  final AppAppearanceController _appearanceController =
      AppAppearance.controller;

  @override
  void initState() {
    super.initState();

    _appearanceController.addListener(_applyDeviceBrightness);
    unawaited(_appearanceController.load());
  }

  void _applyDeviceBrightness() {
    unawaited(
      DeviceBrightnessService.instance.applyAutoBrightness(
        _appearanceController.autoBrightness,
      ),
    );
  }

  @override
  void dispose() {
    _appearanceController.removeListener(_applyDeviceBrightness);
    unawaited(DeviceBrightnessService.instance.applyAutoBrightness(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearanceController,
      builder: (context, _) {
        final data = _appearanceController.data;

        return MaterialApp(
          title: 'WildNote',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(
            brightness: data.darkTheme ? Brightness.dark : Brightness.light,
            accent: data.accentColor,
            highContrast: data.autoContrast,
          ),
          home: _StartupGate(
            appearanceController: _appearanceController,
          ),
        );
      },
    );
  }
}

class _StartupGate extends StatefulWidget {
  final AppAppearanceController appearanceController;

  const _StartupGate({
    required this.appearanceController,
  });

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<UserSession?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _loadSession();
  }

  Future<UserSession?> _loadSession() async {
    try {
      final session = await SessionManager.instance
          .getSession()
          .timeout(const Duration(seconds: 4), onTimeout: () => null);

      AppLogger.instance.info(
        'StartupGate',
        'Session loading completed',
        data: {
          'hasSession': session != null,
          'isGuest': session?.isGuest,
          'userLogin': session?.userLogin,
          'hasAccessToken': session?.accessToken != null,
          'userLayerId': session?.userLayerId,
        },
      );

      return session;
    } catch (e, st) {
      AppLogger.instance.error(
        'StartupGate',
        'Session loading failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserSession?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = snapshot.data;
        if (session == null) {
          return const LoginScreen();
        }

        return MainHomeScreen(
          isGuest: session.isGuest,
          userLogin: session.userLogin,
          appearanceController: widget.appearanceController,
        );
      },
    );
  }
}
