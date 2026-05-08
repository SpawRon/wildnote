import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  String _layerKey(String login) => 'plants_${login.toLowerCase()}';
  String _styleKey(String login) => 'style_plants_${login.toLowerCase()}';

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
        displayName: 'plants_$login',
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
        displayName: 'style_plants_$login',
        keyname: styleKey,
      );
    }

    await _ensureLayerInWebMap(
      auth: auth,
      webMapId: sharedWebMapId,
      layerId: layerId,
      styleId: styleId,
      displayName: 'plants_$login',
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

  Future<int> _createFeature({
    required String auth,
    required int layerId,
    required Map<String, dynamic> observation,
  }) async {
    final lon = (observation['longitude'] as num).toDouble();
    final lat = (observation['latitude'] as num).toDouble();

    final payload = {
      'fields': {
        'local_id': observation['id'],
        'user_login': observation['user_login'],
        'name': observation['name'],
        'description': observation['description'],
        'latitude': observation['latitude'],
        'longitude': observation['longitude'],
        'is_manual': observation['is_manual'],
        'accuracy': observation['accuracy'],
        'created_at': observation['created_at'],
        'gauss_x': observation['gauss_x'],
        'gauss_y': observation['gauss_y'],
        'photo_url_main': null,
        'photo_urls_json': jsonEncode(<String>[]),
        'photo_count': 0,
      },
      'geom': 'POINT($lon $lat)',
    };

    final response = await http.post(
      _uri('/resource/$layerId/feature/', {'srs': '4326'}),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint('CREATE FEATURE ERROR: ${response.statusCode} ${response.body}');
      throw Exception(
        'Не удалось создать точку: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final featureId = data['id'];

    if (featureId is! int) {
      throw Exception('Геопортал не вернул ID созданной точки');
    }

    return featureId;
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

    final payload = {
      'id': featureId,
      'fields': {
        'local_id': observation['id'],
        'user_login': observation['user_login'],
        'name': observation['name'],
        'description': observation['description'],
        'latitude': observation['latitude'],
        'longitude': observation['longitude'],
        'is_manual': observation['is_manual'],
        'accuracy': observation['accuracy'],
        'created_at': observation['created_at'],
        'gauss_x': observation['gauss_x'],
        'gauss_y': observation['gauss_y'],
        'photo_url_main': photoUrls.isNotEmpty ? photoUrls.first : null,
        'photo_urls_json': jsonEncode(photoUrls),
        'photo_count': photoUrls.length,
      },
      'geom': 'POINT($lon $lat)',
    };

    final response = await http.put(
      _uri('/resource/$layerId/feature/$featureId', {'srs': '4326'}),
      headers: _headers(auth, json: true),
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      debugPrint('UPDATE FEATURE ERROR: ${response.statusCode} ${response.body}');
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

  Future<int?> _findFeatureByLocalId({
    required String auth,
    required int layerId,
    required Map<String, dynamic> observation,
  }) async {
    final localId = observation['id'];
    final userLogin = (observation['user_login'] as String?)?.trim();

    if (localId == null || userLogin == null || userLogin.isEmpty) {
      return null;
    }

    try {
      final rows = await _getFeatures(
        auth: auth,
        layerId: layerId,
        query: {
          'limit': '1',
          'offset': '0',
          'fields': 'local_id,user_login',
          'fld_local_id__eq': localId.toString(),
          'fld_user_login__eq': userLogin,
        },
      );

      if (rows.isEmpty) return null;
      return _toInt(rows.first['id']);
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'Find feature by local id failed',
        error: e,
        stackTrace: st,
        data: {'layerId': layerId, 'localId': localId},
      );
      return null;
    }
  }

  Future<int?> _findRecentDuplicateFeature({
    required String auth,
    required int layerId,
    required Map<String, dynamic> observation,
    Duration window = const Duration(seconds: 45),
  }) async {
    final userLogin = (observation['user_login'] as String?)?.trim();
    final name = (observation['name'] as String?)?.trim();
    final description = (observation['description'] as String?)?.trim() ?? '';
    final latitude = _finiteDouble(observation['latitude']);
    final longitude = _finiteDouble(observation['longitude']);
    final createdAt = DateTime.tryParse(
      (observation['created_at'] as String?)?.trim() ?? '',
    );

    if (userLogin == null ||
        userLogin.isEmpty ||
        name == null ||
        name.isEmpty ||
        latitude == null ||
        longitude == null ||
        createdAt == null) {
      return null;
    }

    try {
      final rows = await _getFeatures(
        auth: auth,
        layerId: layerId,
        query: {
          'limit': '80',
          'offset': '0',
          'srs': '4326',
          'fields': 'local_id,user_login,name,description,latitude,longitude,created_at',
          'fld_user_login__eq': userLogin,
          'fld_name__eq': name,
          'order_by': '-created_at',
        },
      );

      for (final row in rows) {
        final fields = _extractFields(row);
        final remoteLocalId = _toInt(fields['local_id']);
        final currentLocalId = _toInt(observation['id']);

        if (currentLocalId != null &&
            remoteLocalId != null &&
            currentLocalId == remoteLocalId) {
          continue;
        }

        final remoteUser = _asTrimmedString(fields['user_login']);
        final remoteName = _asTrimmedString(fields['name']);
        final remoteDescription =
            _asTrimmedString(fields['description']) ?? '';

        if (remoteUser != userLogin) continue;
        if (remoteName != name) continue;
        if (remoteDescription != description) continue;

        final remoteLat = _finiteDouble(fields['latitude']);
        final remoteLon = _finiteDouble(fields['longitude']);
        if (remoteLat == null || remoteLon == null) continue;

        final meters = _approxDistanceMeters(
          latitude,
          longitude,
          remoteLat,
          remoteLon,
        );
        if (meters > 1.5) continue;

        final remoteCreatedAt =
        DateTime.tryParse(_asTrimmedString(fields['created_at']) ?? '');
        if (remoteCreatedAt == null) continue;

        final diff = createdAt.isAfter(remoteCreatedAt)
            ? createdAt.difference(remoteCreatedAt)
            : remoteCreatedAt.difference(createdAt);
        if (diff <= window) {
          final featureId = _toInt(row['id']);
          if (featureId != null) {
            AppLogger.instance.warning(
              'GeoportalApiService',
              'Recent duplicate feature found',
              data: {
                'layerId': layerId,
                'featureId': featureId,
                'localId': currentLocalId,
                'remoteLocalId': remoteLocalId,
                'secondsDiff': diff.inSeconds,
                'distanceMeters': meters,
              },
            );
            return featureId;
          }
        }
      }
    } catch (e, st) {
      AppLogger.instance.warning(
        'GeoportalApiService',
        'Recent duplicate check failed',
        error: e,
        stackTrace: st,
        data: {'layerId': layerId, 'name': name},
      );
    }

    return null;
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

  Map<String, dynamic> _extractFields(Map<String, dynamic> row) {
    final rawFields = row['fields'];
    if (rawFields is Map<String, dynamic>) return rawFields;
    if (rawFields is Map) {
      return rawFields.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
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

  double _approxDistanceMeters(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const earthRadius = 6371000.0;
    final lat1Rad = lat1 * 3.141592653589793 / 180.0;
    final lat2Rad = lat2 * 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    final dLon = (lon2 - lon1) * 3.141592653589793 / 180.0;
    final x = dLon * math.cos((lat1Rad + lat2Rad) / 2.0);
    final y = dLat;
    return earthRadius * math.sqrt((x * x) + (y * y));
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
          'name': observation['name'],
          'latitude': observation['latitude'],
          'longitude': observation['longitude'],
          'createdAt': observation['created_at'],
          'photos': photos.length,
        },
      );

      final existingByLocalId = await _findFeatureByLocalId(
        auth: auth,
        layerId: layerId,
        observation: observation,
      );

      if (existingByLocalId != null) {
        final urls = await _listAttachmentImageUrls(
          auth: auth,
          layerId: layerId,
          featureId: existingByLocalId,
        );

        AppLogger.instance.warning(
          'GeoportalApiService',
          'Feature with same local_id already exists; create skipped',
          data: {
            'layerId': layerId,
            'localId': observation['id'],
            'featureId': existingByLocalId,
            'attachmentUrls': urls.length,
          },
        );

        return GeoportalPointResult(
          success: true,
          remoteFeatureId: existingByLocalId,
          folderPath: session.remoteFolder,
          photoUrls: urls,
          warning: 'Такая локальная запись уже есть на сервере. Новая точка не создана.',
        );
      }

      final recentDuplicateId = await _findRecentDuplicateFeature(
        auth: auth,
        layerId: layerId,
        observation: observation,
      );

      if (recentDuplicateId != null) {
        final urls = await _listAttachmentImageUrls(
          auth: auth,
          layerId: layerId,
          featureId: recentDuplicateId,
        );

        AppLogger.instance.warning(
          'GeoportalApiService',
          'Recent probable duplicate found; create skipped',
          data: {
            'layerId': layerId,
            'localId': observation['id'],
            'featureId': recentDuplicateId,
            'attachmentUrls': urls.length,
          },
        );

        return GeoportalPointResult(
          success: true,
          remoteFeatureId: recentDuplicateId,
          folderPath: session.remoteFolder,
          photoUrls: urls,
          warning: 'Найдена похожая точка, созданная недавно. Новая точка не создана.',
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
          final remoteName =
              '${session.userLogin}_${observation['id']}_${i + 1}${p.extension(file.path)}';

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
}
