import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database_helper.dart';
import '../services/app_logger.dart';
import '../services/geoportal_sync_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'observation_detail_screen.dart';
import '../widgets/wild_page_header.dart';

enum _ClearHistoryMode { localOnly, localAndServer }

class HistoryScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;

  const HistoryScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
  });

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _observations = [];
  String? _authToken;
  bool _isLoading = true;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => _isLoading = true);

    try {
      final session = await SessionManager.instance.getSession();
      final data = await GeoportalSyncService.instance.loadHistoryForUser(
        userLogin: widget.userLogin,
      );

      if (!mounted) return;
      setState(() {
        _authToken = session?.accessToken;
        _observations = data;
        _isLoading = false;
      });
    } catch (e, st) {
      AppLogger.instance.error(
        'HistoryScreen',
        'History reload failed',
        error: e,
        stackTrace: st,
        data: {'userLogin': widget.userLogin},
      );

      final fallback = await DatabaseHelper.instance.getObservations(
        userLogin: widget.userLogin,
      );

      if (!mounted) return;
      setState(() {
        _observations = fallback;
        _isLoading = false;
      });
      _showMessage('История открыта локально');
    }
  }

  Future<void> _openDeveloperLog() async {
    AppLogger.instance.info(
      'HistoryScreen',
      'Developer log opened',
      data: {'userLogin': widget.userLogin},
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeveloperLogSheet(userLogin: widget.userLogin),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;

    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _statusText(int status) {
    switch (status) {
      case ObservationStatus.localOnly:
        return 'Локально';
      case ObservationStatus.queued:
        return 'В очереди';
      case ObservationStatus.synced:
        return 'Отправлено';
      case ObservationStatus.error:
        return 'Ошибка';
      default:
        return 'Неизвестно';
    }
  }

  IconData _statusIcon(int status) {
    switch (status) {
      case ObservationStatus.synced:
        return Icons.cloud_done_rounded;
      case ObservationStatus.queued:
        return Icons.schedule_send_rounded;
      case ObservationStatus.error:
        return Icons.error_outline_rounded;
      default:
        return Icons.save_alt_rounded;
    }
  }

  Color _statusColor(int status) {
    switch (status) {
      case ObservationStatus.synced:
        return AppColors.success;
      case ObservationStatus.queued:
        return AppColors.muted;
      case ObservationStatus.error:
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Future<void> _deleteObservation(Map<String, dynamic> item) async {
    final remoteOnly = item['_remote_only'] == true;
    final localId = item['id'] as int?;
    final remoteFeatureId = item['remote_feature_id'] as int?;

    AppLogger.instance.info(
      'HistoryScreen',
      'Delete observation pressed',
      data: {
        'localId': localId,
        'remoteFeatureId': remoteFeatureId,
        'remoteOnly': remoteOnly,
      },
    );

    setState(() => _isBusy = true);

    final result = remoteOnly && remoteFeatureId != null
        ? await GeoportalSyncService.instance.deleteRemoteFeatureForCurrentUser(remoteFeatureId)
        : await GeoportalSyncService.instance.deleteObservationEverywhere(localId ?? 0);

    if (!mounted) return;
    setState(() => _isBusy = false);

    _showMessage(result.message);
    await reload();
  }

  Future<void> _clearAll() async {
    AppLogger.instance.info(
      'HistoryScreen',
      'Clear all pressed',
      data: {'userLogin': widget.userLogin},
    );

    if (_observations.isEmpty) return;

    final mode = await showDialog<_ClearHistoryMode>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Очистить историю',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Выберите, где удалить записи.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, _ClearHistoryMode.localOnly),
                        child: Text(widget.isGuest ? 'Очистить' : 'У себя'),
                      ),
                    ),
                  ],
                ),
                if (!widget.isGuest) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _ClearHistoryMode.localAndServer),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('Удалить у себя и на геопортале'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (mode == null) return;

    setState(() => _isBusy = true);

    final result = await GeoportalSyncService.instance.clearHistory(
      userLogin: widget.userLogin,
      includeServer: mode == _ClearHistoryMode.localAndServer,
    );

    if (!mounted) return;
    setState(() => _isBusy = false);

    await reload();
    _showMessage(result.message);
  }

  Future<void> _sendOne(int observationId) async {
    AppLogger.instance.info('HistoryScreen', 'Send one pressed', data: {'id': observationId});
    setState(() => _isBusy = true);

    final result = await GeoportalSyncService.instance.sendObservationById(observationId);

    if (!mounted) return;
    setState(() => _isBusy = false);

    _showMessage(result.message);
    await reload();
  }

  Future<void> _sendAll() async {
    AppLogger.instance.info('HistoryScreen', 'Send all pressed', data: {'userLogin': widget.userLogin});
    setState(() => _isBusy = true);

    final result = await GeoportalSyncService.instance.sendAllPending(userLogin: widget.userLogin);

    if (!mounted) return;
    setState(() => _isBusy = false);

    _showMessage(result.message);
    await reload();
  }

  Widget _buildTopIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: onPressed == null ? AppColors.muted.withValues(alpha: 0.5) : color ?? AppColors.primaryDark),
          ),
        ),
      ),
    );
  }

  Widget _buildUserBadge() {
    final label = widget.isGuest ? 'Гость' : widget.userLogin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.isGuest ? Icons.cloud_off_rounded : Icons.cloud_done_outlined,
            size: 17,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),

        ],
      ),
    );
  }

  bool _isRemotePath(String? value) {
    if (value == null) return false;
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Map<String, String>? get _imageHeaders {
    if (_authToken == null || _authToken!.isEmpty) return null;
    return <String, String>{'Authorization': _authToken!};
  }

  Widget _buildImage(String? path, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.surfaceSoft,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppColors.muted),
    );

    final cacheWidth = width == null ? null : (width * 3).round();
    final cacheHeight = height == null ? null : (height * 3).round();

    if (_isRemotePath(path)) {
      return Image.network(
        path!,
        headers: _imageHeaders,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }

    if (path != null && path.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(path),
          width: width,
          height: height,
          fit: BoxFit.cover,
          cacheWidth: width == null ? 240 : (width * 2).round(),
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      );
    }

    return placeholder;
  }

  List<String> _photoPaths(Map<String, dynamic> item) {
    final photos = item['photos'] is List
        ? List<Map<String, dynamic>>.from(item['photos'] as List)
        : <Map<String, dynamic>>[];

    final paths = <String>[];
    for (final photo in photos) {
      final value = photo['uploaded_url'] ?? photo['url'] ?? photo['file_path'];
      final path = value?.toString().trim();
      if (path != null && path.isNotEmpty && !paths.contains(path)) {
        paths.add(path);
      }
    }
    return paths;
  }

  double? _asFiniteDouble(dynamic value) {
    if (value == null) return null;
    double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else {
      parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    }
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _formatCoordinates(Map<String, dynamic> item) {
    final lat = _asFiniteDouble(item['latitude']);
    final lon = _asFiniteDouble(item['longitude']);

    if (lat == null || lon == null || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return 'Координаты не найдены';
    }

    return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
  }

  String _titleFor(Map<String, dynamic> item) {
    final name = item['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;

    final attributes = _attributesFor(item);
    final plantName = attributes[PlantAttributeKeys.plantName]?.toString().trim();
    if (plantName != null && plantName.isNotEmpty) return plantName;

    return 'Без названия';
  }

  String? _descriptionFor(Map<String, dynamic> item) {
    final description = item['description']?.toString().trim();
    if (description != null && description.isNotEmpty) return description;

    final attributes = _attributesFor(item);
    final attrDescription = attributes[PlantAttributeKeys.description]?.toString().trim();
    if (attrDescription != null && attrDescription.isNotEmpty) return attrDescription;

    return null;
  }

  Map<String, dynamic> _attributesFor(Map<String, dynamic> item) {
    final raw = item['attributes'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    final jsonRaw = item['attributes_json'];
    if (jsonRaw is String && jsonRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonRaw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  void _openObservationDetails(Map<String, dynamic> item) {
    final photos = _photoPaths(item);
    final status = _asInt(item['status']) ?? ObservationStatus.localOnly;
    final isManual = _asInt(item['is_manual']) == 1;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ObservationDetailScreen(
          data: ObservationDetailData(
            title: _titleFor(item),
            description: _descriptionFor(item),
            photos: photos,
            attributes: _attributesFor(item),
            imageHeaders: _imageHeaders,
            badges: [
              ObservationDetailBadge(
                icon: Icons.calendar_month_outlined,
                text: _formatDate(item['created_at'] as String?),
              ),
              ObservationDetailBadge(
                icon: _statusIcon(status),
                text: _statusText(status),
                color: _statusColor(status),
              ),
              if (isManual)
                const ObservationDetailBadge(
                  icon: Icons.edit_location_alt_outlined,
                  text: 'Ручной ввод',
                ),
            ],
            technicalRows: [
              MapEntry('Координаты', _formatCoordinates(item)),
              MapEntry(
                'Точность',
                _asFiniteDouble(item['accuracy']) == null
                    ? '—'
                    : '±${_asFiniteDouble(item['accuracy'])!.toStringAsFixed(1)} м',
              ),
              MapEntry('Гаусс X / Y', _gaussText(item)),
              MapEntry('Фото', photos.length.toString()),
              MapEntry('ID объекта', _remoteIdText(item)),
            ],
          ),
        ),
      ),
    );
  }

  String _gaussText(Map<String, dynamic> item) {
    final x = _asFiniteDouble(item['gauss_x']);
    final y = _asFiniteDouble(item['gauss_y']);
    if (x == null || y == null) return '—';
    return '${x.toStringAsFixed(2)} / ${y.toStringAsFixed(2)}';
  }

  String _remoteIdText(Map<String, dynamic> item) {
    final value = _asInt(item['remote_feature_id']) ?? _asInt(item['id']);
    return value == null || value <= 0 ? '—' : value.toString();
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final photos = _photoPaths(item);
    final firstPhoto = photos.isEmpty ? null : photos.first;
    final remoteOnly = item['_remote_only'] == true;
    final status = item['status'] as int? ?? 0;
    final syncError = item['sync_error'] as String?;
    final title = _titleFor(item);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openObservationDetails(item),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _buildImage(firstPhoto, width: 76, height: 76),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 76,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(item['created_at'] as String?),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                _statusIcon(status),
                                size: 17,
                                color: _statusColor(status),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _statusText(status),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (photos.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.photo_library_outlined,
                                  size: 16,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${photos.length}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    children: [
                      if (!widget.isGuest && !remoteOnly && status != ObservationStatus.synced)
                        IconButton(
                          onPressed: _isBusy ? null : () => _sendOne(item['id'] as int),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          tooltip: 'Отправить',
                        ),
                      IconButton(
                        onPressed: _isBusy ? null : () => _deleteObservation(item),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                        ),
                        tooltip: 'Удалить',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (syncError != null &&
            syncError.trim().isNotEmpty &&
            status == ObservationStatus.error)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                syncError,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.danger),
              ),
            ),
          ),
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRecords = _observations.isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          WildPageHeader(
            title: 'История',
            trailing: _buildUserBadge(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
            child: Row(
              children: [
                if (!widget.isGuest) ...[
                  _buildTopIconButton(
                    icon: _isBusy ? Icons.hourglass_top_rounded : Icons.cloud_upload_outlined,
                    onPressed: _isBusy ? null : _sendAll,
                    tooltip: 'Отправить всё',
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                ],
                _buildTopIconButton(
                  icon: Icons.delete_sweep_outlined,
                  onPressed: (_isBusy || !hasRecords) ? null : _clearAll,
                  tooltip: 'Очистить всё',
                  color: AppColors.danger,
                ),
                const SizedBox(width: 10),
                _buildTopIconButton(
                  icon: Icons.description_outlined,
                  onPressed: _openDeveloperLog,
                  tooltip: 'Лог приложения',
                  color: AppColors.primaryDark,
                ),
                const Spacer(),
                _buildTopIconButton(
                  icon: Icons.refresh_rounded,
                  onPressed: _isBusy ? null : reload,
                  tooltip: 'Обновить',
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _observations.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Записей пока нет',
                  style: TextStyle(fontSize: 16, color: AppColors.muted),
                ),
              ),
            )
                : RefreshIndicator(
              onRefresh: reload,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 116),
                itemCount: _observations.length,
                itemBuilder: (context, index) => _buildHistoryCard(_observations[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeveloperLogSheet extends StatefulWidget {
  final String userLogin;

  const _DeveloperLogSheet({required this.userLogin});

  @override
  State<_DeveloperLogSheet> createState() => _DeveloperLogSheetState();
}

class _DeveloperLogSheetState extends State<_DeveloperLogSheet> {
  late Future<String> _logFuture;
  String _currentLog = '';

  @override
  void initState() {
    super.initState();
    _logFuture = _loadLog();
  }

  Future<String> _loadLog() async {
    final log = await AppLogger.instance.readRecent(
      window: const Duration(hours: 1),
      maxLines: 900,
    );
    _currentLog = log;
    return log;
  }

  Future<void> _reload() async {
    setState(() => _logFuture = _loadLog());
  }

  Future<void> _copyLog() async {
    final log = _currentLog.isNotEmpty
        ? _currentLog
        : await AppLogger.instance.readRecent(
      window: const Duration(hours: 1),
      maxLines: 900,
    );

    await Clipboard.setData(ClipboardData(text: log));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Лог скопирован')));
  }

  Future<void> _clearLog() async {
    await AppLogger.instance.clear();
    await _reload();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Лог очищен')));
  }

  Future<void> _openGithubIssue() async {
    final rawLog = _currentLog.isNotEmpty
        ? _currentLog
        : await AppLogger.instance.readRecent(
      window: const Duration(hours: 1),
      maxLines: 900,
    );

    const maxChars = 7000;
    final log = rawLog.length > maxChars ? rawLog.substring(rawLog.length - maxChars) : rawLog;

    final now = DateTime.now().toIso8601String();

    final body = '''
## Что произошло
Опишите проблему здесь.

## Данные
- Пользователь: ${widget.userLogin}
- Время: $now
- Период лога: последний час
- Версия: укажите вручную, если знаете

## Лог
```text
$log
```
''';

    await Clipboard.setData(ClipboardData(text: rawLog));

    final uri = Uri.https(
      'github.com',
      '/SpawRon/wildnote/issues/new',
      {
        'title': 'Проблема WildNote $now',
        'body': body,
      },
    );

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Открыта форма GitHub. Полный лог также скопирован.'
              : 'Не удалось открыть GitHub. Лог скопирован.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          child: Material(
            color: AppColors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.muted.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Лог приложения',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primaryDark),
                        ),
                      ),
                      IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Обновить'),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close), tooltip: 'Закрыть'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyLog,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openGithubIssue,
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text('Проблема'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(onPressed: _clearLog, icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Очистить лог'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FutureBuilder<String>(
                      future: _logFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return Center(child: Text('Не удалось прочитать лог: ${snapshot.error}'));
                        }

                        final log = snapshot.data ?? '';
                        _currentLog = log;

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSoft,
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              log,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
