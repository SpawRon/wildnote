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
      userLogin: map['userLogin'] as String,
      isGuest: map['isGuest'] as bool,
      accessToken: map['accessToken'] as String?,
      remoteFolder: map['remoteFolder'] as String?,
      userFolderId: map['userFolderId'] as int?,
      userLayerId: map['userLayerId'] as int?,
      userStyleId: map['userStyleId'] as int?,
      webMapId: map['webMapId'] as int?,
    );
  }
}

class SessionManager {
  SessionManager._privateConstructor();
  static final SessionManager instance = SessionManager._privateConstructor();

  static const String _sessionKey = 'wildnote_user_session';

  Future<void> saveSession(UserSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toMap()));
  }

  Future<UserSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;

    final map = jsonDecode(raw) as Map<String, dynamic>;
    return UserSession.fromMap(map);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}