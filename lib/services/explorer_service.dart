import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../data/database_helper.dart';
import 'geoportal_api_service.dart';
import 'session_manager.dart';

class ExplorerUserStat {
  final String userLogin;
  final int pointsCount;
  final int layerId;

  const ExplorerUserStat({
    required this.userLogin,
    required this.pointsCount,
    required this.layerId,
  });
}

class ExplorerPoint {
  final int remoteFeatureId;
  final int? localId;
  final int sourceLayerId;
  final int? sourceFeatureId;
  final String userLogin;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final bool isManual;
  final double? accuracy;
  final String? createdAt;
  final double? gaussX;
  final double? gaussY;
  final String? photoUrlMain;
  final List<String> photoUrls;
  final int photoCount;
  final Map<String, dynamic> attributes;

  const ExplorerPoint({
    required this.remoteFeatureId,
    required this.sourceLayerId,
    required this.userLogin,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.isManual,
    required this.photoUrls,
    required this.photoCount,
    this.localId,
    this.sourceFeatureId,
    this.description,
    this.accuracy,
    this.createdAt,
    this.gaussX,
    this.gaussY,
    this.photoUrlMain,
    this.attributes = const {},
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

class _UserFolderRef {
  final int id;
  final String userLogin;

  const _UserFolderRef({
    required this.id,
    required this.userLogin,
  });
}

class _UserLayerRef {
  final int id;
  final String userLogin;

  const _UserLayerRef({
    required this.id,
    required this.userLogin,
  });
}

class ExplorerService {
  ExplorerService._privateConstructor();

  static final ExplorerService instance = ExplorerService._privateConstructor();

  final Distance _distance = const Distance();

  Future<List<ExplorerUserStat>> loadUserStats({
    required UserSession session,
  }) async {
    if (session.isGuest || session.accessToken == null) return const [];

    final layers = await _discoverUserLayers(session);
    if (layers.isEmpty) return const [];

    final counts = await Future.wait(
      layers.map((layer) async {
        final rows = await _fetchLayerFeatures(
          auth: session.accessToken!,
          layerId: layer.id,
          query: const {
            'limit': '5000',
            'offset': '0',
            'srs': '4326',
          },
        );

        return ExplorerUserStat(
          userLogin: layer.userLogin,
          pointsCount: rows.length,
          layerId: layer.id,
        );
      }),
    );

    counts.sort((a, b) {
      final byCount = b.pointsCount.compareTo(a.pointsCount);
      if (byCount != 0) return byCount;
      return a.userLogin.compareTo(b.userLogin);
    });

    return counts;
  }

  Future<List<ExplorerPoint>> loadPointsByUser({
    required UserSession session,
    required String userLogin,
    int? knownLayerId,
  }) async {
    if (session.isGuest || session.accessToken == null) return const [];

    final login = userLogin.trim().toLowerCase();
    if (login.isEmpty) return const [];

    int? layerId = knownLayerId;

    if (layerId == null) {
      final layers = await _discoverUserLayers(session);
      for (final layer in layers) {
        if (layer.userLogin == login) {
          layerId = layer.id;
          break;
        }
      }
    }

    if (layerId == null) return const [];

    final rows = await _fetchLayerFeatures(
      auth: session.accessToken!,
      layerId: layerId,
      query: _defaultFeatureQuery(),
    );

    final fullRows = await _hydrateRowsWithFullFeatures(
      auth: session.accessToken!,
      layerId: layerId,
      rows: rows,
    );

    return _parsePoints(
      fullRows,
      defaultUserLogin: login,
      sourceLayerId: layerId,
    );
  }

  Future<List<ExplorerPoint>> loadPointsByRadius({
    required UserSession session,
    required double centerLatitude,
    required double centerLongitude,
    required double radiusMeters,
  }) async {
    if (session.isGuest || session.accessToken == null) return const [];
    if (!centerLatitude.isFinite || !centerLongitude.isFinite) return const [];
    if (!radiusMeters.isFinite || radiusMeters <= 0) return const [];

    final layers = await _discoverUserLayers(session);
    if (layers.isEmpty) return const [];

    final center = LatLng(centerLatitude, centerLongitude);

    final latDelta = radiusMeters / 111320.0;
    final cosLat = math.cos(centerLatitude * math.pi / 180.0).abs();
    final safeCosLat = cosLat < 0.01 ? 0.01 : cosLat;
    final lonDelta = radiusMeters / (111320.0 * safeCosLat);

    final minLat = centerLatitude - latDelta;
    final maxLat = centerLatitude + latDelta;
    final minLon = centerLongitude - lonDelta;
    final maxLon = centerLongitude + lonDelta;

    final rowsByLayer = await Future.wait(
      layers.map((layer) async {
        final rows = await _fetchLayerFeatures(
          auth: session.accessToken!,
          layerId: layer.id,
          query: _defaultFeatureQuery(),
        );

        final fullRows = await _hydrateRowsWithFullFeatures(
          auth: session.accessToken!,
          layerId: layer.id,
          rows: rows,
        );

        return _parsePoints(
          fullRows,
          defaultUserLogin: layer.userLogin,
          sourceLayerId: layer.id,
        );
      }),
    );

    final all = rowsByLayer.expand((items) => items).toList();

    final filtered = all.where((point) {
      if (!_isValidLatLon(point.latitude, point.longitude)) return false;

      if (point.latitude < minLat || point.latitude > maxLat) return false;
      if (point.longitude < minLon || point.longitude > maxLon) return false;

      final meters = _distance.as(LengthUnit.Meter, center, point.latLng);
      return meters.isFinite && meters <= radiusMeters;
    }).toList()
      ..sort((a, b) {
        final aDist = _distance.as(LengthUnit.Meter, center, a.latLng);
        final bDist = _distance.as(LengthUnit.Meter, center, b.latLng);
        return aDist.compareTo(bDist);
      });

    return filtered;
  }

  Future<List<String>> resolvePhotoUrls({
    required UserSession? session,
    required ExplorerPoint point,
  }) async {
    if (point.photoUrls.isNotEmpty) {
      return point.photoUrls;
    }

    if (session == null || session.accessToken == null) {
      return const [];
    }

    final featureId = point.sourceFeatureId ?? point.remoteFeatureId;
    if (featureId <= 0) return const [];

    try {
      final response = await http.get(
        _uri('/resource/${point.sourceLayerId}/feature/$featureId/attachment/'),
        headers: _headers(session.accessToken!),
      );

      if (response.statusCode != 200) {
        return const [];
      }

      final decoded = jsonDecode(response.body);
      final items = <Map<String, dynamic>>[];

      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            items.add(item.map((k, v) => MapEntry(k.toString(), v)));
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        final value = decoded['items'] ?? decoded['attachments'];
        if (value is List) {
          for (final item in value) {
            if (item is Map) {
              items.add(item.map((k, v) => MapEntry(k.toString(), v)));
            }
          }
        }
      } else if (decoded is Map) {
        final map = decoded.map((k, v) => MapEntry(k.toString(), v));
        final value = map['items'] ?? map['attachments'];
        if (value is List) {
          for (final item in value) {
            if (item is Map) {
              items.add(item.map((k, v) => MapEntry(k.toString(), v)));
            }
          }
        }
      }

      final urls = <String>[];

      for (final item in items) {
        final id = _toInt(item['id']);
        if (id == null) continue;

        urls.add(
          _normalizeAttachmentImageUrl(
            '${GeoportalApiService.apiBaseUrl}/resource/${point.sourceLayerId}/feature/$featureId/attachment/$id',
          ),
        );
      }

      return urls;
    } catch (_) {
      return const [];
    }
  }

  String formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';

    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String buildBoundingBoxWkt3857({
    required double centerLatitude,
    required double centerLongitude,
    required double radiusMeters,
  }) {
    final merc = _toWebMercator(centerLatitude, centerLongitude);
    final minX = merc.$1 - radiusMeters;
    final maxX = merc.$1 + radiusMeters;
    final minY = merc.$2 - radiusMeters;
    final maxY = merc.$2 + radiusMeters;

    return 'POLYGON(($minX $minY, $maxX $minY, $maxX $maxY, $minX $maxY, $minX $minY))';
  }

  Future<List<_UserLayerRef>> _discoverUserLayers(UserSession session) async {
    final auth = session.accessToken;
    if (auth == null || auth.isEmpty) return const [];

    final folders = await _discoverUserFolders(auth);
    if (folders.isEmpty) return const [];

    final folderById = <int, _UserFolderRef>{
      for (final item in folders) item.id: item,
    };

    final resources = await _searchResources(auth: auth, cls: 'vector_layer');

    final v4Layers = <_UserLayerRef>[];
    final legacyLayers = <_UserLayerRef>[];

    for (final row in resources) {
      final resource = _extractResource(row);
      final layerId = _toInt(resource['id']);
      final parentId = _parentId(resource['parent']);
      final keyname = _asTrimmedString(resource['keyname']);

      if (layerId == null || parentId == null || keyname == null) continue;

      final folder = folderById[parentId];
      if (folder == null) continue;

      final login = folder.userLogin.toLowerCase();
      final key = keyname.toLowerCase();

      final expectedV4 = 'plants_${login}_v4';
      final expectedLegacy = 'plants_$login';

      if (key == expectedV4) {
        v4Layers.add(
          _UserLayerRef(
            id: layerId,
            userLogin: folder.userLogin,
          ),
        );
      } else if (key == expectedLegacy) {
        legacyLayers.add(
          _UserLayerRef(
            id: layerId,
            userLogin: folder.userLogin,
          ),
        );
      }
    }

    final result = v4Layers.isNotEmpty ? v4Layers : legacyLayers;
    result.sort((a, b) => a.userLogin.compareTo(b.userLogin));
    return result;
  }

  Future<List<_UserFolderRef>> _discoverUserFolders(String auth) async {
    final resources = await _searchResources(auth: auth, cls: 'resource_group');
    final folders = <_UserFolderRef>[];

    for (final row in resources) {
      final resource = _extractResource(row);
      final folderId = _toInt(resource['id']);
      final keyname = _asTrimmedString(resource['keyname']);
      final parentId = _parentId(resource['parent']);

      if (folderId == null || keyname == null || parentId == null) continue;
      if (parentId != GeoportalApiService.rootUsersGroupId) continue;
      if (!keyname.toLowerCase().startsWith('user_')) continue;

      final login = keyname.substring(5).trim().toLowerCase();
      if (login.isEmpty) continue;

      folders.add(
        _UserFolderRef(
          id: folderId,
          userLogin: login,
        ),
      );
    }

    folders.sort((a, b) => a.userLogin.compareTo(b.userLogin));
    return folders;
  }

  Future<List<Map<String, dynamic>>> _searchResources({
    required String auth,
    String? cls,
  }) async {
    final query = <String, String>{
      'serialization': 'full',
      if (cls != null && cls.trim().isNotEmpty) 'cls': cls.trim(),
    };

    final response = await http.get(
      _uri('/resource/search/', query),
      headers: _headers(auth),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось выполнить resource/search: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchLayerFeatures({
    required String auth,
    required int layerId,
    required Map<String, String> query,
  }) async {
    final response = await http.get(
      _uri('/resource/$layerId/feature/', query),
      headers: _headers(auth),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось получить features слоя $layerId: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    if (decoded is Map<String, dynamic>) {
      final value = decoded['features'] ?? decoded['items'];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } else if (decoded is Map) {
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      final value = map['features'] ?? map['items'];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    }

    return const [];
  }

  Future<Map<String, dynamic>?> _fetchSingleFeature({
    required String auth,
    required int layerId,
    required int featureId,
  }) async {
    final response = await http.get(
      _uri(
        '/resource/$layerId/feature/$featureId',
        {'srs': '4326', 'geom_format': 'geojson'},
      ),
      headers: _headers(auth),
    );

    if (response.statusCode != 200) {
      return null;
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _hydrateRowsWithFullFeatures({
    required String auth,
    required int layerId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final fullRows = await Future.wait(
      rows.map((row) async {
        final featureId = _toInt(row['id']);
        if (featureId == null || featureId <= 0) return row;

        final full = await _fetchSingleFeature(
          auth: auth,
          layerId: layerId,
          featureId: featureId,
        );

        return full ?? row;
      }),
    );

    return fullRows;
  }

  Map<String, String> _defaultFeatureQuery() {
    return const {
      'limit': '5000',
      'offset': '0',
      'srs': '4326',
      'geom_format': 'geojson',
    };
  }

  List<ExplorerPoint> _parsePoints(
      List<Map<String, dynamic>> rows, {
        required String defaultUserLogin,
        required int sourceLayerId,
      }) {
    final result = <ExplorerPoint>[];

    for (final row in rows) {
      final point = _parsePoint(
        row,
        defaultUserLogin: defaultUserLogin,
        sourceLayerId: sourceLayerId,
      );

      if (point != null) {
        result.add(point);
      }
    }

    return result;
  }

  ExplorerPoint? _parsePoint(
      Map<String, dynamic> row, {
        required String defaultUserLogin,
        required int sourceLayerId,
      }) {
    final fields = _extractFields(row);

    dynamic pick(String key) {
      if (fields.containsKey(key)) return fields[key];
      return row[key];
    }

    final coords = _extractLatLon(row, fields);
    final latitude = coords?.$1;
    final longitude = coords?.$2;

    if (latitude == null || longitude == null) {
      return null;
    }

    final attributes = _parseAttributesJson(pick('attributes_json'));

    final userLogin = _asTrimmedString(pick('user_login')) ?? defaultUserLogin;

    final name =
        _asTrimmedString(attributes[PlantAttributeKeys.plantName]) ??
            _asTrimmedString(pick('name')) ??
            _asTrimmedString(pick('plant_name')) ??
            'Без названия';

    final description =
        _asTrimmedString(attributes[PlantAttributeKeys.description]) ??
            _asTrimmedString(pick('description'));

    final createdAt =
        _asTrimmedString(pick('observed_at')) ??
            _asTrimmedString(pick('created_at'));

    final accuracy = _finiteDouble(pick('accuracy'));
    final gaussX = _finiteDouble(pick('gauss_x'));
    final gaussY = _finiteDouble(pick('gauss_y'));

    final manualRaw = pick('is_manual');
    final isManual =
        _toInt(manualRaw) == 1 ||
            manualRaw == true ||
            _asTrimmedString(manualRaw)?.toLowerCase() == 'true';

    final mainUrl = _normalizeAttachmentImageUrl(
      _asTrimmedString(pick('photo_url_main')) ?? '',
    );

    final photoUrls = _parsePhotoUrls(pick('photo_urls_json'), mainUrl);

    final explicitPhotoCount = _toInt(pick('photo_count'));
    final resolvedPhotoCount =
    explicitPhotoCount != null && explicitPhotoCount > 0
        ? explicitPhotoCount
        : photoUrls.length;

    return ExplorerPoint(
      remoteFeatureId: _toInt(row['id']) ?? 0,
      localId: _toInt(pick('local_id')),
      sourceLayerId: sourceLayerId,
      sourceFeatureId: _toInt(row['id']),
      userLogin: userLogin,
      name: name,
      description: description,
      latitude: latitude,
      longitude: longitude,
      isManual: isManual,
      accuracy: accuracy,
      createdAt: createdAt,
      gaussX: gaussX,
      gaussY: gaussY,
      photoUrlMain: mainUrl.isEmpty ? null : mainUrl,
      photoUrls: photoUrls,
      photoCount: resolvedPhotoCount,
      attributes: attributes,
    );
  }

  Map<String, dynamic> _parseAttributesJson(dynamic raw) {
    if (raw == null) return {};

    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map(
                (key, value) => MapEntry(key.toString(), value),
          );
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  (double, double)? _extractLatLon(
      Map<String, dynamic> row,
      Map<String, dynamic> fields,
      ) {
    final lat = _finiteDouble(fields['latitude']);
    final lon = _finiteDouble(fields['longitude']);

    if (lat != null && lon != null && _isValidLatLon(lat, lon)) {
      return (lat, lon);
    }

    final geom = row['geom'] ?? row['geometry'];

    if (geom is String) {
      final match = RegExp(
        r'POINT\s*\(?\s*([-0-9\.]+)\s+([-0-9\.]+)\s*\)?',
        caseSensitive: false,
      ).firstMatch(geom);

      if (match != null) {
        final lonValue = _finiteDouble(match.group(1));
        final latValue = _finiteDouble(match.group(2));

        if (latValue != null &&
            lonValue != null &&
            _isValidLatLon(latValue, lonValue)) {
          return (latValue, lonValue);
        }
      }
    }

    if (geom is Map) {
      final geo = geom.map((k, v) => MapEntry(k.toString(), v));
      final coordinates = geo['coordinates'];

      if (coordinates is List && coordinates.length >= 2) {
        final lonValue = _finiteDouble(coordinates[0]);
        final latValue = _finiteDouble(coordinates[1]);

        if (latValue != null &&
            lonValue != null &&
            _isValidLatLon(latValue, lonValue)) {
          return (latValue, lonValue);
        }
      }
    }

    return null;
  }

  List<String> _parsePhotoUrls(dynamic raw, String mainUrl) {
    final urls = <String>[];

    if (raw is List) {
      for (final item in raw) {
        final value = _normalizeAttachmentImageUrl(item?.toString() ?? '');
        if (value.isNotEmpty && !urls.contains(value)) {
          urls.add(value);
        }
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final value = _normalizeAttachmentImageUrl(item?.toString() ?? '');
            if (value.isNotEmpty && !urls.contains(value)) {
              urls.add(value);
            }
          }
        }
      } catch (_) {
        final value = _normalizeAttachmentImageUrl(raw);
        if (value.isNotEmpty && !urls.contains(value)) {
          urls.add(value);
        }
      }
    }

    if (mainUrl.isNotEmpty && !urls.contains(mainUrl)) {
      urls.insert(0, mainUrl);
    }

    return urls;
  }

  String _normalizeAttachmentImageUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    var normalized = value;

    if (normalized.startsWith('/api/')) {
      normalized = '${GeoportalApiService.portalBaseUrl}$normalized';
    } else if (normalized.startsWith('/resource/')) {
      normalized = '${GeoportalApiService.apiBaseUrl}$normalized';
    } else if (normalized.startsWith('/')) {
      normalized = '${GeoportalApiService.portalBaseUrl}$normalized';
    }

    if (normalized.contains('/image?')) {
      return normalized;
    }

    if (RegExp(r'/attachment/\d+$', caseSensitive: false).hasMatch(normalized)) {
      return '$normalized/image?size=1600x1600';
    }

    return normalized;
  }

  Map<String, dynamic> _extractResource(Map<String, dynamic> row) {
    final raw = row['resource'];

    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }

    return row;
  }

  Map<String, dynamic> _extractFields(Map<String, dynamic> row) {
    final rawFields = row['fields'];

    if (rawFields is Map<String, dynamic> && rawFields.isNotEmpty) {
      return rawFields;
    }

    if (rawFields is Map && rawFields.isNotEmpty) {
      return rawFields.map((key, value) => MapEntry(key.toString(), value));
    }

    const fallbackKeys = <String>[
      'local_uuid',
      'local_id',
      'user_login',
      'name',
      'plant_name',
      'description',
      'latitude',
      'longitude',
      'is_manual',
      'accuracy',
      'created_at',
      'observed_at',
      'gauss_x',
      'gauss_y',
      'zone',
      'attributes_json',
      'attribute_schema_version',
      'photo_url_main',
      'photo_urls_json',
      'photo_count',
    ];

    final flat = <String, dynamic>{};

    for (final key in fallbackKeys) {
      if (row.containsKey(key)) {
        flat[key] = row[key];
      }
    }

    return flat;
  }

  int? _parentId(dynamic raw) {
    if (raw is int) return raw;

    if (raw is num) return raw.toInt();

    if (raw is Map) {
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      return _toInt(map['id']);
    }

    return null;
  }

  String? _asTrimmedString(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    return text;
  }

  double? _finiteDouble(dynamic value) {
    if (value == null) return null;

    double? parsed;

    if (value is double) {
      parsed = value;
    } else if (value is int) {
      parsed = value.toDouble();
    } else if (value is num) {
      parsed = value.toDouble();
    } else {
      parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    }

    if (parsed == null || !parsed.isFinite) return null;

    return parsed;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;

    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value.toString());
  }

  bool _isValidLatLon(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  (double, double) _toWebMercator(double latitude, double longitude) {
    final lat = latitude.clamp(-85.05112878, 85.05112878);
    final lon = longitude.clamp(-180.0, 180.0);

    final x = lon * 20037508.34 / 180.0;

    var y = math.log(math.tan((90.0 + lat) * math.pi / 360.0)) /
        (math.pi / 180.0);
    y = y * 20037508.34 / 180.0;

    return (x, y);
  }

  Map<String, String> _headers(String auth) {
    return {
      'Accept': '*/*',
      'Authorization': auth,
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${GeoportalApiService.apiBaseUrl}$path')
        .replace(queryParameters: query);
  }
}