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
}
