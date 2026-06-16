import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class ObservationStatus {
  static const int localOnly = 0;
  static const int queued = 1;
  static const int synced = 2;
  static const int error = 3;
}

class PlantAttributeKeys {
  static const String plantName = 'plant_name';
  static const String description = 'description';
  static const String identificationStatus = 'identification_status';
  static const String habitat = 'habitat';
  static const String soilType = 'soil_type';
  static const String moisture = 'moisture';
  static const String lightCondition = 'light_condition';
  static const String lifeStage = 'life_stage';
  static const String phenophase = 'phenophase';
  static const String plantCondition = 'plant_condition';
  static const String abundanceCategory = 'abundance_category';
  static const String individualCount = 'individual_count';
  static const String areaOccupied = 'area_occupied';
  static const String anthropogenicImpact = 'anthropogenic_impact';
  static const String threatFactor = 'threat_factor';
  static const String protectionStatus = 'protection_status';
  static const String comment = 'comment';
}

class DatabaseHelper {
  DatabaseHelper._privateConstructor();

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static const String _databaseName = 'wildnote.db';

  static const int _databaseVersion = 6;

  static const int _plantSchemaVersion = 4;

  static const Set<String> _numberAttributeKeys = <String>{
    PlantAttributeKeys.individualCount,
    PlantAttributeKeys.areaOccupied,
  };

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createV4Schema(db);
    await _seedV4AttributeDefinitions(db);
    await _seedV4AttributeOptions(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await _dropAllKnownTables(db);
      await _createV4Schema(db);
      await _seedV4AttributeDefinitions(db);
      await _seedV4AttributeOptions(db);
      return;
    }

    if (oldVersion < 6) {
      await _migrateToV6(db);
    }

    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
  }

  Future<void> _migrateToV6(Database db) async {
    final now = DateTime.now().toIso8601String();

    await db.delete(
      'attribute_definitions',
      where: 'attribute_key = ?',
      whereArgs: [PlantAttributeKeys.comment],
    );

    await db.delete(
      'attribute_options',
      where: 'attribute_key = ? OR normalized_value = ?',
      whereArgs: [PlantAttributeKeys.comment, normalizeOptionValue('Другое')],
    );

    await db.update(
      'attribute_options',
      {
        'sync_status': 0,
        'synced_at': now,
      },
      where: 'is_builtin = 0 AND sync_status = 1 AND remote_id IS NULL',
    );
  }

  Future<void> _migrateToV7(Database db) async {
    // место для будущей миграции без пересоздания всей базы
  }

  Future<void> _dropAllKnownTables(Database db) async {
    await db.execute('DROP TABLE IF EXISTS photos');
    await db.execute('DROP TABLE IF EXISTS observation_attributes');
    await db.execute('DROP TABLE IF EXISTS attribute_options');
    await db.execute('DROP TABLE IF EXISTS attribute_definitions');
    await db.execute('DROP TABLE IF EXISTS observations');
    await db.execute('DROP TABLE IF EXISTS user_resources');
  }

  Future<void> _createV4Schema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_uuid TEXT NOT NULL UNIQUE,
        user_login TEXT NOT NULL,

        observed_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT,

        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        is_manual INTEGER NOT NULL DEFAULT 0,
        accuracy REAL,
        altitude REAL,

        gauss_x REAL,
        gauss_y REAL,
        zone INTEGER,

        status INTEGER NOT NULL DEFAULT 0,
        remote_feature_id INTEGER,
        remote_folder TEXT,
        sync_error TEXT,
        synced_at TEXT,

        deleted_at TEXT,
        schema_version INTEGER NOT NULL DEFAULT 4
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attribute_definitions (
        attribute_key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        value_type TEXT NOT NULL,
        input_type TEXT NOT NULL,

        is_required INTEGER NOT NULL DEFAULT 0,
        is_core INTEGER NOT NULL DEFAULT 0,
        is_synced INTEGER NOT NULL DEFAULT 1,
        allow_custom INTEGER NOT NULL DEFAULT 1,

        hint TEXT,
        dwc_term TEXT,

        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attribute_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        attribute_key TEXT NOT NULL,
        value TEXT NOT NULL,
        normalized_value TEXT NOT NULL,

        is_builtin INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,

        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,

        remote_id INTEGER,
        synced_at TEXT,
        sync_status INTEGER NOT NULL DEFAULT 0,

        FOREIGN KEY (attribute_key)
          REFERENCES attribute_definitions(attribute_key)
          ON DELETE CASCADE,

        UNIQUE(attribute_key, normalized_value)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS observation_attributes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        observation_id INTEGER NOT NULL,

        attribute_key TEXT NOT NULL,
        value_text TEXT,
        value_number REAL,
        value_bool INTEGER,
        option_id INTEGER,

        created_at TEXT NOT NULL,
        updated_at TEXT,

        FOREIGN KEY (observation_id)
          REFERENCES observations(id)
          ON DELETE CASCADE,

        FOREIGN KEY (option_id)
          REFERENCES attribute_options(id)
          ON DELETE SET NULL,

        UNIQUE(observation_id, attribute_key)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        observation_id INTEGER NOT NULL,

        file_path TEXT,
        uploaded_url TEXT,
        remote_attachment_id INTEGER,

        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,

        FOREIGN KEY (observation_id)
          REFERENCES observations(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_resources (
        user_login TEXT PRIMARY KEY,
        user_folder_id INTEGER,
        user_layer_id INTEGER,
        user_style_id INTEGER,
        webmap_id INTEGER,
        updated_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_observations_user_created '
          'ON observations(user_login, created_at)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_observations_status '
          'ON observations(status)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_observation_attributes_observation '
          'ON observation_attributes(observation_id)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_observation_attributes_key '
          'ON observation_attributes(attribute_key)',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attribute_options_key_value '
          'ON attribute_options(attribute_key, normalized_value)',
    );
  }

  Future<void> _seedV4AttributeDefinitions(Database db) async {
    final now = DateTime.now().toIso8601String();

    Future<void> add({
      required String key,
      required String title,
      required String valueType,
      required String inputType,
      required int sortOrder,
      bool requiredField = false,
      bool core = false,
      bool allowCustom = true,
      String? hint,
      String? dwcTerm,
    }) async {
      await db.insert(
        'attribute_definitions',
        {
          'attribute_key': key,
          'title': title,
          'value_type': valueType,
          'input_type': inputType,
          'is_required': requiredField ? 1 : 0,
          'is_core': core ? 1 : 0,
          'is_synced': 1,
          'allow_custom': allowCustom ? 1 : 0,
          'hint': hint,
          'dwc_term': dwcTerm,
          'sort_order': sortOrder,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await add(
      key: PlantAttributeKeys.plantName,
      title: 'Название растения',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 10,
      requiredField: true,
      core: true,
      dwcTerm: 'scientificName',
    );

    await add(
      key: PlantAttributeKeys.description,
      title: 'Описание',
      valueType: 'text',
      inputType: 'multiline_text',
      sortOrder: 20,
      core: true,
    );

    await add(
      key: PlantAttributeKeys.identificationStatus,
      title: 'Статус определения',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 30,
    );

    await add(
      key: PlantAttributeKeys.habitat,
      title: 'Местообитание',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 40,
      dwcTerm: 'habitat',
    );

    await add(
      key: PlantAttributeKeys.soilType,
      title: 'Тип почвы',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 50,
    );

    await add(
      key: PlantAttributeKeys.moisture,
      title: 'Увлажнение',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 60,
    );

    await add(
      key: PlantAttributeKeys.lightCondition,
      title: 'Освещенность',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 70,
    );

    await add(
      key: PlantAttributeKeys.lifeStage,
      title: 'Жизненная стадия',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 80,
      dwcTerm: 'lifeStage',
    );

    await add(
      key: PlantAttributeKeys.phenophase,
      title: 'Фенологическая фаза',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 90,
      dwcTerm: 'reproductiveCondition',
    );

    await add(
      key: PlantAttributeKeys.plantCondition,
      title: 'Состояние растения',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 100,
      dwcTerm: 'vitality',
    );

    await add(
      key: PlantAttributeKeys.abundanceCategory,
      title: 'Категория численности',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 110,
    );

    await add(
      key: PlantAttributeKeys.individualCount,
      title: 'Количество особей',
      valueType: 'number',
      inputType: 'number',
      sortOrder: 120,
      allowCustom: false,
      dwcTerm: 'individualCount',
    );

    await add(
      key: PlantAttributeKeys.areaOccupied,
      title: 'Площадь участка, м²',
      valueType: 'number',
      inputType: 'number',
      sortOrder: 130,
    );

    await add(
      key: PlantAttributeKeys.anthropogenicImpact,
      title: 'Антропогенное воздействие',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 140,
    );

    await add(
      key: PlantAttributeKeys.threatFactor,
      title: 'Угрожающий фактор',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 150,
    );

    await add(
      key: PlantAttributeKeys.protectionStatus,
      title: 'Охранный статус',
      valueType: 'text',
      inputType: 'searchable_list',
      sortOrder: 160,
    );

    await add(
      key: PlantAttributeKeys.comment,
      title: 'Примечание',
      valueType: 'text',
      inputType: 'multiline_text',
      sortOrder: 170,
    );
  }

  Future<void> _seedV4AttributeOptions(Database db) async {
    final now = DateTime.now().toIso8601String();

    Future<void> add(String key, List<String> values) async {
      for (final value in values) {
        final normalized = normalizeOptionValue(value);

        await db.insert(
          'attribute_options',
          {
            'attribute_key': key,
            'value': value,
            'normalized_value': normalized,
            'is_builtin': 1,
            'is_deleted': 0,
            'created_at': now,
            'updated_at': now,
            'sync_status': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    await add(PlantAttributeKeys.identificationStatus, [
      'Предварительно',
      'Подтверждено',
      'Требует проверки',
      'Не определено до вида',
    ]);

    await add(PlantAttributeKeys.habitat, [
      'Лес',
      'Луг',
      'Болото',
      'Тундра',
      'Побережье',
      'Берег водоема',
      'Каменистый склон',
      'Скала',
      'Осыпь',
      'Дорога или обочина',
      'Нарушенный участок',
      'Городская территория',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.soilType, [
      'Торфяная',
      'Песчаная',
      'Суглинистая',
      'Глинистая',
      'Каменистая',
      'Известковая',
      'Подзолистая',
      'Заболоченная',
      'Переувлажненная',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.moisture, [
      'Сухо',
      'Умеренно влажно',
      'Влажно',
      'Переувлажнено',
      'Заболочено',
      'Водная среда',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.lightCondition, [
      'Открытое место',
      'Полутень',
      'Тень',
      'Под пологом леса',
      'Сильное затенение',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.lifeStage, [
      'Проросток',
      'Молодое растение',
      'Взрослое вегетативное',
      'Взрослое генеративное',
      'Стареющее растение',
      'Отмирающее растение',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.phenophase, [
      'Без цветения',
      'Бутонизация',
      'Цветение',
      'Плодоношение',
      'Семена',
      'После плодоношения',
      'Окончание вегетации',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.plantCondition, [
      'Хорошее',
      'Удовлетворительное',
      'Ослабленное',
      'Поврежденное',
      'Усыхающее',
      'Погибшее',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.abundanceCategory, [
      'Одиночное растение',
      'Несколько особей',
      'Группа',
      'Куртина',
      'Популяция',
      'Массовое скопление',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.anthropogenicImpact, [
      'Не выявлено',
      'Слабое',
      'Умеренное',
      'Сильное',
      'Очень сильное',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.threatFactor, [
      'Нет явных угроз',
      'Вытаптывание',
      'Сбор растений',
      'Выкапывание',
      'Строительство',
      'Дорога рядом',
      'Рекреационная нагрузка',
      'Загрязнение',
      'Осушение',
      'Зарастание',
      'Выпас',
      'Пожар',
      'Не определено',
    ]);

    await add(PlantAttributeKeys.protectionStatus, [
      'Не указан',
      'Красная книга РФ',
      'Красная книга региона',
      'ООПТ',
      'Локально редкий вид',
      'Требует проверки',
    ]);
  }

  String normalizeOptionValue(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<int> insertObservation({
    required Map<String, dynamic> observation,
    required List<String> photoPaths,
    required Map<String, Object?> attributes,
  }) async {
    final db = await database;

    return db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();

      final userLogin = observation['user_login']?.toString().trim() ?? '';
      if (userLogin.isEmpty) {
        throw Exception('Нельзя сохранить наблюдение без user_login');
      }

      final latitude = _toDouble(observation['latitude']);
      final longitude = _toDouble(observation['longitude']);

      if (latitude == null || longitude == null) {
        throw Exception('Нельзя сохранить наблюдение без координат');
      }

      final createdAt =
          observation['created_at']?.toString() ?? DateTime.now().toIso8601String();

      final observedAt = observation['observed_at']?.toString() ?? createdAt;

      final rawLocalUuid = observation['local_uuid']?.toString().trim();
      final localUuid = rawLocalUuid != null && rawLocalUuid.isNotEmpty
          ? rawLocalUuid
          : _buildLocalUuid(userLogin);

      final observationId = await txn.insert(
        'observations',
        {
          'local_uuid': localUuid,
          'user_login': userLogin,
          'observed_at': observedAt,
          'created_at': createdAt,
          'updated_at': observation['updated_at']?.toString() ?? now,
          'latitude': latitude,
          'longitude': longitude,
          'is_manual': _toInt(observation['is_manual']) ?? 0,
          'accuracy': _toDouble(observation['accuracy']),
          'altitude': _toDouble(observation['altitude']),
          'gauss_x': _toDouble(observation['gauss_x']),
          'gauss_y': _toDouble(observation['gauss_y']),
          'zone': _toInt(observation['zone']),
          'status': _toInt(observation['status']) ?? ObservationStatus.queued,
          'remote_feature_id': _toInt(observation['remote_feature_id']),
          'remote_folder': observation['remote_folder']?.toString(),
          'sync_error': observation['sync_error']?.toString(),
          'synced_at': observation['synced_at']?.toString(),
          'deleted_at': observation['deleted_at']?.toString(),
          'schema_version': _plantSchemaVersion,
        },
      );

      await _insertAttributesInTransaction(
        txn: txn,
        observationId: observationId,
        attributes: attributes,
        now: now,
      );

      for (int i = 0; i < photoPaths.length; i++) {
        final path = photoPaths[i].trim();
        if (path.isEmpty) continue;

        await txn.insert('photos', {
          'observation_id': observationId,
          'file_path': path,
          'order_index': i,
          'created_at': now,
        });
      }

      return observationId;
    });
  }

  Future<void> _insertAttributesInTransaction({
    required Transaction txn,
    required int observationId,
    required Map<String, Object?> attributes,
    required String now,
  }) async {
    for (final entry in attributes.entries) {
      final key = entry.key.trim();
      final rawValue = entry.value;

      if (key.isEmpty || rawValue == null) continue;

      final valueText = _attributeValueToStorageText(rawValue);
      if (valueText.isEmpty) continue;

      double? valueNumber;

      if (_numberAttributeKeys.contains(key)) {
        valueNumber = rawValue is num
            ? rawValue.toDouble()
            : double.tryParse(valueText.replaceAll(',', '.'));
      }

      await txn.insert(
        'observation_attributes',
        {
          'observation_id': observationId,
          'attribute_key': key,
          'value_text': valueText,
          'value_number': valueNumber,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  String _attributeValueToStorageText(Object rawValue) {
    if (rawValue is Iterable) {
      final values = rawValue
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();

      if (values.isEmpty) return '';
      return jsonEncode(values);
    }

    if (rawValue is Map) {
      return jsonEncode(rawValue);
    }

    return rawValue.toString().trim();
  }

  Object? _decodeStoredAttributeValue(String? raw) {
    if (raw == null) return null;

    final value = raw.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('[') || value.startsWith('{')) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }

    return value;
  }

  Future<Map<String, Object?>> getObservationAttributes(int observationId) async {
    final db = await database;

    final rows = await db.query(
      'observation_attributes',
      where: 'observation_id = ?',
      whereArgs: [observationId],
    );

    final result = <String, Object?>{};

    for (final row in rows) {
      final key = row['attribute_key']?.toString();
      if (key == null || key.isEmpty) continue;

      final valueText = row['value_text'];
      final valueNumber = row['value_number'];
      final valueBool = row['value_bool'];

      if (_numberAttributeKeys.contains(key) && valueNumber != null) {
        result[key] = valueNumber;
      } else if (valueBool != null) {
        result[key] = valueBool;
      } else {
        result[key] = _decodeStoredAttributeValue(valueText?.toString());
      }
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getAttributeDefinitions() async {
    final db = await database;

    return db.query(
      'attribute_definitions',
      orderBy: 'sort_order ASC, title ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAttributeOptions({
    required String attributeKey,
    String? search,
    int limit = 50,
  }) async {
    final db = await database;

    final normalizedSearch = search == null || search.trim().isEmpty
        ? null
        : normalizeOptionValue(search);

    return db.query(
      'attribute_options',
      where: normalizedSearch == null
          ? 'attribute_key = ? AND is_deleted = 0'
          : 'attribute_key = ? AND is_deleted = 0 AND normalized_value LIKE ?',
      whereArgs: normalizedSearch == null
          ? [attributeKey]
          : [attributeKey, '%$normalizedSearch%'],
      orderBy: 'is_builtin DESC, value ASC',
      limit: limit,
    );
  }

  Future<void> upsertAttributeOption({
    required String attributeKey,
    required String value,
    required String createdBy,
    int syncStatus = 1,
    int? remoteId,
    bool builtin = false,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final trimmed = value.trim();

    if (trimmed.isEmpty) return;

    final normalized = normalizeOptionValue(trimmed);

    await db.insert(
      'attribute_options',
      {
        'attribute_key': attributeKey,
        'value': trimmed,
        'normalized_value': normalized,
        'is_builtin': builtin ? 1 : 0,
        'is_deleted': 0,
        'created_by': createdBy,
        'created_at': now,
        'updated_at': now,
        'remote_id': remoteId,
        'synced_at': syncStatus == 0 ? now : null,
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (remoteId != null || syncStatus == 0) {
      await db.update(
        'attribute_options',
        {
          'value': trimmed,
          'remote_id': remoteId,
          'synced_at': now,
          'sync_status': syncStatus,
          'updated_at': now,
        },
        where: 'attribute_key = ? AND normalized_value = ?',
        whereArgs: [attributeKey, normalized],
      );
    }
  }

  Future<void> saveRemoteAttributeOption({
    required String attributeKey,
    required String value,
    required int remoteId,
    String? createdBy,
  }) async {
    await upsertAttributeOption(
      attributeKey: attributeKey,
      value: value,
      createdBy: createdBy ?? 'remote',
      remoteId: remoteId,
      syncStatus: 0,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedAttributeOptions({
    int limit = 100,
  }) async {
    final db = await database;

    return db.query(
      'attribute_options',
      where: 'is_deleted = 0 AND is_builtin = 0 AND sync_status = 1',
      orderBy: 'datetime(created_at) ASC',
      limit: limit,
    );
  }

  Future<void> markAttributeOptionSynced({
    required int id,
    int? remoteId,
  }) async {
    final db = await database;

    await db.update(
      'attribute_options',
      {
        'remote_id': ?remoteId,
        'synced_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }



  Future<Map<String, dynamic>?> getAttributeOption({
    required String attributeKey,
    required String value,
  }) async {
    final db = await database;
    final normalized = normalizeOptionValue(value);

    final rows = await db.query(
      'attribute_options',
      where: 'attribute_key = ? AND normalized_value = ?',
      whereArgs: [attributeKey, normalized],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<int?> markAttributeOptionDeleted({
    required String attributeKey,
    required String value,
  }) async {
    final db = await database;
    final normalized = normalizeOptionValue(value);
    final now = DateTime.now().toIso8601String();

    final rows = await db.query(
      'attribute_options',
      where: 'attribute_key = ? AND normalized_value = ?',
      whereArgs: [attributeKey, normalized],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final remoteIdRaw = rows.first['remote_id'];
    final remoteId = _toInt(remoteIdRaw);

    await db.update(
      'attribute_options',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 0,
      },
      where: 'attribute_key = ? AND normalized_value = ?',
      whereArgs: [attributeKey, normalized],
    );

    return remoteId;
  }

  Future<List<Map<String, dynamic>>> getObservations({
    required String userLogin,
  }) async {
    final db = await database;

    final observationRows = await db.query(
      'observations',
      where: 'user_login = ? AND deleted_at IS NULL',
      whereArgs: [userLogin],
      orderBy: 'datetime(created_at) DESC',
    );

    if (observationRows.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final ids = observationRows
        .map((row) => _toInt(row['id']))
        .whereType<int>()
        .toList(growable: false);

    if (ids.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final placeholders = List<String>.filled(ids.length, '?').join(',');

    final photoRows = await db.query(
      'photos',
      where: 'observation_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'observation_id ASC, order_index ASC',
    );

    final attributeRows = await db.query(
      'observation_attributes',
      where: 'observation_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'observation_id ASC',
    );

    final photosByObservation = <int, List<Map<String, dynamic>>>{};
    for (final photo in photoRows) {
      final observationId = _toInt(photo['observation_id']);
      if (observationId == null) continue;

      photosByObservation
          .putIfAbsent(observationId, () => <Map<String, dynamic>>[])
          .add(Map<String, dynamic>.from(photo));
    }

    final attributesByObservation = <int, Map<String, Object?>>{};
    for (final row in attributeRows) {
      final observationId = _toInt(row['observation_id']);
      if (observationId == null) continue;

      final key = row['attribute_key']?.toString();
      if (key == null || key.isEmpty) continue;

      final valueText = row['value_text'];
      final valueNumber = row['value_number'];
      final valueBool = row['value_bool'];

      Object? value;
      if (_numberAttributeKeys.contains(key) && valueNumber != null) {
        value = _toDouble(valueNumber);
      } else if (valueBool != null) {
        value = _toInt(valueBool);
      } else {
        value = _decodeStoredAttributeValue(valueText?.toString());
      }

      if (value == null) continue;

      attributesByObservation
          .putIfAbsent(observationId, () => <String, Object?>{})[key] = value;
    }

    final result = <Map<String, dynamic>>[];

    for (final row in observationRows) {
      final id = _toInt(row['id']);
      if (id == null) continue;

      final attributes = attributesByObservation[id] ?? <String, Object?>{};
      final photos = photosByObservation[id] ?? const <Map<String, dynamic>>[];

      result.add({
        ...row,
        'name': attributes[PlantAttributeKeys.plantName] ?? 'Без названия',
        'description': attributes[PlantAttributeKeys.description],
        'attributes': attributes,
        'photos': photos,
      });
    }

    return result;
  }

  Future<Map<String, dynamic>?> getObservationById(int id) async {
    final db = await database;

    final rows = await db.query(
      'observations',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final observation = rows.first;

    final photos = await db.query(
      'photos',
      where: 'observation_id = ?',
      whereArgs: [id],
      orderBy: 'order_index ASC',
    );

    final attributes = await getObservationAttributes(id);

    return {
      ...observation,
      'name': attributes[PlantAttributeKeys.plantName] ?? 'Без названия',
      'description': attributes[PlantAttributeKeys.description],
      'attributes': attributes,
      'photos': photos,
    };
  }

  Future<List<Map<String, dynamic>>> getPendingObservations({
    required String userLogin,
  }) async {
    final db = await database;

    return db.query(
      'observations',
      where: 'user_login = ? AND deleted_at IS NULL AND (status = ? OR status = ?)',
      whereArgs: [userLogin, ObservationStatus.queued, ObservationStatus.error],
      orderBy: 'datetime(created_at) DESC',
    );
  }

  Future<void> updateObservationStatus({
    required int id,
    required int status,
    String? error,
    int? remoteFeatureId,
    String? remoteFolder,
    String? syncedAt,
  }) async {
    final db = await database;

    final fields = <String, Object?>{
      'status': status,
      'sync_error': error,
      'remote_feature_id': remoteFeatureId,
      'remote_folder': remoteFolder,
      'synced_at': syncedAt,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await db.update(
      'observations',
      fields,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePhotoUploadedUrl({
    required int photoId,
    required String uploadedUrl,
    int? remoteAttachmentId,
  }) async {
    final db = await database;

    await db.update(
      'photos',
      {
        'uploaded_url': uploadedUrl,
        'remote_attachment_id': ?remoteAttachmentId,
      },
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  Future<int> deleteObservation(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return db.update(
      'observations',
      {
        'deleted_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> hardDeleteObservation(int id) async {
    final db = await database;

    await db.delete(
      'observations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllObservations({
    required String userLogin,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'observations',
      {
        'deleted_at': now,
        'updated_at': now,
      },
      where: 'user_login = ?',
      whereArgs: [userLogin],
    );
  }

  Future<void> hardClearAllObservations({
    required String userLogin,
  }) async {
    final db = await database;

    await db.delete(
      'observations',
      where: 'user_login = ?',
      whereArgs: [userLogin],
    );
  }

  Future<void> saveUserResources({
    required String userLogin,
    required int userFolderId,
    required int userLayerId,
    required int userStyleId,
    required int webMapId,
  }) async {
    final db = await database;

    await db.insert(
      'user_resources',
      {
        'user_login': userLogin,
        'user_folder_id': userFolderId,
        'user_layer_id': userLayerId,
        'user_style_id': userStyleId,
        'webmap_id': webMapId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUserResources(String userLogin) async {
    final db = await database;

    final rows = await db.query(
      'user_resources',
      where: 'user_login = ?',
      whereArgs: [userLogin],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  String _buildLocalUuid(String userLogin) {
    final millis = DateTime.now().microsecondsSinceEpoch;
    final random = math.Random().nextInt(0x7fffffff).toRadixString(16);
    return '${userLogin}_${millis}_$random';
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value.isFinite ? value : null;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();

    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value.toString());
  }
}
