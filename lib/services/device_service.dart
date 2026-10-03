import 'dart:io';
import 'dart:math';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/device_model.dart';

class DeviceService {
  static final DeviceService instance = DeviceService._internal();

  DeviceService._internal();

  String? _cachedDeviceId;

  String? get currentDeviceId => _cachedDeviceId;

  static String generateUniqueDeviceId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(4, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    return 'D-$hex';
  }

  static String generateUniqueRequestId() {
    final rand = Random.secure().nextInt(9999).toString().padLeft(4, '0');
    return 'REQ_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  Future<File> _getDeviceIdFile() async {
    final hindviDir = Directory(DatabaseHelper.instance.hindviFolderPath);
    if (!await hindviDir.exists()) {
      await hindviDir.create(recursive: true);
    }
    return File(join(hindviDir.path, '.device_id'));
  }

  /// Returns the permanent unique deviceId for this phone/device.
  /// Never changes across updates.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    try {
      // 1. Try reading from persistent file
      final idFile = await _getDeviceIdFile();
      if (await idFile.exists()) {
        final content = (await idFile.readAsString()).trim();
        if (content.isNotEmpty) {
          _cachedDeviceId = content;
          return _cachedDeviceId!;
        }
      }

      // 2. Try reading from SQLite devices table
      final db = await DatabaseHelper.instance.database;
      final existingRows = await db.query(
        'devices',
        orderBy: 'created_at ASC',
        limit: 1,
      );

      if (existingRows.isNotEmpty) {
        final foundId = existingRows.first['device_id'] as String;
        if (foundId.isNotEmpty) {
          _cachedDeviceId = foundId;
          await idFile.writeAsString(foundId);
          return _cachedDeviceId!;
        }
      }

      // 3. Generate a new permanent deviceId
      final newId = generateUniqueDeviceId();
      _cachedDeviceId = newId;

      await idFile.writeAsString(newId);

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'devices',
        {
          'device_id': newId,
          'device_name': getDeviceDefaultName(),
          'user_id': null,
          'status': DeviceStatus.approved,
          'created_at': now,
          'updated_at': now,
          'last_seen_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      return newId;
    } catch (_) {
      // Fallback
      _cachedDeviceId ??= generateUniqueDeviceId();
      return _cachedDeviceId!;
    }
  }

  String getDeviceDefaultName() {
    if (Platform.isAndroid) {
      return 'Android Phone';
    } else if (Platform.isWindows) {
      return 'Windows PC';
    } else if (Platform.isIOS) {
      return 'iPhone';
    } else if (Platform.isMacOS) {
      return 'Mac';
    } else if (Platform.isLinux) {
      return 'Linux PC';
    }
    return 'Hindvi Device';
  }

  /// Returns the current device object from database
  Future<HindviDevice> getCurrentDevice() async {
    final devId = await getDeviceId();
    final db = await DatabaseHelper.instance.database;

    final rows = await db.query(
      'devices',
      where: 'device_id = ?',
      whereArgs: [devId],
      limit: 1,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    if (rows.isEmpty) {
      final newDev = HindviDevice(
        deviceId: devId,
        deviceName: getDeviceDefaultName(),
        status: DeviceStatus.approved,
        createdAt: now,
        updatedAt: now,
        lastSeenAt: now,
      );
      await db.insert('devices', newDev.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      return newDev;
    }

    return HindviDevice.fromMap(rows.first);
  }

  /// Checks if this device is currently REVOKED
  Future<bool> isCurrentDeviceRevoked() async {
    try {
      final dev = await getCurrentDevice();
      return dev.isRevoked;
    } catch (_) {
      return false;
    }
  }

  /// Checks if this device is currently APPROVED
  Future<bool> isCurrentDeviceApproved() async {
    try {
      final dev = await getCurrentDevice();
      return dev.isApproved;
    } catch (_) {
      return true;
    }
  }

  /// Register or update a device in the database
  Future<void> saveDevice(HindviDevice device) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'devices',
      device.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get list of all registered devices
  Future<List<HindviDevice>> getAllDevices() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'devices',
      orderBy: "CASE WHEN status = 'PENDING' THEN 0 WHEN status = 'APPROVED' THEN 1 ELSE 2 END, updated_at DESC",
    );
    return rows.map((r) => HindviDevice.fromMap(r)).toList();
  }

  /// Set device status to APPROVED
  Future<void> approveDevice(String deviceId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'devices',
      {
        'status': DeviceStatus.approved,
        'updated_at': now,
        'last_seen_at': now,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  /// Set device status to REVOKED
  Future<void> revokeDevice(String deviceId) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'devices',
      {
        'status': DeviceStatus.revoked,
        'updated_at': now,
      },
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  /// Delete a device record
  Future<void> deleteDevice(String deviceId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  // ============================================================
  // DEVICE REQUESTS MANAGEMENT
  // ============================================================

  /// Record a new device request locally
  Future<DeviceRequestModel> createDeviceRequest({
    required String userId,
    required String userName,
    required String requestType,
    String? requestedRole,
  }) async {
    final devId = await getDeviceId();
    final reqId = generateUniqueRequestId();
    final now = DateTime.now().millisecondsSinceEpoch;

    final request = DeviceRequestModel(
      requestId: reqId,
      userId: userId,
      userName: userName,
      deviceId: devId,
      deviceName: getDeviceDefaultName(),
      requestType: requestType,
      status: DeviceStatus.pending,
      requestedRole: requestedRole,
      createdAt: now,
      updatedAt: now,
    );

    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'device_requests',
      request.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return request;
  }

  /// Get list of device requests
  Future<List<DeviceRequestModel>> getDeviceRequests({bool pendingOnly = false}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'device_requests',
      where: pendingOnly ? 'status = ?' : null,
      whereArgs: pendingOnly ? [DeviceStatus.pending] : null,
      orderBy: "CASE WHEN status = 'PENDING' THEN 0 ELSE 1 END, created_at DESC",
    );
    return rows.map((r) => DeviceRequestModel.fromMap(r)).toList();
  }

  /// Update device request status
  Future<void> updateDeviceRequestStatus(String requestId, String status) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'device_requests',
      {
        'status': status,
        'updated_at': now,
      },
      where: 'request_id = ?',
      whereArgs: [requestId],
    );
  }

  /// Delete a device request
  Future<void> deleteDeviceRequest(String requestId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'device_requests',
      where: 'request_id = ?',
      whereArgs: [requestId],
    );
  }
}
