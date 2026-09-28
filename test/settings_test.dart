import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hindvi_app/database/database_helper.dart';
import 'package:hindvi_app/screens/mandal_data_transfer_screen.dart';
import 'package:hindvi_app/screens/recovery_data_screen.dart';
import 'package:hindvi_app/screens/restore_screen.dart';
import 'package:hindvi_app/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Settings & Storage Safety Tests', () {
    test('Storage folder structure uses /storage/emulated/0/हिंदवी and Old on Android', () {
      final helper = DatabaseHelper.instance;
      expect(helper.databaseFileName, equals('hindvi_latest.db'));

      if (Platform.isAndroid) {
        expect(helper.hindviFolderPath, equals('/storage/emulated/0/हिंदवी'));
        expect(helper.oldFolderPath, equals('/storage/emulated/0/हिंदवी/Old'));
      } else {
        expect(helper.hindviFolderPath.endsWith('हिंदवी'), isTrue);
        expect(helper.oldFolderPath.endsWith('Old'), isTrue);
      }
    });

    test('deleteOldBackupFile strictly forbids deleting active hindvi_latest.db', () async {
      final helper = DatabaseHelper.instance;
      final activeFile = File('${helper.hindviFolderPath}/hindvi_latest.db');

      expect(
        () async => await helper.deleteOldBackupFile(activeFile),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('Settings screen renders modern Material 3 options', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('सेटिंग्ज'), findsOneWidget);
      expect(find.text('डेटा व्यवस्थापन'), findsOneWidget);
      expect(find.text('मंडळ डेटा ट्रान्सफर'), findsOneWidget);
      expect(find.text('बॅकअप'), findsOneWidget);
      expect(find.text('रिस्टोर'), findsOneWidget);
      expect(find.text('जुना / Recovery Data'), findsOneWidget);
    });

    testWidgets('Tapping Mandal Data Transfer navigates to MandalDataTransferScreen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('मंडळ डेटा ट्रान्सफर'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(MandalDataTransferScreen), findsOneWidget);
      expect(find.text('डेटा पाठवा (जुना फोन)'), findsOneWidget);
      expect(find.text('डेटा स्वीकारा (नवीन फोन)'), findsOneWidget);
    });

    testWidgets('Tapping Restore navigates to RestoreScreen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('रिस्टोर'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RestoreScreen), findsOneWidget);
      expect(find.text('बाहेरील बॅकअप फाइल निवडा'), findsOneWidget);
    });

    testWidgets('Tapping Recovery Data navigates to RecoveryDataScreen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('जुना / Recovery Data'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RecoveryDataScreen), findsOneWidget);
      expect(find.text('जुना व Recovery डेटा व्यवस्थापन'), findsOneWidget);
    });

    testWidgets('Tapping Backup opens backup sheet with Backup Now button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('बॅकअप'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Backup Now'), findsOneWidget);
      expect(find.text('डेटाबेस स्थिती: सुरक्षित'), findsOneWidget);
      expect(find.textContaining('Last Backup:'), findsOneWidget);
    });
  });
}
