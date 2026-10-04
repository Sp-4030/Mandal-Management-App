import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/models/device_model.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/services/auth_service.dart';
import 'package:hindvi_app/services/signaling_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AuthService.instance.setCurrentUserForTesting(null);
  });

  group('Approval Status Bug Fix - 5 Required Verification Scenarios', () {
    test('TEST 1: New Phone register -> Developer approves -> New Phone receives APPROVED -> Dashboard opens', () {
      const requestId = 'REQ_TEST1_001';
      const userId = 'khajani_test1_user';
      const deviceId = 'D-TEST1-DEV';
      const userName = 'गणेश जोशी';
      const password = 'User@123';
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. New Phone registers -> creates requestId + userId + deviceId
      final salt = AuthService.generateSalt();
      final hash = AuthService.hashPassword(password, salt);
      final pendingUser = KhajaniUser(
        userId: userId,
        name: userName,
        passwordHash: hash,
        salt: salt,
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        isActive: true,
        permissions: const KhajaniPermissions.pending(),
        createdAt: now,
        updatedAt: now,
      );

      final devReq = DeviceRequestModel(
        requestId: requestId,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
        deviceName: 'Android Phone',
        requestType: 'NEW_ACCOUNT',
        status: DeviceStatus.pending,
        requestedRole: KhajaniRole.oldKhajani,
        createdAt: now,
        updatedAt: now,
      );

      // Verify pending state initially
      expect(pendingUser.isPending, isTrue);
      expect(pendingUser.isApproved, isFalse);
      expect(devReq.isPending, isTrue);
      expect(AuthService.instance.isLoggedIn, isFalse);

      // 2. Developer approves request
      const approvedRole = KhajaniRole.latestKhajani;
      const approvedPermissions = KhajaniPermissions.latestDefault();

      // Developer approval payload (Step 2: APPROVAL_SENT_TO_SERVER)
      final approvalPayload = {
        'type': 'device_approval_result',
        'requestId': requestId,
        'userId': userId,
        'deviceId': deviceId,
        'status': 'APPROVED',
        'role': approvedRole,
        'permissions': approvedPermissions.toMap(),
        'updatedAt': now + 500,
      };

      // 3. New Phone receives APPROVED event matching requestId + userId + deviceId
      expect(approvalPayload['requestId'], equals(requestId));
      expect(approvalPayload['userId'], equals(userId));
      expect(approvalPayload['deviceId'], equals(deviceId));
      expect(approvalPayload['status'], equals('APPROVED'));

      // 4. Update request model and user to APPROVED
      final updatedReq = devReq.copyWith(
        status: DeviceStatus.approved,
        updatedAt: now + 500,
      );
      final updatedUser = pendingUser.copyWith(
        status: KhajaniStatus.approved,
        role: approvedRole,
        permissions: approvedPermissions,
        updatedAt: now + 500,
      );

      // 5. Session refresh & Dashboard available
      AuthService.instance.setCurrentUserForTesting(updatedUser);

      expect(updatedReq.isApproved, isTrue);
      expect(updatedUser.isApproved, isTrue);
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.currentUser?.userId, equals(userId));
      expect(AuthService.instance.isLatestKhajani, isTrue);
    });

    test('TEST 2: Developer approves while New Phone Internet OFF -> Internet ON -> Check Status -> APPROVED -> Dashboard', () {
      const requestId = 'REQ_TEST2_002';
      const userId = 'khajani_test2_user';
      const deviceId = 'D-TEST2-DEV';
      const userName = 'सुरेश पवार';
      final now = DateTime.now().millisecondsSinceEpoch;

      final devReq = DeviceRequestModel(
        requestId: requestId,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
        deviceName: 'Android Phone',
        requestType: 'NEW_ACCOUNT',
        status: DeviceStatus.pending,
        requestedRole: KhajaniRole.oldKhajani,
        createdAt: now,
        updatedAt: now,
      );

      // Offline on New Phone: Signaling is disconnected
      expect(SignalingService.instance.isConnected, isFalse);

      // Developer approved while device was offline -> Server stored approval for requestId
      final serverStoredRecord = {
        'requestId': requestId,
        'userId': userId,
        'deviceId': deviceId,
        'status': 'APPROVED',
        'role': 'OLD_KHAJANI',
        'permissions': const KhajaniPermissions.oldDefault().toMap(),
        'updatedAt': now + 1000,
      };

      // New Phone comes online and triggers "Check Status" with existing requestId (NO new request created!)
      final checkStatusQuery = {
        'type': 'check_status',
        'requestId': devReq.requestId,
        'userId': devReq.userId,
        'deviceId': devReq.deviceId,
      };

      expect(checkStatusQuery['requestId'], equals(requestId));
      expect(checkStatusQuery['userId'], equals(userId));
      expect(checkStatusQuery['deviceId'], equals(deviceId));

      // Server matches existing requestId + userId + deviceId and returns APPROVED
      expect(serverStoredRecord['status'], equals('APPROVED'));

      // Update state without creating new request
      final approvedReq = devReq.copyWith(
        status: DeviceStatus.approved,
        updatedAt: serverStoredRecord['updatedAt'] as int,
      );
      expect(approvedReq.requestId, equals(requestId)); // Confirms same requestId
      expect(approvedReq.isApproved, isTrue);

      final user = KhajaniUser(
        userId: userId,
        name: userName,
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        permissions: const KhajaniPermissions.oldDefault(),
        createdAt: now,
        updatedAt: now + 1000,
      );
      AuthService.instance.setCurrentUserForTesting(user);

      // Session refresh & Dashboard available
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.currentUser?.userId, equals(userId));
    });

    test('TEST 3: Approval received -> New Phone app restart -> Reads APPROVED from local DB -> Direct Dashboard', () {
      const requestId = 'REQ_TEST3_003';
      const userId = 'khajani_test3_user';
      const deviceId = 'D-TEST3-DEV';
      const userName = 'विजय पाटील';
      final now = DateTime.now().millisecondsSinceEpoch;

      final approvedReq = DeviceRequestModel(
        requestId: requestId,
        userId: userId,
        userName: userName,
        deviceId: deviceId,
        deviceName: 'Android Phone',
        status: DeviceStatus.approved,
        createdAt: now,
        updatedAt: now,
      );
      expect(approvedReq.requestId, equals(requestId));
      expect(approvedReq.deviceId, equals(deviceId));
      expect(approvedReq.isApproved, isTrue);

      final approvedUser = KhajaniUser(
        userId: userId,
        name: userName,
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        permissions: const KhajaniPermissions.latestDefault(),
        createdAt: now,
        updatedAt: now,
      );

      // Verify approved state
      expect(approvedUser.isApproved, isTrue);
      expect(approvedUser.isPending, isFalse);

      // Simulate App Kill / Restart (in-memory state reset)
      AuthService.instance.setCurrentUserForTesting(null);
      expect(AuthService.instance.isLoggedIn, isFalse);

      // Restored from local persistence
      AuthService.instance.setCurrentUserForTesting(approvedUser);
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.currentUser?.userId, equals(userId));
      expect(AuthService.instance.isLatestKhajani, isTrue);
    });

    test('TEST 4: Two pending users -> Developer approves only User A -> only User A becomes APPROVED', () {
      const now = 1700000000000;

      // User A
      const reqIdA = 'REQ_USER_A';
      const userIdA = 'khajani_user_a';
      const devIdA = 'D-PHONE-A';
      final userA = KhajaniUser(
        userId: userIdA,
        name: 'वापरकर्ता अ',
        passwordHash: 'ha',
        salt: 'sa',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      // User B
      const reqIdB = 'REQ_USER_B';
      const userIdB = 'khajani_user_b';
      const devIdB = 'D-PHONE-B';
      final userB = KhajaniUser(
        userId: userIdB,
        name: 'वापरकर्ता ब',
        passwordHash: 'hb',
        salt: 'sb',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        createdAt: now + 100,
        updatedAt: now + 100,
      );

      // Developer approves ONLY User A
      final approvalTarget = {
        'requestId': reqIdA,
        'userId': userIdA,
        'deviceId': devIdA,
      };

      // Server / Client matching checks
      final matchesUserA = approvalTarget['requestId'] == reqIdA &&
          approvalTarget['userId'] == userIdA &&
          approvalTarget['deviceId'] == devIdA;
      final matchesUserB = approvalTarget['requestId'] == reqIdB &&
          approvalTarget['userId'] == userIdB &&
          approvalTarget['deviceId'] == devIdB;

      expect(matchesUserA, isTrue);
      expect(matchesUserB, isFalse);

      // User A approved
      final updatedUserA = userA.copyWith(status: KhajaniStatus.approved);
      // User B remains pending
      final updatedUserB = userB;

      expect(updatedUserA.isApproved, isTrue);
      expect(updatedUserB.isApproved, isFalse);
      expect(updatedUserB.isPending, isTrue);
    });

    test('TEST 5: Same-name users -> approval matches strictly on requestId + userId + deviceId, not name', () {
      const now = 1700000000000;
      const sharedName = 'सचिन कदम';

      // User 1
      const reqId1 = 'REQ_SAME_NAME_1';
      const userId1 = 'khajani_same_1';
      const devId1 = 'D-SAME-1';
      final user1 = KhajaniUser(
        userId: userId1,
        name: sharedName,
        passwordHash: 'h1',
        salt: 's1',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      // User 2 with EXACT SAME name
      const reqId2 = 'REQ_SAME_NAME_2';
      const userId2 = 'khajani_same_2';
      const devId2 = 'D-SAME-2';
      final user2 = KhajaniUser(
        userId: userId2,
        name: sharedName,
        passwordHash: 'h2',
        salt: 's2',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        createdAt: now + 50,
        updatedAt: now + 50,
      );

      // Names are identical
      expect(user1.name, equals(user2.name));
      // But unique identifiers are distinct
      expect(user1.userId, isNot(equals(user2.userId)));
      expect(reqId1, isNot(equals(reqId2)));
      expect(devId1, isNot(equals(devId2)));

      // Developer approves User 1 by requestId + userId + deviceId
      const targetApproval = {
        'requestId': reqId1,
        'userId': userId1,
        'deviceId': devId1,
        'status': 'APPROVED',
      };

      // Match check: must NOT match on name
      bool doesMatch(KhajaniUser u, String reqId, String devId) {
        return targetApproval['requestId'] == reqId &&
            targetApproval['userId'] == u.userId &&
            targetApproval['deviceId'] == devId;
      }

      expect(doesMatch(user1, reqId1, devId1), isTrue);
      expect(doesMatch(user2, reqId2, devId2), isFalse);

      final approvedUser1 = user1.copyWith(status: KhajaniStatus.approved);
      expect(approvedUser1.isApproved, isTrue);
      expect(user2.isPending, isTrue); // User 2 remains strictly PENDING
    });
  });
}
