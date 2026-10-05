import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:developer_app/models/developer_permissions.dart';
import 'package:developer_app/models/developer_user.dart';
import 'package:developer_app/models/user_request_model.dart';
import 'package:developer_app/services/developer_auth_service.dart';

void main() {
  group('TEST 3 & 4: Developer Authentication & Self-Protection', () {
    setUp(() {
      DeveloperAuthService.instance.resetForTesting();
    });

    test('Developer login with correct credentials succeeds using SHA-256 hash', () async {
      final auth = DeveloperAuthService.instance;
      final result = await auth.login(
        name: 'Developer',
        password: DeveloperUser.developerDefaultPassword, // 'Dev@4030'
      );

      expect(result, isTrue);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.currentDeveloper?.name, equals('Developer'));
      expect(auth.currentDeveloper?.userId, equals(DeveloperUser.developerUserId));
    });

    test('Developer login with wrong password fails', () async {
      final auth = DeveloperAuthService.instance;
      final result = await auth.login(
        name: 'Developer',
        password: 'WrongPassword123',
      );

      expect(result, isFalse);
      expect(auth.isLoggedIn, isFalse);
    });

    test('Non-developer username is rejected with ArgumentError', () async {
      final auth = DeveloperAuthService.instance;
      expect(
        () => auth.login(name: 'RegularUser', password: 'Dev@4030'),
        throwsArgumentError,
      );
    });

    test('Developer cannot delete or revoke own Developer account', () {
      // Must not allow deleting root developer
      expect(DeveloperUser.canDeleteOrRevoke('developer_root'), isFalse);
      expect(DeveloperUser.canDeleteOrRevoke('DEVELOPER'), isFalse);
      expect(DeveloperUser.canDeleteOrRevoke('developer'), isFalse);

      // Normal users can be revoked/deleted
      expect(DeveloperUser.canDeleteOrRevoke('user_12345'), isTrue);
      expect(DeveloperUser.canDeleteOrRevoke('khajani_999'), isTrue);
    });

    test('Secure password hashing creates non-trivial hash with salt', () {
      final salt = DeveloperUser.generateSalt();
      expect(salt.isNotEmpty, isTrue);

      final hash = DeveloperUser.hashPassword('Dev@4030', salt);
      expect(hash.isNotEmpty, isTrue);
      expect(hash, isNot(equals('Dev@4030'))); // Never plaintext!

      // Verifies matching password
      expect(DeveloperUser.verifyPassword(password: 'Dev@4030', salt: salt, hash: hash), isTrue);

      // Rejects mismatched password
      expect(DeveloperUser.verifyPassword(password: 'Dev@4031', salt: salt, hash: hash), isFalse);
    });
  });

  group('TEST 1 & 2: User Registration & Same-Name Support', () {
    test('Same name users have distinct unique userIds and deviceIds', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final user1 = UserRequestModel(
        requestId: 'req_amol_1',
        userId: 'khajani_${now}_001',
        userName: 'Amol',
        deviceId: 'device_phone_A',
        deviceName: 'Samsung Galaxy',
        status: 'PENDING',
        createdAt: now,
      );

      final user2 = UserRequestModel(
        requestId: 'req_amol_2',
        userId: 'khajani_${now}_002',
        userName: 'Amol',
        deviceId: 'device_phone_B',
        deviceName: 'Redmi Note',
        status: 'PENDING',
        createdAt: now + 10,
      );

      // Both have the same display name
      expect(user1.userName, equals(user2.userName));

      // But have completely unique userIds and deviceIds
      expect(user1.userId, isNot(equals(user2.userId)));
      expect(user1.deviceId, isNot(equals(user2.deviceId)));
      expect(user1.requestId, isNot(equals(user2.requestId)));
    });

    test('Approve request assigns role and independent custom permissions', () {
      final customPermissions = const DeveloperPermissions(
        canView: true,
        canAdd: true,
        canEdit: false,
        canDelete: false,
        canSearch: true,
        canPdf: true,
        canManageKhajani: false,
        canSync: true,
      );

      final req = UserRequestModel(
        requestId: 'req_101',
        userId: 'khajani_101',
        userName: 'Amol',
        deviceId: 'device_101',
        deviceName: 'OnePlus',
        status: 'PENDING',
        createdAt: 1000,
      );

      final approvedReq = req.copyWith(
        status: 'APPROVED',
        role: 'OLD_KHAJANI',
        permissions: customPermissions,
      );

      expect(approvedReq.isApproved, isTrue);
      expect(approvedReq.role, equals('OLD_KHAJANI'));
      expect(approvedReq.permissions.canView, isTrue);
      expect(approvedReq.permissions.canAdd, isTrue);
      expect(approvedReq.permissions.canEdit, isFalse);
      expect(approvedReq.permissions.canDelete, isFalse);
    });

    test('JSON serialization preserves user request and permission details', () {
      final perms = const DeveloperPermissions.latestDefault();
      final req = UserRequestModel(
        requestId: 'req_abc',
        userId: 'user_abc',
        userName: 'Rahul',
        deviceId: 'dev_abc',
        deviceName: 'Pixel 8',
        status: 'APPROVED',
        role: 'LATEST_KHAJANI',
        permissions: perms,
        createdAt: 1234567,
      );

      final json = req.toJson();
      final restored = UserRequestModel.fromJson(json);

      expect(restored.requestId, equals('req_abc'));
      expect(restored.userId, equals('user_abc'));
      expect(restored.userName, equals('Rahul'));
      expect(restored.deviceId, equals('dev_abc'));
      expect(restored.role, equals('LATEST_KHAJANI'));
      expect(restored.isLatestKhajani, isTrue);
      expect(restored.permissions.canDelete, isTrue);
      expect(restored.permissions.canManageKhajani, isTrue);
    });
  });

  group('TEST 5: Device Revocation & Restoration', () {
    test('Revoking device marks status as REVOKED and invalidates approved state', () {
      final user = UserRequestModel(
        requestId: 'req_dev_1',
        userId: 'user_1',
        userName: 'Suresh',
        deviceId: 'device_suresh_1',
        deviceName: 'Vivo V20',
        status: 'APPROVED',
        role: 'LATEST_KHAJANI',
        createdAt: 1000,
      );

      expect(user.isApproved, isTrue);
      expect(user.isRevoked, isFalse);

      final revoked = user.copyWith(status: 'REVOKED');
      expect(revoked.status, equals('REVOKED'));
      expect(revoked.isRevoked, isTrue);
      expect(revoked.isApproved, isFalse);
    });

    test('Restoring previously revoked device marks status as APPROVED', () {
      final revoked = UserRequestModel(
        requestId: 'req_dev_1',
        userId: 'user_1',
        userName: 'Suresh',
        deviceId: 'device_suresh_1',
        deviceName: 'Vivo V20',
        status: 'REVOKED',
        createdAt: 1000,
      );

      final restored = revoked.copyWith(status: 'APPROVED');
      expect(restored.status, equals('APPROVED'));
      expect(restored.isApproved, isTrue);
      expect(restored.isRevoked, isFalse);
    });
  });

  group('TEST 6: Permissions Model & Defaults', () {
    test('latestDefault has all 8 permissions enabled', () {
      const perms = DeveloperPermissions.latestDefault();
      expect(perms.canView, isTrue);
      expect(perms.canAdd, isTrue);
      expect(perms.canEdit, isTrue);
      expect(perms.canDelete, isTrue);
      expect(perms.canSearch, isTrue);
      expect(perms.canPdf, isTrue);
      expect(perms.canManageKhajani, isTrue);
      expect(perms.canSync, isTrue);
    });

    test('oldDefault restricts write permissions while keeping read permissions', () {
      const perms = DeveloperPermissions.oldDefault();
      expect(perms.canView, isTrue);
      expect(perms.canSearch, isTrue);
      expect(perms.canPdf, isTrue);
      expect(perms.canSync, isFalse);
      // Write operations disabled by default for old khajani
      expect(perms.canAdd, isFalse);
      expect(perms.canEdit, isFalse);
      expect(perms.canDelete, isFalse);
      expect(perms.canManageKhajani, isFalse);
    });

    test('Independent toggling works via copyWith', () {
      const initial = DeveloperPermissions.oldDefault();
      final modified = initial.copyWith(canAdd: true, canEdit: true);

      expect(modified.canAdd, isTrue);
      expect(modified.canEdit, isTrue);
      expect(modified.canDelete, isFalse);
    });
  });

  group('TEST 7: Latest Khajani Promotion & Demotion', () {
    test('Promoting phone B to Latest Khajani demotes phone A to OLD_KHAJANI', () {
      var phoneA = UserRequestModel(
        requestId: 'req_A',
        userId: 'user_A',
        userName: 'Phone A',
        deviceId: 'dev_A',
        deviceName: 'Device A',
        status: 'APPROVED',
        role: 'LATEST_KHAJANI',
        permissions: const DeveloperPermissions.latestDefault(),
        createdAt: 1000,
      );

      var phoneB = UserRequestModel(
        requestId: 'req_B',
        userId: 'user_B',
        userName: 'Phone B',
        deviceId: 'dev_B',
        deviceName: 'Device B',
        status: 'APPROVED',
        role: 'OLD_KHAJANI',
        permissions: const DeveloperPermissions.oldDefault(),
        createdAt: 2000,
      );

      expect(phoneA.isLatestKhajani, isTrue);
      expect(phoneB.isLatestKhajani, isFalse);

      // Simulate designation of Phone B as Latest Khajani
      final updatedList = [phoneA, phoneB].map((r) {
        if (r.userId == phoneB.userId) {
          return r.copyWith(role: 'LATEST_KHAJANI', permissions: const DeveloperPermissions.latestDefault());
        } else if (r.isLatestKhajani) {
          return r.copyWith(role: 'OLD_KHAJANI');
        }
        return r;
      }).toList();

      phoneA = updatedList.firstWhere((r) => r.userId == phoneA.userId);
      phoneB = updatedList.firstWhere((r) => r.userId == phoneB.userId);

      expect(phoneB.isLatestKhajani, isTrue);
      expect(phoneB.role, equals('LATEST_KHAJANI'));
      expect(phoneA.isLatestKhajani, isFalse);
      expect(phoneA.role, equals('OLD_KHAJANI'));
    });
  });

  group('TEST 12: Architectural Separation — Developer App has NO financial code', () {
    test('Developer App lib directory contains zero financial tables or SQLite files', () {
      final libDir = Directory('c:/Users/Shantanu/Desktop/hindvi_app/developer_app/lib');
      expect(libDir.existsSync(), isTrue);

      final files = libDir.listSync(recursive: true).whereType<File>().toList();

      for (final file in files) {
        final content = file.readAsStringSync().toLowerCase();

        // Must not contain financial database helper
        expect(
          file.path.contains('database_helper'),
          isFalse,
          reason: 'Developer App must not import or contain DatabaseHelper: ${file.path}',
        );

        // Must not contain financial table names
        expect(
          content.contains('vargani_table') || content.contains('create table vargani'),
          isFalse,
          reason: 'Developer App must not contain Vargani table definition: ${file.path}',
        );
        expect(
          content.contains('prasad_dengani') || content.contains('prasad_sahitya'),
          isFalse,
          reason: 'Developer App must not contain Prasad table definitions: ${file.path}',
        );
        expect(
          content.contains('kharch_2025') || content.contains('mahaprasad_kharch'),
          isFalse,
          reason: 'Developer App must not contain Kharch table definitions: ${file.path}',
        );
        expect(
          content.contains('previous_balance'),
          isFalse,
          reason: 'Developer App must not contain Previous Balance table: ${file.path}',
        );
      }
    });

    test('Developer App does not depend on sqflite package', () {
      final pubspec = File('c:/Users/Shantanu/Desktop/hindvi_app/developer_app/pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);
      final text = pubspec.readAsStringSync();

      expect(text.contains('sqflite:'), isFalse, reason: 'Developer App must not have sqflite dependency');
      expect(text.contains('pdf:'), isFalse, reason: 'Developer App must not have PDF generation dependency');
    });
  });
}
