/// database_helper.dart
///
/// This file contains a helper class for working with the local SQLite
/// database used by the WildNote mobile application.  The database stores
/// plant observations and their associated photographs.  The helper
/// encapsulates opening the database, creating the schema, and common
/// operations such as inserting new observations, querying existing
/// observations with their photos, updating synchronisation status and
/// deleting old records.
///
/// Usage example:
///
/// ```dart
/// final db = await DatabaseHelper.instance.database;
/// final obsId = await DatabaseHelper.instance.insertObservation(
///   observation: {
///     'name': 'Белая берёза',
///     'description': 'Растёт на окраине леса',
///     'latitude': 68.97,
///     'longitude': 33.07,
///     'is_manual': 0,
///     'accuracy': 4.0,
///     'created_at': DateTime.now().toIso8601String(),
///     'status': 0,
///   },
///   photoPaths: ['/path/to/photo1.jpg', '/path/to/photo2.jpg'],
/// );
/// ```
///
/// When synchronising with the geoportal, update the `status` column and
/// populate the `uploaded_url` in the photos table once the upload
/// succeeds.  See `markObservationSynced` and `updatePhotoUploadedUrl`.

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  // Singleton pattern: a single instance throughout the app.
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static const String _databaseName = 'wildnote.db';
  static const int _databaseVersion = 1;

  Database? _database;

  /// Returns the singleton database instance, opening it if necessary.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Opens the database file and creates the tables on first run.
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Called only once when the database is first created.  Executes the
  /// SQL statements from `database_schema.sql` to create tables.
  Future<void> _onCreate(Database db, int version) async {
    // Observations table.
    await db.execute('''
      CREATE TABLE observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        zone INTEGER
      )
    ''');

    // Photos table.
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
  }

  /// Handles schema upgrades when the database version changes.  This
  /// implementation simply recreates the tables.  In a production app,
  /// migrations should preserve existing data.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < newVersion) {
      // For simplicity, drop and recreate tables.  In a real project,
      // consider writing migration scripts to transform data.
      await db.execute('DROP TABLE IF EXISTS photos');
      await db.execute('DROP TABLE IF EXISTS observations');
      await _onCreate(db, newVersion);
    }
  }

  /// Inserts a new observation with its associated photo paths.  Returns
  /// the row ID of the inserted observation.  Use this when the user
  /// presses the save/submit button in the AddPlant screen.  Photo paths
  /// should be absolute paths obtained from the camera or image picker.
  Future<int> insertObservation({
    required Map<String, dynamic> observation,
    required List<String> photoPaths,
  }) async {
    final db = await database;
    // Insert observation record.
    final obsId = await db.insert('observations', observation);
    // Insert each photo entry.
    for (int i = 0; i < photoPaths.length; i++) {
      await db.insert('photos', {
        'observation_id': obsId,
        'file_path': photoPaths[i],
        'order_index': i,
      });
    }
    return obsId;
  }

  /// Retrieves all observations from the database, optionally filtering by
  /// synchronisation status.  The returned list contains a map for each
  /// observation with an additional `photos` key whose value is a list
  /// of maps representing the associated photo rows.
  Future<List<Map<String, dynamic>>> getObservations({int? status}) async {
    final db = await database;
    final whereClause = status != null ? 'WHERE status = ?' : '';
    final whereArgs = status != null ? [status] : null;
    final obsRows = await db.rawQuery(
      'SELECT * FROM observations $whereClause ORDER BY datetime(created_at) DESC',
      whereArgs,
    );
    // For each observation, fetch its photos.
    final result = <Map<String, dynamic>>[];
    for (final obs in obsRows) {
      final photos = await db.query(
        'photos',
        where: 'observation_id = ?',
        whereArgs: [obs['id']],
        orderBy: 'order_index',
      );
      final Map<String, dynamic> entry = Map<String, dynamic>.from(obs);
      entry['photos'] = photos;
      result.add(entry);
    }
    return result;
  }

  /// Updates an existing observation.  Pass the `id` of the observation
  /// alongside any fields that have changed.  To modify associated
  /// photos, delete and re‑insert them separately or implement a
  /// dedicated method.
  Future<void> updateObservation(int id, Map<String, dynamic> fields) async {
    final db = await database;
    await db.update(
      'observations',
      fields,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes an observation and all its photos.  Use this when the
  /// user removes a record from the history screen.  Returns the number
  /// of deleted observation rows (0 or 1).
  Future<int> deleteObservation(int id) async {
    final db = await database;
    // ON DELETE CASCADE ensures photo rows are removed automatically.
    return await db.delete(
      'observations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks an observation as successfully synchronised.  Also updates
  /// optional Gauss–Krüger coordinates if provided.  Call this after
  /// receiving a successful response from the geoportal API.  For
  /// example, set status = 2 and fill in gauss_x, gauss_y and zone.
  Future<void> markObservationSynced({
    required int id,
    double? gaussX,
    double? gaussY,
    int? zone,
  }) async {
    final db = await database;
    final updateFields = <String, Object>{'status': 2};
    if (gaussX != null) updateFields['gauss_x'] = gaussX;
    if (gaussY != null) updateFields['gauss_y'] = gaussY;
    if (zone != null) updateFields['zone'] = zone;
    await db.update(
      'observations',
      updateFields,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Updates the uploaded URL of a photo once it has been stored on
  /// the geoportal.  Use this to replace the local file path with
  /// a remote HTTP or HTTPS URL.  Returns the number of updated rows.
  Future<int> updatePhotoUploadedUrl({
    required int photoId,
    required String uploadedUrl,
  }) async {
    final db = await database;
    return await db.update(
      'photos',
      {'uploaded_url': uploadedUrl},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }
}