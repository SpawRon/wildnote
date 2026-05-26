import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AppLogLevel {
  debug,
  info,
  warning,
  error,
}

class AppLogger {
  AppLogger._privateConstructor();

  static final AppLogger instance = AppLogger._privateConstructor();

  static const int _maxMemoryLines = 900;
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxFileLinesAfterRotation = 3500;

  final List<String> _memoryLines = <String>[];
  final List<String> _pendingLines = <String>[];

  File? _file;
  bool _initialized = false;
  bool _isFlushing = false;
  Timer? _flushTimer;

  Future<void> init() async {
    if (_initialized) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      _file = File('${logsDir.path}/wildnote.log');
      if (!await _file!.exists()) {
        await _file!.create(recursive: true);
      }

      _initialized = true;
      info('AppLogger', 'Logger initialized', data: {'path': _file!.path});
    } catch (e, st) {
      debugPrint('APP LOGGER INIT ERROR: $e');
      debugPrint(st.toString());
    }
  }

  void debug(
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    log(scope, message, level: AppLogLevel.debug, data: data);
  }

  void info(
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    log(scope, message, level: AppLogLevel.info, data: data);
  }

  void warning(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    log(
      scope,
      message,
      level: AppLogLevel.warning,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    log(
      scope,
      message,
      level: AppLogLevel.error,
      error: error,
      stackTrace: stackTrace,
      data: data,
    );
  }

  void log(
    String scope,
    String message, {
    AppLogLevel level = AppLogLevel.info,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    final now = DateTime.now().toIso8601String();
    final levelText = level.name.toUpperCase();
    final buffer = StringBuffer()
      ..write('[$now] ')
      ..write('[$levelText] ')
      ..write('[$scope] ')
      ..write(_sanitize(message));

    if (data != null && data.isNotEmpty) {
      buffer.write(' data=');
      buffer.write(_encodeData(data));
    }

    if (error != null) {
      buffer.write(' error=');
      buffer.write(_sanitize(error.toString()));
    }

    if (stackTrace != null) {
      final stackLines = stackTrace
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(8)
          .join(' | ');
      buffer.write(' stack=');
      buffer.write(_sanitize(stackLines));
    }

    final line = buffer.toString();

    _memoryLines.add(line);
    if (_memoryLines.length > _maxMemoryLines) {
      _memoryLines.removeRange(0, _memoryLines.length - _maxMemoryLines);
    }

    _pendingLines.add(line);

    if (kDebugMode || level == AppLogLevel.error) {
      debugPrint(line);
    }

    _scheduleFlush();
  }

  Future<String> readRecent({
    Duration window = const Duration(hours: 1),
    int maxLines = 700,
  }) async {
    await init();

    final cutoff = DateTime.now().subtract(window);
    final file = _file;

    final lines = <String>[];

    if (file != null && await file.exists()) {
      try {
        final all = await file.readAsLines();
        for (final line in all.reversed) {
          final dt = _dateFromLine(line);
          if (dt == null || dt.isAfter(cutoff)) {
            lines.add(line);
          }
          if (lines.length >= maxLines) break;
        }
      } catch (e) {
        lines.addAll(_memoryLines.reversed.take(maxLines));
      }
    } else {
      lines.addAll(_memoryLines.reversed.take(maxLines));
    }

    final ordered = lines.reversed.toList();
    if (ordered.isEmpty) {
      return 'Лог пуст. Попробуйте повторить действие и открыть лог снова.';
    }

    return ordered.join('\n');
  }

  Future<String> readAll({
    int maxLines = 2000,
  }) async {
    await init();

    final file = _file;
    if (file == null || !await file.exists()) {
      return _memoryLines.take(maxLines).join('\n');
    }

    final all = await file.readAsLines();
    final start = all.length > maxLines ? all.length - maxLines : 0;
    return all.sublist(start).join('\n');
  }

  Future<void> clear() async {
    _memoryLines.clear();
    _pendingLines.clear();

    final file = _file;
    if (file != null && await file.exists()) {
      await file.writeAsString('');
    }

    info('AppLogger', 'Log cleared');
  }

  Future<void> flush() async {
    if (_isFlushing) return;
    if (_pendingLines.isEmpty) return;

    _isFlushing = true;
    final batch = List<String>.from(_pendingLines);
    _pendingLines.clear();

    try {
      await init();

      final file = _file;
      if (file == null) return;

      await _rotateIfNeeded(file);
      await file.writeAsString(
        '${batch.join('\n')}\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (e, st) {
      debugPrint('APP LOGGER FLUSH ERROR: $e');
      debugPrint(st.toString());
    } finally {
      _isFlushing = false;

      if (_pendingLines.isNotEmpty) {
        _scheduleFlush();
      }
    }
  }

  void _scheduleFlush() {
    if (_file == null) return;

    _flushTimer ??= Timer(const Duration(milliseconds: 500), () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> _rotateIfNeeded(File file) async {
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      if (length <= _maxFileBytes) return;

      final lines = await file.readAsLines();
      final start = lines.length > _maxFileLinesAfterRotation
          ? lines.length - _maxFileLinesAfterRotation
          : 0;

      final kept = lines.sublist(start);
      await file.writeAsString('${kept.join('\n')}\n');
    } catch (_) {
      // Ротация лога не должна ломать приложение.
    }
  }

  DateTime? _dateFromLine(String line) {
    if (!line.startsWith('[')) return null;
    final end = line.indexOf(']');
    if (end <= 1) return null;
    return DateTime.tryParse(line.substring(1, end));
  }

  String _encodeData(Map<String, Object?> data) {
    final safe = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key.toLowerCase().contains('token') ||
          key.toLowerCase().contains('password') ||
          key.toLowerCase().contains('auth')) {
        safe[key] = '***';
      } else {
        safe[key] = value;
      }
    }

    try {
      return _sanitize(jsonEncode(safe));
    } catch (_) {
      return _sanitize(safe.toString());
    }
  }

  String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'Basic\s+[A-Za-z0-9+/=]+'), 'Basic ***')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
  }
}
