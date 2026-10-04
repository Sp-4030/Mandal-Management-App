// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/device_model.dart';
import '../models/khajani_user.dart';
import 'device_service.dart';
import 'signaling_service.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();

  AuthService._internal();

  static const String developerName = 'Developer';
  static const String developerDefaultPassword = 'Dev@4030';
  static const String developerUserId = 'developer_root';

  KhajaniUser? _currentUser;

  KhajaniUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _currentUser!.isApproved;
  bool get isDeveloper => _currentUser?.isDeveloper ?? false;
  bool get isLatestKhajani =>
      _currentUser == null || (_currentUser?.isLatestKhajani ?? false);
  bool get isOldKhajani => _currentUser?.isOldKhajani ?? false;

  bool get canModify =>
      isDeveloper ||
      (_currentUser == null
          ? true
          : (_currentUser!.isApproved &&
              isLatestKhajani &&
              canAdd &&
              canEdit));

  bool get canView =>
      isDeveloper || (_currentUser?.effectivePermissions.canView ?? true);
  bool get canAdd =>
      isDeveloper ||
      (_currentUser?.effectivePermissions.canAdd ?? (_currentUser == null));
  bool get canEdit =>
      isDeveloper ||
      (_currentUser?.effectivePermissions.canEdit ?? (_currentUser == null));
  bool get canDelete =>
      isDeveloper ||
      (_currentUser?.effectivePermissions.canDelete ?? (_currentUser == null));
  bool get canSearch =>
      isDeveloper || (_currentUser?.effectivePermissions.canSearch ?? true);
  bool get canPdf =>
      isDeveloper || (_currentUser?.effectivePermissions.canPdf ?? true);
  bool get canManageKhajani =>
      isDeveloper ||
      (_currentUser?.effectivePermissions.canManageKhajani ??
          (_currentUser == null));
  bool get canSync =>
      isDeveloper ||
      (_currentUser?.effectivePermissions.canSync ?? (_currentUser == null));

  void setCurrentUserForTesting(KhajaniUser? user) {
    _currentUser = user;
  }

  void _assertIsDeveloper() {
    if (!isDeveloper) {
      throw StateError('केवळ Developer लाच ही कृती करण्याची परवानगी आहे.');
    }
  }

  // ============================================================
  // PASSWORD HASHING & SECURITY
  // ============================================================

  static String generateSalt([int length = 16]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  static bool verifyPassword({
    required String password,
    required String salt,
    required String hash,
  }) {
    return hashPassword(password, salt) == hash;
  }

  static String generateUniqueUserId() {
    final rand = Random.secure().nextInt(999999).toString().padLeft(6, '0');
    return 'khajani_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  // ============================================================
  // ENSURE DEVELOPER ACCOUNT
  // ============================================================

  Future<void> ensureDeveloperAccount(DatabaseExecutor db) async {
    try {
      // Defensive check for status column
      try {
        final tableInfo = await db.rawQuery('PRAGMA table_info(khajani_users)');
        final existingCols = tableInfo.map((r) => r['name'] as String).toSet();
        if (!existingCols.contains('status')) {
          await db.execute(
            "ALTER TABLE khajani_users ADD COLUMN status TEXT NOT NULL DEFAULT 'APPROVED'",
          );
        }
      } catch (_) {}

      final existing = await db.query(
        'khajani_users',
        where: 'role = ? OR user_id = ? OR LOWER(name) = ?',
        whereArgs: [
          KhajaniRole.developer,
          developerUserId,
          developerName.toLowerCase(),
        ],
        limit: 1,
      );

      final now = DateTime.now().millisecondsSinceEpoch;

      if (existing.isEmpty) {
        final salt = generateSalt();
        final hash = hashPassword(developerDefaultPassword, salt);
        await db.insert(
          'khajani_users',
          {
            'user_id': developerUserId,
            'name': developerName,
            'password_hash': hash,
            'salt': salt,
            'role': KhajaniRole.developer,
            'status': KhajaniStatus.approved,
            'is_active': 1,
            'can_view': 1,
            'can_add': 1,
            'can_edit': 1,
            'can_delete': 1,
            'can_search': 1,
            'can_pdf': 1,
            'can_manage_khajani': 1,
            'can_sync': 1,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final row = existing.first;
        final userId = row['user_id'] as String;
        await db.update(
          'khajani_users',
          {
            'role': KhajaniRole.developer,
            'status': KhajaniStatus.approved,
            'is_active': 1,
            'can_view': 1,
            'can_add': 1,
            'can_edit': 1,
            'can_delete': 1,
            'can_search': 1,
            'can_pdf': 1,
            'can_manage_khajani': 1,
            'can_sync': 1,
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }
    } catch (_) {
      // Continue safely if schema is not ready yet
    }
  }

  // ============================================================
  // SESSION INITIALIZATION
  // ============================================================

  Future<void> initSession() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await ensureDeveloperAccount(db);

      final isRevoked = await DeviceService.instance.isCurrentDeviceRevoked();
      DatabaseHelper.instance.setDeviceRevokedState(isRevoked);
      if (isRevoked) {
        _currentUser = null;
        await _clearSession(db);
        return;
      }

      final sessionRows = await db.query(
        'khajani_session',
        where: 'id = 1',
        limit: 1,
      );

      if (sessionRows.isEmpty) {
        _currentUser = null;
        return;
      }

      final session = sessionRows.first;
      final userId = session['user_id'] as String?;
      final keepLoggedIn = (session['keep_logged_in'] as num?)?.toInt() == 1;

      if (!keepLoggedIn || userId == null || userId.isEmpty) {
        _currentUser = null;
        return;
      }

      final userRows = await db.query(
        'khajani_users',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (userRows.isNotEmpty) {
        final user = KhajaniUser.fromMap(userRows.first);
        if (user.isActive && user.isApproved) {
          _currentUser = user;
        } else {
          _currentUser = null;
          await _clearSession(db);
        }
      } else {
        _currentUser = null;
        await _clearSession(db);
      }

      if (_currentUser == null) {
        // App Restart Fallback: If device is approved and has an approved user in local DB, restore session
        final approvedReq = await DeviceService.instance.getLatestApprovedRequest();
        if (approvedReq != null && approvedReq.userId.isNotEmpty) {
          final fallbackRows = await db.query(
            'khajani_users',
            where: 'user_id = ? AND status = ?',
            whereArgs: [approvedReq.userId, KhajaniStatus.approved],
            limit: 1,
          );
          if (fallbackRows.isNotEmpty) {
            final user = KhajaniUser.fromMap(fallbackRows.first);
            if (user.isActive && user.isApproved) {
              _currentUser = user;
              final now = DateTime.now().millisecondsSinceEpoch;
              await db.insert(
                'khajani_session',
                {
                  'id': 1,
                  'user_id': user.userId,
                  'keep_logged_in': 1,
                  'logged_in_at': now,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      }
    } catch (_) {
      _currentUser = null;
    }
  }

  // ============================================================
  // USER CHECKS & QUERIES
  // ============================================================

  Future<bool> hasAnyKhajanis() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.rawQuery(
        "SELECT COUNT(*) AS count FROM khajani_users WHERE role != 'DEVELOPER' AND status = 'APPROVED'",
      );
      final count = (result.first['count'] as num?)?.toInt() ?? 0;
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasAnyUsers() async {
    return hasAnyKhajanis();
  }

  Future<List<KhajaniUser>> getAllKhajanis({bool includePending = true}) async {
    final db = await DatabaseHelper.instance.database;
    await ensureDeveloperAccount(db);
    final rows = await db.query(
      'khajani_users',
      where: includePending ? null : 'status = ?',
      whereArgs: includePending ? null : [KhajaniStatus.approved],
      orderBy:
          "CASE WHEN role = 'DEVELOPER' THEN 0 WHEN status = 'PENDING' THEN 3 WHEN role = 'LATEST_KHAJANI' THEN 1 ELSE 2 END, created_at DESC",
    );
    return rows.map((r) => KhajaniUser.fromMap(r)).toList();
  }

  Future<List<KhajaniUser>> getPendingRequests() async {
    final db = await DatabaseHelper.instance.database;
    await ensureDeveloperAccount(db);
    final rows = await db.query(
      'khajani_users',
      where: 'status = ?',
      whereArgs: [KhajaniStatus.pending],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => KhajaniUser.fromMap(r)).toList();
  }

  Future<int> getPendingRequestsCount() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final res = await db.rawQuery(
        'SELECT COUNT(*) as count FROM khajani_users WHERE status = ?',
        [KhajaniStatus.pending],
      );
      return (res.first['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<KhajaniUser?> getKhajaniById(String userId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'khajani_users',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return KhajaniUser.fromMap(rows.first);
  }

  Future<KhajaniUser?> getLatestKhajani() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'khajani_users',
      where: 'role = ? AND status = ?',
      whereArgs: [KhajaniRole.latestKhajani, KhajaniStatus.approved],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return KhajaniUser.fromMap(rows.first);
  }

  // ============================================================
  // FIRST KHAJANI SETUP
  // ============================================================

  Future<KhajaniUser> registerFirstKhajani({
    required String name,
    required String password,
    required bool keepLoggedIn,
  }) async {
    final trimmedName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('नाव आवश्यक आहे.');
    }
    if (trimmedName.toLowerCase() == developerName.toLowerCase()) {
      throw ArgumentError(
        "'$developerName' हे नाव राखीव आहे. कृपया दुसरे नाव वापरा किंवा Developer पासवर्डने लॉगिन करा.",
      );
    }
    if (password.length < 4) {
      throw ArgumentError('पासवर्ड किमान ४ अक्षरांचा असावा.');
    }

    final db = await DatabaseHelper.instance.database;
    await ensureDeveloperAccount(db);

    final now = DateTime.now().millisecondsSinceEpoch;
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    final userId = generateUniqueUserId();

    final user = KhajaniUser(
      userId: userId,
      name: trimmedName,
      passwordHash: hash,
      salt: salt,
      role: KhajaniRole.latestKhajani,
      status: KhajaniStatus.approved,
      isActive: true,
      permissions: const KhajaniPermissions.latestDefault(),
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert(
        'khajani_users',
        user.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.insert(
        'khajani_session',
        {
          'id': 1,
          'user_id': userId,
          'keep_logged_in': keepLoggedIn ? 1 : 0,
          'logged_in_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _currentUser = user;
    return user;
  }

  // ============================================================
  // NEW USER REQUEST (PENDING APPROVAL)
  // ============================================================

  Future<KhajaniUser> requestNewAccount({
    required String name,
    required String password,
  }) async {
    final trimmedName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('नाव आवश्यक आहे.');
    }
    if (trimmedName.toLowerCase() == developerName.toLowerCase()) {
      throw ArgumentError(
        "'$developerName' हे नाव राखीव आहे. कृपया दुसरे नाव वापरा.",
      );
    }
    if (password.length < 4) {
      throw ArgumentError('पासवर्ड किमान ४ अक्षरांचा असावा.');
    }

    final db = await DatabaseHelper.instance.database;
    await ensureDeveloperAccount(db);

    final now = DateTime.now().millisecondsSinceEpoch;
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    final userId = generateUniqueUserId();

    final user = KhajaniUser(
      userId: userId,
      name: trimmedName,
      passwordHash: hash,
      salt: salt,
      role: KhajaniRole.oldKhajani,
      status: KhajaniStatus.pending,
      isActive: true,
      permissions: const KhajaniPermissions.pending(),
      createdAt: now,
      updatedAt: now,
    );

    await db.insert(
      'khajani_users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Also register device request
    try {
      final devReq = await DeviceService.instance.createDeviceRequest(
        userId: userId,
        userName: trimmedName,
        requestType: 'NEW_ACCOUNT',
        requestedRole: KhajaniRole.oldKhajani,
      );

      // Dispatch request via signaling service (connects on demand if internet available, offline safe)
      SignalingService.instance.sendDeviceRequest(devReq);
      SignalingService.instance.registerClient(
        role: 'CLIENT',
        deviceId: devReq.deviceId,
        userId: devReq.userId,
        userName: devReq.userName,
        requestId: devReq.requestId,
      );
    } catch (_) {}

    return user;
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<KhajaniUser?> login({
    required String name,
    required String password,
    required bool keepLoggedIn,
  }) async {
    final isRevoked = await DeviceService.instance.isCurrentDeviceRevoked();
    DatabaseHelper.instance.setDeviceRevokedState(isRevoked);
    if (isRevoked) {
      throw StateError(
        'हे डिव्हाइस रद्द (REVOKED) केले आहे. ॲप वापरता येणार नाही. कृपया Developer शी संपर्क साधा.',
      );
    }

    final trimmedName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmedName.isEmpty || password.isEmpty) {
      return null;
    }

    final db = await DatabaseHelper.instance.database;
    await ensureDeveloperAccount(db);

    final allUsers = await db.query(
      'khajani_users',
      where: 'LOWER(TRIM(name)) = ?',
      whereArgs: [trimmedName.toLowerCase()],
      orderBy:
          "CASE WHEN role = 'DEVELOPER' THEN 0 WHEN status = 'APPROVED' THEN 1 ELSE 2 END, created_at DESC",
    );

    KhajaniUser? matchedUser;
    bool wasDeactivatedMatch = false;
    bool wasPendingMatch = false;

    for (final row in allUsers) {
      final user = KhajaniUser.fromMap(row);
      if (verifyPassword(
        password: password,
        salt: user.salt,
        hash: user.passwordHash,
      )) {
        if (user.isPending) {
          wasPendingMatch = true;
          continue;
        }
        if (!user.isActive) {
          wasDeactivatedMatch = true;
          continue;
        }
        matchedUser = user;
        break;
      }
    }

    if (matchedUser == null) {
      if (wasPendingMatch) {
        throw StateError('Developer approval pending');
      }
      if (wasDeactivatedMatch) {
        throw StateError(
          'हे खाते निष्क्रिय (Deactivated) केले आहे. कृपया Developer शी संपर्क साधा.',
        );
      }
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'khajani_session',
      {
        'id': 1,
        'user_id': matchedUser.userId,
        'keep_logged_in': keepLoggedIn ? 1 : 0,
        'logged_in_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _currentUser = matchedUser;
    return matchedUser;
  }

  // ============================================================
  // SET NEW KHAJANI (REGULAR HANDOVER)
  // ============================================================

  Future<KhajaniUser> setNewKhajani({
    required String name,
    required String password,
  }) async {
    if (!isLatestKhajani && !isDeveloper) {
      throw StateError(
        'केवळ चालू खजानी किंवा Developer नवीन खजानी सेट करू शकतात.',
      );
    }

    final trimmedName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('नाव आवश्यक आहे.');
    }
    if (trimmedName.toLowerCase() == developerName.toLowerCase()) {
      throw ArgumentError("'$developerName' हे नाव राखीव आहे.");
    }
    if (password.length < 4) {
      throw ArgumentError('पासवर्ड किमान ४ अक्षरांचा असावा.');
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    final newUserId = generateUniqueUserId();

    final newUser = KhajaniUser(
      userId: newUserId,
      name: trimmedName,
      passwordHash: hash,
      salt: salt,
      role: KhajaniRole.latestKhajani,
      status: KhajaniStatus.approved,
      isActive: true,
      permissions: const KhajaniPermissions.latestDefault(),
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.update(
        'khajani_users',
        {
          'role': KhajaniRole.oldKhajani,
          'can_add': 0,
          'can_edit': 0,
          'can_delete': 0,
          'can_manage_khajani': 0,
          'can_sync': 0,
          'updated_at': now,
        },
        where: 'role = ?',
        whereArgs: [KhajaniRole.latestKhajani],
      );

      await txn.insert('khajani_users', newUser.toMap());
    });

    if (_currentUser != null && _currentUser!.isLatestKhajani) {
      _currentUser = _currentUser!.copyWith(
        role: KhajaniRole.oldKhajani,
        permissions: const KhajaniPermissions.oldDefault(),
        updatedAt: now,
      );
    }

    return newUser;
  }

  // ============================================================
  // DEVELOPER ADMIN CONTROLS
  // ============================================================

  Future<KhajaniUser> createKhajaniByDeveloper({
    required String name,
    required String password,
    required String role,
    required KhajaniPermissions permissions,
  }) async {
    _assertIsDeveloper();

    final trimmedName = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('नाव आवश्यक आहे.');
    }
    if (trimmedName.toLowerCase() == developerName.toLowerCase()) {
      throw ArgumentError("'$developerName' हे नाव राखीव आहे.");
    }
    if (role == KhajaniRole.developer) {
      throw ArgumentError('कोणत्याही वापरकर्त्याला Developer बनवता येत नाही.');
    }
    if (role != KhajaniRole.latestKhajani && role != KhajaniRole.oldKhajani) {
      throw ArgumentError('अवैध भूमिका (Invalid Role).');
    }
    if (password.length < 4) {
      throw ArgumentError('पासवर्ड किमान ४ अक्षरांचा असावा.');
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    final userId = generateUniqueUserId();

    final newUser = KhajaniUser(
      userId: userId,
      name: trimmedName,
      passwordHash: hash,
      salt: salt,
      role: role,
      status: KhajaniStatus.approved,
      isActive: true,
      permissions: permissions,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('khajani_users', newUser.toMap());
    return newUser;
  }

  // ============================================================
  // DEVELOPER: APPROVE PENDING USER REQUEST
  // ============================================================

  Future<void> approveKhajaniRequest({
    required String userId,
    required String role,
    required KhajaniPermissions permissions,
    String? deviceId,
    String? requestId,
  }) async {
    _assertIsDeveloper();

    if (userId == developerUserId) {
      throw StateError('Developer खाते आधीच मंजूर आहे.');
    }
    if (role == KhajaniRole.developer) {
      throw ArgumentError('कोणत्याही वापरकर्त्याला Developer बनवता येत नाही.');
    }
    if (role != KhajaniRole.latestKhajani && role != KhajaniRole.oldKhajani) {
      throw ArgumentError('अवैध भूमिका (Invalid Role).');
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    var targetUser = await getKhajaniById(userId);

    // If targetUser is null, find in device_requests and create account entry
    if (targetUser == null) {
      final reqs = await DeviceService.instance.getDeviceRequests();
      final match = reqs.firstWhere(
        (r) => r.userId == userId || (requestId != null && r.requestId == requestId),
        orElse: () => DeviceRequestModel(
          requestId: requestId ?? 'req_$now',
          userId: userId,
          userName: 'नवीन वापरकर्ता',
          deviceId: deviceId ?? '',
          deviceName: 'Android Phone',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final salt = generateSalt();
      targetUser = KhajaniUser(
        userId: userId,
        name: match.userName,
        passwordHash: '',
        salt: salt,
        role: role,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: permissions,
        createdAt: match.createdAt,
        updatedAt: now,
      );

      await db.insert(
        'khajani_users',
        targetUser.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      if (targetUser.isDeveloper) {
        throw StateError('Developer खात्यात बदल करता येत नाही.');
      }
    }

    await db.transaction((txn) async {
      // If approved as LATEST_KHAJANI, demote existing LATEST_KHAJANI to OLD_KHAJANI
      if (role == KhajaniRole.latestKhajani) {
        await txn.update(
          'khajani_users',
          {
            'role': KhajaniRole.oldKhajani,
            'can_add': 0,
            'can_edit': 0,
            'can_delete': 0,
            'can_manage_khajani': 0,
            'can_sync': 0,
            'updated_at': now,
          },
          where: 'role = ? AND user_id != ?',
          whereArgs: [KhajaniRole.latestKhajani, userId],
        );
      }

      await txn.update(
        'khajani_users',
        {
          'role': role,
          'status': KhajaniStatus.approved,
          'is_active': 1,
          ...permissions.toMap(),
          'updated_at': now,
        },
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    });

    if (_currentUser?.userId == userId) {
      _currentUser = _currentUser!.copyWith(
        role: role,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: permissions,
        updatedAt: now,
      );
    }

    // Update device request and device status locally
    try {
      final requests = await DeviceService.instance.getDeviceRequests();
      final matchingReq = requests.where((r) => r.userId == userId || (requestId != null && r.requestId == requestId)).toList();
      for (final req in matchingReq) {
        await DeviceService.instance.updateDeviceRequestStatus(req.requestId, DeviceStatus.approved);
        if (req.deviceId.isNotEmpty) {
          await DeviceService.instance.approveDevice(req.deviceId);
        }
      }
      if (deviceId != null && deviceId.isNotEmpty) {
        await DeviceService.instance.approveDevice(deviceId);
      }

      // Notify through PC Signaling Server
      final targetDev = (deviceId != null && deviceId.isNotEmpty && deviceId != 'N/A')
          ? deviceId
          : (matchingReq.isNotEmpty ? matchingReq.first.deviceId : '');
      final reqId = (requestId != null && requestId.isNotEmpty)
          ? requestId
          : (matchingReq.isNotEmpty ? matchingReq.first.requestId : 'req_$userId');

      // STEP 1: DEVELOPER_APPROVED
      print('[DEVELOPER_APPROVED] requestId=$reqId userId=$userId deviceId=$targetDev status=APPROVED');

      // STEP 2: APPROVAL_SENT_TO_SERVER logged inside sendDeviceApproval
      SignalingService.instance.sendDeviceApproval(
        requestId: reqId,
        deviceId: targetDev,
        userId: userId,
        status: KhajaniStatus.approved,
        role: role,
        permissions: permissions,
      );
    } catch (_) {}
  }

  /// Helper to apply approved status to local SQLite database and refresh session
  Future<void> applyApprovalLocally({
    required String requestId,
    required String userId,
    required String deviceId,
    required String role,
    Map<String, dynamic>? permissionsMap,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // 1. Update device_requests
      if (requestId.isNotEmpty) {
        await txn.update(
          'device_requests',
          {'status': 'APPROVED', 'updated_at': now},
          where: 'request_id = ?',
          whereArgs: [requestId],
        );
      } else if (userId.isNotEmpty) {
        await txn.update(
          'device_requests',
          {'status': 'APPROVED', 'updated_at': now},
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }

      // 2. Update khajani_users
      if (userId.isNotEmpty) {
        final updateData = <String, dynamic>{
          'role': role,
          'status': 'APPROVED',
          'is_active': 1,
          'updated_at': now,
        };
        if (permissionsMap != null) {
          updateData.addAll(permissionsMap);
        }

        final existing = await txn.query(
          'khajani_users',
          where: 'user_id = ?',
          whereArgs: [userId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          await txn.update(
            'khajani_users',
            updateData,
            where: 'user_id = ?',
            whereArgs: [userId],
          );
        } else {
          final reqRows = await txn.query(
            'device_requests',
            where: 'user_id = ?',
            whereArgs: [userId],
            limit: 1,
          );
          final userName = reqRows.isNotEmpty
              ? (reqRows.first['user_name'] as String? ?? 'नवीन वापरकर्ता')
              : 'नवीन वापरकर्ता';
          final salt = generateSalt();
          updateData['user_id'] = userId;
          updateData['name'] = userName;
          updateData['password_hash'] = '';
          updateData['salt'] = salt;
          updateData['created_at'] = now;
          await txn.insert(
            'khajani_users',
            updateData,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // 3. Update devices
      if (deviceId.isNotEmpty) {
        await txn.update(
          'devices',
          {'status': 'APPROVED', 'updated_at': now, 'last_seen_at': now},
          where: 'device_id = ?',
          whereArgs: [deviceId],
        );
      }

      // 4. Update session
      if (userId.isNotEmpty) {
        await txn.insert(
          'khajani_session',
          {
            'id': 1,
            'user_id': userId,
            'keep_logged_in': 1,
            'logged_in_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    // STEP 7 LOG
    print('[NEW_PHONE_SAVED_APPROVAL_TO_SQLITE] requestId=$requestId userId=$userId deviceId=$deviceId status=APPROVED');

    // STEP 8
    await initSession();
    print('[NEW_PHONE_REFRESHED_SESSION] requestId=$requestId userId=$userId deviceId=$deviceId status=APPROVED');
  }

  // ============================================================
  // DEVELOPER: REJECT OR DELETE REQUEST
  // ============================================================

  Future<void> rejectOrDeleteRequest({
    required String requestId,
    required String userId,
    String? deviceId,
  }) async {
    _assertIsDeveloper();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Delete or mark rejected in device_requests
    await DeviceService.instance.deleteDeviceRequest(requestId);

    // If there is a pending user in khajani_users, remove
    if (userId.isNotEmpty && userId != developerUserId) {
      final user = await getKhajaniById(userId);
      if (user != null && user.isPending) {
        await db.delete('khajani_users', where: 'user_id = ?', whereArgs: [userId]);
      }
    }

    if (deviceId != null && deviceId.isNotEmpty) {
      await db.update(
        'devices',
        {'status': DeviceStatus.rejected, 'updated_at': now},
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );
    }

    // Send rejection signal
    if (SignalingService.instance.isConnected) {
      SignalingService.instance.sendDeviceRejection(
        requestId: requestId,
        deviceId: deviceId ?? '',
        userId: userId,
      );
    }
  }

  // ============================================================
  // SECOND DEVICE REQUEST
  // ============================================================

  Future<DeviceRequestModel> requestNewDevice({
    required String userId,
    required String userName,
    String? requestedRole,
  }) async {
    final devReq = await DeviceService.instance.createDeviceRequest(
      userId: userId,
      userName: userName,
      requestType: 'NEW_DEVICE',
      requestedRole: requestedRole ?? KhajaniRole.oldKhajani,
    );

    if (!SignalingService.instance.isConnected) {
      SignalingService.instance.connect();
    }
    SignalingService.instance.sendDeviceRequest(devReq);
    return devReq;
  }

  Future<void> updateKhajaniRole({
    required String userId,
    required String newRole,
  }) async {
    _assertIsDeveloper();

    if (userId == developerUserId) {
      throw StateError('Developer खात्याचा रोल बदलता येत नाही.');
    }
    if (newRole == KhajaniRole.developer) {
      throw ArgumentError('कोणत्याही वापरकर्त्याला Developer बनवता येत नाही.');
    }
    if (newRole != KhajaniRole.latestKhajani &&
        newRole != KhajaniRole.oldKhajani) {
      throw ArgumentError('अवैध भूमिका (Invalid Role).');
    }

    final targetUser = await getKhajaniById(userId);
    if (targetUser != null && targetUser.isDeveloper) {
      throw StateError('Developer खात्याचा रोल बदलता येत नाही.');
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'khajani_users',
      {
        'role': newRole,
        'updated_at': now,
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    if (_currentUser?.userId == userId) {
      _currentUser = _currentUser!.copyWith(role: newRole, updatedAt: now);
    }
  }

  Future<void> updateKhajaniPermissions({
    required String userId,
    required KhajaniPermissions permissions,
  }) async {
    _assertIsDeveloper();

    if (userId == developerUserId) {
      throw StateError('Developer खात्याच्या परवानग्या बदलता येत नाहीत.');
    }
    final targetUser = await getKhajaniById(userId);
    if (targetUser != null && targetUser.isDeveloper) {
      throw StateError('Developer खात्याच्या परवानग्या बदलता येत नाहीत.');
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'khajani_users',
      {
        ...permissions.toMap(),
        'updated_at': now,
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    if (_currentUser?.userId == userId) {
      _currentUser = _currentUser!.copyWith(
        permissions: permissions,
        updatedAt: now,
      );
    }

    try {
      if (SignalingService.instance.isConnected) {
        SignalingService.instance.sendPermissionUpdate(
          deviceId: '',
          userId: userId,
          permissions: permissions,
        );
      }
    } catch (_) {}
  }

  Future<void> revokeDevice(String deviceId) async {
    _assertIsDeveloper();
    await DeviceService.instance.revokeDevice(deviceId);
    try {
      if (SignalingService.instance.isConnected) {
        SignalingService.instance.sendDeviceRevoke(deviceId: deviceId);
      }
    } catch (_) {}
  }

  Future<void> restoreDevice(String deviceId) async {
    _assertIsDeveloper();
    await DeviceService.instance.approveDevice(deviceId);
    try {
      if (SignalingService.instance.isConnected) {
        SignalingService.instance.sendDeviceApproval(
          requestId: 'restore_$deviceId',
          deviceId: deviceId,
          userId: '',
          status: DeviceStatus.approved,
          role: KhajaniRole.oldKhajani,
          permissions: const KhajaniPermissions.oldDefault(),
        );
      }
    } catch (_) {}
  }

  Future<void> deleteDevice(String deviceId) async {
    _assertIsDeveloper();
    await DeviceService.instance.deleteDevice(deviceId);
  }

  Future<void> toggleKhajaniStatus({
    required String userId,
    required bool isActive,
  }) async {
    _assertIsDeveloper();

    if (userId == developerUserId) {
      throw StateError('Developer खाते निष्क्रिय करता येत नाही.');
    }
    final targetUser = await getKhajaniById(userId);
    if (targetUser != null && targetUser.isDeveloper) {
      throw StateError('Developer खाते निष्क्रिय करता येत नाही.');
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'khajani_users',
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': now,
      },
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    if (!isActive) {
      await db.update(
        'khajani_session',
        {
          'user_id': null,
          'keep_logged_in': 0,
          'logged_in_at': null,
        },
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      if (_currentUser?.userId == userId) {
        _currentUser = null;
      }
    } else if (_currentUser?.userId == userId) {
      _currentUser = _currentUser!.copyWith(isActive: true, updatedAt: now);
    }
  }

  Future<void> deleteKhajani({required String userId}) async {
    _assertIsDeveloper();

    if (userId == developerUserId) {
      throw StateError('Developer खाते हटवता येत नाही.');
    }
    final targetUser = await getKhajaniById(userId);
    if (targetUser != null && targetUser.isDeveloper) {
      throw StateError('Developer खाते हटवता येत नाही.');
    }

    final db = await DatabaseHelper.instance.database;

    await db.transaction((txn) async {
      await txn.delete(
        'khajani_users',
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      await txn.update(
        'khajani_session',
        {
          'user_id': null,
          'keep_logged_in': 0,
          'logged_in_at': null,
        },
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    });

    if (_currentUser?.userId == userId) {
      _currentUser = null;
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    final db = await DatabaseHelper.instance.database;
    await _clearSession(db);
    _currentUser = null;
  }

  Future<void> _clearSession(DatabaseExecutor db) async {
    await db.insert(
      'khajani_session',
      {
        'id': 1,
        'user_id': null,
        'keep_logged_in': 0,
        'logged_in_at': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
