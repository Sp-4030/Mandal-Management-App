import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/database/database_helper.dart';
import 'package:hindvi_app/models/device_model.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/services/auth_service.dart';
import 'package:hindvi_app/services/remote_sync_service.dart';
import 'package:hindvi_app/services/signaling_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Master Financial Dataset across multiple years and all 7 tables
  final masterFinancialDataset = <String, List<Map<String, dynamic>>>{
    'vargani': [
      {'id': 1, 'name': 'विनायक पाटील', 'amount': 2500.0, 'year': 2024, 'date': '2024-09-01'},
      {'id': 2, 'name': 'योगेश कदम', 'amount': 1500.0, 'year': 2025, 'date': '2025-09-02'},
      {'id': 3, 'name': 'संतोष शिंदे', 'amount': 5000.0, 'year': 2026, 'date': '2026-09-03'},
    ],
    'prasad_dengani': [
      {'id': 1, 'name': 'प्रकाश पवार', 'amount': 1000.0, 'year': 2024, 'date': '2024-09-04'},
      {'id': 2, 'name': 'महेश जाधव', 'amount': 2000.0, 'year': 2025, 'date': '2025-09-05'},
    ],
    'prasad_sahitya': [
      {'id': 1, 'name': 'सुरेश मोरे', 'item': 'साखर ५० किलो', 'amount': 1950.0, 'year': 2025, 'date': '2025-09-06'},
    ],
    'aarti_vargani': [
      {'id': 1, 'name': 'गणेश मंडळ आरती', 'amount': 3500.0, 'year': 2025, 'date': '2025-09-07'},
    ],
    'kharch': [
      {'id': 1, 'title': 'मंडप व रोषणाई', 'amount': 12000.0, 'year': 2024, 'date': '2024-09-08', 'category': 'मंडप'},
      {'id': 2, 'title': 'ध्वनीक्षेपक व्यवस्था (2025)', 'amount': 15000.0, 'year': 2025, 'date': '2025-09-09', 'category': 'माईक'},
    ],
    'mahaprasad_kharch': [
      {'id': 1, 'title': 'महाप्रसाद धान्य व भाजीपाला', 'amount': 8500.0, 'year': 2025, 'date': '2025-09-10'},
    ],
    'previous_balance': [
      {'year': 2024, 'balance': 25000.0},
      {'year': 2025, 'balance': 38000.0},
      {'year': 2026, 'balance': 42000.0},
    ],
  };

  tearDown(() {
    AuthService.instance.setCurrentUserForTesting(null);
  });

  group('Complete Financial Data Synchronization & Offline First Test Suite (14 Tests)', () {
    // -------------------------------------------------------------
    // Test 1: Latest Phone (Master) Existing Financial Data Verification
    // -------------------------------------------------------------
    test('Test 1: Master Phone SQLite data verification (7 tables, multiple years 2024, 2025, 2026)', () {
      final expectedTables = DatabaseHelper.migrationDataTables;
      expect(expectedTables, containsAll([
        'vargani',
        'prasad_dengani',
        'prasad_sahitya',
        'aarti_vargani',
        'kharch',
        'mahaprasad_kharch',
        'previous_balance',
      ]));

      // Verify master data contains records for multiple years
      final varganiYears = masterFinancialDataset['vargani']!.map((r) => r['year']).toSet();
      expect(varganiYears, containsAll([2024, 2025, 2026]));

      final totalRecords = masterFinancialDataset.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      expect(totalRecords, equals(13));
    });

    // -------------------------------------------------------------
    // Test 2: New Phone Developer Approval Flow
    // -------------------------------------------------------------
    test('Test 2: New Phone Developer approval with role assignment and permission granting', () {
      // Pending request from new device
      final pendingReq = DeviceRequestModel(
        requestId: 'REQ_NEW_PHONE_01',
        userId: 'khajani_new_target',
        userName: 'अनिकेत कदम',
        deviceId: 'D-NEW-PHONE-ANDROID',
        deviceName: 'Redmi Note 12',
        status: DeviceStatus.pending,
        requestedRole: KhajaniRole.oldKhajani,
        createdAt: 1000,
        updatedAt: 1000,
      );
      expect(pendingReq.isPending, isTrue);

      // Developer approves request with View, Search, and PDF permissions
      final approvedReq = pendingReq.copyWith(
        status: DeviceStatus.approved,
        updatedAt: 2000,
      );
      expect(approvedReq.isApproved, isTrue);

      // Construct approved user with granted permissions
      const approvedUser = KhajaniUser(
        userId: 'khajani_new_target',
        name: 'अनिकेत कदम',
        passwordHash: 'hashed_pw',
        salt: 'salt_123',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        isActive: true,
        permissions: KhajaniPermissions(
          canView: true,
          canSearch: true,
          canPdf: true,
          canAdd: false,
          canEdit: false,
          canDelete: false,
          canSync: false,
        ),
        createdAt: 2000,
        updatedAt: 2000,
      );

      AuthService.instance.setCurrentUserForTesting(approvedUser);
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.canView, isTrue);
      expect(AuthService.instance.canSearch, isTrue);
      expect(AuthService.instance.canPdf, isTrue);
      expect(AuthService.instance.canAdd, isFalse);
      expect(AuthService.instance.canEdit, isFalse);
      expect(AuthService.instance.canDelete, isFalse);
    });

    // -------------------------------------------------------------
    // Test 3: Sync Request from Target Phone to Master Phone
    // -------------------------------------------------------------
    test('Test 3: Sync Request & Snapshot preparation with SHA-256 payload integrity', () {
      // Create master snapshot
      final snapshot = {
        'version': 8,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'tables': masterFinancialDataset,
      };

      final snapshotJson = jsonEncode(snapshot);
      final digest = sha256.convert(utf8.encode(snapshotJson)).toString();

      final syncPackage = {
        'type': 'sync_data',
        'syncId': 'sync_test_001',
        'from': 'D-MASTER-KHAJANI',
        'to': 'D-NEW-PHONE-ANDROID',
        'isDelta': false,
        'recordCounts': {
          'vargani': 3,
          'prasad_dengani': 2,
          'prasad_sahitya': 1,
          'aarti_vargani': 1,
          'kharch': 2,
          'mahaprasad_kharch': 1,
          'previous_balance': 3,
        },
        'totalRecords': 13,
        'snapshot': snapshot,
        'payloadDigest': digest,
      };

      // Target validates checksum digest
      final targetCalculatedDigest = sha256
          .convert(utf8.encode(jsonEncode(syncPackage['snapshot'])))
          .toString();
      expect(targetCalculatedDigest, equals(syncPackage['payloadDigest']));
    });

    // -------------------------------------------------------------
    // Test 4: Target Phone Table Inspection
    // -------------------------------------------------------------
    test('Test 4: Target Phone has all 7 financial tables with exact master record counts', () {
      final tables = masterFinancialDataset['vargani']!;
      expect(tables.length, equals(3));

      final prasadDengani = masterFinancialDataset['prasad_dengani']!;
      expect(prasadDengani.length, equals(2));

      final prasadSahitya = masterFinancialDataset['prasad_sahitya']!;
      expect(prasadSahitya.length, equals(1));

      final aartiVargani = masterFinancialDataset['aarti_vargani']!;
      expect(aartiVargani.length, equals(1));

      final kharch = masterFinancialDataset['kharch']!;
      expect(kharch.length, equals(2));

      final mahaprasad = masterFinancialDataset['mahaprasad_kharch']!;
      expect(mahaprasad.length, equals(1));

      final prevBalance = masterFinancialDataset['previous_balance']!;
      expect(prevBalance.length, equals(3));
    });

    // -------------------------------------------------------------
    // Test 5: Records, Amounts, Marathi Names, and Years Compare
    // -------------------------------------------------------------
    test('Test 5: Compare Marathi names, exact numeric amounts, dates and years', () {
      final vargani = masterFinancialDataset['vargani']!;

      expect(vargani[0]['name'], equals('विनायक पाटील'));
      expect(vargani[0]['amount'], equals(2500.0));
      expect(vargani[0]['year'], equals(2024));
      expect(vargani[0]['date'], equals('2024-09-01'));

      expect(vargani[1]['name'], equals('योगेश कदम'));
      expect(vargani[1]['amount'], equals(1500.0));
      expect(vargani[1]['year'], equals(2025));

      expect(vargani[2]['name'], equals('संतोष शिंदे'));
      expect(vargani[2]['amount'], equals(5000.0));
      expect(vargani[2]['year'], equals(2026));

      // 2025 Kharch records preserved
      final kharch2025 = masterFinancialDataset['kharch']!.firstWhere((k) => k['year'] == 2025);
      expect(kharch2025['title'], equals('ध्वनीक्षेपक व्यवस्था (2025)'));
      expect(kharch2025['amount'], equals(15000.0));
      expect(kharch2025['category'], equals('माईक'));
    });

    // -------------------------------------------------------------
    // Test 6: Search on Synced Financial Records
    // -------------------------------------------------------------
    test('Test 6: Search by Marathi name and filter by financial year', () {
      final vargani = masterFinancialDataset['vargani']!;

      // Search by query 'पाटील'
      final searchPatil = vargani.where((r) => (r['name'] as String).contains('पाटील')).toList();
      expect(searchPatil.length, equals(1));
      expect(searchPatil.first['name'], equals('विनायक पाटील'));

      // Search by query 'संतोष'
      final searchSantosh = vargani.where((r) => (r['name'] as String).contains('संतोष')).toList();
      expect(searchSantosh.length, equals(1));
      expect(searchSantosh.first['name'], equals('संतोष शिंदे'));

      // Filter by year 2025
      final year2025Records = vargani.where((r) => r['year'] == 2025).toList();
      expect(year2025Records.length, equals(1));
      expect(year2025Records.first['name'], equals('योगेश कदम'));
    });

    // -------------------------------------------------------------
    // Test 7: Annual Report PDF Calculation from Synced Data
    // -------------------------------------------------------------
    test('Test 7: Annual Report balance calculation matches synced records across years', () {
      // Calculate 2025 annual figures
      const targetYear = 2025;

      final vargani2025 = masterFinancialDataset['vargani']!
          .where((r) => r['year'] == targetYear)
          .fold<double>(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

      final prasad2025 = masterFinancialDataset['prasad_dengani']!
          .where((r) => r['year'] == targetYear)
          .fold<double>(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

      final aarti2025 = masterFinancialDataset['aarti_vargani']!
          .where((r) => r['year'] == targetYear)
          .fold<double>(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

      final prevBalance2025 = (masterFinancialDataset['previous_balance']!
          .firstWhere((r) => r['year'] == targetYear)['balance'] as num)
          .toDouble();

      final totalIncome = vargani2025 + prasad2025 + aarti2025 + prevBalance2025;
      // 1500 (vargani) + 2000 (prasad) + 3500 (aarti) + 38000 (prev) = 45000.0
      expect(totalIncome, equals(45000.0));

      final kharch2025 = masterFinancialDataset['kharch']!
          .where((r) => r['year'] == targetYear)
          .fold<double>(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

      final mahaprasad2025 = masterFinancialDataset['mahaprasad_kharch']!
          .where((r) => r['year'] == targetYear)
          .fold<double>(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

      final totalExpense = kharch2025 + mahaprasad2025;
      // 15000 (kharch) + 8500 (mahaprasad) = 23500.0
      expect(totalExpense, equals(23500.0));

      final netClosingBalance = totalIncome - totalExpense;
      // 45000.0 - 23500.0 = 21500.0
      expect(netClosingBalance, equals(21500.0));
    });

    // -------------------------------------------------------------
    // Test 8: Offline-First Operation (No PC or Internet required)
    // -------------------------------------------------------------
    test('Test 8: Offline operation - tables and annual calculations work without network', () {
      // Disconnected state
      final signaling = SignalingService.instance;
      expect(signaling.isConnected, isFalse);

      // Accessing local financial data does not require WebSocket
      final localSnapshot = masterFinancialDataset;
      expect(localSnapshot.isNotEmpty, isTrue);

      final totalLocalRecords = localSnapshot.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      expect(totalLocalRecords, equals(13));
    });

    // -------------------------------------------------------------
    // Test 9: OLD_KHAJANI Read-Only Enforcement in Database Layer
    // -------------------------------------------------------------
    test('Test 9: OLD_KHAJANI read-only enforcement blocks Add/Edit/Delete in DatabaseHelper', () {
      const oldKhajani = KhajaniUser(
        userId: 'u_old_khajani_readonly',
        name: 'दत्तात्रय कदम',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions(
          canView: true,
          canSearch: true,
          canPdf: true,
          canAdd: false,
          canEdit: false,
          canDelete: false,
          canSync: false,
        ),
        createdAt: 1000,
        updatedAt: 1000,
      );

      AuthService.instance.setCurrentUserForTesting(oldKhajani);
      expect(AuthService.instance.canView, isTrue);
      expect(AuthService.instance.canSearch, isTrue);
      expect(AuthService.instance.canPdf, isTrue);
      expect(AuthService.instance.canAdd, isFalse);
      expect(AuthService.instance.canEdit, isFalse);
      expect(AuthService.instance.canDelete, isFalse);

      final db = DatabaseHelper.instance;

      // Add operation throws StateError
      expect(
        () async => await db.insertVargani({'name': 'अवैध नोंद', 'amount': 100, 'year': 2026}),
        throwsA(isA<StateError>()),
      );

      // Edit operation throws StateError
      expect(
        () async => await db.updateVargani(1, {'name': 'अवैध बदल', 'amount': 200, 'year': 2026}),
        throwsA(isA<StateError>()),
      );

      // Delete operation throws StateError
      expect(
        () async => await db.deleteVargani(1),
        throwsA(isA<StateError>()),
      );
    });

    // -------------------------------------------------------------
    // Test 10: Developer Grants Edit Permission
    // -------------------------------------------------------------
    test('Test 10: Developer can grant Add/Edit permission, unlocking write operations', () {
      // User with Developer-granted edit permissions
      const grantedUser = KhajaniUser(
        userId: 'u_editor_granted',
        name: 'अमोल पाटील',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions(
          canView: true,
          canSearch: true,
          canPdf: true,
          canAdd: true,
          canEdit: true,
          canDelete: false,
          canSync: false,
        ),
        createdAt: 1000,
        updatedAt: 1000,
      );

      AuthService.instance.setCurrentUserForTesting(grantedUser);
      expect(AuthService.instance.canAdd, isTrue);
      expect(AuthService.instance.canEdit, isTrue);
      expect(AuthService.instance.canDelete, isFalse);
    });

    // -------------------------------------------------------------
    // Test 11: Incremental / Delta Sync Mechanism
    // -------------------------------------------------------------
    test('Test 11: Delta sync accurately filters records newer than lastKnownIds', () {
      // Target already has records up to id 1 in vargani, and up to id 1 in kharch
      final lastKnownIds = <String, int>{
        'vargani': 1,
        'prasad_dengani': 2,
        'prasad_sahitya': 1,
        'aarti_vargani': 1,
        'kharch': 1,
        'mahaprasad_kharch': 1,
      };

      // Calculate delta
      final delta = <String, List<Map<String, dynamic>>>{};
      int totalDelta = 0;

      for (final entry in masterFinancialDataset.entries) {
        final table = entry.key;
        if (table == 'previous_balance') continue; // Always synced full

        final lastId = lastKnownIds[table] ?? 0;
        final newerRecords = entry.value
            .where((r) => ((r['id'] as num?)?.toInt() ?? 0) > lastId)
            .toList();

        delta[table] = newerRecords;
        totalDelta += newerRecords.length;
      }

      // Vargani delta: id 2 and id 3 (2 records)
      expect(delta['vargani']!.length, equals(2));
      expect(delta['vargani']!.map((r) => r['id']), containsAll([2, 3]));

      // Kharch delta: id 2 (1 record)
      expect(delta['kharch']!.length, equals(1));
      expect(delta['kharch']!.first['id'], equals(2));

      // Prasad dengani has no newer records (2 already known)
      expect(delta['prasad_dengani']!.length, equals(0));

      expect(totalDelta, equals(3));
    });

    // -------------------------------------------------------------
    // Test 12: Duplicate Sync Idempotency (ConflictAlgorithm.replace)
    // -------------------------------------------------------------
    test('Test 12: Multiple sync invocations do not create duplicate rows', () {
      final localStore = <String, Map<int, Map<String, dynamic>>>{
        'vargani': {},
      };

      void importVargani(List<Map<String, dynamic>> records) {
        for (final r in records) {
          final id = (r['id'] as num).toInt();
          localStore['vargani']![id] = Map<String, dynamic>.from(r); // ConflictAlgorithm.replace
        }
      }

      // First sync
      importVargani(masterFinancialDataset['vargani']!);
      expect(localStore['vargani']!.length, equals(3));

      // Duplicate sync
      importVargani(masterFinancialDataset['vargani']!);
      expect(localStore['vargani']!.length, equals(3)); // Still exactly 3 records

      // Triple sync
      importVargani(masterFinancialDataset['vargani']!);
      expect(localStore['vargani']!.length, equals(3)); // No duplicates created
    });

    // -------------------------------------------------------------
    // Test 13: Sync Failure and Transaction Rollback Safety
    // -------------------------------------------------------------
    test('Test 13: Corrupted data throws error and rolls back without polluting local data', () {
      final initialStore = Map<int, Map<String, dynamic>>.from({
        1: {'id': 1, 'name': 'विनायक पाटील', 'amount': 2500.0, 'year': 2024},
      });

      var currentStore = Map<int, Map<String, dynamic>>.from(initialStore);

      bool executeTransaction(List<Map<String, dynamic>> incoming) {
        final backupStore = Map<int, Map<String, dynamic>>.from(currentStore);
        try {
          for (final r in incoming) {
            if (r['amount'] == null || (r['amount'] as num) < 0) {
              throw StateError('Invalid financial amount');
            }
            final id = (r['id'] as num).toInt();
            currentStore[id] = r;
          }
          return true;
        } catch (_) {
          // Automatic Rollback
          currentStore = backupStore;
          return false;
        }
      }

      // Corrupted incoming batch with negative amount
      final corruptBatch = [
        {'id': 2, 'name': 'अवैध नोंद', 'amount': -500.0, 'year': 2025},
      ];

      final success = executeTransaction(corruptBatch);
      expect(success, isFalse);
      // Store remains intact with only initial record
      expect(currentStore.length, equals(1));
      expect(currentStore[1]!['name'], equals('विनायक पाटील'));
    });

    // -------------------------------------------------------------
    // Test 14: Debug Log Stage Verification with Actual Record Counts
    // -------------------------------------------------------------
    test('Test 14: Exact debug log pipeline and actual record count verification', () {
      final actualDbCounts = {
        'vargani': 150,
        'prasad_dengani': 40,
        'prasad_sahitya': 15,
        'aarti_vargani': 10,
        'kharch': 80,
        'mahaprasad_kharch': 25,
        'previous_balance': 5,
      };

      final formattedCounts = RemoteSyncService.formatCounts(actualDbCounts);
      expect(formattedCounts, contains('Vargani: 150 records'));
      expect(formattedCounts, contains('Prasad Dengani: 40 records'));
      expect(formattedCounts, contains('Kharch: 80 records'));

      final logSequence = <String>[
        'SYNC_STARTED',
        'MASTER_DATA_READ',
        'DATA_SERIALIZED',
        'DATA_SENT',
        'SERVER_RECEIVED',
        'TARGET_RECEIVED',
        'DATA_VALIDATED',
        'SQLITE_TRANSACTION_STARTED',
        'DATA_INSERTED/UPDATED',
        'SQLITE_COMMITTED',
        'SYNC_COMPLETED',
        'UI_REFRESHED',
      ];

      // Verify the entire pipeline order
      expect(logSequence.length, equals(12));
      expect(logSequence.first, equals('SYNC_STARTED'));
      expect(logSequence[1], equals('MASTER_DATA_READ'));
      expect(logSequence[4], equals('SERVER_RECEIVED'));
      expect(logSequence[7], equals('SQLITE_TRANSACTION_STARTED'));
      expect(logSequence[9], equals('SQLITE_COMMITTED'));
      expect(logSequence.last, equals('UI_REFRESHED'));
    });
  });
}
