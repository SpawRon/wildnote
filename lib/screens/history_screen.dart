import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database_helper.dart';
import '../services/app_logger.dart';
import '../services/geoportal_sync_service.dart';
import '../services/session_manager.dart';
import 'login_screen.dart';

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
      _showMessage('Не удалось обновить историю с сервера. Показаны локальные записи.');
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeveloperLogSheet(
        userLogin: widget.userLogin,
      ),
    );
  }


  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
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
        ? await GeoportalSyncService.instance.deleteRemoteFeatureForCurrentUser(
      remoteFeatureId,
    )
        : await GeoportalSyncService.instance.deleteObservationEverywhere(
      localId ?? 0,
    );

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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Очистить историю',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF131D1C),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _ClearHistoryMode.localOnly),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0B7A75),
                        side: const BorderSide(
                          color: Color(0xFF0B7A75),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        widget.isGuest ? 'Очистить' : 'На устройстве',
                      ),
                    ),
                    if (!widget.isGuest)
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          context,
                          _ClearHistoryMode.localAndServer,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Везде'),
                      ),
                  ],
                ),
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

    final result =
    await GeoportalSyncService.instance.sendObservationById(observationId);

    if (!mounted) return;
    setState(() => _isBusy = false);

    _showMessage(result.message);
    await reload();
  }

  Future<void> _sendAll() async {
    AppLogger.instance.info('HistoryScreen', 'Send all pressed', data: {'userLogin': widget.userLogin});
    setState(() => _isBusy = true);

    final result = await GeoportalSyncService.instance.sendAllPending(
      userLogin: widget.userLogin,
    );

    if (!mounted) return;
    setState(() => _isBusy = false);

    _showMessage(result.message);
    await reload();
  }

  Future<void> _logout(BuildContext context) async {
    AppLogger.instance.info('HistoryScreen', 'Logout pressed', data: {'userLogin': widget.userLogin});
    await SessionManager.instance.clearSession();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  Widget _buildActionButton({
    required String text,
    required VoidCallback? onPressed,
    Color? foregroundColor,
  }) {
    return SizedBox(
      width: 150,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor,
        ),
        child: Text(text),
      ),
    );
  }

  Widget _buildUserBadge() {
    final label = widget.isGuest ? 'Гость' : widget.userLogin;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.isGuest ? Icons.cloud_off : Icons.cloud_done_outlined,
            size: 16,
            color: Colors.blueGrey.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _isBusy ? null : () => _logout(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.logout,
                  size: 18,
                  color: _isBusy ? Colors.grey : Colors.redAccent,
                ),
              ),
            ),
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

  Widget _buildHistoryPreview(String? path) {
    final borderRadius = BorderRadius.circular(8);

    if (_isRemotePath(path)) {
      final headers = _authToken == null || _authToken!.isEmpty
          ? null
          : <String, String>{'Authorization': _authToken!};

      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          path!,
          headers: headers,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.image,
            color: Colors.grey,
          ),
        ),
      );
    }

    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(path),
          width: 72,
          height: 72,
          fit: BoxFit.cover,
        ),
      );
    }

    return const Icon(
      Icons.image,
      color: Colors.grey,
    );
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

  String _formatCoordinates(Map<String, dynamic> item) {
    final lat = _asFiniteDouble(item['latitude']);
    final lon = _asFiniteDouble(item['longitude']);

    if (lat == null ||
        lon == null ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return 'Координаты не найдены';
    }

    return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRecords = _observations.isNotEmpty;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'История',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _openDeveloperLog,
                      icon: const Icon(Icons.description_outlined),
                      tooltip: 'Лог приложения',
                    ),
                  ],
                ),
                _buildUserBadge(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!widget.isGuest)
                  _buildActionButton(
                    text: _isBusy ? 'Отправка...' : 'Отправить всё',
                    onPressed: _isBusy ? null : _sendAll,
                  ),
                _buildActionButton(
                  text: 'Очистить всё',
                  onPressed: (_isBusy || !hasRecords) ? null : _clearAll,
                  foregroundColor: Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _observations.isEmpty
                ? const Center(child: Text('Записей пока нет'))
                : RefreshIndicator(
              onRefresh: reload,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _observations.length,
                itemBuilder: (context, index) {
                  final item = _observations[index];

                  final photos = item['photos'] is List
                      ? List<Map<String, dynamic>>.from(
                    item['photos'] as List,
                  )
                      : <Map<String, dynamic>>[];

                  final hasPhoto = photos.isNotEmpty;
                  final firstPhotoPath = hasPhoto
                      ? (photos.first['uploaded_url'] ??
                      photos.first['url'] ??
                      photos.first['file_path'])
                  as String?
                      : null;
                  final remoteOnly = item['_remote_only'] == true;

                  final status = item['status'] as int? ?? 0;
                  final isManual = (item['is_manual'] as int? ?? 0) == 1;
                  final syncError = item['sync_error'] as String?;

                  IconData statusIcon;
                  Color statusColor;

                  if (status == ObservationStatus.synced) {
                    statusIcon = Icons.cloud_done;
                    statusColor = Colors.green;
                  } else if (status == ObservationStatus.queued) {
                    statusIcon = Icons.schedule_send;
                    statusColor = Colors.blueGrey;
                  } else if (status == ObservationStatus.error) {
                    statusIcon = Icons.error_outline;
                    statusColor = Colors.redAccent;
                  } else {
                    statusIcon = Icons.save;
                    statusColor = Colors.orange;
                  }

                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _buildHistoryPreview(firstPhotoPath),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (item['name'] as String?)?.isNotEmpty ==
                                      true
                                      ? item['name'] as String
                                      : 'Без названия',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(
                                    item['created_at'] as String?,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatCoordinates(item),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (isManual)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Координаты введены вручную',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      statusIcon,
                                      size: 18,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _statusText(status),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                if (syncError != null &&
                                    syncError.trim().isNotEmpty &&
                                    status == ObservationStatus.error)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      syncError,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              if (!widget.isGuest &&
                                  !remoteOnly &&
                                  status != ObservationStatus.synced)
                                IconButton(
                                  onPressed: _isBusy
                                      ? null
                                      : () => _sendOne(
                                    item['id'] as int,
                                  ),
                                  icon: const Icon(
                                    Icons.upload,
                                    color: Colors.blueGrey,
                                  ),
                                  tooltip: 'Отправить',
                                ),
                              IconButton(
                                onPressed: _isBusy
                                    ? null
                                    : () => _deleteObservation(item),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'Удалить',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
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

  const _DeveloperLogSheet({
    required this.userLogin,
  });

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
    setState(() {
      _logFuture = _loadLog();
    });
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лог скопирован')),
    );
  }

  Future<void> _clearLog() async {
    await AppLogger.instance.clear();
    await _reload();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лог очищен')),
    );
  }

  Future<void> _openGithubIssue() async {
    final rawLog = _currentLog.isNotEmpty
        ? _currentLog
        : await AppLogger.instance.readRecent(
      window: const Duration(hours: 1),
      maxLines: 900,
    );

    const maxChars = 7000;
    final log = rawLog.length > maxChars
        ? rawLog.substring(rawLog.length - maxChars)
        : rawLog;

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

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Лог приложения',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Обновить',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Закрыть',
                  ),
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
                  IconButton(
                    onPressed: _clearLog,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Очистить лог',
                  ),
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
                      return Center(
                        child: Text(
                          'Не удалось прочитать лог: ${snapshot.error}',
                        ),
                      );
                    }

                    final log = snapshot.data ?? '';
                    _currentLog = log;

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          log,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
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
    );
  }
}
