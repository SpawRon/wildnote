import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/main_home_screen.dart';
import 'services/app_logger.dart';
import 'services/session_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogger.instance.init();

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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<UserSession?> _sessionFuture;

  @override
  void initState() {
    super.initState();

    AppLogger.instance.info('StartupGate', 'Loading saved session');
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
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final session = snapshot.data;
        if (session == null) {
          AppLogger.instance.info(
            'StartupGate',
            'Opening LoginScreen',
          );

          return const LoginScreen();
        }

        AppLogger.instance.info(
          'StartupGate',
          'Opening MainHomeScreen',
          data: {
            'userLogin': session.userLogin,
            'isGuest': session.isGuest,
          },
        );

        return MainHomeScreen(
          isGuest: session.isGuest,
          userLogin: session.userLogin,
        );
      },
    );
  }
}