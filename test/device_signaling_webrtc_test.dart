import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/database/database_helper.dart';
import 'package:hindvi_app/models/device_model.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/services/auth_service.dart';
import 'package:hindvi_app/services/device_service.dart';
import 'package:hindvi_app/services/signaling_service.dart';
import 'package:hindvi_app/services/webrtc_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Device Models & Status Tests', () {
    test('DeviceStatus constants and Marathi titles', () {
      expect(DeviceStatus.pending, 'PENDING');
      expect(DeviceStatus.approved, 'APPROVED');
      expect(DeviceStatus.rejected, 'REJECTED');
      expect(DeviceStatus.revoked, 'REVOKED');

      expect(DeviceStatus.isApproved('APPROVED'), isTrue);
      expect(DeviceStatus.isRevoked('REVOKED'), isTrue);
      expect(DeviceStatus.isPending('PENDING'), isTrue);
      expect(DeviceStatus.isRejected('REJECTED'), isTrue);

      expect(DeviceStatus.marathiTitle('APPROVED'), contains('मंजूर'));
      expect(DeviceStatus.marathiTitle('REVOKED'), contains('रद्द'));
      expect(DeviceStatus.marathiTitle('PENDING'), contains('प्रलंबित'));
    });

    test('HindviDevice serialization & copyWith', () {
      const dev = HindviDevice(
        deviceId: 'D-ABC12345',
        deviceName: 'Android Phone',
        userId: 'khajani_101',
        status: DeviceStatus.approved,
        createdAt: 1000,
        updatedAt: 2000,
        lastSeenAt: 2500,
      );

      expect(dev.isApproved, isTrue);
      expect(dev.isRevoked, isFalse);
      expect(dev.deviceId, 'D-ABC12345');

      final map = dev.toMap();
      expect(map['device_id'], 'D-ABC12345');
      expect(map['device_name'], 'Android Phone');
      expect(map['user_id'], 'khajani_101');
      expect(map['status'], 'APPROVED');

      final fromMap = HindviDevice.fromMap(map);
      expect(fromMap.deviceId, dev.deviceId);
      expect(fromMap.deviceName, dev.deviceName);
      expect(fromMap.userId, dev.userId);
      expect(fromMap.status, dev.status);

      final revokedDev = dev.copyWith(status: DeviceStatus.revoked);
      expect(revokedDev.isRevoked, isTrue);
      expect(revokedDev.isApproved, isFalse);
    });

    test('DeviceRequestModel serialization & properties', () {
      final req = DeviceRequestModel(
        requestId: 'REQ_001',
        userId: 'khajani_test_1',
        userName: 'अमित कदम',
        deviceId: 'D-12345678',
        deviceName: 'Xiaomi Note',
        requestType: 'NEW_ACCOUNT',
        status: DeviceStatus.pending,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(req.isPending, isTrue);
      expect(req.requestedAt, 1000);
      expect(req.marathiRequestType, 'नवीन खाते');

      final map = req.toMap();
      expect(map['request_id'], 'REQ_001');
      expect(map['device_id'], 'D-12345678');
      expect(map['user_name'], 'अमित कदम');

      final fromMap = DeviceRequestModel.fromMap(map);
      expect(fromMap.requestId, req.requestId);
      expect(fromMap.userId, req.userId);
      expect(fromMap.deviceId, req.deviceId);
      expect(fromMap.status, req.status);
    });
  });

  group('Device ID Generation & Separation of Account vs Device', () {
    test('generateUniqueDeviceId produces D-XXXXXXXX format', () {
      final id1 = DeviceService.generateUniqueDeviceId();
      final id2 = DeviceService.generateUniqueDeviceId();

      expect(id1.startsWith('D-'), isTrue);
      expect(id2.startsWith('D-'), isTrue);
      expect(id1.length, 10); // D- + 8 hex chars
      expect(id1, isNot(equals(id2)));
    });

    test('Same-name users can have distinct userIds and deviceIds', () {
      final userId1 = AuthService.generateUniqueUserId();
      final userId2 = AuthService.generateUniqueUserId();
      expect(userId1, isNot(equals(userId2)));

      final devId1 = DeviceService.generateUniqueDeviceId();
      final devId2 = DeviceService.generateUniqueDeviceId();
      expect(devId1, isNot(equals(devId2)));

      // Phone 1: Rahul, U001, D001
      // Phone 2: Rahul, U002, D002
      const user1 = KhajaniUser(
        userId: 'U001',
        name: 'Rahul',
        passwordHash: 'hash1',
        salt: 'salt1',
        role: KhajaniRole.latestKhajani,
        createdAt: 1000,
        updatedAt: 1000,
      );

      const user2 = KhajaniUser(
        userId: 'U002',
        name: 'Rahul',
        passwordHash: 'hash2',
        salt: 'salt2',
        role: KhajaniRole.oldKhajani,
        createdAt: 2000,
        updatedAt: 2000,
      );

      expect(user1.name, equals(user2.name));
      expect(user1.userId, isNot(equals(user2.userId)));
    });
  });

  group('Developer Account Security & Rules', () {
    test('Developer credentials and SHA-256 verification', () {
      const devName = AuthService.developerName;
      expect(devName, 'Developer');

      const expectedSalt = 'hindvi_dev_salt_4030';
      const expectedPassword = 'Dev@4030';
      final expectedHash = sha256
          .convert(utf8.encode('$expectedSalt:$expectedPassword'))
          .toString();

      final isValid = AuthService.verifyPassword(
        password: expectedPassword,
        salt: expectedSalt,
        hash: expectedHash,
      );
      expect(isValid, isTrue);

      final isWrong = AuthService.verifyPassword(
        password: 'WrongPassword',
        salt: expectedSalt,
        hash: expectedHash,
      );
      expect(isWrong, isFalse);
    });

    test('Developer user object has full permissions and cannot be modified', () {
      final devUser = KhajaniUser(
        userId: AuthService.developerUserId,
        name: AuthService.developerName,
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.developer,
        permissions: const KhajaniPermissions.developer(),
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(devUser.isDeveloper, isTrue);
      expect(devUser.effectivePermissions.canView, isTrue);
      expect(devUser.effectivePermissions.canAdd, isTrue);
      expect(devUser.effectivePermissions.canEdit, isTrue);
      expect(devUser.effectivePermissions.canDelete, isTrue);
      expect(devUser.effectivePermissions.canSearch, isTrue);
      expect(devUser.effectivePermissions.canPdf, isTrue);
      expect(devUser.effectivePermissions.canManageKhajani, isTrue);
      expect(devUser.effectivePermissions.canSync, isTrue);
    });

    test('Developer account cannot be deleted or role reassigned', () async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: AuthService.developerUserId,
          name: AuthService.developerName,
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.developer,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      // Attempting to delete Developer account throws StateError
      expect(
        () => AuthService.instance.deleteKhajani(
          userId: AuthService.developerUserId,
        ),
        throwsA(isA<StateError>()),
      );

      // Attempting to deactivate Developer account throws StateError
      expect(
        () => AuthService.instance.toggleKhajaniStatus(
          userId: AuthService.developerUserId,
          isActive: false,
        ),
        throwsA(isA<StateError>()),
      );

      // Attempting to change Developer permissions throws StateError
      expect(
        () => AuthService.instance.updateKhajaniPermissions(
          userId: AuthService.developerUserId,
          permissions: const KhajaniPermissions.oldDefault(),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Database Device Revocation Enforcement', () {
    test('Setting device revoked locks database writes', () {
      final dbHelper = DatabaseHelper.instance;

      // Ensure normal state first
      dbHelper.setDeviceRevokedState(false);

      // Revoke the device
      dbHelper.setDeviceRevokedState(true);

      // All financial write assert methods must throw StateError
      expect(
        () => dbHelper.assertDeviceNotRevokedForTesting(),
        throwsA(isA<StateError>()),
      );

      // Restoring the device unlocks writes
      dbHelper.setDeviceRevokedState(false);
      expect(
        () => dbHelper.assertDeviceNotRevokedForTesting(),
        returnsNormally,
      );
    });
  });

  group('Signaling Service & Remote Sync Architecture', () {
    test('Signaling service default URL and configuration', () {
      final signaling = SignalingService.instance;
      expect(SignalingService.defaultServerUrl, anyOf(contains('ws://'), contains('wss://')));
      expect(signaling.serverUrl, isNotEmpty);
      expect(signaling.isConnected, isFalse);
    });

    test('WebRtcSyncService Master Phone Check', () {
      final syncService = WebRtcSyncService.instance;

      // Developer is authorized master
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: AuthService.developerUserId,
          name: AuthService.developerName,
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.developer,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      expect(syncService.isMaster, isTrue);

      // Latest Khajani is authorized master
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'khajani_latest',
          name: 'Latest Khajani',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      expect(syncService.isMaster, isTrue);

      // Old Khajani is NOT authorized master (read-only client)
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'khajani_old',
          name: 'Old Khajani',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.oldKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      expect(syncService.isMaster, isFalse);
    });

    test('WebRtcSyncService snapshot checksum validation', () {
      final syncService = WebRtcSyncService.instance;

      final tables = <String, dynamic>{};
      for (final table in DatabaseHelper.migrationDataTables) {
        tables[table] = <Map<String, dynamic>>[];
      }

      final snapshot = {
        'version': 8,
        'created_at': 1000,
        'tables': tables,
      };
      final jsonString = jsonEncode(snapshot);
      final validDigest = sha256.convert(utf8.encode(jsonString)).toString();

      final validPackage = {
        'sync_id': 'sync_123',
        'payload_digest': validDigest,
        'record_counts': {'vargani': 0},
        'snapshot': snapshot,
      };

      expect(syncService.validateSyncPackage(validPackage), isTrue);

      final corruptedPackage = {
        'sync_id': 'sync_123',
        'payload_digest': 'corrupted_digest_value',
        'record_counts': {'vargani': 0},
        'snapshot': snapshot,
      };

      expect(syncService.validateSyncPackage(corruptedPackage), isFalse);
    });
  });

  group('Offline First Verification', () {
    test('Local authentication requires neither PC nor Internet', () {
      // Offline environment: Signaling is not connected
      expect(SignalingService.instance.isConnected, isFalse);

      // User with APPROVED status can operate locally
      const approvedUser = KhajaniUser(
        userId: 'khajani_offline_1',
        name: 'Offline Khajani',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions.latestDefault(),
        createdAt: 1000,
        updatedAt: 1000,
      );

      AuthService.instance.setCurrentUserForTesting(approvedUser);

      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.canView, isTrue);
      expect(AuthService.instance.canAdd, isTrue);
      expect(AuthService.instance.canEdit, isTrue);
      expect(AuthService.instance.canDelete, isTrue);
      expect(AuthService.instance.canSearch, isTrue);
      expect(AuthService.instance.canPdf, isTrue);
    });
  });
}
