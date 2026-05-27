import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  final String userLogin;
  final bool isGuest;
  final String? accessToken;
  final String? remoteFolder;

  final int? userFolderId;
  final int? userLayerId;
  final int? userStyleId;
  final int? webMapId;

  const UserSession({
    required this.userLogin,
    required this.isGuest,
    this.accessToken,
    this.remoteFolder,
    this.userFolderId,
    this.userLayerId,
    this.userStyleId,
    this.webMapId,
  });

  UserSession copyWith({
    String? userLogin,
    bool? isGuest,
    String? accessToken,
    String? remoteFolder,
    int? userFolderId,
    int? userLayerId,
    int? userStyleId,
    int? webMapId,
  }) {
    return UserSession(
      userLogin: userLogin ?? this.userLogin,
      isGuest: isGuest ?? this.isGuest,
      accessToken: accessToken ?? this.accessToken,
      remoteFolder: remoteFolder ?? this.remoteFolder,
      userFolderId: userFolderId ?? this.userFolderId,
      userLayerId: userLayerId ?? this.userLayerId,
      userStyleId: userStyleId ?? this.userStyleId,
      webMapId: webMapId ?? this.webMapId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userLogin': userLogin,
      'isGuest': isGuest,
      'accessToken': accessToken,
      'remoteFolder': remoteFolder,
      'userFolderId': userFolderId,
      'userLayerId': userLayerId,
      'userStyleId': userStyleId,
      'webMapId': webMapId,
    };
  }

  factory UserSession.fromMap(Map<String, dynamic> map) {
    return UserSession(
      userLogin: (map['userLogin'] ?? '').toString().trim(),
      isGuest: map['isGuest'] == true,
      accessToken: map['accessToken'] as String?,
      remoteFolder: map['remoteFolder'] as String?,
      userFolderId: _toInt(map['userFolderId']),
      userLayerId: _toInt(map['userLayerId']),
      userStyleId: _toInt(map['userStyleId']),
      webMapId: _toInt(map['webMapId']),
    );
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class SessionManager {
  SessionManager._privateConstructor();
  static final SessionManager instance = SessionManager._privateConstructor();

  static const String _sessionKey = 'wildnote_user_session';
  static const Duration _prefsTimeout = Duration(seconds: 3);

  Future<SharedPreferences?> _prefsSafe() async {
    try {
      return await SharedPreferences.getInstance().timeout(_prefsTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(UserSession session) async {
    final prefs = await _prefsSafe();
    if (prefs == null) return;
    await prefs.setString(_sessionKey, jsonEncode(session.toMap()));
  }

  Future<UserSession?> getSession() async {
    final prefs = await _prefsSafe();
    if (prefs == null) return null;

    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(_sessionKey);
        return null;
      }

      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final session = UserSession.fromMap(map);
      if (session.userLogin.trim().isEmpty) {
        await prefs.remove(_sessionKey);
        return null;
      }
      return session;
    } catch (_) {
      await prefs.remove(_sessionKey);
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await _prefsSafe();
    if (prefs == null) return;
    await prefs.remove(_sessionKey);
  }
}
