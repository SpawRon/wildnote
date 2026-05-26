import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/explorer_service.dart' as explorer;
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'observation_detail_screen.dart';
import '../widgets/wild_page_header.dart';

enum ExplorerMode { user, area }

class ExplorerScreen extends StatefulWidget {
  final bool isGuest;
  final String userLogin;

  const ExplorerScreen({
    super.key,
    required this.isGuest,
    required this.userLogin,
  });

  @override
  ExplorerScreenState createState() => ExplorerScreenState();
}

class ExplorerScreenState extends State<ExplorerScreen> {
  static const LatLng _fallbackCenter = LatLng(68.9707, 33.0749);

  final explorer.ExplorerService _service = explorer.ExplorerService.instance;
  final MapController _mapController = MapController();
  final TextEditingController _radiusController =
  TextEditingController(text: '1000');
  final FocusNode _radiusFocusNode = FocusNode();

  UserSession? _session;
  ExplorerMode _mode = ExplorerMode.user;
  bool _isLoading = false;
  List<explorer.ExplorerUserStat> _users = const [];
  List<explorer.ExplorerPoint> _points = const [];
  String? _selectedUser;
  LatLng? _areaCenter;
  double _radiusMeters = 1000;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _radiusFocusNode.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (widget.isGuest) return;

    _session ??= await SessionManager.instance.getSession();
    if (_session == null) return;

    if (_mode == ExplorerMode.user) {
      await _loadUserMode();
    } else {
      await _searchByArea();
    }
  }

  Future<void> _bootstrap() async {
    if (widget.isGuest) {
      setState(() {
        _users = const [];
        _points = const [];
      });
      return;
    }

    _session = await SessionManager.instance.getSession();
    _selectedUser = widget.userLogin.trim().toLowerCase();
    await _loadUserMode();
  }

  Future<void> _loadUserMode() async {
    final session = _session;
    if (session == null) return;

    setState(() => _isLoading = true);

    try {
      final users = await _service.loadUserStats(session: session);

      explorer.ExplorerUserStat? selected;
      final wanted = _selectedUser?.trim().toLowerCase();

      if (wanted != null && wanted.isNotEmpty) {
        for (final user in users) {
          if (user.userLogin == wanted) {
            selected = user;
            break;
          }
        }
      }

      selected ??= users.isNotEmpty ? users.first : null;

      final points = selected == null
          ? const <explorer.ExplorerPoint>[]
          : await _service.loadPointsByUser(
        session: session,
        userLogin: selected.userLogin,
        knownLayerId: selected.layerId,
      );

      if (!mounted) return;

      setState(() {
        _users = users;
        _selectedUser = selected?.userLogin;
        _points = points;
        _isLoading = false;
      });

      _moveMapToRelevantTarget();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Не удалось загрузить точки пользователей: $e');
    }
  }

  Future<void> _searchByArea() async {
    final session = _session;
    if (session == null) return;

    final radius = _readRadiusMeters();
    if (radius == null) return;

    if (_areaCenter == null) {
      await _useCurrentLocation(autoSearch: false, showMessageOnError: true);
      if (_areaCenter == null) return;
    }

    setState(() {
      _radiusMeters = radius;
      _isLoading = true;
    });

    try {
      final center = _areaCenter!;
      final points = await _service.loadPointsByRadius(
        session: session,
        centerLatitude: center.latitude,
        centerLongitude: center.longitude,
        radiusMeters: radius,
      );

      if (!mounted) return;

      setState(() {
        _points = points;
        _isLoading = false;
      });

      _moveMap(center, _zoomForRadius(radius));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Не удалось выполнить поиск по области: $e');
    }
  }

  double? _readRadiusMeters() {
    final raw = _radiusController.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);

    if (value == null || !value.isFinite || value <= 0) {
      _showMessage('Введите корректный радиус в метрах');
      return null;
    }

    return value;
  }

  Future<void> _applyRadiusInput() async {
    final radius = _readRadiusMeters();
    if (radius == null) return;

    if (!mounted) return;

    setState(() => _radiusMeters = radius);
    FocusScope.of(context).unfocus();

    if (_mode == ExplorerMode.area && _areaCenter != null) {
      await _searchByArea();
    }
  }

  Future<void> _useCurrentLocation({
    bool autoSearch = true,
    bool showMessageOnError = false,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showMessageOnError) {
          _showMessage('Включите геолокацию на устройстве');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showMessageOnError) {
          _showMessage('Нет разрешения на геолокацию');
        }
        return;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          _isValidLatLon(lastKnown.latitude, lastKnown.longitude)) {
        final cached = LatLng(lastKnown.latitude, lastKnown.longitude);

        if (mounted) {
          setState(() => _areaCenter = cached);
          _moveMap(cached, _zoomForRadius(_radiusMeters));
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      if (!_isValidLatLon(position.latitude, position.longitude)) {
        if (showMessageOnError) {
          _showMessage('Геолокация вернула некорректные координаты');
        }
        return;
      }

      final point = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() => _areaCenter = point);
      _moveMap(point, _zoomForRadius(_radiusMeters));

      if (autoSearch && _mode == ExplorerMode.area) {
        await _searchByArea();
      }
    } catch (e) {
      if (showMessageOnError) {
        _showMessage('Не удалось определить текущее местоположение: $e');
      }
    }
  }

  void _moveMapToRelevantTarget() {
    final center = _areaCenter;

    if (_mode == ExplorerMode.area && center != null) {
      _moveMap(center, _zoomForRadius(_radiusMeters));
      return;
    }

    if (_points.isNotEmpty) {
      _moveMap(_points.first.latLng, 13.2);
      return;
    }

    _moveMap(_fallbackCenter, 10.0);
  }

  void _moveMap(LatLng target, double zoom) {
    if (!_isValidLatLon(target.latitude, target.longitude)) return;
    if (!zoom.isFinite || zoom <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(target, zoom);
      } catch (_) {
        // Карта может быть ещё не смонтирована.
      }
    });
  }

  double _zoomForRadius(double radiusMeters) {
    if (radiusMeters <= 100) return 16.8;
    if (radiusMeters <= 300) return 15.8;
    if (radiusMeters <= 500) return 15.2;
    if (radiusMeters <= 1000) return 14.3;
    if (radiusMeters <= 3000) return 13.0;
    if (radiusMeters <= 5000) return 12.3;
    if (radiusMeters <= 10000) return 11.3;
    return 10.4;
  }

  bool _isValidLatLon(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  Future<void> _openPointsPicker() async {
    if (_points.isEmpty) {
      _showMessage('Список точек пуст');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Точки (${_points.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 108),
                      itemCount: _points.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final point = _points[index];

                        return Column(
                          children: [
                            ListTile(
                              onTap: () {
                                Navigator.of(context).pop();
                                _moveMap(point.latLng, 15.0);
                                _showPointDetails(point);
                              },
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                point.isManual
                                    ? Icons.edit_location_alt_rounded
                                    : Icons.eco_rounded,
                                color: point.isManual
                                    ? AppColors.danger
                                    : AppColors.primary,
                              ),
                              title: Text(
                                point.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              subtitle: Text(
                                '${point.userLogin}\n${_service.formatDate(point.createdAt)}',
                              ),
                              trailing: point.photoCount > 0
                                  ? Text(
                                '${point.photoCount} фото',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                                  : const Icon(
                                Icons.photo_outlined,
                                color: AppColors.muted,
                              ),
                              isThreeLine: true,
                            ),
                            const Divider(height: 1, color: AppColors.border),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showPointDetails(explorer.ExplorerPoint point) {
    final token = _session?.accessToken;
    final photosFuture = _service.resolvePhotoUrls(
      session: _session,
      point: point,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ObservationDetailScreen(
          data: ObservationDetailData(
            title: point.name,
            description: point.description,
            photos: point.photoUrls,
            photosFuture: photosFuture,
            attributes: point.attributes,
            imageHeaders: token == null || token.isEmpty
                ? null
                : <String, String>{'Authorization': token},
            badges: [
              ObservationDetailBadge(
                icon: Icons.person_outline_rounded,
                text: point.userLogin,
              ),
              ObservationDetailBadge(
                icon: Icons.calendar_month_outlined,
                text: _service.formatDate(point.createdAt),
              ),
              if (point.isManual)
                const ObservationDetailBadge(
                  icon: Icons.edit_location_alt_outlined,
                  text: 'Ручной ввод',
                ),
            ],
            technicalRows: [
              MapEntry(
                'Координаты',
                '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
              ),
              MapEntry(
                'Точность',
                point.accuracy == null
                    ? '—'
                    : '±${point.accuracy!.toStringAsFixed(1)} м',
              ),
              MapEntry(
                'Гаусс X / Y',
                point.gaussX == null || point.gaussY == null
                    ? '—'
                    : '${point.gaussX!.toStringAsFixed(2)} / ${point.gaussY!.toStringAsFixed(2)}',
              ),
              MapEntry('Фото', point.photoCount.toString()),
              MapEntry(
                'ID объекта',
                point.remoteFeatureId > 0 ? point.remoteFeatureId.toString() : '—',
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPointsLauncherCard() {
    if (_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final title = _points.isEmpty
        ? 'Ничего не найдено'
        : 'Найдено точек: ${_points.length}';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: _points.isEmpty ? null : _openPointsPicker,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Icon(
                _points.isEmpty
                    ? Icons.search_off_rounded
                    : Icons.format_list_bulleted_rounded,
                color: _points.isEmpty ? AppColors.muted : AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              if (_points.isNotEmpty)
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) {
      return const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Вкладка обзора доступна только после входа в аккаунт геопортала.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    final radiusValid = _radiusMeters.isFinite && _radiusMeters > 0;
    final areaCenter = _areaCenter;
    final areaCenterValid = areaCenter != null &&
        _isValidLatLon(areaCenter.latitude, areaCenter.longitude);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          20,
          AppSpacing.screen,
          116,
        ),
        children: [
          WildPageHeader(
            title: 'Обзор данных',
            padding: EdgeInsets.zero,
            trailing: IconButton(
              onPressed: _isLoading ? null : reload,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Обновить',
            ),
          ),
          const SizedBox(height: 14),
          _buildModeSelector(),
          const SizedBox(height: 14),
          _mode == ExplorerMode.user
              ? _buildUserModeContent()
              : _buildAreaModeContent(),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _fallbackCenter,
                    initialZoom: 10.5,
                    onTap: (tapPosition, point) async {
                      if (_mode != ExplorerMode.area) return;
                      if (!_isValidLatLon(point.latitude, point.longitude)) {
                        return;
                      }

                      setState(() => _areaCenter = point);
                      await _searchByArea();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ru.mauniver.wildnote',
                    ),
                    if (_mode == ExplorerMode.area &&
                        areaCenterValid &&
                        radiusValid)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: areaCenter,
                            radius: _radiusMeters,
                            useRadiusInMeter: true,
                            color: const Color(0x335D7B79),
                            borderColor: AppColors.primary,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_mode == ExplorerMode.area && areaCenterValid)
                          Marker(
                            point: areaCenter,
                            width: 34,
                            height: 34,
                            child: const Icon(
                              Icons.my_location,
                              color: Color(0xFF1E88E5),
                              size: 28,
                            ),
                          ),
                        ..._points
                            .where(
                              (point) => _isValidLatLon(
                            point.latitude,
                            point.longitude,
                          ),
                        )
                            .map(_buildMarker),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _modeButton(
            title: 'Пользователь',
            icon: Icons.person_outline_rounded,
            selected: _mode == ExplorerMode.user,
            onTap: () async {
              if (_mode == ExplorerMode.user) return;
              setState(() => _mode = ExplorerMode.user);
              await _loadUserMode();
            },
          ),
          _modeButton(
            title: 'Область',
            icon: Icons.radar_rounded,
            selected: _mode == ExplorerMode.area,
            onTap: () async {
              if (_mode == ExplorerMode.area) return;
              setState(() => _mode = ExplorerMode.area);
              await _searchByArea();
            },
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: selected ? AppColors.softGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? AppColors.primaryDark : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserModeContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Пользователи',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 10),
          if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Пользовательские слои не найдены',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _users.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final selected = user.userLogin == _selectedUser;

                  return InkWell(
                    onTap: () async {
                      setState(() => _selectedUser = user.userLogin);
                      await _loadUserMode();
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.softGreen : AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${user.userLogin} · ${user.pointsCount}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: selected ? AppColors.primaryDark : AppColors.muted,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _buildPointsLauncherCard(),
        ],
      ),
    );
  }

  Widget _buildAreaModeContent() {
    final center = _areaCenter;

    final radiusText = _radiusMeters.toStringAsFixed(
      _radiusMeters.truncateToDouble() == _radiusMeters ? 0 : 1,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Поиск по области',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            center == null
                ? 'Выберите центр поиска кнопкой или нажатием на карту'
                : 'Центр: ${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}\nРадиус: $radiusText м · найдено: ${_points.length}',
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _radiusController,
                  focusNode: _radiusFocusNode,
                  textInputAction: TextInputAction.done,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onSubmitted: (_) => _applyRadiusInput(),
                  onTapOutside: (_) => _applyRadiusInput(),
                  decoration: const InputDecoration(
                    hintText: 'Радиус, м',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Моё местоположение',
                onPressed: _isLoading ? null : _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
              ),
              IconButton(
                tooltip: 'Искать',
                onPressed: _isLoading ? null : _searchByArea,
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPointsLauncherCard(),
        ],
      ),
    );
  }

  Marker _buildMarker(explorer.ExplorerPoint point) {
    return Marker(
      point: point.latLng,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () {
          _moveMap(point.latLng, 15.0);
          _showPointDetails(point);
        },
        child: Icon(
          Icons.eco_rounded,
          size: 25,
          color: point.isManual ? Colors.redAccent : const Color(0xFF2E7D32),
        ),
      ),
    );
  }
}
