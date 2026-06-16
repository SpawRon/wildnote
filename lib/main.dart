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

  unawaited(
    AppLogger.instance
        .init()
        .timeout(const Duration(seconds: 2))
        .catchError((_) {}),
  );

  void safeLogError(
      String source,
      String message, {
        Object? error,
        StackTrace? stackTrace,
      }) {
    try {
      AppLogger.instance.error(
        source,
        message,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      // ошибки логгера не должны мешать запуску приложения
    }
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    safeLogError(
      'FlutterError',
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    safeLogError(
      'PlatformDispatcher',
      'Unhandled platform error',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  runZonedGuarded<void>(
        () {
      try {
        AppLogger.instance.info('Main', 'Application started');
      } catch (_) {}
      runApp(const WildNoteApp());
    },
        (Object error, StackTrace stack) {
      safeLogError(
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

class _WildNoteAppState extends State<WildNoteApp> with WidgetsBindingObserver {
  final AppAppearanceController _appearanceController =
      AppAppearance.controller;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _appearanceController.addListener(_applyDeviceBrightness);

    unawaited(
      _appearanceController.load().whenComplete(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _applyDeviceBrightness();
          }
        });
      }),
    );
  }

  void _applyDeviceBrightness() {
    final data = _appearanceController.data;

    unawaited(
      DeviceBrightnessService.instance.applyAdaptiveSettings(
        autoBrightness: data.autoBrightness,
        autoContrast: data.autoContrast,
        darkTheme: data.darkTheme,
        onSunlightContrastChanged: _appearanceController.setSunlightContrast,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(DeviceBrightnessService.instance.resetForBackground());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _applyDeviceBrightness();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appearanceController.removeListener(_applyDeviceBrightness);
    unawaited(DeviceBrightnessService.instance.stop());
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
          themeAnimationDuration: Duration.zero,
          themeAnimationCurve: Curves.linear,
          theme: AppTheme.build(
            brightness: data.darkTheme ? Brightness.dark : Brightness.light,
            accent: data.accentColor,
            highContrast: data.autoContrast,
            sunlightContrast: data.sunlightContrast,
            fieldMode: data.largeButtons,
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
