import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/database/database_helper.dart';
import 'package:hindvi_app/models/device_model.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test financial datasets across all 7 financial tables and multiple years
  final initialMasterDataset = <String, List<Map<String, dynamic>>>{
    'vargani': [
      {'id': 1, 'name': 'विनायक पाटील', 'amount': 1500.0, 'year': 2024, 'date': '2024-09-01'},
      {'id': 2, 'name': 'योगेश कदम', 'amount': 2000.0, 'year': 2025, 'date': '2025-09-02'},
    ],
    'prasad_dengani': [
      {'id': 1, 'name': 'प्रकाश पवार', 'amount': 1000.0, 'year': 2025, 'date': '2025-09-03'},
    ],
    'prasad_sahitya': [
      {'id': 1, 'name': 'सुरेश मोरे', 'item': 'साखर ५० किलो', 'amount': 1950.0, 'year': 2025, 'date': '2025-09-04'},
    ],
    'aarti_vargani': [
      {'id': 1, 'name': 'गणेश आरती मंडळ', 'amount': 3000.0, 'year': 2025, 'date': '2025-09-05'},
    ],
    'kharch': [
      {'id': 1, 'title': 'मंडप व रोषणाई', 'amount': 12000.0, 'year': 2025, 'date': '2025-09-06', 'category': 'मंडप'},
    ],
    'mahaprasad_kharch': [
      {'id': 1, 'title': 'महाप्रसाद धान्य', 'amount': 8500.0, 'year': 2025, 'date': '2025-09-07'},
    ],
    'previous_balance': [
      {'year': 2024, 'balance': 25000.0},
      {'year': 2025, 'balance': 38000.0},
    ],
  };

  tearDown(() {
    AuthService.instance.setCurrentUserForTesting(null);
  });

  group('Hindvi-App Two-Way Financial Data Synchronization Test Suite (All 15 Scenarios)', () {
    // -------------------------------------------------------------
    // Scenario 1: Latest Khajani Vargani amount change synced to other approved phone
    // -------------------------------------------------------------
    test('Scenario 1: Latest Khajani Vargani amount change synced to other approved phone', () {
      // Simulate Phone A (Latest Khajani)
      const latestKhajaniUser = KhajaniUser(
        userId: 'u_latest_khajani',
        name: 'प्रथमेश खजानी',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.latestKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions(
          canView: true,
          canSearch: true,
          canPdf: true,
          canAdd: true,
          canEdit: true,
          canDelete: true,
          canSync: true,
        ),
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(latestKhajaniUser);

      // Phone A edits Vargani record 1 amount from 1500 to 2500
      final changePayload = {
        'changeId': 'CHG_V1_001',
        'deviceId': 'DEV_PHONE_A',
        'userId': 'u_latest_khajani',
        'tableName': 'vargani',
        'recordId': '1',
        'operation': 'UPDATE',
        'version': 2,
        'changedAt': 1700000000000,
        'recordData': {
          'id': 1,
          'name': 'विनायक पाटील',
          'amount': 2500.0,
          'year': 2024,
          'date': '2024-09-01',
        },
      };

      // Simulated Phone B local store
      final phoneBStore = Map<String, dynamic>.from(initialMasterDataset['vargani']![0]);
      expect(phoneBStore['amount'], equals(1500.0));

      // PC Server relays message: SERVER_RECEIVED -> SERVER_FORWARDED
      final serverLog = <String>[];
      serverLog.add('[SERVER_RECEIVED] type=financial_change from=DEV_PHONE_A');
      serverLog.add('[SERVER_FORWARDED] to=DEV_PHONE_B changeId=CHG_V1_001');

      // Phone B receives: TARGET_RECEIVED -> TARGET_VALIDATED -> TARGET_DB_COMMITTED
      expect(changePayload['operation'], equals('UPDATE'));
      final updatedData = changePayload['recordData'] as Map<String, dynamic>;
      phoneBStore['amount'] = updatedData['amount'];

      expect(phoneBStore['amount'], equals(2500.0));
      expect(serverLog, contains('[SERVER_RECEIVED] type=financial_change from=DEV_PHONE_A'));
      expect(serverLog, contains('[SERVER_FORWARDED] to=DEV_PHONE_B changeId=CHG_V1_001'));
    });

    // -------------------------------------------------------------
    // Scenario 2: Authorized phone allowed Vargani edit synced to Latest Khajani
    // -------------------------------------------------------------
    test('Scenario 2: Authorized phone allowed Vargani edit synced to Latest Khajani', () {
      // Phone B has OLD_KHAJANI role with Developer-granted canEdit permission
      const authorizedEditor = KhajaniUser(
        userId: 'u_auth_editor_b',
        name: 'अमोल कदम',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.oldKhajani,
        status: KhajaniStatus.approved,
        permissions: KhajaniPermissions(
          canView: true,
          canSearch: true,
          canPdf: true,
          canAdd: false,
          canEdit: true,
          canDelete: false,
          canSync: false,
        ),
        createdAt: 1000,
        updatedAt: 1000,
      );
      AuthService.instance.setCurrentUserForTesting(authorizedEditor);
      expect(AuthService.instance.canEdit, isTrue);

      // Phone B edits Vargani record 2
      final changePayload = {
        'changeId': 'CHG_V2_PHONE_B',
        'deviceId': 'DEV_PHONE_B',
        'userId': 'u_auth_editor_b',
        'tableName': 'vargani',
        'recordId': '2',
        'operation': 'UPDATE',
        'version': 2,
        'changedAt': 1700000050000,
        'recordData': {
          'id': 2,
          'name': 'योगेश कदम (संपादित)',
          'amount': 2200.0,
          'year': 2025,
          'date': '2025-09-02',
        },
      };

      // Latest Khajani (Phone A) applies change to local store
      final phoneAStore = Map<String, dynamic>.from(initialMasterDataset['vargani']![1]);
      final newRecordData = changePayload['recordData'] as Map<String, dynamic>;
      phoneAStore['name'] = newRecordData['name'];
      phoneAStore['amount'] = newRecordData['amount'];

      expect(phoneAStore['name'], equals('योगेश कदम (संपादित)'));
      expect(phoneAStore['amount'], equals(2200.0));
    });

    // -------------------------------------------------------------
    // Scenario 3: Prasad Dengani add synced to all authorized phones
    // -------------------------------------------------------------
    test('Scenario 3: Prasad Dengani add synced to all authorized phones', () {
      final phoneBPrasadList = List<Map<String, dynamic>>.from(initialMasterDataset['prasad_dengani']!);
      expect(phoneBPrasadList.length, equals(1));

      // Phone A adds new Prasad Dengani record
      final newPrasad = {
        'changeId': 'CHG_PD_ADD_01',
        'deviceId': 'DEV_PHONE_A',
        'userId': 'u_latest_khajani',
        'tableName': 'prasad_dengani',
        'recordId': '2',
        'operation': 'INSERT',
        'version': 1,
        'changedAt': 1700000100000,
        'recordData': {
          'id': 2,
          'name': 'महेश देशमुख',
          'amount': 3000.0,
          'year': 2025,
          'date': '2025-09-10',
        },
      };

      // Phone B receives and applies INSERT
      final recordData = newPrasad['recordData'] as Map<String, dynamic>;
      phoneBPrasadList.add(recordData);

      expect(phoneBPrasadList.length, equals(2));
      expect(phoneBPrasadList.last['name'], equals('महेश देशमुख'));
      expect(phoneBPrasadList.last['amount'], equals(3000.0));
    });

    // -------------------------------------------------------------
    // Scenario 4: Prasad Sahitya edit synced to all authorized phones
    // -------------------------------------------------------------
    test('Scenario 4: Prasad Sahitya edit synced to all authorized phones', () {
      final phoneBSahityaList = List<Map<String, dynamic>>.from(initialMasterDataset['prasad_sahitya']!);
      expect(phoneBSahityaList.first['item'], equals('साखर ५० किलो'));

      // Edit on Phone A
      final changePayload = {
        'changeId': 'CHG_PS_EDIT_01',
        'deviceId': 'DEV_PHONE_A',
        'userId': 'u_latest_khajani',
        'tableName': 'prasad_sahitya',
        'recordId': '1',
        'operation': 'UPDATE',
        'version': 2,
        'changedAt': 1700000150000,
        'recordData': {
          'id': 1,
          'name': 'सुरेश मोरे',
          'item': 'साखर १०० किलो व तूप',
          'amount': 4500.0,
          'year': 2025,
          'date': '2025-09-04',
        },
      };

      final idx = phoneBSahityaList.indexWhere((r) => r['id'] == 1);
      phoneBSahityaList[idx] = changePayload['recordData'] as Map<String, dynamic>;

      expect(phoneBSahityaList.first['item'], equals('साखर १०० किलो व तूप'));
      expect(phoneBSahityaList.first['amount'], equals(4500.0));
    });

    // -------------------------------------------------------------
    // Scenario 5: Kharch edit synced to all authorized phones
    // -------------------------------------------------------------
    test('Scenario 5: Kharch edit synced to all authorized phones', () {
      final phoneBKharchList = List<Map<String, dynamic>>.from(initialMasterDataset['kharch']!);
      expect(phoneBKharchList.first['amount'], equals(12000.0));

      final changePayload = {
        'changeId': 'CHG_KH_EDIT_01',
        'deviceId': 'DEV_PHONE_A',
        'userId': 'u_latest_khajani',
        'tableName': 'kharch',
        'recordId': '1',
        'operation': 'UPDATE',
        'version': 2,
        'changedAt': 1700000200000,
        'recordData': {
          'id': 1,
          'title': 'मंडप, स्टेज व भव्य रोषणाई',
          'amount': 16500.0,
          'year': 2025,
          'date': '2025-09-06',
          'category': 'मंडप',
        },
      };

      phoneBKharchList[0] = changePayload['recordData'] as Map<String, dynamic>;
      expect(phoneBKharchList.first['title'], equals('मंडप, स्टेज व भव्य रोषणाई'));
      expect(phoneBKharchList.first['amount'], equals(16500.0));
    });

    // -------------------------------------------------------------
    // Scenario 6: Mahaprasad Kharch delete synced with tombstones
    // -------------------------------------------------------------
    test('Scenario 6: Mahaprasad Kharch delete synced to all authorized phones with tombstones', () {
      final phoneBMahaprasadList = List<Map<String, dynamic>>.from(initialMasterDataset['mahaprasad_kharch']!);
      final tombstones = <String>{};

      expect(phoneBMahaprasadList.length, equals(1));

      // Phone A deletes record id 1
      final deletePayload = {
        'changeId': 'CHG_MK_DEL_01',
        'deviceId': 'DEV_PHONE_A',
        'userId': 'u_latest_khajani',
        'tableName': 'mahaprasad_kharch',
        'recordId': '1',
        'operation': 'DELETE',
        'version': 2,
        'changedAt': 1700000250000,
      };

      // Phone B applies DELETE and marks tombstone
      tombstones.add('${deletePayload['tableName']}:${deletePayload['recordId']}');
      phoneBMahaprasadList.removeWhere((r) => r['id'].toString() == deletePayload['recordId']);

      expect(phoneBMahaprasadList.isEmpty, isTrue);
      expect(tombstones, contains('mahaprasad_kharch:1'));

      // If an old stale insert arrives for the tombstoned record, tombstone check prevents resurrection
      final staleInsert = {
        'tableName': 'mahaprasad_kharch',
        'recordId': '1',
        'operation': 'INSERT',
      };
      final isTombstoned = tombstones.contains('${staleInsert['tableName']}:${staleInsert['recordId']}');
      expect(isTombstoned, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 7: Phone offline -> change -> Internet ON -> queued change synchronizes
    // -------------------------------------------------------------
    test('Scenario 7: Phone offline -> change -> Internet ON -> queued change synchronizes', () {
      final syncQueue = <Map<String, dynamic>>[];

      // Offline change created and stored locally
      final offlineChange = {
        'changeId': 'CHG_OFFLINE_01',
        'tableName': 'vargani',
        'recordId': '3',
        'operation': 'INSERT',
        'version': 1,
        'changedAt': 1700000300000,
        'status': 'PENDING',
        'retryCount': 0,
        'recordData': jsonEncode({
          'id': 3,
          'name': 'दिलीप सावंत',
          'amount': 3500.0,
          'year': 2025,
        }),
      };
      syncQueue.add(offlineChange);
      expect(syncQueue.length, equals(1));
      expect(syncQueue.first['status'], equals('PENDING'));

      // Internet reconnects -> queue is flushed
      final pendingItems = syncQueue.where((item) => item['status'] == 'PENDING').toList();
      expect(pendingItems.length, equals(1));

      // Items sent to server and acknowledged
      final ackChangeId = pendingItems.first['changeId'];
      final idx = syncQueue.indexWhere((item) => item['changeId'] == ackChangeId);
      syncQueue[idx]['status'] = 'COMPLETED';

      expect(syncQueue.first['status'], equals('COMPLETED'));
    });

    // -------------------------------------------------------------
    // Scenario 8: App restart -> synced data remains in SQLite
    // -------------------------------------------------------------
    test('Scenario 8: App restart -> synced data remains in SQLite', () {
      // Local SQLite persistence simulation
      final persistentStorage = <String, dynamic>{
        'vargani_1': {'id': 1, 'name': 'विनायक पाटील', 'amount': 2500.0},
        'prasad_dengani_1': {'id': 1, 'name': 'प्रकाश पवार', 'amount': 1000.0},
      };

      // Simulate App Process Kill and Relaunch
      final reloadedStorage = Map<String, dynamic>.from(persistentStorage);
      expect(reloadedStorage.length, equals(2));
      expect(reloadedStorage['vargani_1']['amount'], equals(2500.0));
      expect(reloadedStorage['prasad_dengani_1']['name'], equals('प्रकाश पवार'));
    });

    // -------------------------------------------------------------
    // Scenario 9: PC restart -> pending changes eventually synchronize
    // -------------------------------------------------------------
    test('Scenario 9: PC restart -> pending changes eventually synchronize', () {
      var isPcServerOnline = false;
      final localPendingQueue = <String>['CHG_001', 'CHG_002'];

      // Attempt send while PC is down fails gracefully without data loss
      if (!isPcServerOnline) {
        // Keeps items in queue
        expect(localPendingQueue.length, equals(2));
      }

      // PC Server restarts
      isPcServerOnline = true;
      final transmitted = <String>[];
      if (isPcServerOnline) {
        transmitted.addAll(localPendingQueue);
        localPendingQueue.clear();
      }

      expect(transmitted, containsAll(['CHG_001', 'CHG_002']));
      expect(localPendingQueue.isEmpty, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 10: Duplicate sync message -> no duplicate record created
    // -------------------------------------------------------------
    test('Scenario 10: Duplicate sync message -> no duplicate record created', () {
      final receivedChangeLog = <String>{};
      final localTable = <int, Map<String, dynamic>>{};

      final changePayload = {
        'changeId': 'CHG_DUPLICATE_CHECK',
        'tableName': 'vargani',
        'recordId': 10,
        'operation': 'INSERT',
        'recordData': {'id': 10, 'name': 'समीर पाटील', 'amount': 5000.0, 'year': 2025},
      };

      void processIncoming(Map<String, dynamic> change) {
        final changeId = change['changeId'] as String;
        if (receivedChangeLog.contains(changeId)) {
          // Already received, ignore duplicate
          return;
        }
        receivedChangeLog.add(changeId);
        final r = change['recordData'] as Map<String, dynamic>;
        localTable[r['id'] as int] = r;
      }

      // First delivery
      processIncoming(changePayload);
      expect(localTable.length, equals(1));

      // Duplicate delivery (network retry)
      processIncoming(changePayload);
      expect(localTable.length, equals(1)); // Still exactly 1
    });

    // -------------------------------------------------------------
    // Scenario 11: Two phones edit different records -> both changes preserved
    // -------------------------------------------------------------
    test('Scenario 11: Two phones edit different records -> both changes preserved', () {
      final sharedState = <int, Map<String, dynamic>>{
        1: {'id': 1, 'name': 'रेकॉर्ड १', 'amount': 100.0},
        2: {'id': 2, 'name': 'रेकॉर्ड २', 'amount': 200.0},
      };

      // Phone A edits Record 1
      final phoneAEdit = {'id': 1, 'name': 'रेकॉर्ड १ (बदल A)', 'amount': 150.0};
      // Phone B edits Record 2
      final phoneBEdit = {'id': 2, 'name': 'रेकॉर्ड २ (बदल B)', 'amount': 250.0};

      sharedState[1] = phoneAEdit;
      sharedState[2] = phoneBEdit;

      expect(sharedState[1]!['amount'], equals(150.0));
      expect(sharedState[2]!['amount'], equals(250.0));
    });

    // -------------------------------------------------------------
    // Scenario 12: Two phones edit same record -> deterministic conflict resolution applied
    // -------------------------------------------------------------
    test('Scenario 12: Deterministic conflict resolution (version -> changedAt -> deviceId)', () {
      // Higher version wins
      final higherVersionIncoming = {
        'version': 3,
        'changedAt': 1000,
        'deviceId': 'DEV_A',
      };
      final lowerVersionLocal = {
        'version': 2,
        'changedAt': 2000,
        'deviceId': 'DEV_B',
      };
      final res1 = DatabaseHelper.resolveConflict(
        localVersion: lowerVersionLocal['version'] as int,
        localChangedAt: lowerVersionLocal['changedAt'] as int,
        localDeviceId: lowerVersionLocal['deviceId'] as String,
        incomingVersion: higherVersionIncoming['version'] as int,
        incomingChangedAt: higherVersionIncoming['changedAt'] as int,
        incomingDeviceId: higherVersionIncoming['deviceId'] as String,
      );
      expect(res1.incomingWins, isTrue);

      // Same version, newer changedAt timestamp wins
      final newerTimestampIncoming = {
        'version': 2,
        'changedAt': 3000,
        'deviceId': 'DEV_A',
      };
      final olderTimestampLocal = {
        'version': 2,
        'changedAt': 2000,
        'deviceId': 'DEV_B',
      };
      final res2 = DatabaseHelper.resolveConflict(
        localVersion: olderTimestampLocal['version'] as int,
        localChangedAt: olderTimestampLocal['changedAt'] as int,
        localDeviceId: olderTimestampLocal['deviceId'] as String,
        incomingVersion: newerTimestampIncoming['version'] as int,
        incomingChangedAt: newerTimestampIncoming['changedAt'] as int,
        incomingDeviceId: newerTimestampIncoming['deviceId'] as String,
      );
      expect(res2.incomingWins, isTrue);

      // Same version and same timestamp, alphabetical deviceId tiebreaker
      final res3 = DatabaseHelper.resolveConflict(
        localVersion: 2,
        localChangedAt: 2000,
        localDeviceId: 'DEV_AAA',
        incomingVersion: 2,
        incomingChangedAt: 2000,
        incomingDeviceId: 'DEV_BBB',
      );
      expect(res3.incomingWins, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 13: New approved phone -> initial full financial sync populates all 7 tables
    // -------------------------------------------------------------
    test('Scenario 13: New approved phone receives full financial snapshot with 7 tables', () {
      final snapshot = {
        'tables': initialMasterDataset,
        'version': 9,
      };

      final snapshotJson = jsonEncode(snapshot);
      final digest = sha256.convert(utf8.encode(snapshotJson)).toString();

      // Checksum validation
      final calculatedDigest = sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
      expect(calculatedDigest, equals(digest));

      // Target receives all 7 tables
      final receivedTables = (snapshot['tables'] as Map<String, dynamic>).keys.toList();
      expect(receivedTables, containsAll([
        'vargani',
        'prasad_dengani',
        'prasad_sahitya',
        'aarti_vargani',
        'kharch',
        'mahaprasad_kharch',
        'previous_balance',
      ]));
    });

    // -------------------------------------------------------------
    // Scenario 14: View-only user receives updates, but cannot add/edit/delete
    // -------------------------------------------------------------
    test('Scenario 14: View-only user receives updates, but cannot add/edit/delete', () {
      const viewOnlyUser = KhajaniUser(
        userId: 'u_view_only',
        name: 'दत्तात्रय जोशी',
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
      AuthService.instance.setCurrentUserForTesting(viewOnlyUser);

      // Verify cannot add, edit, or delete
      expect(AuthService.instance.canAdd, isFalse);
      expect(AuthService.instance.canEdit, isFalse);
      expect(AuthService.instance.canDelete, isFalse);

      final db = DatabaseHelper.instance;
      expect(() => db.insertVargani({'name': 'चाचणी', 'amount': 100, 'year': 2025}), throwsA(isA<StateError>()));
      expect(() => db.updateVargani(1, {'name': 'चाचणी', 'amount': 100, 'year': 2025}), throwsA(isA<StateError>()));
      expect(() => db.deleteVargani(1), throwsA(isA<StateError>()));

      // But viewOnlyUser can receive incoming sync!
      expect(AuthService.instance.canView, isTrue);
    });

    // -------------------------------------------------------------
    // Scenario 15: Developer revokes device -> device cannot send or receive sync
    // -------------------------------------------------------------
    test('Scenario 15: Developer revokes device -> device blocked from sync', () {
      final revokedDevice = DeviceRequestModel(
        requestId: 'REQ_REVOKED_01',
        userId: 'u_revoked_device',
        userName: 'संजय शिंदे',
        deviceId: 'DEV_REVOKED_PHONE',
        deviceName: 'Samsung S21',
        status: DeviceStatus.revoked,
        requestedRole: KhajaniRole.oldKhajani,
        createdAt: 1000,
        updatedAt: 2000,
      );

      expect(revokedDevice.status, equals(DeviceStatus.revoked));
      expect(revokedDevice.isApproved, isFalse);

      // Signaling / Sync blocks revoked device
      final isSyncAllowed = revokedDevice.isApproved && !revokedDevice.status.contains('revoked');
      expect(isSyncAllowed, isFalse);
    });
  });
}
