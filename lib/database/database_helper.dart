import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/remote_sync_service.dart';

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

  static const String _databaseFileName = 'hindvi_latest.db';

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
  // ROLE & PERMISSION CHECK
  // ============================================================

  bool _isDeviceRevoked = false;

  bool get isDeviceRevoked => _isDeviceRevoked;

  void setDeviceRevokedState(bool revoked) {
    _isDeviceRevoked = revoked;
  }

  void _assertDeviceNotRevoked() {
    if (_isDeviceRevoked) {
      throw StateError(
        'हे डिव्हाइस रद्द (Revoked) केले आहे. आर्थिक डेटा ॲक्सेस किंवा बदल करता येणार नाही.',
      );
    }
  }

  void assertDeviceNotRevokedForTesting() => _assertDeviceNotRevoked();

  void _assertCanModifyData() {
    _assertDeviceNotRevoked();
    if (AuthService.instance.isDeveloper) return;
    if (AuthService.instance.isOldKhajani &&
        !AuthService.instance.canEdit &&
        !AuthService.instance.canAdd &&
        !AuthService.instance.canDelete) {
      throw StateError(
        'माजी खजानी (OLD_KHAJANI) यांना बदल किंवा हटवण्याची परवानगी नाही. केवळ वाचन परवानगी आहे.',
      );
    }
  }

  void _assertCanAdd() {
    if (AuthService.instance.isDeveloper) return;
    _assertCanModifyData();
    if (!AuthService.instance.canAdd) {
      throw StateError('नोंद जोडण्याची परवानगी (Add Permission) नाही.');
    }
  }

  void _assertCanEdit() {
    if (AuthService.instance.isDeveloper) return;
    _assertCanModifyData();
    if (!AuthService.instance.canEdit) {
      throw StateError('बदल करण्याची परवानगी (Edit Permission) नाही.');
    }
  }

  void _assertCanDelete() {
    if (AuthService.instance.isDeveloper) return;
    _assertCanModifyData();
    if (!AuthService.instance.canDelete) {
      throw StateError('हटवण्याची परवानगी (Delete Permission) नाही.');
    }
  }

  void _assertCanSync() {
    _assertDeviceNotRevoked();
    if (AuthService.instance.isDeveloper) return;
    if (!AuthService.instance.canView && !AuthService.instance.canSync) {
      throw StateError(
        'डेटा सिंक / मायग्रेशन करण्याची परवानगी (Sync Permission) नाही.',
      );
    }
  }

  void _assertCanSyncData() {
    _assertDeviceNotRevoked();
    if (AuthService.instance.isDeveloper) return;
    if (!AuthService.instance.canView) {
      throw StateError(
        'आर्थिक माहिती पाहण्याची किंवा सिंक करण्याची परवानगी (View Permission) नाही.',
      );
    }
  }

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
      await hindviFolder.create(recursive: true);
    }

    if (!await oldFolder.exists()) {
      await oldFolder.create(recursive: true);
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
          File(
            join(
              Directory.current.path,
              'Hindvi',
              'Backup',
              'Latest',
              _databaseFileName,
            ),
          ),
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

    return join(_hindviFolderPath, _databaseFileName);
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

    final path = await _databaseFilePath();

    final db = await openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    await _createSyncTables(db);

    return db;
  }

  // ============================================================
  // TIMESTAMP
  // ============================================================

  String _timestamp(DateTime date, {bool includeSeconds = false}) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    final datePart =
        '${date.year}_${twoDigits(date.month)}_${twoDigits(date.day)}';

    final timePart =
        '${twoDigits(date.hour)}_${twoDigits(date.minute)}${includeSeconds ? '_${twoDigits(date.second)}' : ''}';

    return includeSeconds ? '${datePart}_$timePart' : datePart;
  }

  // ============================================================
  // FILE EXTENSION
  // ============================================================

  String extensionOf(String name) {
    final dot = name.lastIndexOf('.');

    return dot < 0 ? '' : name.substring(dot);
  }

  // ============================================================
  // UNIQUE OLD BACKUP FILE
  //
  // USED ONLY DURING RESTORE
  // ============================================================

  Future<File> _uniqueOldBackupFile() async {
    final oldFolder = Directory(await _oldFolderPathValue());

    final timestamp = _timestamp(DateTime.now(), includeSeconds: true);

    var file = File(join(oldFolder.path, 'hindvi_old_$timestamp.db'));

    var counter = 1;

    while (await file.exists()) {
      file = File(join(oldFolder.path, 'hindvi_old_${timestamp}_$counter.db'));

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

  Future<void> _createAutomaticBackup(Database db) async {
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
        await db.execute('PRAGMA wal_checkpoint(FULL)');
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
      throw StateError('A database backup or restore is already running.');
    }

    final db = await database;

    await _createAutomaticBackup(db);

    final path = await _databaseFilePath();

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
      throw StateError('A database backup or restore is already running.');
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

      final exportFile = File(
        join(
          _hindviFolderPath,
          'hindvi_export_${_timestamp(DateTime.now(), includeSeconds: true)}.db',
        ),
      );

      await databaseFile.copy(exportFile.path);

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
      throw StateError('A database backup or restore is already running.');
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

  // ============================================================
  // OLD BACKUP FILES
  // ============================================================

  Future<List<File>> getOldBackupFiles() async {
    await _ensureHindviFolders();
    final oldDir = Directory(await _oldFolderPathValue());
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

  Future<List<File>> listOldBackups() async {
    return await getOldBackupFiles();
  }

  Future<void> deleteOldBackupFile(File file) async {
    await _ensureHindviFolders();
    final oldDir = Directory(await _oldFolderPathValue());
    final activePath = await _databaseFilePath();

    // STRICT SAFETY CHECK: Never allow deleting the active database
    if (canonicalize(file.path) == canonicalize(activePath) ||
        basename(file.path) == _databaseFileName) {
      throw StateError('सक्रिय डेटाबेस () हटवता येत नाही.');
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
  // LAST BACKUP TIME
  // ============================================================

  Future<DateTime?> getLastBackupTime() async {
    final files = await getOldBackupFiles();
    if (files.isEmpty) return null;
    try {
      return files.first.lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // CLEANUP OLD BACKUPS
  // ============================================================

  Future<void> cleanupOldBackups({int keepCount = 10}) async {
    final backups = await getOldBackupFiles();

    if (backups.length <= keepCount) {
      return;
    }

    final toDelete = backups.sublist(keepCount);

    for (final file in toDelete) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  // ============================================================
  // VALIDATE BACKUP FILE
  // ============================================================

  Future<void> validateBackupFile(File file) async {
    if (!await file.exists()) {
      throw const FileSystemException('Backup file does not exist.');
    }

    if (await file.length() == 0) {
      throw const FormatException('Backup file is empty.');
    }

    Database? backupDatabase;

    try {
      backupDatabase = await openDatabase(file.path, readOnly: true);

      final integrityResult = await backupDatabase.rawQuery(
        'PRAGMA integrity_check',
      );

      final integrityStatus =
          integrityResult.first.values.first.toString().toLowerCase();

      if (integrityStatus != 'ok') {
        throw const FormatException('Database integrity check failed.');
      }

      final tablesResult = await backupDatabase.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final existingTables =
          tablesResult.map((row) => row['name'].toString()).toSet();

      if (!_requiredTables.every(
        (table) => existingTables.contains(table.toLowerCase()),
      )) {
        throw const FormatException('Database schema is not compatible.');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid or corrupted database backup.');
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

  Future<File> restoreDatabaseFromFile(File importedFile) async {
    _assertCanSync();

    if (_backupRestoreInProgress) {
      throw StateError('A database backup or restore is already running.');
    }

    _backupRestoreInProgress = true;

    File? stagingFile;
    File? databaseFile;
    File? oldBackupFile;

    bool safetyBackupCreated = false;

    try {
      await validateBackupFile(importedFile);

      databaseFile = File(await _databaseFilePath());

      if (!await databaseFile.exists()) {
        throw FileSystemException(
          'Current database file does not exist',
          databaseFile.path,
        );
      }

      oldBackupFile = await _uniqueOldBackupFile();

      final currentDb = _database;

      if (currentDb != null) {
        try {
          await currentDb.execute('PRAGMA wal_checkpoint(FULL)');
        } catch (_) {}

        await currentDb.close();

        _database = null;
      }

      await databaseFile.copy(oldBackupFile.path);

      safetyBackupCreated = true;

      await validateBackupFile(oldBackupFile);

      stagingFile = File(join(_hindviFolderPath, 'hindvi_restore_staging.db'));

      if (await stagingFile.exists()) {
        await stagingFile.delete();
      }

      await importedFile.copy(stagingFile.path);

      await validateBackupFile(stagingFile);

      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }

      await stagingFile.rename(databaseFile.path);

      stagingFile = null;

      await database;

      return oldBackupFile;
    } catch (error) {
      if (stagingFile != null) {
        try {
          if (await stagingFile.exists()) {
            await stagingFile.delete();
          }
        } catch (_) {}
      }

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

          await oldBackupFile.copy(databaseFile.path);

          await database;
        } catch (_) {
          throw StateError(
            'Restore failed. The previous database is safely stored at: ${oldBackupFile.path}',
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

  Future<void> _onCreate(Database db, int version) async {
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
    await _createAuthTables(db);
    await _createDeviceAndServerTables(db);
    await _createSyncTables(db);
    await AuthService.instance.ensureDeveloperAccount(db);
  }

  // ============================================================
  // DATABASE MIGRATION
  // ============================================================

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
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

    // Version 4
    if (oldVersion < 4) {
      await _createMigrationTables(db);
    }

    // Version 5
    if (oldVersion < 5) {
      await _createAuthTables(db);
    }

    // Version 6: Developer Admin, Active status, and Granular permissions
    if (oldVersion < 6) {
      await _upgradeToVersion6(db);
    }

    // Version 7: Pending User Request Management and status
    if (oldVersion < 7) {
      await _upgradeToVersion7(db);
    }

    // Version 8: Devices, Device Requests, Permissions table, Server Config, Users View
    if (oldVersion < 8) {
      await _upgradeToVersion8(db);
    }

    // Version 9: Financial sync tables (sync_queue, sync_change_log, sync_tombstones, etc.)
    if (oldVersion < 9) {
      await _createSyncTables(db);
    }
  }

  Future<void> _createSyncTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        change_id TEXT UNIQUE NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        changed_at INTEGER NOT NULL,
        version INTEGER NOT NULL,
        record_data TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_change_log (
        change_id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        changed_at INTEGER NOT NULL,
        version INTEGER NOT NULL,
        record_data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_received_changes (
        change_id TEXT PRIMARY KEY,
        received_at INTEGER NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_tombstones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        UNIQUE(table_name, record_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_record_versions (
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        PRIMARY KEY (table_name, record_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        change_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        winner_device_id TEXT NOT NULL,
        loser_device_id TEXT NOT NULL,
        winner_version INTEGER NOT NULL,
        loser_version INTEGER NOT NULL,
        winner_data TEXT,
        loser_data TEXT,
        resolved_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createDeviceAndServerTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL,
        user_id TEXT,
        status TEXT NOT NULL DEFAULT 'APPROVED',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_requests (
        request_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        request_type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        requested_role TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS permissions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        device_id TEXT,
        can_view INTEGER NOT NULL DEFAULT 1,
        can_add INTEGER NOT NULL DEFAULT 1,
        can_edit INTEGER NOT NULL DEFAULT 1,
        can_delete INTEGER NOT NULL DEFAULT 1,
        can_search INTEGER NOT NULL DEFAULT 1,
        can_pdf INTEGER NOT NULL DEFAULT 1,
        can_manage_khajani INTEGER NOT NULL DEFAULT 1,
        can_sync INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS server_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        server_url TEXT NOT NULL DEFAULT 'wss://amino-dropkick-resample.ngrok-free.dev',
        auto_connect INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO server_config (id, server_url, auto_connect, updated_at)
      VALUES (1, 'wss://amino-dropkick-resample.ngrok-free.dev', 1, 0)
    ''');

    await db.execute('''
      CREATE VIEW IF NOT EXISTS users AS SELECT * FROM khajani_users
    ''');
  }

  Future<void> _upgradeToVersion8(DatabaseExecutor db) async {
    try {
      await _createDeviceAndServerTables(db);
    } catch (_) {}
  }

  Future<void> _upgradeToVersion7(DatabaseExecutor db) async {
    try {
      final tableInfo = await db.rawQuery('PRAGMA table_info(khajani_users)');
      final existingCols = tableInfo.map((r) => r['name'] as String).toSet();

      if (!existingCols.contains('status')) {
        await db.execute(
          "ALTER TABLE khajani_users ADD COLUMN status TEXT NOT NULL DEFAULT 'APPROVED'",
        );
      }
    } catch (_) {}
  }

  Future<void> _upgradeToVersion6(DatabaseExecutor db) async {
    try {
      final tableInfo = await db.rawQuery('PRAGMA table_info(khajani_users)');
      final existingCols = tableInfo.map((r) => r['name'] as String).toSet();

      final newCols = {
        'is_active': 'INTEGER NOT NULL DEFAULT 1',
        'can_view': 'INTEGER NOT NULL DEFAULT 1',
        'can_add': 'INTEGER NOT NULL DEFAULT 1',
        'can_edit': 'INTEGER NOT NULL DEFAULT 1',
        'can_delete': 'INTEGER NOT NULL DEFAULT 1',
        'can_search': 'INTEGER NOT NULL DEFAULT 1',
        'can_pdf': 'INTEGER NOT NULL DEFAULT 1',
        'can_manage_khajani': 'INTEGER NOT NULL DEFAULT 1',
        'can_sync': 'INTEGER NOT NULL DEFAULT 1',
      };

      for (final entry in newCols.entries) {
        if (!existingCols.contains(entry.key)) {
          await db.execute(
            'ALTER TABLE khajani_users ADD COLUMN ${entry.key} ${entry.value}',
          );
        }
      }

      await db.execute('''
        UPDATE khajani_users
        SET can_add = 0, can_edit = 0, can_delete = 0, can_manage_khajani = 0, can_sync = 0
        WHERE role = 'OLD_KHAJANI'
      ''');

      await AuthService.instance.ensureDeveloperAccount(db);
    } catch (_) {}
  }

  Future<void> _createAuthTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS khajani_users (
        user_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'APPROVED',
        is_active INTEGER NOT NULL DEFAULT 1,
        can_view INTEGER NOT NULL DEFAULT 1,
        can_add INTEGER NOT NULL DEFAULT 1,
        can_edit INTEGER NOT NULL DEFAULT 1,
        can_delete INTEGER NOT NULL DEFAULT 1,
        can_search INTEGER NOT NULL DEFAULT 1,
        can_pdf INTEGER NOT NULL DEFAULT 1,
        can_manage_khajani INTEGER NOT NULL DEFAULT 1,
        can_sync INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS khajani_session (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_id TEXT,
        keep_logged_in INTEGER NOT NULL DEFAULT 0,
        logged_in_at INTEGER
      )
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO khajani_session (id, user_id, keep_logged_in, logged_in_at)
      VALUES (1, NULL, 0, NULL)
    ''');
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
      data[table] =
          rows
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
    }
    return {
      'schemaVersion': await db.getVersion(),
      'dataVersion': 1,
      'tables': data,
    };
  }

  Future<Map<String, dynamic>> createFinancialSnapshot() async {
    return await createMigrationSnapshot();
  }

  Future<Map<String, int>> getLatestKnownIds() async {
    final db = await database;
    final map = <String, int>{};
    for (final table in migrationDataTables) {
      final res = await db.rawQuery('SELECT MAX(id) as max_id FROM $table');
      final maxId = (res.first['max_id'] as num?)?.toInt() ?? 0;
      map[table] = maxId;
    }
    return map;
  }

  Future<bool> importFinancialSnapshot({
    required String syncId,
    required Map<String, dynamic> tables,
    required String payloadDigest,
  }) async {
    return await importMigrationSnapshot(
      migrationId: syncId,
      tables: tables,
      payloadDigest: payloadDigest,
    );
  }

  Future<bool> importMigrationSnapshot({
    required String migrationId,
    required Map<String, dynamic> tables,
    required String payloadDigest,
  }) async {
    _assertCanSyncData();

    final db = await database;
    try {
      await db.transaction((txn) async {
        for (final table in migrationDataTables) {
          await txn.delete(table);
          final rows = tables[table] as List<dynamic>? ?? [];
          for (final row in rows) {
            await txn.insert(
              table,
              Map<String, dynamic>.from(row as Map),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        final counts = <String, int>{};
        for (final table in migrationDataTables) {
          final res = await txn.rawQuery('SELECT COUNT(*) AS c FROM $table');
          counts[table] = (res.first['c'] as num?)?.toInt() ?? 0;
        }

        await txn.insert(
          'migration_history',
          {
            'migration_id': migrationId,
            'completed_at': DateTime.now().millisecondsSinceEpoch,
            'direction': 'received',
            'record_counts': jsonEncode(counts),
            'payload_digest': payloadDigest,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await _createAutomaticBackup(db);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a delta/incremental snapshot containing only records added or updated since lastKnownIds
  Future<Map<String, dynamic>> createDeltaSnapshot({Map<String, int>? lastKnownIds}) async {
    final db = await database;
    final data = <String, List<Map<String, dynamic>>>{};
    final ids = lastKnownIds ?? {};
    int totalDeltaCount = 0;

    for (final table in migrationDataTables) {
      final lastId = ids[table] ?? 0;
      final rows = await db.query(
        table,
        where: 'id > ?',
        whereArgs: [lastId],
        orderBy: 'id ASC',
      );
      data[table] = rows.map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
      totalDeltaCount += rows.length;
    }

    return {
      'schemaVersion': await db.getVersion(),
      'dataVersion': 1,
      'isDelta': true,
      'totalDeltaCount': totalDeltaCount,
      'tables': data,
    };
  }

  /// Imports a delta/incremental snapshot without wiping out the entire database
  Future<bool> importDeltaSnapshot({
    required String syncId,
    required Map<String, dynamic> deltaTables,
    required String payloadDigest,
  }) async {
    _assertCanSyncData();

    final db = await database;
    try {
      await db.transaction((txn) async {
        for (final table in migrationDataTables) {
          final rows = deltaTables[table] as List<dynamic>? ?? [];
          for (final row in rows) {
            await txn.insert(
              table,
              Map<String, dynamic>.from(row as Map),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        final counts = <String, int>{};
        for (final table in migrationDataTables) {
          final res = await txn.rawQuery('SELECT COUNT(*) AS c FROM $table');
          counts[table] = (res.first['c'] as num?)?.toInt() ?? 0;
        }

        await txn.insert(
          'migration_history',
          {
            'migration_id': syncId,
            'completed_at': DateTime.now().millisecondsSinceEpoch,
            'direction': 'delta_received',
            'record_counts': jsonEncode(counts),
            'payload_digest': payloadDigest,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await _createAutomaticBackup(db);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> moveMigrationDataToRecovery({
    required String migrationId,
    required String destination,
    required String payload,
    required String payloadDigest,
    required DateTime migratedAt,
  }) async {
    _assertCanSync();

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
          'expires_at':
              migratedAt.add(const Duration(days: 7)).millisecondsSinceEpoch,
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

  Future<void> recordMigrationSent({
    required String migrationId,
    required String destination,
    required String payload,
    required String payloadDigest,
    required DateTime migratedAt,
  }) async {
    await moveMigrationDataToRecovery(
      migrationId: migrationId,
      destination: destination,
      payload: payload,
      payloadDigest: payloadDigest,
      migratedAt: migratedAt,
    );
  }

  Future<Map<String, dynamic>?> getMigrationRecovery() async {
    final db = await database;
    final rows = await db.query('migration_recovery', where: 'id = 1');
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> restoreMigrationRecovery() async {
    _assertCanSync();

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
    _assertCanSync();
    final db = await database;
    await db.delete('migration_recovery', where: 'id = 1');
  }

  // ============================================================
  // VARGANI
  // ============================================================

  Future<int> insertVargani(Map<String, dynamic> data) async {
    _assertCanAdd();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=vargani op=INSERT recordId=NEW');

    int id = 0;
    await db.transaction((txn) async {
      id = await txn.insert(
        'vargani',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'vargani',
        recordId: id.toString(),
        operation: 'INSERT',
        version: 1,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=vargani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=vargani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return id;
  }

  Future<List<Map<String, dynamic>>> getVargani(int year) async {
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
    final normalized =
        name.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    for (final row in list) {
      if (excludeId != null && row['id'] == excludeId) continue;
      final existingNormalized =
          (row['name']?.toString() ?? '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .toLowerCase();
      if (existingNormalized == normalized) {
        return true;
      }
    }
    return false;
  }

  Future<int> updateVargani(int id, Map<String, dynamic> data) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=vargani op=UPDATE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.update(
        'vargani',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'vargani', id.toString());
      final newVersion = currentVersion + 1;

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'vargani',
        recordId: id.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=vargani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=vargani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<int> deleteVargani(int id) async {
    _assertCanDelete();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=vargani op=DELETE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.delete('vargani', where: 'id = ?', whereArgs: [id]);

      final currentVersion = await _getRecordVersionInTxn(txn, 'vargani', id.toString());
      final newVersion = currentVersion + 1;

      await _recordDeleteInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'vargani',
        recordId: id.toString(),
        version: newVersion,
        changedAt: now,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=vargani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=vargani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<double> getVarganiTotal(int year) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM vargani
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ============================================================
  // PREVIOUS BALANCE
  // ============================================================

  Future<void> savePreviousBalance(int year, double amount) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=previous_balance op=UPDATE recordId=$year');

    await db.transaction((txn) async {
      await txn.insert('previous_balance', {
        'year': year,
        'amount': amount,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final currentVersion = await _getRecordVersionInTxn(txn, 'previous_balance', year.toString());
      final newVersion = currentVersion + 1;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'previous_balance',
        recordId: year.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: {'year': year, 'amount': amount},
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=previous_balance recordId=$year');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=previous_balance recordId=$year status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();
  }

  Future<double> getPreviousBalance(int year) async {
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

    return (result.first['amount'] as num?)?.toDouble() ?? 0.0;
  }

  // ============================================================
  // PRASAD DENGANI
  // ============================================================

  Future<int> insertPrasadDengani(Map<String, dynamic> data) async {
    _assertCanAdd();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=prasad_dengani op=INSERT recordId=NEW');

    int id = 0;
    await db.transaction((txn) async {
      id = await txn.insert(
        'prasad_dengani',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'prasad_dengani',
        recordId: id.toString(),
        operation: 'INSERT',
        version: 1,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=prasad_dengani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=prasad_dengani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return id;
  }

  Future<List<Map<String, dynamic>>> getPrasadDengani(int year) async {
    final db = await database;

    return await db.query(
      'prasad_dengani',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updatePrasadDengani(int id, Map<String, dynamic> data) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=prasad_dengani op=UPDATE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.update(
        'prasad_dengani',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'prasad_dengani', id.toString());
      final newVersion = currentVersion + 1;

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'prasad_dengani',
        recordId: id.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=prasad_dengani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=prasad_dengani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<int> deletePrasadDengani(int id) async {
    _assertCanDelete();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=prasad_dengani op=DELETE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.delete(
        'prasad_dengani',
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'prasad_dengani', id.toString());
      final newVersion = currentVersion + 1;

      await _recordDeleteInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'prasad_dengani',
        recordId: id.toString(),
        version: newVersion,
        changedAt: now,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=prasad_dengani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=prasad_dengani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<double> getPrasadDenganiTotal(int year) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM prasad_dengani
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ============================================================
  // PRASAD SAHITYA
  // ============================================================

  Future<int> insertPrasadSahitya(Map<String, dynamic> data) async {
    _assertCanAdd();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=prasad_sahitya op=INSERT recordId=NEW');

    int id = 0;
    await db.transaction((txn) async {
      id = await txn.insert(
        'prasad_sahitya',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'prasad_sahitya',
        recordId: id.toString(),
        operation: 'INSERT',
        version: 1,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=prasad_sahitya recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=prasad_sahitya recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return id;
  }

  Future<List<Map<String, dynamic>>> getPrasadSahitya(int year) async {
    final db = await database;

    return await db.query(
      'prasad_sahitya',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updatePrasadSahitya(int id, Map<String, dynamic> data) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=prasad_sahitya op=UPDATE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.update(
        'prasad_sahitya',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'prasad_sahitya', id.toString());
      final newVersion = currentVersion + 1;

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'prasad_sahitya',
        recordId: id.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=prasad_sahitya recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=prasad_sahitya recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<int> deletePrasadSahitya(int id) async {
    _assertCanDelete();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=prasad_sahitya op=DELETE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.delete(
        'prasad_sahitya',
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'prasad_sahitya', id.toString());
      final newVersion = currentVersion + 1;

      await _recordDeleteInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'prasad_sahitya',
        recordId: id.toString(),
        version: newVersion,
        changedAt: now,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=prasad_sahitya recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=prasad_sahitya recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  // ============================================================
  // AARTI VARGANI
  // ============================================================

  Future<int> insertAartiVargani(Map<String, dynamic> data) async {
    _assertCanAdd();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=aarti_vargani op=INSERT recordId=NEW');

    int id = 0;
    await db.transaction((txn) async {
      id = await txn.insert(
        'aarti_vargani',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'aarti_vargani',
        recordId: id.toString(),
        operation: 'INSERT',
        version: 1,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=aarti_vargani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=aarti_vargani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return id;
  }

  Future<List<Map<String, dynamic>>> getAartiVargani(int year) async {
    final db = await database;

    return await db.query(
      'aarti_vargani',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateAartiVargani(int id, Map<String, dynamic> data) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=aarti_vargani op=UPDATE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.update(
        'aarti_vargani',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'aarti_vargani', id.toString());
      final newVersion = currentVersion + 1;

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'aarti_vargani',
        recordId: id.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=aarti_vargani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=aarti_vargani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<int> deleteAartiVargani(int id) async {
    _assertCanDelete();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=aarti_vargani op=DELETE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.delete(
        'aarti_vargani',
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'aarti_vargani', id.toString());
      final newVersion = currentVersion + 1;

      await _recordDeleteInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'aarti_vargani',
        recordId: id.toString(),
        version: newVersion,
        changedAt: now,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=aarti_vargani recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=aarti_vargani recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<double> getAartiVarganiTotal(int year) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM aarti_vargani
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ============================================================
  // KHARCH
  // ============================================================

  Future<int> insertKharch(Map<String, dynamic> data) async {
    _assertCanAdd();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=kharch op=INSERT recordId=NEW');

    int id = 0;
    await db.transaction((txn) async {
      id = await txn.insert(
        'kharch',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'kharch',
        recordId: id.toString(),
        operation: 'INSERT',
        version: 1,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=kharch recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=kharch recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return id;
  }

  Future<List<Map<String, dynamic>>> getKharch(int year) async {
    final db = await database;

    return await db.query(
      'kharch',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateKharch(int id, Map<String, dynamic> data) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=kharch op=UPDATE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.update(
        'kharch',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'kharch', id.toString());
      final newVersion = currentVersion + 1;

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'kharch',
        recordId: id.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=kharch recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=kharch recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<int> deleteKharch(int id) async {
    _assertCanDelete();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=kharch op=DELETE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.delete('kharch', where: 'id = ?', whereArgs: [id]);

      final currentVersion = await _getRecordVersionInTxn(txn, 'kharch', id.toString());
      final newVersion = currentVersion + 1;

      await _recordDeleteInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'kharch',
        recordId: id.toString(),
        version: newVersion,
        changedAt: now,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=kharch recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=kharch recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<double> getKharchTotal(int year) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM kharch
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ============================================================
  // MAHAPRASAD KHARCH
  // ============================================================

  Future<int> insertMahaprasadKharch(Map<String, dynamic> data) async {
    _assertCanAdd();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=mahaprasad_kharch op=INSERT recordId=NEW');

    int id = 0;
    await db.transaction((txn) async {
      id = await txn.insert(
        'mahaprasad_kharch',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'mahaprasad_kharch',
        recordId: id.toString(),
        operation: 'INSERT',
        version: 1,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=mahaprasad_kharch recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=mahaprasad_kharch recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return id;
  }

  Future<List<Map<String, dynamic>>> getMahaprasadKharch(int year) async {
    final db = await database;

    return await db.query(
      'mahaprasad_kharch',
      where: 'year = ?',
      whereArgs: [year],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateMahaprasadKharch(int id, Map<String, dynamic> data) async {
    _assertCanEdit();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=mahaprasad_kharch op=UPDATE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.update(
        'mahaprasad_kharch',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'mahaprasad_kharch', id.toString());
      final newVersion = currentVersion + 1;

      final rowData = Map<String, dynamic>.from(data);
      rowData['id'] = id;

      await _recordChangeInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'mahaprasad_kharch',
        recordId: id.toString(),
        operation: 'UPDATE',
        version: newVersion,
        changedAt: now,
        recordData: rowData,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=mahaprasad_kharch recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=mahaprasad_kharch recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<int> deleteMahaprasadKharch(int id) async {
    _assertCanDelete();
    final db = await database;

    final deviceId = await DeviceService.instance.getDeviceId();
    final userId = AuthService.instance.currentUser?.userId ?? '';
    final changeId = 'chg_${DateTime.now().microsecondsSinceEpoch}_$deviceId';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[CHANGE_CREATED] changeId=$changeId table=mahaprasad_kharch op=DELETE recordId=$id');

    int result = 0;
    await db.transaction((txn) async {
      result = await txn.delete(
        'mahaprasad_kharch',
        where: 'id = ?',
        whereArgs: [id],
      );

      final currentVersion = await _getRecordVersionInTxn(txn, 'mahaprasad_kharch', id.toString());
      final newVersion = currentVersion + 1;

      await _recordDeleteInTxn(
        txn: txn,
        changeId: changeId,
        deviceId: deviceId,
        userId: userId,
        tableName: 'mahaprasad_kharch',
        recordId: id.toString(),
        version: newVersion,
        changedAt: now,
      );
    });

    print('[LOCAL_DB_COMMITTED] changeId=$changeId table=mahaprasad_kharch recordId=$id');
    print('[SYNC_QUEUE_ADDED] changeId=$changeId table=mahaprasad_kharch recordId=$id status=PENDING');

    await _createAutomaticBackup(db);

    RemoteSyncService.instance.notifyLocalChangeCreated();

    return result;
  }

  Future<double> getMahaprasadKharchTotal(int year) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM mahaprasad_kharch
      WHERE year = ?
      ''',
      [year],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ============================================================
  // SYNC CHANGE RECORDING & CONFLICT HANDLING HELPERS
  // ============================================================

  Future<void> _recordChangeInTxn({
    required Transaction txn,
    required String changeId,
    required String deviceId,
    required String userId,
    required String tableName,
    required String recordId,
    required String operation,
    required int version,
    required int changedAt,
    required Map<String, dynamic> recordData,
  }) async {
    final jsonStr = jsonEncode(recordData);

    await txn.insert(
      'sync_record_versions',
      {
        'table_name': tableName,
        'record_id': recordId,
        'version': version,
        'updated_at': changedAt,
        'device_id': deviceId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await txn.insert(
      'sync_change_log',
      {
        'change_id': changeId,
        'device_id': deviceId,
        'user_id': userId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'changed_at': changedAt,
        'version': version,
        'record_data': jsonStr,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await txn.insert(
      'sync_queue',
      {
        'change_id': changeId,
        'device_id': deviceId,
        'user_id': userId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'changed_at': changedAt,
        'version': version,
        'record_data': jsonStr,
        'status': 'PENDING',
        'created_at': changedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _recordDeleteInTxn({
    required Transaction txn,
    required String changeId,
    required String deviceId,
    required String userId,
    required String tableName,
    required String recordId,
    required int version,
    required int changedAt,
  }) async {
    await txn.insert(
      'sync_tombstones',
      {
        'table_name': tableName,
        'record_id': recordId,
        'deleted_at': changedAt,
        'device_id': deviceId,
        'user_id': userId,
        'version': version,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await txn.insert(
      'sync_record_versions',
      {
        'table_name': tableName,
        'record_id': recordId,
        'version': version,
        'updated_at': changedAt,
        'device_id': deviceId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final jsonStr = jsonEncode({'id': recordId});
    await txn.insert(
      'sync_change_log',
      {
        'change_id': changeId,
        'device_id': deviceId,
        'user_id': userId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': 'DELETE',
        'changed_at': changedAt,
        'version': version,
        'record_data': jsonStr,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await txn.insert(
      'sync_queue',
      {
        'change_id': changeId,
        'device_id': deviceId,
        'user_id': userId,
        'table_name': tableName,
        'record_id': recordId,
        'operation': 'DELETE',
        'changed_at': changedAt,
        'version': version,
        'record_data': jsonStr,
        'status': 'PENDING',
        'created_at': changedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _getRecordVersionInTxn(
    Transaction txn,
    String tableName,
    String recordId,
  ) async {
    final rows = await txn.query(
      'sync_record_versions',
      columns: ['version'],
      where: 'table_name = ? AND record_id = ?',
      whereArgs: [tableName, recordId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['version'] as num?)?.toInt() ?? 0;
  }

  static ConflictResolution resolveConflict({
    required int incomingVersion,
    required int incomingChangedAt,
    required String incomingDeviceId,
    required int localVersion,
    required int localChangedAt,
    required String localDeviceId,
  }) {
    // 1. Higher version wins
    if (incomingVersion > localVersion) {
      return ConflictResolution(
        incomingWins: true,
        winnerDeviceId: incomingDeviceId,
        loserDeviceId: localDeviceId,
        winnerVersion: incomingVersion,
        loserVersion: localVersion,
        reason: 'Incoming version ($incomingVersion) > Local version ($localVersion)',
      );
    }
    if (incomingVersion < localVersion) {
      return ConflictResolution(
        incomingWins: false,
        winnerDeviceId: localDeviceId,
        loserDeviceId: incomingDeviceId,
        winnerVersion: localVersion,
        loserVersion: incomingVersion,
        reason: 'Local version ($localVersion) > Incoming version ($incomingVersion)',
      );
    }

    // 2. Later timestamp wins
    if (incomingChangedAt > localChangedAt) {
      return ConflictResolution(
        incomingWins: true,
        winnerDeviceId: incomingDeviceId,
        loserDeviceId: localDeviceId,
        winnerVersion: incomingVersion,
        loserVersion: localVersion,
        reason: 'Incoming timestamp ($incomingChangedAt) > Local timestamp ($localChangedAt)',
      );
    }
    if (incomingChangedAt < localChangedAt) {
      return ConflictResolution(
        incomingWins: false,
        winnerDeviceId: localDeviceId,
        loserDeviceId: incomingDeviceId,
        winnerVersion: localVersion,
        loserVersion: incomingVersion,
        reason: 'Local timestamp ($localChangedAt) > Incoming timestamp ($incomingChangedAt)',
      );
    }

    // 3. Deterministic tie-breaker on deviceId
    final cmp = incomingDeviceId.compareTo(localDeviceId);
    if (cmp > 0) {
      return ConflictResolution(
        incomingWins: true,
        winnerDeviceId: incomingDeviceId,
        loserDeviceId: localDeviceId,
        winnerVersion: incomingVersion,
        loserVersion: localVersion,
        reason: 'Tie-break: Incoming deviceId ($incomingDeviceId) > Local deviceId ($localDeviceId)',
      );
    } else {
      return ConflictResolution(
        incomingWins: false,
        winnerDeviceId: localDeviceId,
        loserDeviceId: incomingDeviceId,
        winnerVersion: localVersion,
        loserVersion: incomingVersion,
        reason: 'Tie-break: Local deviceId ($localDeviceId) >= Incoming deviceId ($incomingDeviceId)',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSyncQueue() async {
    final db = await database;
    return await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'changed_at ASC',
    );
  }

  Future<void> updateSyncQueueStatus(String changeId, String status) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': status},
      where: 'change_id = ?',
      whereArgs: [changeId],
    );
  }

  Future<void> markSyncQueueCompleted(String changeId) async {
    final db = await database;
    await db.delete(
      'sync_queue',
      where: 'change_id = ?',
      whereArgs: [changeId],
    );
  }

  Future<List<Map<String, dynamic>>> getSyncConflicts() async {
    final db = await database;
    return await db.query('sync_conflicts', orderBy: 'resolved_at DESC');
  }

  Future<bool> applyIncomingFinancialChange({
    required String changeId,
    required String deviceId,
    required String userId,
    required String tableName,
    required String recordId,
    required String operation,
    required int changedAt,
    required int version,
    required Map<String, dynamic> recordData,
  }) async {
    _assertCanSyncData();
    final db = await database;

    try {
      final success = await db.transaction<bool>((txn) async {
        // 1. Check idempotency: already applied changeId
        final alreadyReceived = await txn.query(
          'sync_received_changes',
          where: 'change_id = ?',
          whereArgs: [changeId],
          limit: 1,
        );
        if (alreadyReceived.isNotEmpty) {
          return true;
        }

        // 2. Check tombstones: has this record been deleted?
        final tombstones = await txn.query(
          'sync_tombstones',
          where: 'table_name = ? AND record_id = ?',
          whereArgs: [tableName, recordId],
          limit: 1,
        );

        if (tombstones.isNotEmpty && operation != 'DELETE') {
          final tombstoneDeletedAt = (tombstones.first['deleted_at'] as num).toInt();
          final tombstoneVersion = (tombstones.first['version'] as num).toInt();

          // If incoming change is older than or equal to deletion, ignore resurrection
          if (version <= tombstoneVersion || changedAt <= tombstoneDeletedAt) {
            print('[SYNC_CONFLICT] table=$tableName recordId=$recordId incomingVersion=$version tombstoneVersion=$tombstoneVersion winner=tombstone_deleted');
            await txn.insert(
              'sync_received_changes',
              {
                'change_id': changeId,
                'received_at': DateTime.now().millisecondsSinceEpoch,
                'table_name': tableName,
                'record_id': recordId,
                'operation': operation,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            return true;
          }
        }

        // 3. Conflict resolution for UPDATE / INSERT if record already exists
        if (operation == 'UPDATE' || operation == 'INSERT') {
          final localVersionRows = await txn.query(
            'sync_record_versions',
            where: 'table_name = ? AND record_id = ?',
            whereArgs: [tableName, recordId],
            limit: 1,
          );

          if (localVersionRows.isNotEmpty) {
            final localVersion = (localVersionRows.first['version'] as num).toInt();
            final localUpdatedAt = (localVersionRows.first['updated_at'] as num).toInt();
            final localDeviceId = (localVersionRows.first['device_id'] as String?) ?? '';

            final conflict = resolveConflict(
              incomingVersion: version,
              incomingChangedAt: changedAt,
              incomingDeviceId: deviceId,
              localVersion: localVersion,
              localChangedAt: localUpdatedAt,
              localDeviceId: localDeviceId,
            );

            if (!conflict.incomingWins) {
              // Local wins! Do NOT overwrite!
              print('[SYNC_CONFLICT] table=$tableName recordId=$recordId incomingVersion=$version localVersion=$localVersion winner=local');

              await txn.insert('sync_conflicts', {
                'change_id': changeId,
                'table_name': tableName,
                'record_id': recordId,
                'winner_device_id': localDeviceId,
                'loser_device_id': deviceId,
                'winner_version': localVersion,
                'loser_version': version,
                'winner_data': 'LOCAL_RETAINED',
                'loser_data': jsonEncode(recordData),
                'resolved_at': DateTime.now().millisecondsSinceEpoch,
              }, conflictAlgorithm: ConflictAlgorithm.replace);

              await txn.insert(
                'sync_received_changes',
                {
                  'change_id': changeId,
                  'received_at': DateTime.now().millisecondsSinceEpoch,
                  'table_name': tableName,
                  'record_id': recordId,
                  'operation': operation,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              return true;
            } else {
              // Incoming wins! Overwrite local data with traceability
              print('[SYNC_CONFLICT] table=$tableName recordId=$recordId incomingVersion=$version localVersion=$localVersion winner=incoming');
              await txn.insert('sync_conflicts', {
                'change_id': changeId,
                'table_name': tableName,
                'record_id': recordId,
                'winner_device_id': deviceId,
                'loser_device_id': localDeviceId,
                'winner_version': version,
                'loser_version': localVersion,
                'winner_data': jsonEncode(recordData),
                'loser_data': 'LOCAL_OVERWRITTEN',
                'resolved_at': DateTime.now().millisecondsSinceEpoch,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }

        // 4. Apply the change to SQLite
        if (operation == 'INSERT' || operation == 'UPDATE') {
          final cleanData = Map<String, dynamic>.from(recordData);
          await txn.insert(
            tableName,
            cleanData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Clear any old tombstone if revived
          await txn.delete(
            'sync_tombstones',
            where: 'table_name = ? AND record_id = ?',
            whereArgs: [tableName, recordId],
          );
        } else if (operation == 'DELETE') {
          if (tableName == 'previous_balance') {
            final year = int.tryParse(recordId) ?? recordData['year'];
            if (year != null) {
              await txn.delete(tableName, where: 'year = ?', whereArgs: [year]);
            }
          } else {
            final intId = int.tryParse(recordId) ?? recordData['id'];
            if (intId != null) {
              await txn.delete(tableName, where: 'id = ?', whereArgs: [intId]);
            }
          }

          // Record tombstone
          await txn.insert(
            'sync_tombstones',
            {
              'table_name': tableName,
              'record_id': recordId,
              'deleted_at': changedAt,
              'device_id': deviceId,
              'user_id': userId,
              'version': version,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // 5. Update record version
        await txn.insert(
          'sync_record_versions',
          {
            'table_name': tableName,
            'record_id': recordId,
            'version': version,
            'updated_at': changedAt,
            'device_id': deviceId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // 6. Record change as received
        await txn.insert(
          'sync_received_changes',
          {
            'change_id': changeId,
            'received_at': DateTime.now().millisecondsSinceEpoch,
            'table_name': tableName,
            'record_id': recordId,
            'operation': operation,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        return true;
      });

      await _createAutomaticBackup(db);
      return success;
    } catch (e) {
      print('[ERROR] Failed to apply incoming financial change: $e');
      return false;
    }
  }
}

class ConflictResolution {
  final bool incomingWins;
  final String winnerDeviceId;
  final String loserDeviceId;
  final int winnerVersion;
  final int loserVersion;
  final String reason;

  ConflictResolution({
    required this.incomingWins,
    required this.winnerDeviceId,
    required this.loserDeviceId,
    required this.winnerVersion,
    required this.loserVersion,
    required this.reason,
  });
}
