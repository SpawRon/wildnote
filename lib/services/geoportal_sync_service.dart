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


  bool _looksLikeSkippedCreateWarning(String? value) {
    final text = value?.toLowerCase().trim() ?? '';
    if (text.isEmpty) return false;

    return text.contains('новая точка не создана') ||
        text.contains('похожая точка') ||
        text.contains('уже отправлялась ранее') ||
        text.contains('create skipped');
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

    final syncErrorText = observation['sync_error']?.toString();
    final shouldRepairSkippedCreate =
    _looksLikeSkippedCreateWarning(syncErrorText);

    if (status == ObservationStatus.synced &&
        remoteFeatureId != null &&
        !shouldRepairSkippedCreate) {
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

    if (shouldRepairSkippedCreate) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Synced observation will be resent because previous send reused another feature',
        data: {
          'observationId': observationId,
          'oldRemoteFeatureId': remoteFeatureId,
          'syncError': syncErrorText,
        },
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

      if (response.remoteFeatureId == null || response.remoteFeatureId! <= 0) {
        await DatabaseHelper.instance.updateObservationStatus(
          id: observationId,
          status: ObservationStatus.error,
          error: 'Геопортал не вернул ID созданной точки',
        );

        return const SyncResult(
          success: false,
          message: 'Геопортал не вернул ID созданной точки',
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


  Future<SyncResult> syncAttributeOptions({
    required String userLogin,
  }) async {
    final session = await SessionManager.instance.getSession();

    if (session == null || session.isGuest || session.accessToken == null) {
      return const SyncResult(
        success: false,
        message: 'Для синхронизации справочников нужно войти в аккаунт',
      );
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: false,
      );

      final remoteOptions = await GeoportalApiService.instance
          .fetchSharedAttributeOptions(session: workingSession);

      for (final item in remoteOptions) {
        final remoteId = item['remote_id'];
        final key = item['attribute_key']?.toString();
        final value = item['value']?.toString();

        if (remoteId is! int || key == null || value == null) continue;

        final isDeleted = item['is_deleted'] == 1 ||
            item['is_deleted']?.toString() == '1' ||
            item['is_deleted'] == true;

        if (isDeleted) {
          await DatabaseHelper.instance.markAttributeOptionDeleted(
            attributeKey: key,
            value: value,
          );
        } else {
          await DatabaseHelper.instance.saveRemoteAttributeOption(
            attributeKey: key,
            value: value,
            remoteId: remoteId,
            createdBy: item['created_by']?.toString(),
          );
        }
      }

      final dirty = await DatabaseHelper.instance.getUnsyncedAttributeOptions();

      int published = 0;
      int failed = 0;

      for (final item in dirty) {
        final id = item['id'];
        final key = item['attribute_key']?.toString();
        final value = item['value']?.toString();

        if (id is! int || key == null || value == null) continue;

        try {
          final remoteId = await GeoportalApiService.instance
              .publishSharedAttributeOption(
            session: workingSession,
            attributeKey: key,
            value: value,
          );

          await DatabaseHelper.instance.markAttributeOptionSynced(
            id: id,
            remoteId: remoteId,
          );

          published++;
        } catch (e, st) {
          failed++;
          AppLogger.instance.warning(
            'GeoportalSyncService',
            'Attribute option publishing failed',
            error: e,
            stackTrace: st,
            data: {
              'attributeKey': key,
              'value': value,
            },
          );
        }
      }

      return SyncResult(
        success: failed == 0,
        message: 'Справочники обновлены. Получено: ${remoteOptions.length}. Отправлено: $published. Ошибок: $failed',
        sentCount: published,
        failedCount: failed,
      );
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Attribute options sync failed',
        error: e,
        stackTrace: st,
        data: {'userLogin': userLogin},
      );

      return SyncResult(
        success: false,
        message: 'Не удалось синхронизировать справочники: $e',
      );
    }
  }

  Future<SyncResult> publishAttributeOption({
    required String attributeKey,
    required String value,
    required String createdBy,
  }) async {
    await DatabaseHelper.instance.upsertAttributeOption(
      attributeKey: attributeKey,
      value: value,
      createdBy: createdBy,
      syncStatus: 1,
    );

    final session = await SessionManager.instance.getSession();

    if (session == null || session.isGuest || session.accessToken == null) {
      return const SyncResult(
        success: true,
        message: 'Вариант сохранён локально и будет отправлен после входа',
      );
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: false,
      );

      final remoteId = await GeoportalApiService.instance
          .publishSharedAttributeOption(
        session: workingSession,
        attributeKey: attributeKey,
        value: value,
      );

      final dirty = await DatabaseHelper.instance.getUnsyncedAttributeOptions();
      for (final item in dirty) {
        if (item['attribute_key']?.toString() == attributeKey &&
            DatabaseHelper.instance.normalizeOptionValue(
              item['value']?.toString() ?? '',
            ) ==
                DatabaseHelper.instance.normalizeOptionValue(value)) {
          final id = item['id'];
          if (id is int) {
            await DatabaseHelper.instance.markAttributeOptionSynced(
              id: id,
              remoteId: remoteId,
            );
          }
          break;
        }
      }

      return const SyncResult(
        success: true,
        message: 'Вариант добавлен в общий справочник',
      );
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Immediate attribute option publish failed',
        error: e,
        stackTrace: st,
        data: {
          'attributeKey': attributeKey,
          'value': value,
        },
      );

      return SyncResult(
        success: true,
        message: 'Вариант сохранён локально и будет отправлен позже: $e',
      );
    }
  }


  Future<SyncResult> deleteAttributeOption({
    required String attributeKey,
    required String value,
  }) async {
    final trimmed = value.trim();
    if (attributeKey.trim().isEmpty || trimmed.isEmpty) {
      return const SyncResult(
        success: false,
        message: 'Пустой вариант удалить нельзя',
      );
    }

    try {
      final session = await SessionManager.instance.getSession();
      final option = await DatabaseHelper.instance.getAttributeOption(
        attributeKey: attributeKey,
        value: trimmed,
      );

      if (option == null) {
        return const SyncResult(
          success: true,
          message: 'Вариант убран из текущего выбора',
        );
      }

      final isBuiltin = option['is_builtin'] == 1 ||
          option['is_builtin'] == true ||
          option['is_builtin']?.toString() == '1';
      final createdBy = option['created_by']?.toString().trim().toLowerCase();
      final sessionLogin = session?.userLogin.trim().toLowerCase();
      final remoteId = option['remote_id'];
      final hasRemoteId = remoteId != null && remoteId.toString().trim().isNotEmpty;
      final isOwn = sessionLogin != null &&
          sessionLogin.isNotEmpty &&
          createdBy != null &&
          createdBy == sessionLogin;

      if (isBuiltin) {
        return const SyncResult(
          success: false,
          message: 'Заготовленный вариант нельзя удалить из общего списка',
        );
      }

      if (hasRemoteId && !isOwn) {
        return const SyncResult(
          success: false,
          message: 'Чужой вариант нельзя удалить из общего списка',
        );
      }

      await DatabaseHelper.instance.markAttributeOptionDeleted(
        attributeKey: attributeKey,
        value: trimmed,
      );

      if (!hasRemoteId) {
        return const SyncResult(
          success: true,
          message: 'Вариант удалён локально',
        );
      }

      if (session == null || session.isGuest || session.accessToken == null) {
        return const SyncResult(
          success: true,
          message: 'Вариант удалён локально. На сервере он будет убран после входа',
        );
      }

      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: false,
      );

      await GeoportalApiService.instance.deleteSharedAttributeOption(
        session: workingSession,
        attributeKey: attributeKey,
        value: trimmed,
      );

      return const SyncResult(
        success: true,
        message: 'Вариант убран из общего списка',
      );
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalSyncService',
        'Attribute option delete failed',
        error: e,
        stackTrace: st,
        data: {
          'attributeKey': attributeKey,
          'value': trimmed,
        },
      );

      return SyncResult(
        success: false,
        message: 'Не удалось удалить вариант: $e',
      );
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
    final localUuids = <String>{};

    for (final item in local) {
      final remoteIdRaw = item['remote_feature_id'];
      if (remoteIdRaw is num) {
        final remoteId = remoteIdRaw.toInt();
        if (remoteId > 0) {
          localRemoteIds.add(remoteId);
        }
      }
      final localUuid = item['local_uuid']?.toString().trim();
      if (localUuid != null && localUuid.isNotEmpty) {
        localUuids.add(localUuid);
      }
      merged.add(item);
    }

    for (final item in remote) {
      final remoteIdRaw = item['remote_feature_id'];
      if (remoteIdRaw is num) {
        final remoteId = remoteIdRaw.toInt();
        if (remoteId > 0 && localRemoteIds.contains(remoteId)) {
          AppLogger.instance.debug(
            'GeoportalSyncService',
            'Remote history item skipped: already represented by local remote_feature_id',
            data: {'remoteFeatureId': remoteId},
          );
          continue;
        }
      }

      final remoteLocalUuid = item['local_uuid']?.toString().trim();
      if (remoteLocalUuid != null &&
          remoteLocalUuid.isNotEmpty &&
          localUuids.contains(remoteLocalUuid)) {
        AppLogger.instance.debug(
          'GeoportalSyncService',
          'Remote history item skipped: already represented by local_uuid',
          data: {'localUuid': remoteLocalUuid},
        );
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
    final sessionUser = session.userLogin.trim();
    final requestedUser = userLogin.trim();
    if (sessionUser.toLowerCase() != requestedUser.toLowerCase()) {
      return local;
    }

    try {
      final workingSession = await _ensureWorkspace(
        session,
        refreshRemote: false,
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
