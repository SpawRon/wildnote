import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_logger.dart';
import 'session_manager.dart';

class GeoportalLoginResult {
  final bool success;
  final String? accessToken;
  final String? folderPath;
  final String? userKeyname;
  final String? error;

  const GeoportalLoginResult({
    required this.success,
    this.accessToken,
    this.folderPath,
    this.userKeyname,
    this.error,
  });
}

class UserWorkspaceResult {
  final String userLogin;
  final int folderId;
  final int layerId;
  final int styleId;
  final int webMapId;
  final String folderPath;

  const UserWorkspaceResult({
    required this.userLogin,
    required this.folderId,
    required this.layerId,
    required this.styleId,
    required this.webMapId,
    required this.folderPath,
  });
}

class GeoportalPointResult {
  final bool success;
  final int? remoteFeatureId;
  final String? folderPath;
  final List<String> photoUrls;
  final String? warning;
  final String? error;

  const GeoportalPointResult({
    required this.success,
    this.remoteFeatureId,
    this.folderPath,
    this.photoUrls = const [],
    this.warning,
    this.error,
  });
}

class _LayerFieldSchema {
  final Map<int, String> keyById;
  final List<String> orderedKeys;

  const _LayerFieldSchema({
    required this.keyById,
    required this.orderedKeys,
  });
}

class GeoportalApiService {
  GeoportalApiService._privateConstructor();
  static final GeoportalApiService instance =
  GeoportalApiService._privateConstructor();

  static const String portalBaseUrl = 'https://geo.mauniver.ru';
  static const String apiBaseUrl = '$portalBaseUrl/api';

  static const int rootUsersGroupId = 3560;
  static const int sharedWebMapId = 3568;
  static const int userLayerSrsId = 3857;


  String _buildBasicAuth(String login, String password) {
    final raw = '$login:$password';
    final encoded = base64Encode(utf8.encode(raw));
    return 'Basic $encoded';
  }

  Map<String, String> _headers(String auth, {bool json = false}) {
    return {
      'Accept': '*/*',
      'Authorization': auth,
      if (json) 'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
  }

  String _folderKey(String login) => 'user_${login.toLowerCase()}';
  String _layerKey(String login) => 'plants_${login.toLowerCase()}_v4';
  String _styleKey(String login) => 'style_plants_${login.toLowerCase()}_v4';

  Future<GeoportalLoginResult> login({
    required String login,
    required String password,
  }) async {
    if (login.trim().isEmpty || password.trim().isEmpty) {
      return const GeoportalLoginResult(
        success: false,
        error: 'Введите логин и пароль',
      );
    }

    try {
      final auth = _buildBasicAuth(login, password);

      final response = await http.get(
        _uri('/component/auth/current_user'),
        headers: _headers(auth),
      );

      if (response.statusCode != 200) {
        return GeoportalLoginResult(
          success: false,
          error: 'Неверный логин или пароль (${response.statusCode})',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final keyname = (data['keyname'] as String?)?.trim();

      if (keyname == null || keyname.isEmpty) {
        return const GeoportalLoginResult(
          success: false,
          error: 'Геопортал не вернул keyname пользователя',
        );
      }

      return GeoportalLoginResult(
        success: true,
        accessToken: auth,
        folderPath: 'resource_group:${_folderKey(keyname)}',
        userKeyname: keyname,
      );
    } catch (e) {
      return GeoportalLoginResult(
        success: false,
        error: 'Ошибка подключения: $e',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _searchResources({
    required String auth,
    String? keyname,
    String? displayName,
    String? cls,
  }) async {
    final query = <String, String>{
      'serialization': 'full',
    };

    if (keyname != null) query['keyname'] = keyname;
    if (displayName != null) query['display_name'] = displayName;
    if (cls != null) query['cls'] = cls;

    final response = await http.get(
      _uri('/resource/search/', query),
      headers: _headers(auth),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось выполнить resource/search: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! List) return [];

    return data.map<Map<String, dynamic>>((e) {
      return Map<String, dynamic>.from(e as Map);
    }).toList();
  }

  Future<Map<String, dynamic>?> _searchOneByKeyname({
    required String auth,
    required String keyname,
    String? cls,
  }) async {
    final results = await _searchResources(
      auth: auth,
      keyname: keyname,
      cls: cls,
    );

    if (results.isEmpty) return null;
    return results.first;
  }

  Future<Map<String, dynamic>> _getResource({
    required String auth,
    required int id,
  }) async {
    final response = await http.get(
      _uri('/resource/$id'),
      headers: _headers(auth),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось получить ресурс $id: ${response.statusCode} ${response.body}',
      );
    }

    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<int> _createResourceGroup({
    required String auth,
    required int parentId,
    required String displayName,
    required String keyname,
  }) async {
    final payload = {
      'resource': {
        'cls': 'resource_group',
        'parent': {'id': parentId},
        'display_name': displayName,
        'keyname': keyname,
        'description': 'Рабочая папка пользователя $displayName',
      }
    };

    final response = await http.post(
      _uri('/resource/'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
        'Не удалось создать папку: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
  }

  List<Map<String, dynamic>> _remoteLayerFields() {
    return [
      {
        'keyname': 'local_uuid',
        'display_name': 'Local UUID',
        'datatype': 'STRING',
      },
      {
        'keyname': 'local_id',
        'display_name': 'Local ID',
        'datatype': 'INTEGER',
      },
      {
        'keyname': 'user_login',
        'display_name': 'Логин пользователя',
        'datatype': 'STRING',
      },

      {
        'keyname': 'name',
        'display_name': 'Название',
        'datatype': 'STRING',
      },
      {
        'keyname': 'description',
        'display_name': 'Описание',
        'datatype': 'STRING',
      },

      {
        'keyname': 'latitude',
        'display_name': 'Широта',
        'datatype': 'REAL',
      },
      {
        'keyname': 'longitude',
        'display_name': 'Долгота',
        'datatype': 'REAL',
      },
      {
        'keyname': 'is_manual',
        'display_name': 'Ручной ввод',
        'datatype': 'INTEGER',
      },
      {
        'keyname': 'accuracy',
        'display_name': 'Точность',
        'datatype': 'REAL',
      },
      {
        'keyname': 'created_at',
        'display_name': 'Дата создания',
        'datatype': 'STRING',
      },
      {
        'keyname': 'observed_at',
        'display_name': 'Дата наблюдения',
        'datatype': 'STRING',
      },

      {
        'keyname': 'gauss_x',
        'display_name': 'Gauss X',
        'datatype': 'REAL',
      },
      {
        'keyname': 'gauss_y',
        'display_name': 'Gauss Y',
        'datatype': 'REAL',
      },
      {
        'keyname': 'zone',
        'display_name': 'Зона',
        'datatype': 'INTEGER',
      },

      {
        'keyname': 'attributes_json',
        'display_name': 'Атрибуты JSON',
        'datatype': 'STRING',
      },
      {
        'keyname': 'attribute_schema_version',
        'display_name': 'Версия схемы атрибутов',
        'datatype': 'INTEGER',
      },

      {
        'keyname': 'photo_url_main',
        'display_name': 'Основное фото URL',
        'datatype': 'STRING',
      },
      {
        'keyname': 'photo_urls_json',
        'display_name': 'Список фото URL',
        'datatype': 'STRING',
      },
      {
        'keyname': 'photo_count',
        'display_name': 'Количество фото',
        'datatype': 'INTEGER',
      },
    ];
  }


  String _safeIdentityPart(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 'empty';

    final normalized = text.replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-я_-]+'), '_');
    return normalized.length > 80 ? normalized.substring(0, 80) : normalized;
  }

  String? _effectiveLocalUuid(Map<String, dynamic> observation) {
    final existing = _asTrimmedString(observation['local_uuid']);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final userLogin = _asTrimmedString(observation['user_login']);
    final localId = _toInt(observation['id']);
    final createdAt = _asTrimmedString(observation['created_at']);

    if (userLogin == null || userLogin.isEmpty || localId == null || createdAt == null || createdAt.isEmpty) {
      return null;
    }

    // Для старых локальных записей, где ещё нет local_uuid в БД.
    // Главное отличие от старого local_id: сюда входит created_at,
    // поэтому новая запись с тем же локальным id уже не склеится со старой.
    return [
      'legacy',
      _safeIdentityPart(userLogin),
      _safeIdentityPart(localId),
      _safeIdentityPart(createdAt),
      _safeIdentityPart(observation['latitude']),
      _safeIdentityPart(observation['longitude']),
    ].join('_');
  }

  Map<String, dynamic> _buildRemoteFeatureFields({
    required Map<String, dynamic> observation,
    required Map<String, dynamic> attributes,
    required List<String> photoUrls,
  }) {
    final cleanAttributes = <String, dynamic>{};

    for (final entry in attributes.entries) {
      final key = entry.key.trim();
      final value = entry.value;
      if (key.isEmpty || value == null) continue;

      if (value is String) {
        final text = value.trim();
        if (text.isNotEmpty) {
          cleanAttributes[key] = text;
        }
      } else {
        cleanAttributes[key] = value;
      }
    }

    final plantName =
        _asString(cleanAttributes['plant_name']) ??
            _asString(observation['name']);

    final description =
        _asString(cleanAttributes['description']) ??
            _asString(observation['description']);

    final observedAt =
        _asString(observation['observed_at']) ??
            _asString(observation['created_at']);

    return {
      'local_uuid': _effectiveLocalUuid(observation),
      'local_id': observation['id'],
      'user_login': observation['user_login'],

      'name': plantName ?? 'Без названия',
      'description': description,

      'latitude': observation['latitude'],
      'longitude': observation['longitude'],
      'is_manual': observation['is_manual'],
      'accuracy': observation['accuracy'],
      'created_at': observation['created_at'],
      'observed_at': observedAt,

      'gauss_x': observation['gauss_x'],
      'gauss_y': observation['gauss_y'],
      'zone': observation['zone'],

      'attributes_json': jsonEncode(cleanAttributes),
      'attribute_schema_version': 4,

      'photo_url_main': photoUrls.isNotEmpty ? photoUrls.first : null,
      'photo_urls_json': jsonEncode(photoUrls),
      'photo_count': photoUrls.length,
    };
  }

  Map<String, dynamic> _parseAttributesJson(dynamic raw) {
    if (raw == null) return {};

    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return Map<String, dynamic>.from(decoded);
        }

        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Future<int> _createEmptyVectorLayer({
    required String auth,
    required int parentId,
    required String displayName,
    required String keyname,
  }) async {
    final payload = {
      'resource': {
        'cls': 'vector_layer',
        'parent': {'id': parentId},
        'display_name': displayName,
        'keyname': keyname,
        'description': 'Персональный слой редких растений пользователя',
      },
      'resmeta': {
        'items': {},
      },
      'vector_layer': {
        'srs': {'id': userLayerSrsId},
        'geometry_type': 'POINT',
        'fields': _remoteLayerFields(),
      }
    };

    final response = await http.post(
      _uri('/resource/'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
        'Не удалось создать векторный слой: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
  }

  Future<void> deleteFeature({
    required UserSession session,
    required int featureId,
  }) async {
    if (session.accessToken == null || session.userLayerId == null) {
      throw Exception('Нет данных для удаления feature на сервере');
    }

    final response = await http.delete(
      _uri('/resource/${session.userLayerId}/feature/$featureId'),
      headers: _headers(session.accessToken!),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось удалить точку на сервере: ${response.statusCode} ${response.body}',
      );
    }
  }

  String _buildMapServerStyleXml() {
    return '''
<map>
  <layer>
    <class>
      <expression>([is_manual] = 1)</expression>
      <style>
        <color red="220" green="76" blue="70"/>
        <outlinecolor red="255" green="255" blue="255"/>
        <size>16</size>
        <symbol>std:diamond</symbol>
      </style>
      <style>
        <color red="255" green="255" blue="255"/>
        <size>6</size>
        <symbol>std:circle</symbol>
      </style>
    </class>
    <class>
      <style>
        <color red="46" green="125" blue="50"/>
        <outlinecolor red="255" green="255" blue="255"/>
        <size>14</size>
        <symbol>std:circle</symbol>
      </style>
    </class>
  </layer>
</map>
''';
  }

  Future<int> _createMapServerStyle({
    required String auth,
    required int layerId,
    required String displayName,
    required String keyname,
  }) async {
    final payload = {
      'mapserver_style': {
        'xml': _buildMapServerStyleXml(),
      },
      'resource': {
        'cls': 'mapserver_style',
        'parent': {'id': layerId},
        'display_name': displayName,
        'keyname': keyname,
        'description': 'Автостиль персонального слоя',
      }
    };

    final response = await http.post(
      _uri('/resource/'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
        'Не удалось создать стиль: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
  }

  Future<void> _updateMapServerStyle({
    required String auth,
    required int styleId,
  }) async {
    final payload = {
      'mapserver_style': {
        'xml': _buildMapServerStyleXml(),
      }
    };

    final response = await http.put(
      _uri('/resource/$styleId'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось обновить стиль: ${response.statusCode} ${response.body}',
      );
    }
  }

  bool _upsertLayerInChildren({
    required List<dynamic> children,
    required int layerId,
    required int styleId,
    required String displayName,
  }) {
    for (int i = 0; i < children.length; i++) {
      final item = Map<String, dynamic>.from(children[i] as Map);

      if (item['item_type'] == 'layer' && item['style_parent_id'] == layerId) {
        item['display_name'] = displayName;
        item['layer_enabled'] = true;
        item['layer_identifiable'] = true;
        item['layer_style_id'] = styleId;
        item['style_parent_id'] = layerId;
        item['layer_adapter'] = 'image';
        children[i] = item;
        return true;
      }

      if (item['item_type'] == 'group' && item['children'] is List) {
        final groupChildren = List<dynamic>.from(item['children'] as List);
        final found = _upsertLayerInChildren(
          children: groupChildren,
          layerId: layerId,
          styleId: styleId,
          displayName: displayName,
        );
        if (found) {
          item['children'] = groupChildren;
          children[i] = item;
          return true;
        }
      }
    }
    return false;
  }

  void _insertLayerIntoFirstGroupOrRoot(
      List<dynamic> children,
      Map<String, dynamic> layerItem,
      ) {
    for (int i = 0; i < children.length; i++) {
      final item = Map<String, dynamic>.from(children[i] as Map);
      if (item['item_type'] == 'group' && item['children'] is List) {
        final groupChildren = List<dynamic>.from(item['children'] as List);
        groupChildren.insert(0, layerItem);
        item['children'] = groupChildren;
        children[i] = item;
        return;
      }
    }

    children.insert(0, layerItem);
  }

  Future<void> _ensureLayerInWebMap({
    required String auth,
    required int webMapId,
    required int layerId,
    required int styleId,
    required String displayName,
  }) async {
    final webMapResource = await _getResource(auth: auth, id: webMapId);
    final webmap = Map<String, dynamic>.from(
      webMapResource['webmap'] as Map<String, dynamic>,
    );
    final rootItem = Map<String, dynamic>.from(
      webmap['root_item'] as Map<String, dynamic>,
    );
    final children = List<dynamic>.from(rootItem['children'] as List? ?? []);

    final found = _upsertLayerInChildren(
      children: children,
      layerId: layerId,
      styleId: styleId,
      displayName: displayName,
    );

    if (!found) {
      final layerItem = <String, dynamic>{
        'item_type': 'layer',
        'display_name': displayName,
        'layer_enabled': true,
        'layer_identifiable': true,
        'layer_transparency': null,
        'layer_style_id': styleId,
        'style_parent_id': layerId,
        'layer_min_scale_denom': null,
        'layer_max_scale_denom': null,
        'layer_adapter': 'image',
        'draw_order_position': null,
        'legend_symbols': null,
        'payload': null,
      };

      _insertLayerIntoFirstGroupOrRoot(children, layerItem);
    }

    final payload = {
      'webmap': {
        'root_item': {
          'item_type': 'root',
          'children': children,
        }
      }
    };

    final response = await http.put(
      _uri('/resource/$webMapId'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось привязать слой к webmap: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<UserWorkspaceResult> ensureUserWorkspace({
    required String login,
    required String auth,
  }) async {
    final folderKey = _folderKey(login);
    final layerKey = _layerKey(login);
    final styleKey = _styleKey(login);

    int folderId;
    int layerId;
    int styleId;

    final folder = await _searchOneByKeyname(
      auth: auth,
      keyname: folderKey,
      cls: 'resource_group',
    );

    if (folder != null) {
      folderId = (folder['resource'] as Map<String, dynamic>)['id'] as int;
    } else {
      folderId = await _createResourceGroup(
        auth: auth,
        parentId: rootUsersGroupId,
        displayName: login,
        keyname: folderKey,
      );
    }

    final layer = await _searchOneByKeyname(
      auth: auth,
      keyname: layerKey,
      cls: 'vector_layer',
    );

    if (layer != null) {
      layerId = (layer['resource'] as Map<String, dynamic>)['id'] as int;
    } else {
      layerId = await _createEmptyVectorLayer(
        auth: auth,
        parentId: folderId,
        displayName: 'plants_${login}_v4',
        keyname: layerKey,
      );
    }

    final style = await _searchOneByKeyname(
      auth: auth,
      keyname: styleKey,
      cls: 'mapserver_style',
    );

    if (style != null) {
      styleId = (style['resource'] as Map<String, dynamic>)['id'] as int;
      await _updateMapServerStyle(
        auth: auth,
        styleId: styleId,
      );
    } else {
      styleId = await _createMapServerStyle(
        auth: auth,
        layerId: layerId,
        displayName: 'style_plants_${login}_v4',
        keyname: styleKey,
      );
    }

    await _ensureLayerInWebMap(
      auth: auth,
      webMapId: sharedWebMapId,
      layerId: layerId,
      styleId: styleId,
      displayName: 'plants_${login}_v4',
    );

    return UserWorkspaceResult(
      userLogin: login,
      folderId: folderId,
      layerId: layerId,
      styleId: styleId,
      webMapId: sharedWebMapId,
      folderPath: 'resource_group:$folderKey',
    );
  }


  String _sharedOptionsGroupKey() => 'wildnote_shared_dictionaries';
  String _sharedOptionsLayerKey() => 'wildnote_attribute_options_v1';

  List<Map<String, dynamic>> _sharedOptionLayerFields() {
    return [
      {
        'keyname': 'attribute_key',
        'display_name': 'Ключ атрибута',
        'datatype': 'STRING',
      },
      {
        'keyname': 'value',
        'display_name': 'Значение',
        'datatype': 'STRING',
      },
      {
        'keyname': 'normalized_value',
        'display_name': 'Нормализованное значение',
        'datatype': 'STRING',
      },
      {
        'keyname': 'created_by',
        'display_name': 'Автор',
        'datatype': 'STRING',
      },
      {
        'keyname': 'created_at',
        'display_name': 'Дата создания',
        'datatype': 'STRING',
      },
      {
        'keyname': 'updated_at',
        'display_name': 'Дата обновления',
        'datatype': 'STRING',
      },
      {
        'keyname': 'is_deleted',
        'display_name': 'Удалено',
        'datatype': 'INTEGER',
      },
    ];
  }

  Future<int> _createSharedOptionsLayer({
    required String auth,
    required int parentId,
  }) async {
    final payload = {
      'resource': {
        'cls': 'vector_layer',
        'parent': {'id': parentId},
        'display_name': 'WildNote attribute options',
        'keyname': _sharedOptionsLayerKey(),
        'description': 'Общий справочник вариантов для атрибутов WildNote',
      },
      'resmeta': {
        'items': {},
      },
      'vector_layer': {
        'srs': {'id': userLayerSrsId},
        'geometry_type': 'POINT',
        'fields': _sharedOptionLayerFields(),
      }
    };

    final response = await http.post(
      _uri('/resource/'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
        'Не удалось создать общий слой справочников: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
  }

  Future<int> _ensureSharedOptionsLayer({
    required String auth,
  }) async {
    final existingLayer = await _searchOneByKeyname(
      auth: auth,
      keyname: _sharedOptionsLayerKey(),
      cls: 'vector_layer',
    );

    if (existingLayer != null) {
      return (existingLayer['resource'] as Map<String, dynamic>)['id'] as int;
    }

    int groupId;
    final existingGroup = await _searchOneByKeyname(
      auth: auth,
      keyname: _sharedOptionsGroupKey(),
      cls: 'resource_group',
    );

    if (existingGroup != null) {
      groupId = (existingGroup['resource'] as Map<String, dynamic>)['id'] as int;
    } else {
      groupId = await _createResourceGroup(
        auth: auth,
        parentId: rootUsersGroupId,
        displayName: 'WildNote dictionaries',
        keyname: _sharedOptionsGroupKey(),
      );
    }

    return _createSharedOptionsLayer(
      auth: auth,
      parentId: groupId,
    );
  }

  String _normalizeSharedOptionValue(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Map<String, dynamic> _extractSharedOptionFields(Map<String, dynamic> row) {
    final rawFields = row['fields'];

    if (rawFields is Map<String, dynamic>) {
      return rawFields;
    }

    if (rawFields is Map) {
      return rawFields.map((key, value) => MapEntry(key.toString(), value));
    }

    final result = <String, dynamic>{};
    for (final key in const [
      'attribute_key',
      'value',
      'normalized_value',
      'created_by',
      'created_at',
      'updated_at',
      'is_deleted',
    ]) {
      if (row.containsKey(key)) {
        result[key] = row[key];
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> fetchSharedAttributeOptions({
    required UserSession session,
  }) async {
    if (session.accessToken == null || session.accessToken!.isEmpty) {
      return const [];
    }

    final auth = session.accessToken!;
    final layerId = await _ensureSharedOptionsLayer(auth: auth);

    final rows = await _getFeatures(
      auth: auth,
      layerId: layerId,
      query: const {
        'limit': '5000',
        'offset': '0',
        'srs': '4326',
        'fields': 'attribute_key,value,normalized_value,created_by,created_at,updated_at,is_deleted',
      },
    );

    final result = <Map<String, dynamic>>[];

    for (final row in rows) {
      final fields = _extractSharedOptionFields(row);
      final key = _asTrimmedString(fields['attribute_key']);
      final value = _asTrimmedString(fields['value']);
      final isDeleted = _toInt(fields['is_deleted']) == 1;

      if (key == null || value == null) continue;

      result.add({
        'remote_id': _toInt(row['id']),
        'attribute_key': key,
        'value': value,
        'normalized_value':
        _asTrimmedString(fields['normalized_value']) ??
            _normalizeSharedOptionValue(value),
        'created_by': _asTrimmedString(fields['created_by']),
        'is_deleted': isDeleted ? 1 : 0,
      });
    }

    return result;
  }

  Future<int?> _findSharedAttributeOption({
    required String auth,
    required int layerId,
    required String attributeKey,
    required String normalizedValue,
  }) async {
    final rows = await _getFeatures(
      auth: auth,
      layerId: layerId,
      query: {
        'limit': '100',
        'offset': '0',
        'srs': '4326',
        'fields': 'attribute_key,value,normalized_value,is_deleted',
        'fld_attribute_key__eq': attributeKey,
      },
    );

    for (final row in rows) {
      final fields = _extractSharedOptionFields(row);
      final remoteNormalized =
          _asTrimmedString(fields['normalized_value']) ??
              _normalizeSharedOptionValue(
                _asTrimmedString(fields['value']) ?? '',
              );

      if (remoteNormalized == normalizedValue &&
          _toInt(fields['is_deleted']) != 1) {
        return _toInt(row['id']);
      }
    }

    return null;
  }

  Future<int> publishSharedAttributeOption({
    required UserSession session,
    required String attributeKey,
    required String value,
  }) async {
    if (session.accessToken == null || session.accessToken!.isEmpty) {
      throw Exception('Нет авторизации для отправки общего справочника');
    }

    final trimmed = value.trim();
    if (attributeKey.trim().isEmpty || trimmed.isEmpty) {
      throw Exception('Пустое значение справочника');
    }

    final auth = session.accessToken!;
    final layerId = await _ensureSharedOptionsLayer(auth: auth);
    final normalized = _normalizeSharedOptionValue(trimmed);

    final existing = await _findSharedAttributeOption(
      auth: auth,
      layerId: layerId,
      attributeKey: attributeKey,
      normalizedValue: normalized,
    );

    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().toIso8601String();

    final payload = {
      'fields': {
        'attribute_key': attributeKey,
        'value': trimmed,
        'normalized_value': normalized,
        'created_by': session.userLogin,
        'created_at': now,
        'updated_at': now,
        'is_deleted': 0,
      },
      'geom': 'POINT(0 0)',
    };

    final response = await http.post(
      _uri('/resource/$layerId/feature/', {'srs': '4326'}),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Не удалось сохранить вариант в общем справочнике: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
  }


  Future<void> deleteSharedAttributeOption({
    required UserSession session,
    required String attributeKey,
    required String value,
  }) async {
    if (session.accessToken == null || session.accessToken!.isEmpty) {
      throw Exception('Нет авторизации для удаления варианта справочника');
    }

    final trimmed = value.trim();
    if (attributeKey.trim().isEmpty || trimmed.isEmpty) {
      return;
    }

    final auth = session.accessToken!;
    final layerId = await _ensureSharedOptionsLayer(auth: auth);
    final normalized = _normalizeSharedOptionValue(trimmed);

    final featureId = await _findSharedAttributeOption(
      auth: auth,
      layerId: layerId,
      attributeKey: attributeKey,
      normalizedValue: normalized,
    );

    if (featureId == null) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    final payload = {
      'id': featureId,
      'fields': {
        'attribute_key': attributeKey,
        'value': trimmed,
        'normalized_value': normalized,
        'created_by': session.userLogin,
        'updated_at': now,
        'is_deleted': 1,
      },
      'geom': 'POINT(0 0)',
    };

    final response = await http.put(
      _uri('/resource/$layerId/feature/$featureId', {'srs': '4326'}),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось удалить вариант из общего справочника: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<int> _createFeature({
    required String auth,
    required int layerId,
    required Map<String, dynamic> observation,
  }) async {
    final lon = (observation['longitude'] as num).toDouble();
    final lat = (observation['latitude'] as num).toDouble();

    final attributes = observation['attributes'] is Map
        ? Map<String, dynamic>.from(observation['attributes'] as Map)
        : <String, dynamic>{};

    final fields = _buildRemoteFeatureFields(
      observation: observation,
      attributes: attributes,
      photoUrls: const [],
    );

    final payload = {
      'fields': fields,
      'geom': 'POINT($lon $lat)',
    };

    final response = await http.post(
      _uri('/resource/$layerId/feature/', {'srs': '4326'}),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Не удалось создать точку: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['id'] as int;
  }


  Future<void> _updateFeaturePhotoFields({
    required String auth,
    required int layerId,
    required int featureId,
    required Map<String, dynamic> observation,
    required List<String> photoUrls,
  }) async {
    final lon = (observation['longitude'] as num).toDouble();
    final lat = (observation['latitude'] as num).toDouble();

    final attributes = observation['attributes'] is Map
        ? Map<String, dynamic>.from(observation['attributes'] as Map)
        : <String, dynamic>{};

    final fields = _buildRemoteFeatureFields(
      observation: observation,
      attributes: attributes,
      photoUrls: photoUrls,
    );

    final payload = {
      'id': featureId,
      'fields': fields,
      'geom': 'POINT($lon $lat)',
    };

    final response = await http.put(
      _uri('/resource/$layerId/feature/$featureId', {'srs': '4326'}),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Не удалось обновить поля фото: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> _uploadSingleFile({
    required String auth,
    required File file,
    required String remoteName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/component/file_upload/'),
    );

    request.headers.addAll(_headers(auth));
    request.fields['name'] = remoteName;
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: remoteName,
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint('UPLOAD ERROR: ${response.statusCode} ${response.body}');
      throw Exception(
        'Не удалось загрузить файл: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final uploadMeta = data['upload_meta'];

    if (uploadMeta is! List || uploadMeta.isEmpty) {
      throw Exception('Геопортал не вернул upload_meta');
    }

    return Map<String, dynamic>.from(uploadMeta.first as Map);
  }

  Future<int> _attachFileToFeature({
    required String auth,
    required int layerId,
    required int featureId,
    required Map<String, dynamic> uploadMeta,
    required String fileName,
  }) async {
    final payload = {
      'name': fileName,
      'size': uploadMeta['size'],
      'mime_type': uploadMeta['mime_type'],
      'file_upload': {
        'id': uploadMeta['id'],
        'size': uploadMeta['size'],
      },
    };

    final response = await http.post(
      _uri('/resource/$layerId/feature/$featureId/attachment/'),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint('ATTACH ERROR: ${response.statusCode} ${response.body}');
      throw Exception(
        'Не удалось прикрепить файл: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final attachmentId = data['id'];

    if (attachmentId is! int) {
      throw Exception('Геопортал не вернул ID attachment');
    }

    return attachmentId;
  }

  String _attachmentImageUrl({
    required int layerId,
    required int featureId,
    required int attachmentId,
  }) {
    return '$apiBaseUrl/resource/$layerId/feature/$featureId/attachment/$attachmentId/image?size=1600x1600';
  }



  Future<List<Map<String, dynamic>>> _getFeatures({
    required String auth,
    required int layerId,
    required Map<String, String> query,
  }) async {
    final response = await http.get(
      _uri('/resource/$layerId/feature/', query),
      headers: _headers(auth),
    );

    if (response.statusCode != 200) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'Feature list request failed',
        data: {
          'layerId': layerId,
          'statusCode': response.statusCode,
          'body': response.body,
        },
      );
      return const [];
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
    }

    return const [];
  }

  Future<int?> _findFeatureByLocalUuid({
    required String auth,
    required int layerId,
    required Map<String, dynamic> observation,
  }) async {
    final localUuid = _effectiveLocalUuid(observation);
    final userLogin = (observation['user_login'] as String?)?.trim();

    if (localUuid == null || localUuid.isEmpty || userLogin == null || userLogin.isEmpty) {
      return null;
    }

    try {
      final rows = await _getFeatures(
        auth: auth,
        layerId: layerId,
        query: {
          'limit': '1',
          'offset': '0',
          'fields': 'local_uuid,user_login',
          'fld_local_uuid__eq': localUuid,
          'fld_user_login__eq': userLogin,
        },
      );

      if (rows.isEmpty) return null;
      return _toInt(rows.first['id']);
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'Find feature by local uuid failed',
        error: e,
        stackTrace: st,
        data: {'layerId': layerId, 'localUuid': localUuid},
      );
      return null;
    }
  }

  Future<List<String>> _listAttachmentImageUrls({
    required String auth,
    required int layerId,
    required int featureId,
  }) async {
    final response = await http.get(
      _uri('/resource/$layerId/feature/$featureId/attachment/'),
      headers: _headers(auth),
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
    }

    final urls = <String>[];
    for (final item in items) {
      final id = _toInt(item['id']);
      if (id == null) continue;
      urls.add(
        _attachmentImageUrl(
          layerId: layerId,
          featureId: featureId,
          attachmentId: id,
        ),
      );
    }
    return urls;
  }

  Future<_LayerFieldSchema> _loadLayerFieldSchema({
    required String auth,
    required int layerId,
  }) async {
    try {
      final resource = await _getResource(auth: auth, id: layerId);
      final byId = <int, String>{};
      final ordered = <String>[];

      void readFields(dynamic rawFields) {
        if (rawFields is! List) return;

        for (final item in rawFields) {
          if (item is! Map) continue;
          final map = item.map((key, value) => MapEntry(key.toString(), value));
          final id = _toInt(map['id']);
          final keyname = _asTrimmedString(map['keyname']) ??
              _asTrimmedString(map['name']) ??
              _asTrimmedString(map['field_name']);

          if (keyname == null || keyname.isEmpty) continue;
          ordered.add(keyname);
          if (id != null) {
            byId[id] = keyname;
          }
        }
      }

      final vectorLayer = resource['vector_layer'];
      if (vectorLayer is Map) {
        final map = vectorLayer.map((key, value) => MapEntry(key.toString(), value));
        readFields(map['fields']);
      }

      final featureLayer = resource['feature_layer'];
      if (featureLayer is Map) {
        final map = featureLayer.map((key, value) => MapEntry(key.toString(), value));
        readFields(map['fields']);
      }

      readFields(resource['fields']);

      AppLogger.instance.info(
        'GeoportalApiService',
        'Layer field schema loaded',
        data: {
          'layerId': layerId,
          'mappedById': byId.length,
          'ordered': ordered.length,
          'keys': ordered.join(','),
        },
      );

      return _LayerFieldSchema(keyById: byId, orderedKeys: ordered);
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'Layer field schema loading failed',
        error: e,
        stackTrace: st,
        data: {'layerId': layerId},
      );

      return const _LayerFieldSchema(keyById: {}, orderedKeys: []);
    }
  }

  Future<Map<String, dynamic>?> _getFeatureById({
    required String auth,
    required int layerId,
    required int featureId,
  }) async {
    try {
      final response = await http.get(
        _uri('/resource/$layerId/feature/$featureId', {'srs': '4326'}),
        headers: _headers(auth),
      );

      if (response.statusCode != 200) {
        AppLogger.instance.warning(
          'GeoportalApiService',
          'Feature detail request failed',
          data: {
            'layerId': layerId,
            'featureId': featureId,
            'statusCode': response.statusCode,
            'body': response.body,
          },
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'Feature detail request exception',
        error: e,
        stackTrace: st,
        data: {'layerId': layerId, 'featureId': featureId},
      );
    }

    return null;
  }

  Map<String, dynamic> _extractFields(
      Map<String, dynamic> row, {
        _LayerFieldSchema fieldSchema = const _LayerFieldSchema(
          keyById: {},
          orderedKeys: [],
        ),
      }) {
    final result = <String, dynamic>{};

    void addKnownFlatFields(Map<String, dynamic> source) {
      const keys = <String>[
        'local_uuid',
        'local_id',
        'user_login',
        'name',
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

      for (final key in keys) {
        if (source.containsKey(key) && !result.containsKey(key)) {
          result[key] = source[key];
        }
      }
    }

    void addMap(dynamic raw) {
      if (raw is Map<String, dynamic>) {
        result.addAll(raw);
      } else if (raw is Map) {
        result.addAll(raw.map((key, value) => MapEntry(key.toString(), value)));
      }
    }

    final rawFields = row['fields'];

    if (rawFields is Map || rawFields is Map<String, dynamic>) {
      addMap(rawFields);
    } else if (rawFields is List) {
      for (int i = 0; i < rawFields.length; i++) {
        final item = rawFields[i];

        if (item is! Map) {
          if (i < fieldSchema.orderedKeys.length) {
            result[fieldSchema.orderedKeys[i]] = item;
          }
          continue;
        }

        final map = item.map((key, value) => MapEntry(key.toString(), value));

        String? key = _asTrimmedString(map['keyname']) ??
            _asTrimmedString(map['field_name']);

        final field = map['field'];
        int? fieldId;

        if (field is Map) {
          final fieldMap = field.map((k, v) => MapEntry(k.toString(), v));
          key ??= _asTrimmedString(fieldMap['keyname']) ??
              _asTrimmedString(fieldMap['field_name']);
          fieldId = _toInt(fieldMap['id']);
        } else {
          fieldId = _toInt(field);
        }

        fieldId ??= _toInt(map['field_id']) ??
            _toInt(map['field']) ??
            _toInt(map['id']);

        if (fieldId != null && fieldSchema.keyById.containsKey(fieldId)) {
          key = fieldSchema.keyById[fieldId];
        }

        key ??= _asTrimmedString(map['name']);

        if ((key == null || key.isEmpty) && i < fieldSchema.orderedKeys.length) {
          key = fieldSchema.orderedKeys[i];
        }

        if (key == null || key.isEmpty) continue;

        dynamic value;
        if (map.containsKey('value')) {
          value = map['value'];
        } else if (map.containsKey('val')) {
          value = map['val'];
        } else if (map.containsKey('data')) {
          value = map['data'];
        } else if (map.containsKey('v')) {
          value = map['v'];
        } else if (map.containsKey('field_value')) {
          value = map['field_value'];
        } else {
          continue;
        }

        result[key] = value;
      }
    }

    addMap(row['properties']);
    addKnownFlatFields(row);

    void addAlias(String target, List<String> aliases) {
      if (result.containsKey(target) && result[target] != null) return;
      for (final alias in aliases) {
        if (result.containsKey(alias) && result[alias] != null) {
          result[target] = result[alias];
          return;
        }
      }
    }

    addAlias('name', const ['Название', 'Наименование', 'title', 'plant_name']);
    addAlias('description', const ['Описание', 'desc', 'comment', 'Комментарий']);
    addAlias('latitude', const ['Широта', 'lat']);
    addAlias('longitude', const ['Долгота', 'lon', 'lng']);
    addAlias('is_manual', const ['Ручной ввод', 'manual']);
    addAlias('accuracy', const ['Точность', 'accuracy_m']);
    addAlias('created_at', const ['Дата создания', 'Дата', 'created', 'createdAt', 'datetime']);
    addAlias('observed_at', const ['Дата наблюдения', 'observed', 'observedAt']);
    addAlias('gauss_x', const ['Gauss X', 'Гаусс X']);
    addAlias('gauss_y', const ['Gauss Y', 'Гаусс Y']);
    addAlias('zone', const ['Зона']);
    addAlias('attributes_json', const ['Атрибуты JSON', 'attributes']);
    addAlias('attribute_schema_version', const ['Версия схемы атрибутов']);
    addAlias('photo_url_main', const ['Основное фото URL', 'photo_url']);
    addAlias('photo_urls_json', const ['Список фото URL', 'photo_urls']);
    addAlias('photo_count', const ['Количество фото', 'photos_count']);

    return result;
  }

  bool _isValidLatLon(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  (double, double)? _extractLatLonFromFeature(
      Map<String, dynamic> row,
      Map<String, dynamic> fields,
      ) {
    final lat = _finiteDouble(fields['latitude'] ?? row['latitude']);
    final lon = _finiteDouble(fields['longitude'] ?? row['longitude']);
    if (lat != null && lon != null && _isValidLatLon(lat, lon)) {
      return (lat, lon);
    }

    final geom = row['geom'] ?? row['geometry'];

    if (geom is String) {
      final match = RegExp(
        r'POINT\s*\(?\s*([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*\)?',
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
      final map = geom.map((key, value) => MapEntry(key.toString(), value));
      final coordinates = map['coordinates'];
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

  String? _asTrimmedString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
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


  Future<GeoportalPointResult> createPoint({
    required UserSession session,
    required Map<String, dynamic> observation,
    required List<Map<String, dynamic>> photos,
  }) async {
    if (session.accessToken == null || session.accessToken!.isEmpty) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'createPoint rejected: empty access token',
      );

      return const GeoportalPointResult(
        success: false,
        error: 'Нет данных авторизации. Войдите снова.',
      );
    }

    if (session.userLayerId == null) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'createPoint rejected: empty userLayerId',
        data: {'userLogin': session.userLogin},
      );

      return const GeoportalPointResult(
        success: false,
        error: 'Не найден персональный слой пользователя',
      );
    }

    try {
      final auth = session.accessToken!;
      final layerId = session.userLayerId!;

      AppLogger.instance.info(
        'GeoportalApiService',
        'createPoint started',
        data: {
          'userLogin': session.userLogin,
          'layerId': layerId,
          'localId': observation['id'],
          'localUuid': _effectiveLocalUuid(observation),
          'name': observation['name'],
          'latitude': observation['latitude'],
          'longitude': observation['longitude'],
          'createdAt': observation['created_at'],
          'photos': photos.length,
        },
      );

      final existingByLocalUuid = await _findFeatureByLocalUuid(
        auth: auth,
        layerId: layerId,
        observation: observation,
      );

      if (existingByLocalUuid != null) {
        final urls = await _listAttachmentImageUrls(
          auth: auth,
          layerId: layerId,
          featureId: existingByLocalUuid,
        );

        AppLogger.instance.warning(
          'GeoportalApiService',
          'Feature with same local_uuid already exists; create skipped',
          data: {
            'layerId': layerId,
            'localUuid': _effectiveLocalUuid(observation),
            'featureId': existingByLocalUuid,
            'attachmentUrls': urls.length,
          },
        );

        return GeoportalPointResult(
          success: true,
          remoteFeatureId: existingByLocalUuid,
          folderPath: session.remoteFolder,
          photoUrls: urls,
          warning: 'Эта запись уже отправлялась ранее. Новая точка не создана.',
        );
      }

      final featureId = await _createFeature(
        auth: auth,
        layerId: layerId,
        observation: observation,
      );

      AppLogger.instance.info(
        'GeoportalApiService',
        'Feature created',
        data: {
          'layerId': layerId,
          'featureId': featureId,
          'localId': observation['id'],
        },
      );

      final photoUrls = <String>[];
      int availableLocalPhotos = 0;
      int attachErrors = 0;

      for (int i = 0; i < photos.length; i++) {
        final photo = photos[i];
        final filePath = photo['file_path'] as String?;
        if (filePath == null || filePath.isEmpty) continue;

        final file = File(filePath);
        if (!await file.exists()) {
          AppLogger.instance.warning(
            'GeoportalApiService',
            'Local photo file not found',
            data: {
              'featureId': featureId,
              'photoIndex': i,
              'filePath': filePath,
            },
          );
          continue;
        }

        availableLocalPhotos++;

        try {
          final localPhotoKey = _safeIdentityPart(
            _effectiveLocalUuid(observation) ?? observation['id'],
          );
          final remoteName =
              '${session.userLogin}_${localPhotoKey}_${i + 1}${p.extension(file.path)}';

          AppLogger.instance.info(
            'GeoportalApiService',
            'Photo upload started',
            data: {
              'featureId': featureId,
              'photoIndex': i,
              'remoteName': remoteName,
            },
          );

          final uploadMeta = await _uploadSingleFile(
            auth: auth,
            file: file,
            remoteName: remoteName,
          );

          final attachmentId = await _attachFileToFeature(
            auth: auth,
            layerId: layerId,
            featureId: featureId,
            uploadMeta: uploadMeta,
            fileName: remoteName,
          );

          final url = _attachmentImageUrl(
            layerId: layerId,
            featureId: featureId,
            attachmentId: attachmentId,
          );

          photoUrls.add(url);

          AppLogger.instance.info(
            'GeoportalApiService',
            'Photo attached',
            data: {
              'featureId': featureId,
              'photoIndex': i,
              'attachmentId': attachmentId,
            },
          );
        } catch (e, st) {
          attachErrors++;
          debugPrint('PHOTO ATTACH ERROR: $e');

          AppLogger.instance.error(
            'GeoportalApiService',
            'Photo attach exception',
            error: e,
            stackTrace: st,
            data: {
              'featureId': featureId,
              'photoIndex': i,
              'filePath': filePath,
            },
          );
        }
      }

      await _updateFeaturePhotoFields(
        auth: auth,
        layerId: layerId,
        featureId: featureId,
        observation: observation,
        photoUrls: photoUrls,
      );

      String? warning;
      if (attachErrors > 0) {
        warning = 'Не все фото загрузились: $attachErrors из $availableLocalPhotos';
      }

      AppLogger.instance.info(
        'GeoportalApiService',
        'createPoint finished',
        data: {
          'featureId': featureId,
          'photoUrls': photoUrls.length,
          'warning': warning,
        },
      );

      return GeoportalPointResult(
        success: true,
        remoteFeatureId: featureId,
        folderPath: session.remoteFolder,
        photoUrls: photoUrls,
        warning: warning,
      );
    } catch (e, st) {
      AppLogger.instance.error(
        'GeoportalApiService',
        'createPoint exception',
        error: e,
        stackTrace: st,
        data: {
          'localId': observation['id'],
          'name': observation['name'],
        },
      );

      return GeoportalPointResult(
        success: false,
        error: 'Ошибка отправки точки: $e',
      );
    }
  }

  String _normalizeHistoryPhotoUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    var normalized = value;
    if (normalized.startsWith('/api/')) {
      normalized = '$portalBaseUrl$normalized';
    } else if (normalized.startsWith('/resource/')) {
      normalized = '$apiBaseUrl$normalized';
    } else if (normalized.startsWith('/')) {
      normalized = '$portalBaseUrl$normalized';
    }

    if (normalized.contains('/image?')) return normalized;
    if (RegExp(r'/attachment/\d+$', caseSensitive: false).hasMatch(normalized)) {
      return '$normalized/image?size=1600x1600';
    }
    return normalized;
  }

  List<String> _photoUrlsFromHistoryFields(Map<String, dynamic> fields) {
    final urls = <String>[];

    void addUrl(dynamic raw) {
      if (raw == null) return;
      final normalized = _normalizeHistoryPhotoUrl(raw.toString());
      if (normalized.isNotEmpty && !urls.contains(normalized)) {
        urls.add(normalized);
      }
    }

    addUrl(fields['photo_url_main']);

    final rawList = fields['photo_urls_json'];
    if (rawList is List) {
      for (final item in rawList) {
        addUrl(item);
      }
    } else if (rawList is String && rawList.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawList);
        if (decoded is List) {
          for (final item in decoded) {
            addUrl(item);
          }
        } else {
          addUrl(rawList);
        }
      } catch (_) {
        addUrl(rawList);
      }
    }

    return urls;
  }

  Future<List<Map<String, dynamic>>> fetchUserLayerHistory({
    required UserSession session,
    int limit = 5000,
  }) async {
    if (session.accessToken == null || session.accessToken!.isEmpty) {
      return const [];
    }
    if (session.userLayerId == null) {
      return const [];
    }

    final auth = session.accessToken!;
    final layerId = session.userLayerId!;

    AppLogger.instance.info(
      'GeoportalApiService',
      'Fetch user layer history started',
      data: {
        'userLogin': session.userLogin,
        'layerId': layerId,
        'limit': limit,
      },
    );

    final fieldSchema = await _loadLayerFieldSchema(
      auth: auth,
      layerId: layerId,
    );

    final rows = await _getFeatures(
      auth: auth,
      layerId: layerId,
      query: {
        'limit': limit.toString(),
        'offset': '0',
        'srs': '4326',
        'fields': const [
          'local_uuid',
          'local_id',
          'user_login',
          'name',
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
        ].join(','),
        'order_by': '-created_at',
      },
    );

    final result = <Map<String, dynamic>>[];

    for (final row in rows) {
      final featureId = _toInt(row['id']);
      if (featureId == null || featureId <= 0) continue;

      var rowForParsing = row;
      var fields = _extractFields(rowForParsing, fieldSchema: fieldSchema);

      if (_asTrimmedString(fields['name']) == null &&
          _asTrimmedString(fields['created_at']) == null &&
          _asTrimmedString(fields['description']) == null) {
        final detailedRow = await _getFeatureById(
          auth: auth,
          layerId: layerId,
          featureId: featureId,
        );
        if (detailedRow != null) {
          rowForParsing = detailedRow;
          fields = _extractFields(rowForParsing, fieldSchema: fieldSchema);
        }
      }

      final latLon = _extractLatLonFromFeature(rowForParsing, fields);
      final attributes = _parseAttributesJson(fields['attributes_json']);
      final displayName =
          _asTrimmedString(attributes['plant_name']) ??
              _asTrimmedString(fields['name']) ??
              'Без названия';
      final displayDescription =
          _asTrimmedString(attributes['description']) ??
              _asTrimmedString(fields['description']);

      final photoUrls = _photoUrlsFromHistoryFields(fields);
      if (photoUrls.isEmpty) {
        photoUrls.addAll(
          await _listAttachmentImageUrls(
            auth: auth,
            layerId: layerId,
            featureId: featureId,
          ),
        );
      }

      result.add({
        'id': -featureId,
        '_remote_only': true,
        '_source_layer_id': layerId,
        'local_uuid': _asTrimmedString(fields['local_uuid']),
        'local_id': _toInt(fields['local_id']),
        'remote_feature_id': featureId,
        'remote_folder': session.remoteFolder,
        'user_login': _asTrimmedString(fields['user_login']) ?? session.userLogin,
        'name': displayName,
        'description': displayDescription,
        'attributes': attributes,
        'latitude': latLon?.$1,
        'longitude': latLon?.$2,
        'is_manual': _toInt(fields['is_manual']) ?? 0,
        'accuracy': _finiteDouble(fields['accuracy']),
        'created_at': _asTrimmedString(fields['created_at']),
        'observed_at': _asTrimmedString(fields['observed_at']),
        'gauss_x': _finiteDouble(fields['gauss_x']),
        'gauss_y': _finiteDouble(fields['gauss_y']),
        'zone': _toInt(fields['zone']),
        'sync_error': null,
        'synced_at': _asTrimmedString(fields['created_at']),
        'photo_count': _toInt(fields['photo_count']) ?? photoUrls.length,
        'photos': [
          for (int i = 0; i < photoUrls.length; i++)
            {
              'id': -((featureId * 1000) + i + 1),
              'observation_id': -featureId,
              'file_path': photoUrls[i],
              'uploaded_url': photoUrls[i],
              'url': photoUrls[i],
              'order_index': i,
            },
        ],
      });
    }

    result.sort((a, b) {
      final ad = DateTime.tryParse((a['created_at'] ?? '').toString());
      final bd = DateTime.tryParse((b['created_at'] ?? '').toString());
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    AppLogger.instance.info(
      'GeoportalApiService',
      'Fetch user layer history finished',
      data: {
        'userLogin': session.userLogin,
        'layerId': layerId,
        'count': result.length,
      },
    );

    return result;
  }

  Future<int> deleteAllFeaturesInUserLayer({
    required UserSession session,
  }) async {
    if (session.accessToken == null || session.accessToken!.isEmpty) {
      throw Exception('Нет данных авторизации');
    }
    if (session.userLayerId == null) {
      throw Exception('Не найден персональный слой пользователя');
    }

    final auth = session.accessToken!;
    final layerId = session.userLayerId!;

    final rows = await _getFeatures(
      auth: auth,
      layerId: layerId,
      query: const {
        'limit': '5000',
        'offset': '0',
        'fields': 'id',
      },
    );

    int deleted = 0;
    for (final row in rows) {
      final featureId = _toInt(row['id']);
      if (featureId == null || featureId <= 0) continue;

      final response = await http.delete(
        _uri('/resource/$layerId/feature/$featureId'),
        headers: _headers(auth),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Не удалось удалить точку $featureId: ${response.statusCode} ${response.body}',
        );
      }
      deleted++;
    }

    AppLogger.instance.info(
      'GeoportalApiService',
      'All features in user layer deleted',
      data: {
        'userLogin': session.userLogin,
        'layerId': layerId,
        'deleted': deleted,
      },
    );

    return deleted;
  }

}
