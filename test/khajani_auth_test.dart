import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/database/database_helper.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/screens/kharch_screen.dart';
import 'package:hindvi_app/screens/login_screen.dart';
import 'package:hindvi_app/screens/mahaprasad_kharch_screen.dart';
import 'package:hindvi_app/screens/prasad_dengani_screen.dart';
import 'package:hindvi_app/screens/settings_screen.dart';
import 'package:hindvi_app/screens/vargani_screen.dart';
import 'package:hindvi_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Khajani Role & User Model Unit Tests', () {
    test('KhajaniRole correctly evaluates latest, old, and developer', () {
      expect(KhajaniRole.isDeveloper('DEVELOPER'), isTrue);
      expect(KhajaniRole.isDeveloper('LATEST_KHAJANI'), isFalse);
      expect(KhajaniRole.isDeveloper('OLD_KHAJANI'), isFalse);

      expect(KhajaniRole.isLatest('LATEST_KHAJANI'), isTrue);
      expect(KhajaniRole.isLatest('OLD_KHAJANI'), isFalse);
      expect(KhajaniRole.isOld('OLD_KHAJANI'), isTrue);
      expect(KhajaniRole.isOld('LATEST_KHAJANI'), isFalse);

      expect(KhajaniRole.marathiTitle('DEVELOPER'), equals('डेव्हलपर (Admin)'));
      expect(KhajaniRole.marathiTitle('LATEST_KHAJANI'), equals('चालू खजानी'));
      expect(KhajaniRole.marathiTitle('OLD_KHAJANI'), equals('माजी खजानी'));
    });

    test('KhajaniUser model correctly computes permissions and serializes', () {
      const latestUser = KhajaniUser(
        userId: 'u_123',
        name: 'अमोल पाटील',
        passwordHash: 'hash123',
        salt: 'salt123',
        role: KhajaniRole.latestKhajani,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(latestUser.isLatestKhajani, isTrue);
      expect(latestUser.isOldKhajani, isFalse);
      expect(latestUser.isDeveloper, isFalse);
      expect(latestUser.canModify, isTrue);
      expect(latestUser.marathiRole, equals('चालू खजानी'));

      final map = latestUser.toMap();
      expect(map['user_id'], equals('u_123'));
      expect(map['role'], equals('LATEST_KHAJANI'));
      expect(map['is_active'], equals(1));
      expect(map['can_add'], equals(1));
      expect(map['can_edit'], equals(1));

      final fromMap = KhajaniUser.fromMap(map);
      expect(fromMap.userId, equals('u_123'));
      expect(fromMap.name, equals('अमोल पाटील'));
      expect(fromMap.canModify, isTrue);

      final oldUser = latestUser.copyWith(role: KhajaniRole.oldKhajani);
      expect(oldUser.isOldKhajani, isTrue);
      expect(oldUser.isLatestKhajani, isFalse);
      expect(oldUser.canModify, isFalse);
      expect(oldUser.marathiRole, equals('माजी खजानी'));
      expect(oldUser.effectivePermissions.canAdd, isFalse);
      expect(oldUser.effectivePermissions.canEdit, isFalse);
      expect(oldUser.effectivePermissions.canDelete, isFalse);
      expect(oldUser.effectivePermissions.canView, isTrue);
      expect(oldUser.effectivePermissions.canSearch, isTrue);
      expect(oldUser.effectivePermissions.canPdf, isTrue);
    });

    test('KhajaniPermissions models default, developer, and custom values correctly', () {
      const devPerms = KhajaniPermissions.developer();
      expect(devPerms.canView, isTrue);
      expect(devPerms.canAdd, isTrue);
      expect(devPerms.canEdit, isTrue);
      expect(devPerms.canDelete, isTrue);
      expect(devPerms.canSearch, isTrue);
      expect(devPerms.canPdf, isTrue);
      expect(devPerms.canManageKhajani, isTrue);
      expect(devPerms.canSync, isTrue);

      const oldPerms = KhajaniPermissions.oldDefault();
      expect(oldPerms.canView, isTrue);
      expect(oldPerms.canAdd, isFalse);
      expect(oldPerms.canEdit, isFalse);
      expect(oldPerms.canDelete, isFalse);
      expect(oldPerms.canSearch, isTrue);
      expect(oldPerms.canPdf, isTrue);
      expect(oldPerms.canManageKhajani, isFalse);
      expect(oldPerms.canSync, isFalse);

      final custom = oldPerms.copyWith(canAdd: true, canPdf: false);
      expect(custom.canAdd, isTrue);
      expect(custom.canPdf, isFalse);
      expect(custom.canEdit, isFalse);

      final map = custom.toMap();
      expect(map['can_add'], equals(1));
      expect(map['can_pdf'], equals(0));
      expect(map['can_edit'], equals(0));

      final roundTrip = KhajaniPermissions.fromMap(map, role: KhajaniRole.oldKhajani);
      expect(roundTrip.canAdd, isTrue);
      expect(roundTrip.canPdf, isFalse);
      expect(roundTrip.canEdit, isFalse);
    });
  });

  group('AuthService Password & Hash Unit Tests', () {
    test('Salts are randomly generated and distinct', () {
      final salt1 = AuthService.generateSalt();
      final salt2 = AuthService.generateSalt();
      expect(salt1.isNotEmpty, isTrue);
      expect(salt2.isNotEmpty, isTrue);
      expect(salt1, isNot(equals(salt2)));
    });

    test('Password hashing produces consistent SHA-256 and does not match plain password', () {
      const pass = 'mandalsecret123';
      const salt = 'random_salt_abc';

      final hash1 = AuthService.hashPassword(pass, salt);
      final hash2 = AuthService.hashPassword(pass, salt);

      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals(pass)));
      expect(hash1.length, equals(64)); // SHA-256 hex length

      expect(
        AuthService.verifyPassword(
          password: pass,
          salt: salt,
          hash: hash1,
        ),
        isTrue,
      );

      expect(
        AuthService.verifyPassword(
          password: 'wrong_password',
          salt: salt,
          hash: hash1,
        ),
        isFalse,
      );
    });

    test('Developer default credentials match specification and hash securely', () {
      expect(AuthService.developerName, equals('Developer'));
      expect(AuthService.developerDefaultPassword, equals('Dev@4030'));
      expect(AuthService.developerUserId, equals('developer_root'));

      final salt = AuthService.generateSalt();
      final hash = AuthService.hashPassword(AuthService.developerDefaultPassword, salt);
      expect(
        AuthService.verifyPassword(
          password: 'Dev@4030',
          salt: salt,
          hash: hash,
        ),
        isTrue,
      );
      expect(
        AuthService.verifyPassword(
          password: 'dev@4030', // case sensitive password
          salt: salt,
          hash: hash,
        ),
        isFalse,
      );
    });

    test('Unique user IDs are unique and prefixed with khajani_', () {
      final id1 = AuthService.generateUniqueUserId();
      final id2 = AuthService.generateUniqueUserId();

      expect(id1.startsWith('khajani_'), isTrue);
      expect(id2.startsWith('khajani_'), isTrue);
      expect(id1, isNot(equals(id2)));
    });
  });

  group('Developer Admin Protection & Rules Tests', () {
    tearDown(() {
      AuthService.instance.setCurrentUserForTesting(null);
    });

    test('Non-developer cannot perform admin management operations', () async {
      const regularUser = KhajaniUser(
        userId: 'khajani_reg_1',
        name: 'संतोष जाधव',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(regularUser);

      expect(
        () async => await AuthService.instance.createKhajaniByDeveloper(
          name: 'नवीन खजानी',
          password: 'pass',
          role: KhajaniRole.oldKhajani,
          permissions: const KhajaniPermissions.oldDefault(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await AuthService.instance.updateKhajaniRole(
          userId: 'u_target',
          newRole: KhajaniRole.oldKhajani,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await AuthService.instance.updateKhajaniPermissions(
          userId: 'u_target',
          permissions: const KhajaniPermissions(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await AuthService.instance.toggleKhajaniStatus(
          userId: 'u_target',
          isActive: false,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await AuthService.instance.deleteKhajani(userId: 'u_target'),
        throwsA(isA<StateError>()),
      );
    });

    test('Developer account cannot be deactivated, deleted, or role-changed', () async {
      const devUser = KhajaniUser(
        userId: AuthService.developerUserId,
        name: AuthService.developerName,
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.developer,
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(devUser);

      expect(
        () async => await AuthService.instance.deleteKhajani(
          userId: AuthService.developerUserId,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await AuthService.instance.toggleKhajaniStatus(
          userId: AuthService.developerUserId,
          isActive: false,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await AuthService.instance.updateKhajaniRole(
          userId: AuthService.developerUserId,
          newRole: KhajaniRole.oldKhajani,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Developer has full permissions unconditionally', () {
      const devUser = KhajaniUser(
        userId: AuthService.developerUserId,
        name: AuthService.developerName,
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.developer,
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(devUser);

      expect(AuthService.instance.isDeveloper, isTrue);
      expect(AuthService.instance.canView, isTrue);
      expect(AuthService.instance.canAdd, isTrue);
      expect(AuthService.instance.canEdit, isTrue);
      expect(AuthService.instance.canDelete, isTrue);
      expect(AuthService.instance.canSearch, isTrue);
      expect(AuthService.instance.canPdf, isTrue);
      expect(AuthService.instance.canManageKhajani, isTrue);
      expect(AuthService.instance.canSync, isTrue);
      expect(AuthService.instance.canModify, isTrue);
    });
  });

  group('DatabaseHelper Repository-Level Granular Permission Tests', () {
    tearDown(() {
      AuthService.instance.setCurrentUserForTesting(null);
    });

    test('User with canAdd=false cannot insert records', () async {
      const user = KhajaniUser(
        userId: 'u_no_add',
        name: 'अमोल',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        permissions: KhajaniPermissions(canAdd: false),
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(user);
      expect(AuthService.instance.canAdd, isFalse);

      final db = DatabaseHelper.instance;
      expect(
        () async => await db.insertVargani({'name': 'चाचणी', 'amount': 100, 'year': 2026}),
        throwsA(isA<StateError>()),
      );
      expect(
        () async => await db.insertPrasadDengani({'name': 'चाचणी', 'amount': 100, 'year': 2026}),
        throwsA(isA<StateError>()),
      );
    });

    test('User with canEdit=false cannot update records', () async {
      const user = KhajaniUser(
        userId: 'u_no_edit',
        name: 'अमोल',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        permissions: KhajaniPermissions(canEdit: false),
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(user);
      expect(AuthService.instance.canEdit, isFalse);

      final db = DatabaseHelper.instance;
      expect(
        () async => await db.updateVargani(1, {'name': 'चाचणी', 'amount': 200, 'year': 2026}),
        throwsA(isA<StateError>()),
      );
      expect(
        () async => await db.savePreviousBalance(2026, 5000),
        throwsA(isA<StateError>()),
      );
    });

    test('User with canDelete=false cannot delete records', () async {
      const user = KhajaniUser(
        userId: 'u_no_del',
        name: 'अमोल',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        permissions: KhajaniPermissions(canDelete: false),
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(user);
      expect(AuthService.instance.canDelete, isFalse);

      final db = DatabaseHelper.instance;
      expect(
        () async => await db.deleteVargani(1),
        throwsA(isA<StateError>()),
      );
      expect(
        () async => await db.deleteKharch(1),
        throwsA(isA<StateError>()),
      );
    });

    test('User with canSync=false cannot perform restore operations', () async {
      const user = KhajaniUser(
        userId: 'u_no_sync',
        name: 'अमोल',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        permissions: KhajaniPermissions(canSync: false),
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(user);
      expect(AuthService.instance.canSync, isFalse);

      final db = DatabaseHelper.instance;
      expect(
        () async => await db.restoreMigrationRecovery(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('UI Read-Only Enforcement Widget Tests for OLD_KHAJANI', () {
    tearDown(() {
      AuthService.instance.setCurrentUserForTesting(null);
    });

    testWidgets('VarganiScreen hides Add FAB and Save button for OLD_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_old',
          name: 'माजी खजानी दादा',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.oldKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: VarganiScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner is visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsOneWidget);

      // FAB 'नवीन वर्गणी' must NOT be present
      expect(find.text('नवीन वर्गणी'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);

      // Save previous balance button must NOT be present
      expect(find.text('जतन'), findsNothing);
    });

    testWidgets('PrasadDenganiScreen hides Add buttons for OLD_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_old',
          name: 'माजी खजानी दादा',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.oldKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PrasadDenganiScreen(initialLoading: false),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner is visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsOneWidget);

      // 'नवीन नोंद' buttons should NOT be present
      expect(find.text('नवीन नोंद'), findsNothing);
    });

    testWidgets('KharchScreen hides Add button for OLD_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_old',
          name: 'माजी खजानी दादा',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.oldKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: KharchScreen(initialLoading: false),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner is visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsOneWidget);

      // 'नवीन नोंद' button must NOT be present
      expect(find.text('नवीन नोंद'), findsNothing);
    });

    testWidgets('MahaprasadKharchScreen hides FAB for OLD_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_old',
          name: 'माजी खजानी दादा',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.oldKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MahaprasadKharchScreen(initialLoading: false),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner is visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsOneWidget);

      // FAB must NOT be present
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('नवीन खर्च'), findsNothing);
    });
  });

  group('UI Write Permission Tests for LATEST_KHAJANI', () {
    tearDown(() {
      AuthService.instance.setCurrentUserForTesting(null);
    });

    testWidgets('VarganiScreen displays Add FAB for LATEST_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_latest',
          name: 'चालू खजानी भाऊ',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: VarganiScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner must NOT be visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsNothing);

      // FAB 'नवीन वर्गणी' MUST be present
      expect(find.text('नवीन वर्गणी'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Save previous balance button MUST be present
      expect(find.text('जतन'), findsOneWidget);
    });

    testWidgets('PrasadDenganiScreen displays Add buttons for LATEST_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_latest',
          name: 'चालू खजानी भाऊ',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PrasadDenganiScreen(initialLoading: false),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner must NOT be visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsNothing);

      // 'नवीन नोंद' buttons should be present (3 sections)
      expect(find.text('नवीन नोंद'), findsNWidgets(3));
    });

    testWidgets('KharchScreen displays Add button for LATEST_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_latest',
          name: 'चालू खजानी भाऊ',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: KharchScreen(initialLoading: false),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner must NOT be visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsNothing);

      // 'नवीन नोंद' button must be present
      expect(find.text('नवीन नोंद'), findsOneWidget);
    });

    testWidgets('MahaprasadKharchScreen displays FAB for LATEST_KHAJANI', (
      WidgetTester tester,
    ) async {
      AuthService.instance.setCurrentUserForTesting(
        const KhajaniUser(
          userId: 'u_latest',
          name: 'चालू खजानी भाऊ',
          passwordHash: 'h',
          salt: 's',
          role: KhajaniRole.latestKhajani,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MahaprasadKharchScreen(initialLoading: false),
        ),
      );
      await tester.pumpAndSettle();

      // Read-only banner must NOT be visible
      expect(find.textContaining('माजी खजानी (केवळ वाचन मोड)'), findsNothing);

      // FAB must be present
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('नवीन खर्च'), findsOneWidget);
    });
  });

  group('Login & First Setup UI Tests', () {
    testWidgets('KhajaniLoginScreen in first setup mode renders first khajani fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KhajaniLoginScreen(isFirstSetupOverride: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('प्रथम खजानी नोंदणी (नवीन सुरूवात)'), findsOneWidget);
      expect(find.text('खजानीचे नाव'), findsOneWidget);
      expect(find.text('पासवर्ड'), findsOneWidget);
      expect(find.text('पासवर्ड पुन्हा टाका (Confirm)'), findsOneWidget);
      expect(find.textContaining('लॉगिन कायम ठेवा'), findsOneWidget);
      expect(find.text('पहिला खजानी तयार करा'), findsOneWidget);
    });

    testWidgets('KhajaniLoginScreen in normal login mode renders login fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KhajaniLoginScreen(isFirstSetupOverride: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('खजानी लॉगिन'), findsOneWidget);
      expect(find.text('खजानीचे नाव'), findsOneWidget);
      expect(find.text('पासवर्ड'), findsOneWidget);
      // Confirm password should NOT appear in login mode
      expect(find.text('पासवर्ड पुन्हा टाका (Confirm)'), findsNothing);
      expect(find.textContaining('लॉगिन कायम ठेवा'), findsOneWidget);
      expect(find.text('लॉगिन करा'), findsOneWidget);
    });
  });

  group('Developer Admin UI Widget Tests', () {
    tearDown(() {
      AuthService.instance.setCurrentUserForTesting(null);
    });

    testWidgets('SettingsScreen displays Developer badge for Developer user', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Settings screen must NEVER display 'खजानी व्यवस्थापन' or 'Developer Control'
      expect(find.text('खजानी व्यवस्थापन'), findsNothing);
      expect(find.textContaining('Developer Control'), findsNothing);
    });
  });

  group('Pending User Request & KhajaniStatus Tests', () {
    test('KhajaniStatus evaluates pending and approved correctly', () {
      expect(KhajaniStatus.isPending('PENDING'), isTrue);
      expect(KhajaniStatus.isPending('APPROVED'), isFalse);
      expect(KhajaniStatus.isApproved('APPROVED'), isTrue);
      expect(KhajaniStatus.isApproved(''), isTrue);
      expect(KhajaniStatus.isApproved(null), isTrue);
      expect(KhajaniStatus.isApproved('PENDING'), isFalse);

      expect(KhajaniStatus.marathiTitle('PENDING'), equals('प्रलंबित (Pending)'));
      expect(KhajaniStatus.marathiTitle('APPROVED'), equals('मंजूर (Approved)'));
    });

    test('Pending KhajaniUser has zero effective permissions and cannot modify', () {
      const pendingUser = KhajaniUser(
        userId: 'u_pending_1',
        name: 'विशाल माने',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.pending,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(pendingUser.isPending, isTrue);
      expect(pendingUser.isApproved, isFalse);
      expect(pendingUser.canModify, isFalse);

      final perms = pendingUser.effectivePermissions;
      expect(perms.canView, isFalse);
      expect(perms.canAdd, isFalse);
      expect(perms.canEdit, isFalse);
      expect(perms.canDelete, isFalse);
      expect(perms.canSearch, isFalse);
      expect(perms.canPdf, isFalse);
      expect(perms.canManageKhajani, isFalse);
      expect(perms.canSync, isFalse);

      final map = pendingUser.toMap();
      expect(map['status'], equals('PENDING'));
      expect(map['can_view'], equals(0));

      final roundTrip = KhajaniUser.fromMap(map);
      expect(roundTrip.isPending, isTrue);
      expect(roundTrip.status, equals('PENDING'));
    });
  });

  group('Pending Requests & Approval Flow Widget Tests', () {
    tearDown(() {
      AuthService.instance.setCurrentUserForTesting(null);
    });

    testWidgets('KhajaniLoginScreen allows toggling to New User Request mode', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: KhajaniLoginScreen(isFirstSetupOverride: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('नवीन वापरकर्ता? खात्याची विनंती करा (New Request)'),
        findsOneWidget,
      );

      await tester.tap(
        find.text('नवीन वापरकर्ता? खात्याची विनंती करा (New Request)'),
      );
      await tester.pumpAndSettle();

      expect(find.text('नवीन खाते विनंती (New User Request)'), findsOneWidget);
      expect(find.text('आपले नाव'), findsOneWidget);
      expect(find.text('पासवर्ड'), findsOneWidget);
      expect(find.text('पासवर्ड पुन्हा टाका (Confirm)'), findsOneWidget);
      expect(find.text('खाते विनंती पाठवा (Submit Request)'), findsOneWidget);
      expect(find.text('आधीच खाते आहे? लॉगिन करा'), findsOneWidget);

      await tester.tap(find.text('आधीच खाते आहे? लॉगिन करा'));
      await tester.pumpAndSettle();

      expect(find.text('खजानी लॉगिन'), findsOneWidget);
    });

    test('Hindvi App evaluates approval status and user permissions without developer management UI', () {
      const approvedUser = KhajaniUser(
        userId: 'khajani_test_sep_1',
        name: 'अमित कदम',
        passwordHash: 'h',
        salt: 's',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        createdAt: 1000,
        updatedAt: 1000,
      );

      AuthService.instance.setCurrentUserForTesting(approvedUser);
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.isLatestKhajani, isTrue);
      expect(AuthService.instance.canModify, isTrue);
      expect(approvedUser.effectivePermissions.canView, isTrue);
      expect(approvedUser.effectivePermissions.canAdd, isTrue);
    });

    test('Developer Management controls in Hindvi App are blocked with StateError', () async {
      expect(
        () => AuthService.instance.approveKhajaniRequest(
          userId: 'u1',
          role: KhajaniRole.oldKhajani,
          permissions: const KhajaniPermissions.oldDefault(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () => AuthService.instance.rejectOrDeleteRequest(
          requestId: 'r1',
          userId: 'u1',
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        () => AuthService.instance.revokeDevice('dev_1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Pending User Request Lifecycle & Security Tests', () {
    test('requestNewAccount validates inputs and rejects invalid requests', () {
      expect(
        () async => await AuthService.instance.requestNewAccount(
          name: '',
          password: 'password123',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () async => await AuthService.instance.requestNewAccount(
          name: 'Developer',
          password: 'password123',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () async => await AuthService.instance.requestNewAccount(
          name: 'अमोल कदम',
          password: '123',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Pending user cannot modify and has zero permissions', () {
      final salt = AuthService.generateSalt();
      final hash = AuthService.hashPassword('mypassword', salt);
      final pendingUser = KhajaniUser(
        userId: 'u_pend_test',
        name: 'अमोल कदम',
        passwordHash: hash,
        salt: salt,
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        createdAt: 1000,
        updatedAt: 1000,
      );

      expect(pendingUser.isPending, isTrue);
      expect(pendingUser.isApproved, isFalse);
      expect(pendingUser.canModify, isFalse);
      expect(pendingUser.effectivePermissions.canView, isFalse);
      expect(pendingUser.effectivePermissions.canAdd, isFalse);
      expect(pendingUser.effectivePermissions.canEdit, isFalse);
      expect(pendingUser.effectivePermissions.canDelete, isFalse);
      expect(pendingUser.effectivePermissions.canManageKhajani, isFalse);
      expect(pendingUser.effectivePermissions.canSync, isFalse);
    });

    test('Multiple accounts can share the same name with distinct unique userIds', () {
      final id1 = AuthService.generateUniqueUserId();
      final id2 = AuthService.generateUniqueUserId();
      expect(id1, isNot(equals(id2)));

      final user1 = KhajaniUser(
        userId: id1,
        name: 'संतोष जाधव',
        passwordHash: 'h1',
        salt: 's1',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        createdAt: 1000,
        updatedAt: 1000,
      );

      final user2 = KhajaniUser(
        userId: id2,
        name: 'संतोष जाधव',
        passwordHash: 'h2',
        salt: 's2',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.pending,
        createdAt: 2000,
        updatedAt: 2000,
      );

      expect(user1.name, equals(user2.name));
      expect(user1.userId, isNot(equals(user2.userId)));
      expect(user1.isApproved, isTrue);
      expect(user2.isPending, isTrue);
    });
  });
}

