import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  static bool _backupRestoreInProgress = false;
  static bool _automaticBackupInProgress = false;

  DatabaseHelper._internal();

  // ============================================================
  // HINDVI STORAGE PATH
  //
  // Desired folder structure:
  // /storage/emulated/0/हिंदवी/
  // ├── hindvi_latest.db
  // └── Old/
  //     └── hindvi_old_YYYY_MM_DD_HH_MM_SS.db
  // ============================================================

  static String get _hindviFolderPath {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/हिंदवी';
    }
    return join(Directory.current.path, 'हिंदवी');
  }

  static String get _oldFolderPath {
    return join(_hindviFolderPath, 'Old');
  }

  String get hindviFolderPath => _hindviFolderPath;
  String get oldFolderPath => _oldFolderPath;
  String get databaseFileName => _databaseFileName;

  // ============================================================
  // CURRENT DATABASE
  //
  // THIS IS THE ONLY LIVE DATABASE
  //
  // /storage/emulated/0/Hindvi/Backup/Latest/
  //     hindvi_latest.db
  // ============================================================

  static const String _databaseFileName =
      'hindvi_latest.db';

  // ============================================================
  // REQUIRED TABLES
  // ============================================================

  static const List<String> _requiredTables = [
    'vargani',
    'prasad_dengani',
    'prasad_sahitya',
    'aarti_vargani',
    'kharch',
    'mahaprasad_kharch',
    'previous_balance',
  ];

  static const List<String> migrationDataTables = [
    'vargani',
    'prasad_dengani',
    'prasad_sahitya',
    'aarti_vargani',
    'kharch',
    'mahaprasad_kharch',
    'previous_balance',
  ];

  // ============================================================
  // DATABASE GETTER
  // ============================================================

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  // ============================================================
  // CREATE HINDVI FOLDERS
  // ============================================================

  Future<void> _ensureHindviFolders() async {
    final hindviFolder = Directory(_hindviFolderPath);
    final oldFolder = Directory(_oldFolderPath);

    if (!await hindviFolder.exists()) {
      await hindviFolder.create(
        recursive: true,
      );
    }

    if (!await oldFolder.exists()) {
      await oldFolder.create(
        recursive: true,
      );
    }

    await _migrateLegacyFolderIfNeeded();
  }

  Future<void> _migrateLegacyFolderIfNeeded() async {
    try {
      final newDbFile = File(join(_hindviFolderPath, _databaseFileName));
      if (!await newDbFile.exists()) {
        final legacyCandidates = [
          File('/storage/emulated/0/Hindvi/Backup/Latest/$_databaseFileName'),
          File('/storage/emulated/0/Hindvi/$_databaseFileName'),
          File(join(Directory.current.path, 'Hindvi', 'Backup', 'Latest', _databaseFileName)),
        ];
        for (final candidate in legacyCandidates) {
          if (await candidate.exists()) {
            await candidate.copy(newDbFile.path);
            break;
          }
        }
      }

      final legacyOldDirs = [
        Directory('/storage/emulated/0/Hindvi/Backup/Old'),
        Directory(join(Directory.current.path, 'Hindvi', 'Backup', 'Old')),
      ];
      final targetOldDir = Directory(_oldFolderPath);
      for (final legDir in legacyOldDirs) {
        if (await legDir.exists()) {
          final items = await legDir.list().toList();
          for (final item in items) {
            if (item is File && item.path.endsWith('.db')) {
              final dest = File(join(targetOldDir.path, basename(item.path)));
              if (!await dest.exists()) {
                await item.copy(dest.path);
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  // ============================================================
  // CURRENT DATABASE PATH
  // ============================================================

  Future<String> _databaseFilePath() async {
    await _ensureHindviFolders();

    return join(
      _hindviFolderPath,
      _databaseFileName,
    );
  }

  // ============================================================
  // OLD BACKUP FOLDER PATH
  // ============================================================

  Future<String> _oldFolderPathValue() async {
    await _ensureHindviFolders();

    return _oldFolderPath;
  }

  // ============================================================
  // INITIALIZE DATABASE
  // ============================================================

  Future<Database> _initDatabase() async {
    await _ensureHindviFolders();

    final path =
    await _databaseFilePath();

    final db = await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    return db;
  }

  // ============================================================
  // TIMESTAMP
  // ============================================================

  String _timestamp(
      DateTime date, {
        bool includeSeconds = false,
      }) {
    String twoDigits(int value) =>
        value.toString().padLeft(2, '0');

    final datePart =
        '${date.year}_'
        '${twoDigits(date.month)}_'
        '${twoDigits(date.day)}';

    final timePart =
        '${twoDigits(date.hour)}_'
        '${twoDigits(date.minute)}'
        '${includeSeconds ? '_${twoDigits(date.second)}' : ''}';

    return includeSeconds
        ? '${datePart}_$timePart'
        : datePart;
  }

  // ============================================================
  // FILE EXTENSION
  // ============================================================

  String extensionOf(String name) {
    final dot = name.lastIndexOf('.');

    return dot < 0
        ? ''
        : name.substring(dot);
  }

  // ============================================================
  // UNIQUE OLD BACKUP FILE
  //
  // USED ONLY DURING RESTORE
  // ============================================================

  Future<File> _uniqueOldBackupFile() async {
    final oldFolder =
    Directory(await _oldFolderPathValue());

    final timestamp = _timestamp(
      DateTime.now(),
      includeSeconds: true,
    );

    var file = File(
      join(
        oldFolder.path,
        'hindvi_old_$timestamp.db',
      ),
    );

    var counter = 1;

    while (await file.exists()) {
      file = File(
        join(
          oldFolder.path,
          'hindvi_old_${timestamp}_$counter.db',
        ),
      );

      counter++;
    }

    return file;
  }

  // ============================================================
  // AUTOMATIC BACKUP
  //
  // IMPORTANT:
  //
  // Latest IS the current/live database.
  //
  // Therefore normal Add/Edit/Delete does NOT create
  // another backup file.
  //
  // We only checkpoint SQLite so the current DB remains
  // safely written.
  // ============================================================

  Future<void> _createAutomaticBackup(
      Database db,
      ) async {
    if (_backupRestoreInProgress) {
      return;
    }

    if (_automaticBackupInProgress) {
      return;
    }

    _automaticBackupInProgress = true;

    try {
      await _ensureHindviFolders();

      try {
        await db.execute(
          'PRAGMA wal_checkpoint(FULL)',
        );
      } catch (_) {
        // Continue if WAL checkpoint is unavailable.
      }
    } catch (_) {
      // Do not break normal database operations.
    } finally {
      _automaticBackupInProgress = false;
    }
  }

  // ============================================================
  // PUBLIC METHOD
  //
  // Returns the CURRENT DATABASE itself.
  //
  // No copy is created.
  // ============================================================

  Future<File> createAutomaticBackup() async {
    if (_backupRestoreInProgress) {
      throw StateError(
        'A database backup or restore is already running.',
      );
    }

    final db = await database;

    await _createAutomaticBackup(db);

    final path =
    await _databaseFilePath();

    return File(path);
  }

  // ============================================================
  // EXPORT BACKUP
  //
  // This creates a separate export file in the Hindvi folder.
  // It does NOT create anything inside Old.
  //
  // Old is reserved only for RESTORE safety copies.
  // ============================================================

  Future<File> createExportBackup() async {
    if (_backupRestoreInProgress) {
      throw StateError(
        'A database backup or restore is already running.',
      );
    }

    _backupRestoreInProgress = true;

    var connectionClosed = false;

    try {
      final db = await database;

      await _createAutomaticBackup(db);

      await db.close();

      _database = null;

      connectionClosed = true;

      final databaseFile =
      File(await _databaseFilePath());

      if (!await databaseFile.exists()) {
        throw FileSystemException(
          'Database file does not exist',
          databaseFile.path,
        );
      }

      final exportFile = File(
        join(
          _hindviFolderPath,
          'hindvi_export_${_timestamp(
            DateTime.now(),
            includeSeconds: true,
          )}.db',
        ),
      );

      await databaseFile.copy(
        exportFile.path,
      );

      return exportFile;
    } finally {
      try {
        if (connectionClosed) {
          await database;
        }
      } finally {
        _backupRestoreInProgress = false;
      }
    }
  }

  // ============================================================
  // EXPLICIT BACKUP (FOR SETTINGS -> BACKUP)
  //
  // Creates a backup copy inside:
  // /storage/emulated/0/हिंदवी/Old/hindvi_old_YYYY_MM_DD_HH_MM_SS.db
  // ============================================================

  Future<File> createExplicitBackup() async {
    if (_backupRestoreInProgress) {
      throw StateError(
        'A database backup or restore is already running.',
      );
    }

    _backupRestoreInProgress = true;
    var connectionClosed = false;

    try {
      final db = await database;
      await _createAutomaticBackup(db);
      await db.close();
      _database = null;
      connectionClosed = true;

      final databaseFile = File(await _databaseFilePath());
      if (!await databaseFile.exists()) {
        throw FileSystemException(
          'Database file does not exist',
          databaseFile.path,
        );
      }

      final backupFile = await _uniqueOldBackupFile();
      await databaseFile.copy(backupFile.path);

      await validateBackupFile(backupFile);
      return backupFile;
    } finally {
      try {
        if (connectionClosed) {
          await database;
        }
      } finally {
        _backupRestoreInProgress = false;
      }
    }
  }

  Future<File> createSafetyBackupBeforeMigration() async {
    return await createExplicitBackup();
  }

  Future<List<File>> getOldBackupFiles() async {
    await _ensureHindviFolders();
    final oldDir = Directory(_oldFolderPath);
    if (!await oldDir.exists()) return [];

    final list = await oldDir.list().toList();
    final files = <File>[];
    for (final entity in list) {
      if (entity is File && entity.path.toLowerCase().endsWith('.db')) {
        files.add(entity);
      }
    }
    files.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return b.path.compareTo(a.path);
      }
    });
    return files;
  }

  Future<DateTime?> getLastBackupTime() async {
    final files = await getOldBackupFiles();
    if (files.isEmpty) return null;
    try {
      return files.first.lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteOldBackupFile(File file) async {
    await _ensureHindviFolders();
    final oldDir = Directory(_oldFolderPath);
    final activePath = await _databaseFilePath();

    // STRICT SAFETY CHECK: Never allow deleting the active database
    if (canonicalize(file.path) == canonicalize(activePath) ||
        basename(file.path) == _databaseFileName) {
      throw StateError('सक्रिय डेटाबेस ($databaseFileName) हटवता येत नाही.');
    }

    final oldCanonical = canonicalize(oldDir.path);
    final fileCanonical = canonicalize(file.path);
    if (!fileCanonical.startsWith(oldCanonical)) {
      throw StateError('केवळ Old फोल्डरमधील बॅकअप फाइल्स हटवता येतात.');
    }

    if (await file.exists()) {
      await file.delete();
    }
  }

  // ============================================================
  // VALIDATE BACKUP FILE
  // ============================================================

  Future<void> validateBackupFile(
      File file,
      ) async {
    if (!await file.exists() ||
        !file.path
            .toLowerCase()
            .endsWith('.db')) {
      throw const FormatException(
        'Invalid database backup file.',
      );
    }

    Database? backupDatabase;

    try {
      backupDatabase = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );

      final integrity =
      await backupDatabase.rawQuery(
        'PRAGMA quick_check',
      );

      if (integrity.length != 1 ||
          integrity.first.values.first != 'ok') {
        throw const FormatException(
          'Database integrity check failed.',
        );
      }

      final tables =
      await backupDatabase.rawQuery(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        ''',
      );

      final tableNames = tables
          .map(
            (row) =>
        row['name'] as String,
      )
          .toSet();

      if (!_requiredTables
          .every(tableNames.contains)) {
        throw const FormatException(
          'Required database tables are missing.',
        );
      }

      final version =
      await backupDatabase.getVersion();

      if (version > 4) {
        throw const FormatException(
          'Database version is not supported.',
        );
      }

      if (version >= 3 &&
          !tableNames.contains(
            'previous_balance',
          )) {
        throw const FormatException(
          'Database schema is not compatible.',
        );
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Invalid or corrupted database backup.',
      );
    } finally {
      await backupDatabase?.close();
    }
  }

  // ============================================================
  // RESTORE DATABASE
  //
  // FLOW:
  //
  // 1. Validate imported DB
  //
  // 2. Current Latest DB:
  //       Latest/hindvi_latest.db
  //
  //    is copied to:
  //       Old/hindvi_old_TIMESTAMP.db
  //
  // 3. Imported DB replaces:
  //       Latest/hindvi_latest.db
  //
  // 4. Old copy remains safe.
  //
  // IMPORTANT:
  // Old file is created ONLY when RESTORE happens.
  // ============================================================

  Future<File> restoreDatabaseFromFile(
      File importedFile,
      ) async {
    if (_backupRestoreInProgress) {
      throw StateError(
        'A database backup or restore is already running.',
      );
    }

    _backupRestoreInProgress = true;

    File? stagingFile;
    File? databaseFile;
    File? oldBackupFile;

    bool safetyBackupCreated = false;

    try {
      // ========================================================
      // STEP 1: VALIDATE IMPORTED DATABASE
      // ========================================================

      await validateBackupFile(
        importedFile,
      );

      // ========================================================
      // STEP 2: CURRENT DATABASE
      // ========================================================

      databaseFile =
          File(await _databaseFilePath());

      if (!await databaseFile.exists()) {
        throw FileSystemException(
          'Current database file does not exist',
          databaseFile.path,
        );
      }

      // ========================================================
      // STEP 3: CREATE OLD COPY
      //
      // THIS HAPPENS ONLY DURING RESTORE.
      // ========================================================

      oldBackupFile =
      await _uniqueOldBackupFile();

      // Close current database before copying/replacing.
      final currentDb = _database;

      if (currentDb != null) {
        try {
          await currentDb.execute(
            'PRAGMA wal_checkpoint(FULL)',
          );
        } catch (_) {}

        await currentDb.close();

        _database = null;
      }

      // Copy CURRENT Latest → Old.
      await databaseFile.copy(
        oldBackupFile.path,
      );

      safetyBackupCreated = true;

      // Validate the safety copy.
      await validateBackupFile(
        oldBackupFile,
      );

      // ========================================================
      // STEP 4: COPY IMPORTED FILE TO TEMPORARY FILE
      // ========================================================

      stagingFile = File(
        join(
          _hindviFolderPath,
          'hindvi_restore_staging.db',
        ),
      );

      if (await stagingFile.exists()) {
        await stagingFile.delete();
      }

      await importedFile.copy(
        stagingFile.path,
      );

      // Validate staging file.
      await validateBackupFile(
        stagingFile,
      );

      // ========================================================
      // STEP 5: REPLACE CURRENT LATEST DATABASE
      // ========================================================

      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }

      await stagingFile.rename(
        databaseFile.path,
      );

      stagingFile = null;

      // ========================================================
      // STEP 6: OPEN RESTORED DATABASE
      // ========================================================

      await database;

      // ========================================================
      // RESTORE SUCCESS
      //
      // Latest now contains the restored database.
      // Old contains the database that existed before restore.
      // ========================================================

      return oldBackupFile;
    } catch (error) {
      // ========================================================
      // CLEAN STAGING FILE
      // ========================================================

      if (stagingFile != null) {
        try {
          if (await stagingFile.exists()) {
            await stagingFile.delete();
          }
        } catch (_) {}
      }

      // ========================================================
      // RESTORE OLD DATABASE IF SOMETHING FAILED
      // ========================================================

      if (safetyBackupCreated &&
          oldBackupFile != null &&
          databaseFile != null) {
        try {
          final currentDb = _database;

          if (currentDb != null) {
            await currentDb.close();
            _database = null;
          }

          if (await databaseFile.exists()) {
            await databaseFile.delete();
          }

          await oldBackupFile.copy(
            databaseFile.path,
          );

          await database;
        } catch (_) {
          throw StateError(
            'Restore failed. '
                'The previous database is safely stored at: '
                '${oldBackupFile.path}',
          );
        }
      }

      rethrow;
    } finally {
      _backupRestoreInProgress = false;
    }
  }

  // ============================================================
  // CREATE DATABASE
  // ============================================================

  Future<void> _onCreate(
      Database db,
      int version,
      ) async {
    await db.execute('''
      CREATE TABLE vargani (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE prasad_dengani (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE prasad_sahitya (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        item TEXT NOT NULL,
        year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE aarti_vargani (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE kharch (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item TEXT NOT NULL,
        buyer_name TEXT NOT NULL,
        amount REAL NOT NULL,
        year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE mahaprasad_kharch (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item TEXT NOT NULL,
        buyer_name TEXT NOT NULL,
        amount REAL NOT NULL,
        year INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE previous_balance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        year INTEGER NOT NULL UNIQUE,
        amount REAL NOT NULL
      )
    ''');

    await _createMigrationTables(db);
  }

  // ============================================================
  // DATABASE MIGRATION
  // ============================================================

  Future<void> _onUpgrade(
      Database db,
      int oldVersion,
      int newVersion,
      ) async {
    // Version 2
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS aarti_vargani (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          amount REAL NOT NULL,
          year INTEGER NOT NULL
        )
      ''');
    }

    // Version 3
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS previous_balance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          year INTEGER NOT NULL UNIQUE,
          amount REAL NOT NULL
        )
      ''');
    }

    if (oldVersion < 4) {
      await _createMigrationTables(db);
    }
  }

  Future<void> _createMigrationTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_history (
        migration_id TEXT PRIMARY KEY,
        completed_at INTEGER NOT NULL,
        direction TEXT NOT NULL,
        record_counts TEXT NOT NULL,
        payload_digest TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_recovery (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        migration_id TEXT NOT NULL,
        migrated_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        destination TEXT NOT NULL,
        payload TEXT NOT NULL,
        record_counts TEXT NOT NULL,
        payload_digest TEXT NOT NULL
      )
    ''');
  }

  Future<Map<String, int>> getTableRecordCounts() async {
    final db = await database;
    final counts = <String, int>{};
    for (final table in migrationDataTables) {
      final res = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      counts[table] = (res.first['c'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<Map<String, dynamic>> getMandalDataSummary() async {
    final counts = await getTableRecordCounts();
    final varganiCount = counts['vargani'] ?? 0;
    final prasadDenganiCount = counts['prasad_dengani'] ?? 0;
    final prasadSahityaCount = counts['prasad_sahitya'] ?? 0;
    final aartiCount = counts['aarti_vargani'] ?? 0;
    final kharchCount = counts['kharch'] ?? 0;
    final mahaprasadCount = counts['mahaprasad_kharch'] ?? 0;
    final balanceCount = counts['previous_balance'] ?? 0;

    final membersCount = varganiCount;
    final incomeCount = varganiCount + prasadDenganiCount + aartiCount;
    final expensesCount = kharchCount + mahaprasadCount;
    final transactionsCount = incomeCount + expensesCount;
    final otherCount = prasadSahityaCount + balanceCount;
    final totalCount = transactionsCount + otherCount;

    return {
      'tableCounts': counts,
      'membersCount': membersCount,
      'incomeCount': incomeCount,
      'expensesCount': expensesCount,
      'transactionsCount': transactionsCount,
      'otherCount': otherCount,
      'totalRecords': totalCount,
    };
  }

  Future<Map<String, dynamic>> createMigrationSnapshot() async {
    final db = await database;
    final data = <String, List<Map<String, dynamic>>>{};
    for (final table in migrationDataTables) {
      final rows = await db.query(table, orderBy: 'id ASC');
      data[table] = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    return {
      'schemaVersion': await db.getVersion(),
      'dataVersion': 1,
      'tables': data,
    };
  }

  Future<bool> importMigrationSnapshot({
    required String migrationId,
    required Map<String, dynamic> tables,
    required String payloadDigest,
  }) async {
    if (tables.keys.toSet().difference(migrationDataTables.toSet()).isNotEmpty ||
        tables.keys.toSet().length != migrationDataTables.length) {
      throw const FormatException('Migration table set is not supported.');
    }

    final normalized = <String, List<Map<String, dynamic>>>{};
    for (final table in migrationDataTables) {
      final rows = tables[table];
      if (rows is! List) {
        throw FormatException('Invalid records for $table.');
      }
      normalized[table] = rows.map((row) {
        if (row is! Map) {
          throw FormatException('Invalid row in $table.');
        }
        final record = Map<String, dynamic>.from(row);
        final id = record['id'];
        if (id is! int || id <= 0) {
          throw FormatException('Invalid record ID in $table.');
        }
        return record;
      }).toList(growable: false);
    }

    final db = await database;
    var alreadyImported = false;
    await db.transaction((txn) async {
      final previous = await txn.query(
        'migration_history',
        where: 'migration_id = ?',
        whereArgs: [migrationId],
        limit: 1,
      );
      if (previous.isNotEmpty) {
        alreadyImported = true;
        return;
      }

      for (final table in migrationDataTables) {
        await txn.delete(table);
      }
      for (final table in migrationDataTables) {
        for (final row in normalized[table]!) {
          await txn.insert(table, row);
        }
      }

      final counts = <String, int>{};
      for (final table in migrationDataTables) {
        final result = await txn.rawQuery('SELECT COUNT(*) AS count FROM $table');
        counts[table] = result.single['count'] as int;
        if (counts[table] != normalized[table]!.length) {
          throw StateError('Record verification failed for $table.');
        }
      }
      await txn.insert('migration_history', {
        'migration_id': migrationId,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
        'direction': 'received',
        'record_counts': jsonEncode(counts),
        'payload_digest': payloadDigest,
      });
    });
    return alreadyImported;
  }

  Future<void> moveMigrationDataToRecovery({
    required String migrationId,
    required String destination,
    required String payload,
    required String payloadDigest,
    required DateTime migratedAt,
  }) async {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final tables = Map<String, dynamic>.from(decoded['tables'] as Map);
    final counts = <String, int>{
      for (final table in migrationDataTables)
        table: (tables[table] as List).length,
    };
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'migration_recovery',
        {
          'id': 1,
          'migration_id': migrationId,
          'migrated_at': migratedAt.millisecondsSinceEpoch,
          'expires_at': migratedAt
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          'destination': destination,
          'payload': payload,
          'record_counts': jsonEncode(counts),
          'payload_digest': payloadDigest,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final table in migrationDataTables) {
        await txn.delete(table);
      }
      await txn.insert('migration_history', {
        'migration_id': migrationId,
        'completed_at': migratedAt.millisecondsSinceEpoch,
        'direction': 'sent',
        'record_counts': jsonEncode(counts),
        'payload_digest': payloadDigest,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, dynamic>?> getMigrationRecovery() async {
    final db = await database;
    final rows = await db.query('migration_recovery', where: 'id = 1');
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> restoreMigrationRecovery() async {
    final db = await database;
    final recoveryRows = await db.query(
      'migration_recovery',
      where: 'id = 1',
      limit: 1,
    );
    if (recoveryRows.isEmpty) {
      throw StateError('No migration recovery is available.');
    }
    if ((recoveryRows.single['expires_at'] as int) <=
        DateTime.now().millisecondsSinceEpoch) {
      await db.delete('migration_recovery', where: 'id = 1');
      throw StateError('The migration recovery period has expired.');
    }
    await db.transaction((txn) async {
      final rows = await txn.query('migration_recovery', where: 'id = 1');
      final recovery = rows.single;
      final decoded = jsonDecode(recovery['payload'] as String) as Map;
      final tables = Map<String, dynamic>.from(decoded['tables'] as Map);
      for (final table in migrationDataTables) {
        await txn.delete(table);
        for (final row in tables[table] as List) {
          await txn.insert(table, Map<String, dynamic>.from(row as Map));
        }
      }
      await txn.delete('migration_recovery', where: 'id = 1');
    });
  }

  Future<void> expireMigrationRecoveryIfNeeded() async {
    final db = await database;
    await db.delete(
      'migration_recovery',
      where: 'expires_at <= ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> deleteMigrationRecoveryNow() async {
    final db = await database;
    await db.delete('migration_recovery', where: 'id = 1');
  }

  // ============================================================
  // VARGANI
  // ============================================================

  Future<int> insertVargani(
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final id = await db.insert(
      'vargani',
      data,
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);

    return id;
  }

  Future<List<Map<String, dynamic>>> getVargani(
      int year,
      ) async {
    final db = await database;

    return await db.query(
      'vargani',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'amount DESC, id ASC',
    );
  }

  /// Checks if another record with the same normalized name already exists in the given year.
  /// If [excludeId] is provided, that record is ignored (useful when editing an existing entry).
  Future<bool> hasVarganiWithSameName(
    int year,
    String name, {
    int? excludeId,
  }) async {
    final list = await getVargani(year);
    final normalized = name.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    for (final row in list) {
      if (excludeId != null && row['id'] == excludeId) continue;
      final existingNormalized = (row['name']?.toString() ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
      if (existingNormalized == normalized) {
        return true;
      }
    }
    return false;
  }

  Future<int> updateVargani(
      int id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final result = await db.update(
      'vargani',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<int> deleteVargani(
      int id,
      ) async {
    final db = await database;

    final result = await db.delete(
      'vargani',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<double> getVarganiTotal(
      int year,
      ) async {
    final db = await database;

    final result =
    await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM vargani
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)
        ?.toDouble() ??
        0.0;
  }

  // ============================================================
  // PREVIOUS BALANCE
  // ============================================================

  Future<void> savePreviousBalance(
      int year,
      double amount,
      ) async {
    final db = await database;

    await db.insert(
      'previous_balance',
      {
        'year': year,
        'amount': amount,
      },
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);
  }

  Future<double> getPreviousBalance(
      int year,
      ) async {
    final db = await database;

    final result = await db.query(
      'previous_balance',
      where: 'year = ?',
      whereArgs: [year],
      limit: 1,
    );

    if (result.isEmpty) {
      return 0.0;
    }

    return (result.first['amount'] as num?)
        ?.toDouble() ??
        0.0;
  }

  // ============================================================
  // PRASAD DENGANI
  // ============================================================

  Future<int> insertPrasadDengani(
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final id = await db.insert(
      'prasad_dengani',
      data,
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);

    return id;
  }

  Future<List<Map<String, dynamic>>> getPrasadDengani(
      int year,
      ) async {
    final db = await database;

    return await db.query(
      'prasad_dengani',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updatePrasadDengani(
      int id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final result = await db.update(
      'prasad_dengani',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<int> deletePrasadDengani(
      int id,
      ) async {
    final db = await database;

    final result = await db.delete(
      'prasad_dengani',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<double> getPrasadDenganiTotal(
      int year,
      ) async {
    final db = await database;

    final result =
    await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM prasad_dengani
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)
        ?.toDouble() ??
        0.0;
  }

  // ============================================================
  // PRASAD SAHITYA
  // ============================================================

  Future<int> insertPrasadSahitya(
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final id = await db.insert(
      'prasad_sahitya',
      data,
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);

    return id;
  }

  Future<List<Map<String, dynamic>>> getPrasadSahitya(
      int year,
      ) async {
    final db = await database;

    return await db.query(
      'prasad_sahitya',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updatePrasadSahitya(
      int id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final result = await db.update(
      'prasad_sahitya',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<int> deletePrasadSahitya(
      int id,
      ) async {
    final db = await database;

    final result = await db.delete(
      'prasad_sahitya',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  // ============================================================
  // AARTI VARGANI
  // ============================================================

  Future<int> insertAartiVargani(
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final id = await db.insert(
      'aarti_vargani',
      data,
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);

    return id;
  }

  Future<List<Map<String, dynamic>>> getAartiVargani(
      int year,
      ) async {
    final db = await database;

    return await db.query(
      'aarti_vargani',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateAartiVargani(
      int id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final result = await db.update(
      'aarti_vargani',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<int> deleteAartiVargani(
      int id,
      ) async {
    final db = await database;

    final result = await db.delete(
      'aarti_vargani',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<double> getAartiVarganiTotal(
      int year,
      ) async {
    final db = await database;

    final result =
    await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM aarti_vargani
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)
        ?.toDouble() ??
        0.0;
  }

  // ============================================================
  // KHARCH
  // ============================================================

  Future<int> insertKharch(
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final id = await db.insert(
      'kharch',
      data,
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);

    return id;
  }

  Future<List<Map<String, dynamic>>> getKharch(
      int year,
      ) async {
    final db = await database;

    return await db.query(
      'kharch',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateKharch(
      int id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final result = await db.update(
      'kharch',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<int> deleteKharch(
      int id,
      ) async {
    final db = await database;

    final result = await db.delete(
      'kharch',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<double> getKharchTotal(
      int year,
      ) async {
    final db = await database;

    final result =
    await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM kharch
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)
        ?.toDouble() ??
        0.0;
  }

  // ============================================================
  // MAHAPRASAD KHARCH
  // ============================================================

  Future<int> insertMahaprasadKharch(
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final id = await db.insert(
      'mahaprasad_kharch',
      data,
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );

    await _createAutomaticBackup(db);

    return id;
  }

  Future<List<Map<String, dynamic>>>
  getMahaprasadKharch(
      int year,
      ) async {
    final db = await database;

    return await db.query(
      'mahaprasad_kharch',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateMahaprasadKharch(
      int id,
      Map<String, dynamic> data,
      ) async {
    final db = await database;

    final result = await db.update(
      'mahaprasad_kharch',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<int> deleteMahaprasadKharch(
      int id,
      ) async {
    final db = await database;

    final result = await db.delete(
      'mahaprasad_kharch',
      where: 'id = ?',
      whereArgs: [id],
    );

    await _createAutomaticBackup(db);

    return result;
  }

  Future<double> getMahaprasadKharchTotal(
      int year,
      ) async {
    final db = await database;

    final result =
    await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM mahaprasad_kharch
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)
        ?.toDouble() ??
        0.0;
  }
}



