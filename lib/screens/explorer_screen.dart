import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/explorer_service.dart';
import '../services/session_manager.dart';

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

  final ExplorerService _service = ExplorerService.instance;
  final MapController _mapController = MapController();
  final TextEditingController _radiusController =
  TextEditingController(text: '1000');
  final FocusNode _radiusFocusNode = FocusNode();

  UserSession? _session;
  ExplorerMode _mode = ExplorerMode.user;
  bool _isLoading = false;
  List<ExplorerUserStat> _users = const [];
  List<ExplorerPoint> _points = const [];
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

      ExplorerUserStat? selected;
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
          ? const <ExplorerPoint>[]
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
    if (_mode == ExplorerMode.area && _areaCenter != null) {
      _moveMap(_areaCenter!, _zoomForRadius(_radiusMeters));
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _points.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final point = _points[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).pop();
                              _moveMap(point.latLng, 15.0);
                              _showPointDetails(point);
                            },
                            leading: CircleAvatar(
                              backgroundColor: point.isManual
                                  ? Colors.redAccent
                                  : const Color(0xFF2E7D32),
                              child: Icon(
                                point.isManual
                                    ? Icons.edit_location_alt
                                    : Icons.eco_rounded,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(point.name),
                            subtitle: Text(
                              '${point.userLogin}\n${_service.formatDate(point.createdAt)}',
                            ),
                            trailing: point.photoCount > 0
                                ? Chip(label: Text('${point.photoCount} фото'))
                                : const Icon(Icons.photo_outlined),
                            isThreeLine: true,
                          ),
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

  void _showPointDetails(ExplorerPoint point) {
    final authHeaders = (_session?.accessToken != null)
        ? <String, String>{'Authorization': _session!.accessToken!}
        : const <String, String>{};

    final photoFuture = _service.resolvePhotoUrls(
      session: _session,
      point: point,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Text(
                    point.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Логин: ${point.userLogin}')),
                      Chip(label: Text(_service.formatDate(point.createdAt))),
                      if (point.isManual)
                        const Chip(label: Text('Введено вручную')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<String>>(
                    future: photoFuture,
                    builder: (context, snapshot) {
                      final urls = snapshot.data ?? point.photoUrls;

                      if (snapshot.connectionState == ConnectionState.waiting &&
                          urls.isEmpty) {
                        return Container(
                          height: 160,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const CircularProgressIndicator(),
                        );
                      }

                      if (urls.isEmpty) {
                        return Container(
                          height: 160,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          alignment: Alignment.center,
                          child: const Text('Фотография не прикреплена'),
                        );
                      }

                      return SizedBox(
                        height: 240,
                        child: PageView.builder(
                          itemCount: urls.length,
                          itemBuilder: (context, index) {
                            final imageUrl = urls[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  imageUrl,
                                  headers: authHeaders,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey.shade200,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.broken_image_outlined,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'Описание',
                    point.description?.trim().isNotEmpty == true
                        ? point.description!.trim()
                        : '—',
                  ),
                  _buildDetailRow(
                    'Широта, долгота',
                    '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                  ),
                  _buildDetailRow(
                    'Точность',
                    point.accuracy == null
                        ? '—'
                        : '±${point.accuracy!.toStringAsFixed(1)} м',
                  ),
                  _buildDetailRow(
                    'Гаусс X / Y',
                    (point.gaussX == null || point.gaussY == null)
                        ? '—'
                        : '${point.gaussX!.toStringAsFixed(2)} / ${point.gaussY!.toStringAsFixed(2)}',
                  ),
                  FutureBuilder<List<String>>(
                    future: photoFuture,
                    builder: (context, snapshot) {
                      final count = (snapshot.data?.isNotEmpty ?? false)
                          ? snapshot.data!.length
                          : point.photoCount;
                      return _buildDetailRow(
                        'Количество фото',
                        count.toString(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsLauncherCard() {
    if (_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_points.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text('Ничего не найдено'),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: OutlinedButton.icon(
        onPressed: _openPointsPicker,
        icon: const Icon(Icons.format_list_bulleted),
        label: Text('Найдено точек: ${_points.length}'),
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
    final areaCenterValid = _areaCenter != null &&
        _isValidLatLon(_areaCenter!.latitude, _areaCenter!.longitude);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Обзор данных',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _isLoading ? null : reload,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Обновить',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('По пользователю'),
                        selected: _mode == ExplorerMode.user,
                        onSelected: (selected) async {
                          if (!selected) return;
                          setState(() => _mode = ExplorerMode.user);
                          await _loadUserMode();
                        },
                      ),
                      ChoiceChip(
                        label: const Text('По области'),
                        selected: _mode == ExplorerMode.area,
                        onSelected: (selected) async {
                          if (!selected) return;
                          setState(() => _mode = ExplorerMode.area);
                          await _searchByArea();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _mode == ExplorerMode.user
                          ? _buildUserModeContent()
                          : _buildAreaModeContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(18),
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
                              point: _areaCenter!,
                              radius: _radiusMeters,
                              useRadiusInMeter: true,
                              color: const Color(0x335D7B79),
                              borderColor: const Color(0xFF5D7B79),
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (_mode == ExplorerMode.area && areaCenterValid)
                            Marker(
                              point: _areaCenter!,
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
          ),
        ],
      ),
    );
  }

  Widget _buildUserModeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Пользователи',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (_users.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Пользовательские слои не найдены'),
          )
        else
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _users.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final user = _users[index];
                final selected = user.userLogin == _selectedUser;
                return ChoiceChip(
                  label: Text('${user.userLogin} (${user.pointsCount})'),
                  selected: selected,
                  onSelected: (_) async {
                    setState(() {
                      _selectedUser = user.userLogin;
                    });
                    await _loadUserMode();
                  },
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        _buildPointsLauncherCard(),
      ],
    );
  }

  Widget _buildAreaModeContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _areaCenter == null
              ? 'Выберите центр поиска кнопкой или тапом по карте'
              : 'Центр: ${_areaCenter!.latitude.toStringAsFixed(5)}, ${_areaCenter!.longitude.toStringAsFixed(5)} • радиус: ${_radiusMeters.toStringAsFixed(_radiusMeters.truncateToDouble() == _radiusMeters ? 0 : 1)} м • найдено: ${_points.length}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 10),
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
                decoration: InputDecoration(
                  hintText: 'Радиус, м',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Моё местоположение',
              onPressed: _isLoading ? null : _useCurrentLocation,
              icon: const Icon(Icons.not_listed_location_sharp),
            ),
            IconButton(
              tooltip: 'Искать',
              onPressed: _isLoading ? null : _searchByArea,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildPointsLauncherCard(),
      ],
    );
  }

  Marker _buildMarker(ExplorerPoint point) {
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