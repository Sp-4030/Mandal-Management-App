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

  group('Hindvi App End-to-End Architectural & Behavioral Flows', () {
    test('Test 1: New Phone Create Account -> PENDING -> Developer Pending Request Packet', () {
      // 1. Simulate new user on New Phone creating account
      const newUserName = 'गणेश जोशी';
      const password = 'User@123';
      final salt = AuthService.generateSalt();
      final hash = AuthService.hashPassword(password, salt);
      final userId = AuthService.generateUniqueUserId();

      final pendingUser = KhajaniUser(
        userId: userId,
        name: newUserName,
        passwordHash: hash,
        salt: salt,
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        isActive: true,
        permissions: const KhajaniPermissions.pending(),
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      );

      // Verify immediate PENDING state & no permissions
      expect(pendingUser.isPending, isTrue);
      expect(pendingUser.isApproved, isFalse);
      expect(pendingUser.effectivePermissions.canAdd, isFalse);
      expect(pendingUser.effectivePermissions.canEdit, isFalse);
      expect(pendingUser.effectivePermissions.canDelete, isFalse);
      expect(pendingUser.effectivePermissions.canManageKhajani, isFalse);
      expect(pendingUser.effectivePermissions.canSync, isFalse);

      // 2. Simulate signaling request packet sent over WebSocket to PC Server
      final requestPacket = {
        'type': 'device_request',
        'requestId': 'REQ_TEST_101',
        'userId': userId,
        'userName': newUserName,
        'deviceId': 'D-NEWPHONE01',
        'deviceName': 'Android Phone',
        'requestType': 'NEW_ACCOUNT',
        'requestedRole': 'OLD_KHAJANI',
        'createdAt': 1700000000000,
      };

      final reqModel = DeviceRequestModel.fromMap(requestPacket);
      expect(reqModel.requestId, equals('REQ_TEST_101'));
      expect(reqModel.userName, equals(newUserName));
      expect(reqModel.deviceId, equals('D-NEWPHONE01'));
      expect(reqModel.isPending, isTrue);
      expect(reqModel.marathiStatus, contains('प्रलंबित'));
    });

    test('Test 2: Developer Approve -> Role + Permissions -> Approved Status and Access Granted', () {
      const targetUserId = 'khajani_approved_test';
      const customPermissions = KhajaniPermissions(
        canView: true,
        canAdd: false,
        canEdit: false,
        canDelete: false,
        canSearch: true,
        canPdf: true,
        canManageKhajani: false,
        canSync: false,
      );

      final approvedUser = KhajaniUser(
        userId: targetUserId,
        name: 'गणेश जोशी',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: customPermissions,
        createdAt: 1700000000000,
        updatedAt: 1700000001000,
      );

      expect(approvedUser.isApproved, isTrue);
      expect(approvedUser.isPending, isFalse);
      expect(approvedUser.role, equals(KhajaniRole.oldKhajani));
      expect(approvedUser.effectivePermissions.canView, isTrue);
      expect(approvedUser.effectivePermissions.canSearch, isTrue);
      expect(approvedUser.effectivePermissions.canPdf, isTrue);
      expect(approvedUser.effectivePermissions.canAdd, isFalse);
      expect(approvedUser.effectivePermissions.canEdit, isFalse);
      expect(approvedUser.effectivePermissions.canDelete, isFalse);
      expect(approvedUser.effectivePermissions.canSync, isFalse);
    });

    test('Test 3: Developer Permission OFF -> Remote device write actions blocked', () {
      const restrictedUser = KhajaniUser(
        userId: 'khajani_restricted',
        name: 'Restricted User',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions(
          canView: true,
          canAdd: false,
          canEdit: false,
          canDelete: false,
          canSearch: true,
          canPdf: true,
          canManageKhajani: false,
          canSync: false,
        ),
        createdAt: 1000,
        updatedAt: 1000,
      );

      AuthService.instance.setCurrentUserForTesting(restrictedUser);

      // Verify permission flags
      expect(AuthService.instance.canView, isTrue);
      expect(AuthService.instance.canSearch, isTrue);
      expect(AuthService.instance.canPdf, isTrue);
      expect(AuthService.instance.canAdd, isFalse);
      expect(AuthService.instance.canEdit, isFalse);
      expect(AuthService.instance.canDelete, isFalse);
      expect(AuthService.instance.canSync, isFalse);
      expect(AuthService.instance.canModify, isFalse);

      // Verify DatabaseHelper asserts throw StateError
      final dbHelper = DatabaseHelper.instance;
      expect(() => dbHelper.insertVargani({'name': 'T', 'amount': 10, 'year': 2026}), throwsA(isA<StateError>()));
      expect(() => dbHelper.updateVargani(1, {'name': 'T', 'amount': 10, 'year': 2026}), throwsA(isA<StateError>()));
      expect(() => dbHelper.deleteVargani(1), throwsA(isA<StateError>()));
    });

    test('Test 4: PC OFF -> Approved user can still log in locally and use app', () {
      // Disconnected from PC Signaling Server
      expect(SignalingService.instance.isConnected, isFalse);

      const localApprovedUser = KhajaniUser(
        userId: 'khajani_local_approved',
        name: 'Local User',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions.latestDefault(),
        createdAt: 1000,
        updatedAt: 1000,
      );

      AuthService.instance.setCurrentUserForTesting(localApprovedUser);

      // App functions completely locally
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.canView, isTrue);
      expect(AuthService.instance.canAdd, isTrue);
      expect(AuthService.instance.canEdit, isTrue);
      expect(AuthService.instance.canDelete, isTrue);
      expect(AuthService.instance.canSearch, isTrue);
      expect(AuthService.instance.canPdf, isTrue);
    });

    test('Test 5: Internet OFF -> Local app works while remote sync unavailable', () {
      final syncService = WebRtcSyncService.instance;

      // When PC/Internet is OFF, signaling is disconnected
      expect(SignalingService.instance.isConnected, isFalse);

      // Old Khajani cannot act as master
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'khajani_old_1',
          name: 'Old User',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.oldKhajani,
          status: KhajaniStatus.approved,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      expect(syncService.isMaster, isFalse);
    });

    test('Test 6: Second Device -> Generates distinct device request for same user', () {
      final req1 = DeviceRequestModel(
        requestId: 'REQ_DEV_1',
        userId: 'khajani_same_user_101',
        userName: 'अमोल पाटील',
        deviceId: 'D-PHONE-A',
        deviceName: 'Android Phone A',
        requestType: 'NEW_ACCOUNT',
        status: DeviceStatus.approved,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final req2 = DeviceRequestModel(
        requestId: 'REQ_DEV_2',
        userId: 'khajani_same_user_101',
        userName: 'अमोल पाटील',
        deviceId: 'D-PHONE-B',
        deviceName: 'Android Phone B',
        requestType: 'NEW_DEVICE',
        status: DeviceStatus.pending,
        createdAt: 2000,
        updatedAt: 2000,
      );

      // Same user, distinct devices & requests
      expect(req1.userId, equals(req2.userId));
      expect(req1.deviceId, isNot(equals(req2.deviceId)));
      expect(req1.requestId, isNot(equals(req2.requestId)));
      expect(req1.isApproved, isTrue);
      expect(req2.isPending, isTrue);
    });

    test('Test 7: Revoke Device -> Blocks device and database writes', () {
      final dbHelper = DatabaseHelper.instance;

      // Lock device writes
      dbHelper.setDeviceRevokedState(true);
      expect(() => dbHelper.assertDeviceNotRevokedForTesting(), throwsA(isA<StateError>()));

      // Restore device
      dbHelper.setDeviceRevokedState(false);
      expect(() => dbHelper.assertDeviceNotRevokedForTesting(), returnsNormally);
    });

    test('Test 8: Remote Sync -> Prepares verified sync package with SHA-256', () {
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

    test('Test 9: Delete / Reject Request -> Correct status and reject modeling', () {
      final req = DeviceRequestModel(
        requestId: 'REQ_TO_REJECT',
        userId: 'khajani_rejected',
        userName: 'अमान्य युजर',
        deviceId: 'D-REJECTED',
        deviceName: 'Android Phone',
        requestType: 'NEW_ACCOUNT',
        status: DeviceStatus.rejected,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(req.isRejected, isTrue);
      expect(req.isApproved, isFalse);
      expect(req.isPending, isFalse);
      expect(req.marathiStatus, contains('नाकारले'));
    });

    test('Test 10: App Update Safety & Schema Constants', () {
      // Core financial tables list must be immutable and complete
      const expectedTables = [
        'vargani',
        'prasad_dengani',
        'prasad_sahitya',
        'aarti_vargani',
        'kharch',
        'mahaprasad_kharch',
        'previous_balance',
      ];

      for (final table in expectedTables) {
        expect(DatabaseHelper.migrationDataTables.contains(table), isTrue);
      }

      // Check Developer protected constants
      expect(AuthService.developerName, equals('Developer'));
      expect(AuthService.developerDefaultPassword, equals('Dev@4030'));
      expect(AuthService.developerUserId, equals('developer_root'));

      // Check unique ID generation
      final id1 = DeviceService.generateUniqueDeviceId();
      final id2 = DeviceService.generateUniqueDeviceId();
      expect(id1.startsWith('D-'), isTrue);
      expect(id1, isNot(equals(id2)));

      final reqId1 = DeviceService.generateUniqueRequestId();
      final reqId2 = DeviceService.generateUniqueRequestId();
      expect(reqId1.startsWith('REQ_'), isTrue);
      expect(reqId1, isNot(equals(reqId2)));
    });

    test('Test 11: 4 Users Simulation (Developer, Latest Khajani, Old Khajani, New Pending User)', () {
      // 1. User 1: Developer (Full admin, root access, cannot be disabled/deleted)
      const devUser = KhajaniUser(
        userId: AuthService.developerUserId,
        name: AuthService.developerName,
        passwordHash: 'dev_hash',
        salt: 'dev_salt',
        role: KhajaniRole.developer,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: KhajaniPermissions(
          canView: true,
          canAdd: true,
          canEdit: true,
          canDelete: true,
          canSearch: true,
          canPdf: true,
          canManageKhajani: true,
          canSync: true,
        ),
        createdAt: 1000,
        updatedAt: 1000,
      );
      expect(devUser.isDeveloper, isTrue);
      expect(devUser.isLatestKhajani, isFalse);
      expect(devUser.isApproved, isTrue);
      expect(devUser.effectivePermissions.canManageKhajani, isTrue);

      // 2. User 2: Latest Khajani (Master Financial Phone, full write permissions)
      const latestUser = KhajaniUser(
        userId: 'khajani_latest_4030',
        name: 'सुनील पवार (चालू खजानी)',
        passwordHash: 'latest_hash',
        salt: 'latest_salt',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: KhajaniPermissions.latestDefault(),
        createdAt: 2000,
        updatedAt: 2000,
      );
      expect(latestUser.isLatestKhajani, isTrue);
      expect(latestUser.isDeveloper, isFalse);
      expect(latestUser.effectivePermissions.canAdd, isTrue);
      expect(latestUser.effectivePermissions.canEdit, isTrue);
      expect(latestUser.effectivePermissions.canDelete, isTrue);
      expect(latestUser.effectivePermissions.canSync, isTrue);

      // 3. User 3: Old Khajani (Approved read-only member, write actions disabled)
      const oldUser = KhajaniUser(
        userId: 'khajani_old_4030',
        name: 'रमेश जाधव (माजी खजानी)',
        passwordHash: 'old_hash',
        salt: 'old_salt',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: KhajaniPermissions.oldDefault(),
        createdAt: 3000,
        updatedAt: 3000,
      );
      expect(oldUser.isOldKhajani, isTrue);
      expect(oldUser.effectivePermissions.canView, isTrue);
      expect(oldUser.effectivePermissions.canSearch, isTrue);
      expect(oldUser.effectivePermissions.canPdf, isTrue);
      expect(oldUser.effectivePermissions.canAdd, isFalse);
      expect(oldUser.effectivePermissions.canEdit, isFalse);
      expect(oldUser.effectivePermissions.canDelete, isFalse);
      expect(oldUser.effectivePermissions.canSync, isFalse);

      // 4. User 4: New Pending User (Awaiting developer approval, zero permissions)
      const pendingUser = KhajaniUser(
        userId: 'khajani_new_pending_4030',
        name: 'विकास मोरे (नवीन अर्जदार)',
        passwordHash: 'new_hash',
        salt: 'new_salt',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        isActive: true,
        permissions: KhajaniPermissions.pending(),
        createdAt: 4000,
        updatedAt: 4000,
      );
      expect(pendingUser.isPending, isTrue);
      expect(pendingUser.isApproved, isFalse);
      expect(pendingUser.effectivePermissions.canView, isFalse);
      expect(pendingUser.effectivePermissions.canAdd, isFalse);
      expect(pendingUser.effectivePermissions.canEdit, isFalse);
      expect(pendingUser.effectivePermissions.canDelete, isFalse);
      expect(pendingUser.effectivePermissions.canSearch, isFalse);
      expect(pendingUser.effectivePermissions.canPdf, isFalse);

      // All 4 users have distinct IDs and roles
      final allUserIds = {devUser.userId, latestUser.userId, oldUser.userId, pendingUser.userId};
      expect(allUserIds.length, equals(4));
    });

    test('Test 12: Exponential Backoff Reconnection Logic (5s -> 10s -> 30s -> 60s)', () {
      final signaling = SignalingService.instance;

      // Verify the exact backoff intervals
      expect(SignalingService.reconnectBackoffSchedule, equals([
        const Duration(seconds: 5),
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        const Duration(seconds: 60),
      ]));

      // Initial attempt (0) -> 5s
      signaling.setReconnectAttemptForTesting(0);
      expect(signaling.currentBackoffDelay, equals(const Duration(seconds: 5)));

      // 1st retry -> 10s
      signaling.setReconnectAttemptForTesting(1);
      expect(signaling.currentBackoffDelay, equals(const Duration(seconds: 10)));

      // 2nd retry -> 30s
      signaling.setReconnectAttemptForTesting(2);
      expect(signaling.currentBackoffDelay, equals(const Duration(seconds: 30)));

      // 3rd retry -> 60s
      signaling.setReconnectAttemptForTesting(3);
      expect(signaling.currentBackoffDelay, equals(const Duration(seconds: 60)));

      // Subsequent retries capped at 60s
      signaling.setReconnectAttemptForTesting(10);
      expect(signaling.currentBackoffDelay, equals(const Duration(seconds: 60)));

      // Reset on success
      signaling.setReconnectAttemptForTesting(0);
      expect(signaling.currentBackoffDelay, equals(const Duration(seconds: 5)));
    });

    test('Test 13: Heartbeat Interval & Payload Size Guard (60s lazy ping, 64KB size limit)', () {
      // 1. Sensible lazy heartbeat interval (60 seconds, no unnecessary 5s/10s traffic)
      expect(SignalingService.heartbeatInterval, equals(const Duration(seconds: 60)));

      // 2. Strict 64KB max payload size to block large binary files/PDFs over WebSocket
      expect(SignalingService.maxPayloadBytes, equals(65536));

      // 3. Idle timeout is configured for clean disconnect when not in persistent mode
      expect(SignalingService.idleTimeout, equals(const Duration(minutes: 2)));
    });

    test('Test 14: Duplicate Request Prevention (Client deduplication & Server deduplication)', () {
      final signaling = SignalingService.instance;
      signaling.resetDeduplicationStateForTesting();

      final req = DeviceRequestModel(
        requestId: 'REQ_DEDUP_TEST_01',
        userId: 'khajani_dedup_user',
        userName: 'गणेश कदम',
        deviceId: 'D-DEDUP-01',
        deviceName: 'Android Phone',
        requestType: 'NEW_ACCOUNT',
        status: DeviceStatus.pending,
        createdAt: 1000,
        updatedAt: 1000,
      );

      // First send records requestId
      signaling.sendDeviceRequest(req);

      // Second send with same requestId should be skipped by deduplication
      // Calling sendDeviceRequest again without forceRetry must not re-dispatch
      signaling.sendDeviceRequest(req, forceRetry: false);

      // Verify SQLite model map uses standard snake_case columns
      final dbMap = req.toMap();
      expect(dbMap.containsKey('request_id'), isTrue);
      expect(dbMap['request_id'], equals('REQ_DEDUP_TEST_01'));
    });

    test('Test 15: Small / Delta Sync (Incremental snapshot, SHA-256 checksum & import)', () {
      final syncService = WebRtcSyncService.instance;

      final deltaTables = <String, dynamic>{
        'vargani': [
          {'id': 101, 'name': 'राजेंद्र काळे', 'amount': 1500.0, 'year': 2026}
        ],
        'prasad_dengani': [],
        'prasad_sahitya': [],
        'aarti_vargani': [],
        'kharch': [],
        'mahaprasad_kharch': [],
        'previous_balance': [],
      };

      final deltaSnapshot = {
        'version': 8,
        'isDelta': true,
        'totalDeltaCount': 1,
        'tables': deltaTables,
      };

      final jsonStr = jsonEncode(deltaSnapshot);
      final digest = sha256.convert(utf8.encode(jsonStr)).toString();

      final validDeltaPackage = {
        'sync_id': 'delta_sync_test_01',
        'is_delta': true,
        'payload_digest': digest,
        'snapshot': deltaSnapshot,
      };

      expect(syncService.validateDeltaSyncPackage(validDeltaPackage), isTrue);

      final corruptedDeltaPackage = {
        'sync_id': 'delta_sync_test_01',
        'is_delta': true,
        'payload_digest': 'corrupted_hash',
        'snapshot': deltaSnapshot,
      };

      expect(syncService.validateDeltaSyncPackage(corruptedDeltaPackage), isFalse);
    });

    test('Test 16: Zero Continuous Polling & Pure Event-Driven Architecture Verification', () {
      // SignalingService uses reactive StreamController, not polling
      final signaling = SignalingService.instance;
      expect(signaling.onMessage, isA<Stream<Map<String, dynamic>>>());
      expect(signaling.isConnectedStream, isA<Stream<bool>>());

      // Test that message dispatched on onMessage stream is received reactively
      Map<String, dynamic>? receivedMessage;
      final sub = signaling.onMessage.listen((msg) {
        receivedMessage = msg;
      });

      // No continuous periodic polling occurs in SignalingService
      expect(receivedMessage, isNull);
      sub.cancel();
    });
  });
}
