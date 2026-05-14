import '../data/database_helper.dart';
import 'app_logger.dart';
import 'geoportal_api_service.dart';
import 'session_manager.dart';

class SyncResult {
  final bool success;
  final String message;
  final int sentCount;
  final int failedCount;

  const SyncResult({
    required this.success,
    required this.message,
    this.sentCount = 0,
    this.failedCount = 0,
  });
}

class GeoportalSyncService {
  GeoportalSyncService._privateConstructor();
  static final GeoportalSyncService instance =
  GeoportalSyncService._privateConstructor();

  final Set<int> _sendingObservationIds = <int>{};
  bool _sendAllRunning = false;

  Future<UserSession> _ensureWorkspace(
      UserSession session, {
        bool refreshRemote = false,
      }) async {
    if (session.isGuest || session.accessToken == null) {
      AppLogger.instance.debug(
        'GeoportalSyncService',
        'Skip workspace for guest or empty token',
        data: {'userLogin': session.userLogin, 'isGuest': session.isGuest},
      );
      return session;
    }

    final hasCachedIds = session.userFolderId != null &&
        session.userLayerId != null &&
        session.userStyleId != null &&
        session.webMapId != null;

    if (hasCachedIds && !refreshRemote) {
      AppLogger.instance.debug(
        'GeoportalSyncService',
        'Use cached workspace ids',
        data: {
          'userLogin': session.userLogin,
          'layerId': session.userLayerId,
          'styleId': session.userStyleId,
          'webMapId': session.webMapId,
        },
      );
      return session;
    }

    AppLogger.instance.info(
      'GeoportalSyncService',
      'Ensure remote workspace',
      data: {'userLogin': session.userLogin, 'refreshRemote': refreshRemote},
    );

    final workspace = await GeoportalApiService.instance.ensureUserWorkspace(
      login: session.userLogin,
      auth: session.accessToken!,
    );

    final resolved = session.copyWith(
      remoteFolder: workspace.folderPath,
      userFolderId: workspace.folderId,
      userLayerId: workspace.layerId,
      userStyleId: workspace.styleId,
      webMapId: workspace.webMapId,
    );

    await SessionManager.instance.saveSession(resolved);

    await DatabaseHelper.instance.saveUserResources(
      userLogin: workspace.userLogin,
      userFolderId: workspace.folderId,
      userLayerId: workspace.layerId,
      userStyleId: workspace.styleId,
      webMapId: workspace.webMapId,
    );

    AppLogger.instance.info(
      'GeoportalSyncService',
      'Workspace resolved',
      data: {
        'userLogin': workspace.userLogin,
        'folderId': workspace.folderId,
        'layerId': workspace.layerId,
        'styleId': workspace.styleId,
        'webMapId': workspace.webMapId,
      },
    );

    return resolved;
  }

  Future<SyncResult> sendObservationById(int observationId) async {
    if (!_sendingObservationIds.add(observationId)) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Duplicate send request ignored',
        data: {'observationId': observationId},
      );

      return const SyncResult(
        success: false,
        message: 'Эта запись уже отправляется. Дождитесь завершения.',
      );
    }

    try {
      return await _sendObservationByIdLocked(observationId);
    } finally {
      _sendingObservationIds.remove(observationId);
    }
  }

  Future<SyncResult> _sendObservationByIdLocked(int observationId) async {
    AppLogger.instance.info(
      'GeoportalSyncService',
      'Send observation started',
      data: {'observationId': observationId},
    );

    final session = await SessionManager.instance.getSession();

    if (session == null || session.isGuest) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Send rejected: no active authorized session',
        data: {'observationId': observationId},
      );

      return const SyncResult(
        success: false,
        message: 'Для отправки нужно войти в аккаунт геопортала',
      );
    }

    final workingSession = await _ensureWorkspace(
      session,
      refreshRemote: true,
    );

    final observation =
    await DatabaseHelper.instance.getObservationById(observationId);

    if (observation == null) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Send rejected: observation not found',
        data: {'observationId': observationId},
      );

      return const SyncResult(
        success: false,
        message: 'Запись не найдена',
      );
    }

    if ((observation['user_login'] as String?) != workingSession.userLogin) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Send rejected: observation user mismatch',
        data: {
          'observationId': observationId,
          'observationUser': observation['user_login'],
          'sessionUser': workingSession.userLogin,
        },
      );

      return const SyncResult(
        success: false,
        message: 'Запись принадлежит другому пользователю',
      );
    }

    final status = observation['status'] as int? ?? ObservationStatus.localOnly;
    final remoteFeatureId = observation['remote_feature_id'] as int?;

    AppLogger.instance.info(
      'GeoportalSyncService',
      'Observation loaded for send',
      data: {
        'observationId': observationId,
        'status': status,
        'remoteFeatureId': remoteFeatureId,
        'name': observation['name'],
        'latitude': observation['latitude'],
        'longitude': observation['longitude'],
        'createdAt': observation['created_at'],
      },
    );

    if (status == ObservationStatus.synced && remoteFeatureId != null) {
      AppLogger.instance.info(
        'GeoportalSyncService',
        'Send skipped: already synced',
        data: {
          'observationId': observationId,
          'remoteFeatureId': remoteFeatureId,
        },
      );

      return const SyncResult(
        success: true,
        message: 'Запись уже синхронизирована',
        sentCount: 1,
      );
    }

    final photos = observation['photos'] is List
        ? List<Map<String, dynamic>>.from(observation['photos'] as List)
        : <Map<String, dynamic>>[];

    try {
      AppLogger.instance.info(
        'GeoportalSyncService',
        'Calling GeoportalApiService.createPoint',
        data: {'observationId': observationId, 'photos': photos.length},
      );

      final response = await GeoportalApiService.instance.createPoint(
        session: workingSession,
        observation: observation,
        photos: photos,
      );

      if (!response.success) {
        await DatabaseHelper.instance.updateObservationStatus(
          id: observationId,
          status: ObservationStatus.error,
          error: response.error ?? 'Ошибка отправки',
        );

        AppLogger.instance.error(
          'GeoportalSyncService',
          'Geoportal createPoint returned failure',
          data: {
            'observationId': observationId,
            'error': response.error,
          },
        );

        return SyncResult(
          success: false,
          message: response.error ?? 'Ошибка отправки',
        );
      }

      for (int i = 0; i < photos.length && i < response.photoUrls.length; i++) {
        final photoId = photos[i]['id'] as int;
        await DatabaseHelper.instance.updatePhotoUploadedUrl(
          photoId: photoId,
          uploadedUrl: response.photoUrls[i],
        );
      }

      final String? warning = response.warning;

      await DatabaseHelper.instance.updateObservationStatus(
        id: observationId,
        status: ObservationStatus.synced,
        error: warning,
        remoteFeatureId: response.remoteFeatureId,
        remoteFolder: response.folderPath ?? workingSession.remoteFolder,
        syncedAt: DateTime.now().toIso8601String(),
      );

      AppLogger.instance.info(
        'GeoportalSyncService',
        'Send observation finished',
        data: {
          'observationId': observationId,
          'remoteFeatureId': response.remoteFeatureId,
          'photoUrls': response.photoUrls.length,
          'warning': warning,
        },
      );

      final message = warning == null || warning.isEmpty
          ? 'Точка успешно отправлена'
          : 'Точка отправлена. $warning';

      return SyncResult(
        success: true,
        message: message,
        sentCount: 1,
      );
    } catch (e, st) {
      await DatabaseHelper.instance.updateObservationStatus(
        id: observationId,
        status: ObservationStatus.error,
        error: e.toString(),
      );

      AppLogger.instance.error(
        'GeoportalSyncService',
        'Send observation exception',
        error: e,
        stackTrace: st,
        data: {'observationId': observationId},
      );

      return SyncResult(
        success: false,
        message: 'Ошибка отправки: $e',
      );
    }
  }

  Future<SyncResult> sendAllPending({
    required String userLogin,
  }) async {
    if (_sendAllRunning) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'sendAllPending ignored: already running',
        data: {'userLogin': userLogin},
      );

      return const SyncResult(
        success: false,
        message: 'Массовая отправка уже выполняется',
      );
    }

    _sendAllRunning = true;

    try {
      AppLogger.instance.info(
        'GeoportalSyncService',
        'sendAllPending started',
        data: {'userLogin': userLogin},
      );

      final session = await SessionManager.instance.getSession();

      if (session == null || session.isGuest) {
        return const SyncResult(
          success: false,
          message: 'Для отправки нужно войти в аккаунт',
        );
      }

      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: true,
      );

      if (userLogin.trim().isNotEmpty && userLogin != workingSession.userLogin) {
        return const SyncResult(
          success: false,
          message: 'Активная сессия не совпадает с пользователем записей',
        );
      }

      final pending = await DatabaseHelper.instance.getPendingObservations(
        userLogin: workingSession.userLogin,
      );

      AppLogger.instance.info(
        'GeoportalSyncService',
        'Pending observations loaded',
        data: {
          'userLogin': workingSession.userLogin,
          'count': pending.length,
        },
      );

      if (pending.isEmpty) {
        return const SyncResult(
          success: true,
          message: 'Нет записей для отправки',
        );
      }

      int ok = 0;
      int failed = 0;

      for (final item in pending) {
        final id = item['id'] as int;
        final result = await sendObservationById(id);
        if (result.success) {
          ok++;
        } else {
          failed++;
        }
      }

      AppLogger.instance.info(
        'GeoportalSyncService',
        'sendAllPending finished',
        data: {'ok': ok, 'failed': failed},
      );

      return SyncResult(
        success: failed == 0,
        message: 'Отправлено: $ok. Ошибок: $failed',
        sentCount: ok,
        failedCount: failed,
      );
    } catch (e, st) {
      AppLogger.instance.error(
        'GeoportalSyncService',
        'sendAllPending exception',
        error: e,
        stackTrace: st,
        data: {'userLogin': userLogin},
      );

      return SyncResult(
        success: false,
        message: 'Ошибка массовой отправки: $e',
      );
    } finally {
      _sendAllRunning = false;
    }
  }

  Future<SyncResult> deleteObservationEverywhere(int observationId) async {
    AppLogger.instance.info(
      'GeoportalSyncService',
      'deleteObservationEverywhere started',
      data: {'observationId': observationId},
    );

    final session = await SessionManager.instance.getSession();

    final observation =
    await DatabaseHelper.instance.getObservationById(observationId);

    if (observation == null) {
      return const SyncResult(
        success: false,
        message: 'Запись не найдена',
      );
    }

    final remoteFeatureId = observation['remote_feature_id'] as int?;

    if (session == null || session.isGuest || remoteFeatureId == null) {
      await DatabaseHelper.instance.deleteObservation(observationId);

      AppLogger.instance.info(
        'GeoportalSyncService',
        'Observation deleted locally only',
        data: {'observationId': observationId},
      );

      return const SyncResult(
        success: true,
        message: 'Запись удалена локально',
      );
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: true,
      );

      await GeoportalApiService.instance.deleteFeature(
        session: workingSession,
        featureId: remoteFeatureId,
      );

      await DatabaseHelper.instance.deleteObservation(observationId);

      AppLogger.instance.info(
        'GeoportalSyncService',
        'Observation deleted locally and remotely',
        data: {
          'observationId': observationId,
          'remoteFeatureId': remoteFeatureId,
        },
      );

      return const SyncResult(
        success: true,
        message: 'Запись удалена локально и на сервере',
      );
    } catch (e, st) {
      await DatabaseHelper.instance.updateObservationStatus(
        id: observationId,
        status: ObservationStatus.error,
        error: 'Не удалось удалить на сервере: $e',
      );

      AppLogger.instance.error(
        'GeoportalSyncService',
        'deleteObservationEverywhere exception',
        error: e,
        stackTrace: st,
        data: {
          'observationId': observationId,
          'remoteFeatureId': remoteFeatureId,
        },
      );

      return SyncResult(
        success: false,
        message:
        'Локальная запись оставлена. Удалить точку на сервере не удалось: $e',
      );
    }
  }

  List<Map<String, dynamic>> _mergeLocalAndRemoteHistory(
      List<Map<String, dynamic>> local,
      List<Map<String, dynamic>> remote,
      ) {
    final merged = <Map<String, dynamic>>[];
    final localRemoteIds = <int>{};

    for (final item in local) {
      final remoteId = item['remote_feature_id'];
      if (remoteId is int && remoteId > 0) {
        localRemoteIds.add(remoteId);
      }
      merged.add(item);
    }

    for (final item in remote) {
      final remoteId = item['remote_feature_id'];
      if (remoteId is int && localRemoteIds.contains(remoteId)) {
        continue;
      }

      final copy = Map<String, dynamic>.from(item);
      copy['status'] = ObservationStatus.synced;
      copy['_remote_only'] = true;
      merged.add(copy);
    }

    int compareDates(Map<String, dynamic> a, Map<String, dynamic> b) {
      final ad = DateTime.tryParse((a['created_at'] ?? '').toString());
      final bd = DateTime.tryParse((b['created_at'] ?? '').toString());
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    }

    merged.sort(compareDates);
    return merged;
  }

  Future<List<Map<String, dynamic>>> loadHistoryForUser({
    required String userLogin,
  }) async {
    final local = await DatabaseHelper.instance.getObservations(
      userLogin: userLogin,
    );

    final session = await SessionManager.instance.getSession();
    if (session == null || session.isGuest) {
      return local;
    }
    if (session.userLogin != userLogin) {
      return local;
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: true,
      );

      final remote = await GeoportalApiService.instance.fetchUserLayerHistory(
        session: workingSession,
      );

      AppLogger.instance.info(
        'GeoportalSyncService',
        'History loaded from local and remote sources',
        data: {
          'userLogin': userLogin,
          'localCount': local.length,
          'remoteCount': remote.length,
        },
      );

      return _mergeLocalAndRemoteHistory(local, remote);
    } catch (e, st) {
      AppLogger.instance.error(
        'GeoportalSyncService',
        'Remote history loading failed; local history will be used',
        error: e,
        stackTrace: st,
        data: {'userLogin': userLogin},
      );
      return local;
    }
  }

  Future<SyncResult> deleteRemoteFeatureForCurrentUser(int featureId) async {
    final session = await SessionManager.instance.getSession();
    if (session == null || session.isGuest) {
      return const SyncResult(
        success: false,
        message: 'Для удаления на сервере нужно войти в аккаунт',
      );
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: true,
      );

      await GeoportalApiService.instance.deleteFeature(
        session: workingSession,
        featureId: featureId,
      );

      return const SyncResult(
        success: true,
        message: 'Запись удалена на сервере',
      );
    } catch (e, st) {
      AppLogger.instance.error(
        'GeoportalSyncService',
        'Delete remote-only feature failed',
        error: e,
        stackTrace: st,
        data: {'featureId': featureId},
      );

      return SyncResult(
        success: false,
        message: 'Не удалось удалить запись на сервере: $e',
      );
    }
  }

  Future<SyncResult> clearHistory({
    required String userLogin,
    required bool includeServer,
  }) async {
    if (!includeServer) {
      await DatabaseHelper.instance.clearAllObservations(userLogin: userLogin);
      return const SyncResult(
        success: true,
        message: 'Локальная история очищена',
      );
    }

    final session = await SessionManager.instance.getSession();
    if (session == null || session.isGuest) {
      await DatabaseHelper.instance.clearAllObservations(userLogin: userLogin);
      return const SyncResult(
        success: true,
        message: 'Локальная история очищена',
      );
    }
    if (session.userLogin != userLogin) {
      return const SyncResult(
        success: false,
        message: 'Активная сессия не совпадает с пользователем истории',
      );
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: true,
      );

      final deletedRemote = await GeoportalApiService.instance.deleteAllFeaturesInUserLayer(
        session: workingSession,
      );

      await DatabaseHelper.instance.clearAllObservations(userLogin: userLogin);

      return SyncResult(
        success: true,
        message: 'История очищена на устройстве и на сервере. Удалено точек на сервере: $deletedRemote',
      );
    } catch (e, st) {
      AppLogger.instance.error(
        'GeoportalSyncService',
        'Clear history everywhere failed',
        error: e,
        stackTrace: st,
        data: {'userLogin': userLogin},
      );

      return SyncResult(
        success: false,
        message: 'Не удалось очистить историю на сервере: $e',
      );
    }
  }

}
