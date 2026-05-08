import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class ObservationStatus {
  static const int localOnly = 0;
  static const int queued = 1;
  static const int synced = 2;
  static const int error = 3;
}

class DatabaseHelper {
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static const String _databaseName = 'wildnote.db';
  static const int _databaseVersion = 3;

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
    await db.execute('''
      CREATE TABLE observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_login TEXT NOT NULL,
        name TEXT,
        description TEXT,
        latitude REAL,
        longitude REAL,
        is_manual INTEGER DEFAULT 0,
        accuracy REAL,
        created_at TEXT NOT NULL,
        status INTEGER DEFAULT 0,
        gauss_x REAL,
        gauss_y REAL,
        zone INTEGER,
        remote_feature_id INTEGER,
        remote_folder TEXT,
        sync_error TEXT,
        synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        observation_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        uploaded_url TEXT,
        order_index INTEGER DEFAULT 0,
        FOREIGN KEY (observation_id) REFERENCES observations(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE user_resources (
        user_login TEXT PRIMARY KEY,
        user_folder_id INTEGER,
        user_layer_id INTEGER,
        user_style_id INTEGER,
        webmap_id INTEGER,
        updated_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
        db,
        'observations',
        'user_login',
        "TEXT NOT NULL DEFAULT 'guest'",
      );
      await _addColumnIfMissing(
        db,
        'observations',
        'remote_feature_id',
        'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        'observations',
        'remote_folder',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        'observations',
        'sync_error',
        'TEXT',
      );
      await _addColumnIfMissing(
        db,
        'observations',
        'synced_at',
        'TEXT',
      );
    }

    if (oldVersion < 3) {
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
    }
  }

  Future<void> _addColumnIfMissing(
      Database db,
      String table,
      String column,
      String definition,
      ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<int> insertObservation({
    required Map<String, dynamic> observation,
    required List<String> photoPaths,
  }) async {
    final db = await database;

    return db.transaction<int>((txn) async {
      final observationId = await txn.insert('observations', observation);

      for (int i = 0; i < photoPaths.length; i++) {
        await txn.insert('photos', {
          'observation_id': observationId,
          'file_path': photoPaths[i],
          'order_index': i,
        });
      }

      return observationId;
    });
  }

  Future<List<Map<String, dynamic>>> getObservations({
    required String userLogin,
  }) async {
    final db = await database;

    final observationRows = await db.query(
      'observations',
      where: 'user_login = ?',
      whereArgs: [userLogin],
      orderBy: 'datetime(created_at) DESC',
    );

    final result = <Map<String, dynamic>>[];

    for (final row in observationRows) {
      final photos = await db.query(
        'photos',
        where: 'observation_id = ?',
        whereArgs: [row['id']],
        orderBy: 'order_index ASC',
      );

      result.add({
        ...row,
        'photos': photos,
      });
    }

    return result;
  }

  Future<Map<String, dynamic>?> getObservationById(int id) async {
    final db = await database;

    final rows = await db.query(
      'observations',
      where: 'id = ?',
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

    return {
      ...observation,
      'photos': photos,
    };
  }

  Future<List<Map<String, dynamic>>> getPendingObservations({
    required String userLogin,
  }) async {
    final db = await database;

    return db.query(
      'observations',
      where: 'user_login = ? AND (status = ? OR status = ?)',
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
  }) async {
    final db = await database;
    await db.update(
      'photos',
      {'uploaded_url': uploadedUrl},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  Future<int> deleteObservation(int id) async {
    final db = await database;
    return db.delete(
      'observations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllObservations({
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
}