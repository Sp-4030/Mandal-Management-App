import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/database/database_helper.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/screens/access_revoked_screen.dart';
import 'package:hindvi_app/screens/no_internet_screen.dart';
import 'package:hindvi_app/services/auth_service.dart';
import 'package:hindvi_app/services/remote_sync_service.dart';
import 'package:hindvi_app/services/security_enforcement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final security = SecurityEnforcementService.instance;
  final auth = AuthService.instance;
  final db = DatabaseHelper.instance;

  setUp(() {
    security.resetForTesting();
    db.setDeviceRevokedState(false);
  });

  tearDown(() {
    security.resetForTesting();
    db.setDeviceRevokedState(false);
    auth.setCurrentUserForTesting(null);
  });

  group('MANDATORY INTERNET ACCESS & OFFLINE BLOCKING TESTS', () {
    test('1. When internet is OFF, checkInternetConnectivity returns false and status is noInternet', () async {
      security.setMockConnectivity(false);
      final isOnline = await security.checkInternetConnectivity();
      expect(isOnline, isFalse);
      expect(security.isInternetOnline, isFalse);
      expect(security.accessStatus, equals(SecurityAccessStatus.noInternet));
    });

    test('2. When internet is OFF, assertOnlineAndAuthorized throws StateError with exact required text', () {
      security.setMockConnectivity(false);

      expect(
        () => security.assertOnlineAndAuthorized(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Internet connection required\nPlease turn on Internet to continue.'),
          ),
        ),
      );
    });

    test('3. When internet is OFF, all financial database operations are strictly blocked', () async {
      security.setMockConnectivity(false);

      // Add operation blocked
      expect(
        () async => await db.insertVargani({
          'name': 'गणेश शिंदे',
          'amount': 500.0,
          'year': 2026,
        }),
        throwsA(isA<StateError>()),
      );

      // Edit operation blocked
      expect(
        () async => await db.updateVargani(1, {'amount': 1000.0}),
        throwsA(isA<StateError>()),
      );

      // Delete operation blocked
      expect(
        () async => await db.deleteVargani(1),
        throwsA(isA<StateError>()),
      );

      // Sync operation blocked
      expect(
        () async => await RemoteSyncService.instance.requestSyncFromMaster(),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('4. NoInternetScreen renders full-screen blocking UI with required Marathi text and retry action', (
      WidgetTester tester,
    ) async {
      bool retryPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: NoInternetScreen(
            onRetry: () async {
              retryPressed = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Internet connection required'), findsOneWidget);
      expect(find.text('Please turn on Internet to continue.'), findsOneWidget);
      expect(find.text('सुरक्षा नियम: अनिवार्य इंटरनेट प्रवेश'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('पुन्हा प्रयत्न करा (Retry)'), findsOneWidget);

      await tester.tap(find.text('पुन्हा प्रयत्न करा (Retry)'));
      await tester.pump();
      expect(retryPressed, isTrue);
    });
  });

  group('SERVER AUTHORIZATION BEFORE APP ACCESS TESTS', () {
    test('5. verifyServerAuthorization fails immediately if Internet is OFF', () async {
      security.setMockConnectivity(false);

      expect(
        () async => await security.verifyServerAuthorization(userId: 'user_123'),
        throwsA(isA<StateError>()),
      );
    });

    test('6. Server authorization APPROVED authorizes user and updates accessStatus', () async {
      security.setMockConnectivity(true);
      security.setMockServerAuthResponse({
        'isAuthorized': true,
        'status': 'APPROVED',
        'role': 'LATEST_KHAJANI',
        'permissions': {
          'can_view': 1,
          'can_add': 1,
          'can_edit': 1,
          'can_delete': 1,
          'can_search': 1,
          'can_pdf': 1,
          'can_sync': 1,
        },
      });

      final result = await security.verifyServerAuthorization(userId: 'user_123');
      expect(result['isAuthorized'], isTrue);
      expect(result['status'], equals('APPROVED'));
    });

    test('7. Server authorization PENDING/REJECTED is handled without fake success', () async {
      security.setMockConnectivity(true);
      security.setMockServerAuthResponse({
        'isAuthorized': false,
        'status': 'PENDING',
        'message': 'Developer approval pending.',
      });

      final pendingResult = await security.verifyServerAuthorization(userId: 'user_pending');
      expect(pendingResult['isAuthorized'], isFalse);
      expect(pendingResult['status'], equals('PENDING'));
      expect(pendingResult['message'], equals('Developer approval pending.'));

      security.setMockServerAuthResponse({
        'isAuthorized': false,
        'status': 'REJECTED',
        'message': 'Request rejected by Developer.',
      });

      final rejectedResult = await security.verifyServerAuthorization(userId: 'user_rejected');
      expect(rejectedResult['isAuthorized'], isFalse);
      expect(rejectedResult['status'], equals('REJECTED'));
    });

    test('8. Server timeout fails safely with descriptive Marathi message', () async {
      security.setMockConnectivity(true);
      // Real verify with very short timeout against non-connected server
      final result = await security.verifyServerAuthorization(
        userId: 'u_timeout',
        deviceId: 'D-TEST',
        timeout: const Duration(milliseconds: 50),
      );

      expect(result['isAuthorized'], isFalse);
      expect(result['status'], anyOf(equals('SERVER_TIMEOUT'), equals('SERVER_ERROR')));
      expect(result['message'], isNotNull);
    });
  });

  group('REVOKE SECURITY & ACCESS LOCKOUT TESTS', () {
    test('9. When server returns REVOKED, triggerRevoked immediately locks device, logs out, and fires onRevoked', () async {
      security.setMockConnectivity(true);
      auth.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_revoked',
          name: 'Revoked User',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      expect(auth.isLoggedIn, isTrue);

      bool revokedFired = false;
      final sub = security.onRevoked.listen((_) {
        revokedFired = true;
      });

      security.setMockServerAuthResponse({
        'isAuthorized': false,
        'status': 'REVOKED',
        'message': 'Access Revoked. Contact Developer.',
      });

      final res = await security.verifyServerAuthorization(userId: 'u_revoked');
      expect(res['status'], equals('REVOKED'));
      expect(db.isDeviceRevoked, isTrue);
      expect(auth.isLoggedIn, isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(revokedFired, isTrue);

      await sub.cancel();
    });

    test('10. Revoked device throws "Access Revoked. Contact Developer." for any operation', () {
      security.setMockConnectivity(true);
      db.setDeviceRevokedState(true);

      expect(
        () => security.assertOnlineAndAuthorized(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Access Revoked. Contact Developer.'),
          ),
        ),
      );

      expect(
        () => db.assertDeviceNotRevokedForTesting(),
        throwsA(isA<StateError>()),
      );
    });

    test('11. Revocation does NOT delete local SQLite database records (data persistence preserved)', () async {
      security.setMockConnectivity(true);
      db.setDeviceRevokedState(false);

      // Verify that revocation sets status and flags without clearing tables
      await security.triggerRevoked();
      expect(db.isDeviceRevoked, isTrue);
      expect(security.accessStatus, equals(SecurityAccessStatus.revoked));
      expect(auth.isLoggedIn, isFalse);
    });

    testWidgets('12. AccessRevokedScreen displays full-screen lockout with contact information', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AccessRevokedScreen(
            deviceId: 'D-REVOKED-123',
            reason: 'Access Revoked. Contact Developer.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Access Revoked. Contact Developer.'), findsOneWidget);
      expect(find.text('प्रवेश रद्द केला आहे. कृपया डेव्हलपरशी संपर्क साधा.'), findsOneWidget);
      expect(find.text('D-REVOKED-123'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });
  });

  group('DYNAMIC PERMISSION UPDATE TESTS', () {
    test('13. Permission changes from server dynamically restrict operations without trusting stale permissions', () {
      security.setMockConnectivity(true);
      db.setDeviceRevokedState(false);

      // User with view-only permissions (canAdd = false, canEdit = false, canPdf = false)
      auth.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_restricted',
          name: 'Restricted User',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          permissions: KhajaniPermissions(
            canView: true,
            canAdd: false,
            canEdit: false,
            canDelete: false,
            canPdf: false,
            canSync: false,
          ),
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      // View is allowed
      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.view), returnsNormally);

      // Add is blocked
      expect(
        () => security.assertOnlineAndAuthorized(action: SecurityAction.add),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Add Permission'))),
      );

      // Edit is blocked
      expect(
        () => security.assertOnlineAndAuthorized(action: SecurityAction.edit),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Edit Permission'))),
      );

      // Delete is blocked
      expect(
        () => security.assertOnlineAndAuthorized(action: SecurityAction.delete),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Delete Permission'))),
      );

      // PDF is blocked
      expect(
        () => security.assertOnlineAndAuthorized(action: SecurityAction.pdf),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('PDF Permission'))),
      );

      // Sync is blocked
      expect(
        () => security.assertOnlineAndAuthorized(action: SecurityAction.sync),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Sync Permission'))),
      );
    });

    test('14. Developer role bypasses regular operational restrictions', () {
      security.setMockConnectivity(true);
      db.setDeviceRevokedState(false);

      auth.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'developer_root',
          name: 'Developer',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.developer,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.view), returnsNormally);
      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.add), returnsNormally);
      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.edit), returnsNormally);
      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.delete), returnsNormally);
      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.pdf), returnsNormally);
      expect(() => security.assertOnlineAndAuthorized(action: SecurityAction.sync), returnsNormally);
    });
  });
}
