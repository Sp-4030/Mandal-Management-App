// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/signaling_service.dart';

class RemoteSyncService {
  static final RemoteSyncService instance = RemoteSyncService._internal();

  RemoteSyncService._internal();

  StreamSubscription? _signalingSubscription;
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<String> syncStatusText = ValueNotifier<String>('तयार (Ready)');

  final StreamController<Map<String, int>> _syncCompletedController =
      StreamController<Map<String, int>>.broadcast();

  Stream<Map<String, int>> get onSyncCompleted => _syncCompletedController.stream;

  // Buffer for assembling chunked sync transfers: syncId -> List of chunks
  final Map<String, Map<int, String>> _chunkBuffers = {};
  final Map<String, int> _chunkExpectedTotals = {};

  // Completer for active sync request on Target phone
  Completer<bool>? _activeSyncCompleter;

  /// Helper to format actual record counts for debug logs
  static String formatCounts(Map<String, int> counts) {
    return 'Vargani: ${counts['vargani'] ?? 0} records, '
        'Prasad Dengani: ${counts['prasad_dengani'] ?? 0} records, '
        'Prasad Sahitya: ${counts['prasad_sahitya'] ?? 0} records, '
        'Aarti Vargani: ${counts['aarti_vargani'] ?? 0} records, '
        'Kharch: ${counts['kharch'] ?? 0} records, '
        'Mahaprasad Kharch: ${counts['mahaprasad_kharch'] ?? 0} records, '
        'Previous Balance: ${counts['previous_balance'] ?? 0} records';
  }

  /// Whether this phone is the MASTER financial database
  bool get isMaster {
    final user = AuthService.instance.currentUser;
    if (user != null) {
      if (user.isOldKhajani) return false;
      if (user.isLatestKhajani) return true;
      if (user.isDeveloper) return true;
    }
    return false;
  }

  /// Initialize listener for remote sync signaling messages
  void initialize() {
    _signalingSubscription?.cancel();
    _signalingSubscription = SignalingService.instance.onMessage.listen(_handleIncomingMessage);
  }

  void dispose() {
    _signalingSubscription?.cancel();
    _syncCompletedController.close();
  }

  void _handleIncomingMessage(Map<String, dynamic> message) async {
    final type = message['type'] as String?;
    switch (type) {
      case 'sync_request':
        await _handleIncomingSyncRequest(message);
        break;

      case 'sync_data':
        await _handleIncomingSyncData(message);
        break;

      case 'sync_chunk':
        await _handleIncomingSyncChunk(message);
        break;

      case 'sync_ack':
        _handleIncomingSyncAck(message);
        break;

      case 'sync_status':
        _handleIncomingSyncStatus(message);
        break;
    }
  }

  // ============================================================
  // MASTER PHONE: RECEIVE REQUEST & SEND FINANCIAL DATA
  // ============================================================

  Future<void> _handleIncomingSyncRequest(Map<String, dynamic> request) async {
    // Only the Master phone responds to sync requests
    if (!isMaster) return;

    final requesterDeviceId = request['requesterDeviceId'] as String?;
    final requesterUserId = request['requesterUserId'] as String?;
    final isDelta = request['isDelta'] as bool? ?? false;
    final lastKnownIdsRaw = request['lastKnownIds'] as Map<String, dynamic>?;
    final Map<String, int>? lastKnownIds = lastKnownIdsRaw?.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );

    if (requesterDeviceId == null || requesterDeviceId.isEmpty) return;

    final myDeviceId = await DeviceService.instance.getDeviceId();
    final syncId = 'sync_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // STAGE 1: SYNC_STARTED
      print('[SYNC_STARTED] requestId=$syncId requester=$requesterDeviceId user=${requesterUserId ?? "unknown"}');

      // STAGE 2: MASTER_DATA_READ
      final actualDbCounts = await DatabaseHelper.instance.getTableRecordCounts();
      print('[MASTER_DATA_READ] ${formatCounts(actualDbCounts)}');

      // Prepare snapshot (Delta or Full)
      final Map<String, dynamic> snapshot;
      int totalRecords = 0;
      if (isDelta && lastKnownIds != null) {
        snapshot = await DatabaseHelper.instance.createDeltaSnapshot(lastKnownIds: lastKnownIds);
        totalRecords = (snapshot['totalDeltaCount'] as num?)?.toInt() ?? 0;
      } else {
        snapshot = await DatabaseHelper.instance.createFinancialSnapshot();
        totalRecords = actualDbCounts.values.fold<int>(0, (sum, count) => sum + count);
      }

      // STAGE 3: DATA_SERIALIZED
      final jsonStr = jsonEncode(snapshot);
      final digest = sha256.convert(utf8.encode(jsonStr)).toString();
      print('[DATA_SERIALIZED] ${formatCounts(actualDbCounts)}');

      // STAGE 4: DATA_SENT
      print('[DATA_SENT] to=$requesterDeviceId, ${formatCounts(actualDbCounts)}');

      // If payload is larger than 45KB, split into chunks for safe transmission
      const chunkSize = 40000;
      if (jsonStr.length > chunkSize) {
        final totalChunks = (jsonStr.length / chunkSize).ceil();
        for (var i = 0; i < totalChunks; i++) {
          final start = i * chunkSize;
          final end = (start + chunkSize < jsonStr.length) ? start + chunkSize : jsonStr.length;
          final chunkPiece = jsonStr.substring(start, end);

          SignalingService.instance.sendSyncChunk(
            toDeviceId: requesterDeviceId,
            fromDeviceId: myDeviceId,
            syncId: syncId,
            chunkIndex: i,
            totalChunks: totalChunks,
            chunkData: chunkPiece,
          );
        }
      } else {
        SignalingService.instance.sendSyncData(
          toDeviceId: requesterDeviceId,
          fromDeviceId: myDeviceId,
          syncId: syncId,
          isDelta: isDelta,
          recordCounts: actualDbCounts,
          totalRecords: totalRecords,
          snapshot: snapshot,
          payloadDigest: digest,
        );
      }
    } catch (e) {
      print('[ERROR_MASTER_SYNC] Failed to prepare or send sync data: $e');
    }
  }

  void _handleIncomingSyncAck(Map<String, dynamic> message) {
    final from = message['from'];
    final status = message['status'];
    print('[SYNC_ACK_RECEIVED] from=$from status=$status');
  }

  void _handleIncomingSyncStatus(Map<String, dynamic> message) {
    final status = message['status'] as String?;
    final msg = message['message'] as String? ?? 'मास्टर फोन ऑफलाइन आहे';
    syncStatusText.value = msg;
    if (status == 'MASTER_OFFLINE') {
      if (_activeSyncCompleter != null && !_activeSyncCompleter!.isCompleted) {
        _activeSyncCompleter!.complete(false);
      }
      isSyncing.value = false;
    }
  }

  // ============================================================
  // TARGET PHONE: RECEIVE & APPLY FINANCIAL DATA TO SQLITE
  // ============================================================

  Future<void> _handleIncomingSyncChunk(Map<String, dynamic> message) async {
    final syncId = message['syncId'] as String?;
    final chunkIndex = (message['chunkIndex'] as num?)?.toInt();
    final totalChunks = (message['totalChunks'] as num?)?.toInt();
    final chunkData = message['chunkData'] as String?;

    if (syncId == null || chunkIndex == null || totalChunks == null || chunkData == null) {
      return;
    }

    _chunkBuffers.putIfAbsent(syncId, () => <int, String>{});
    _chunkBuffers[syncId]![chunkIndex] = chunkData;
    _chunkExpectedTotals[syncId] = totalChunks;

    if (_chunkBuffers[syncId]!.length == totalChunks) {
      // Reassemble all chunks in sequential order
      final buffer = StringBuffer();
      for (var i = 0; i < totalChunks; i++) {
        buffer.write(_chunkBuffers[syncId]![i] ?? '');
      }
      _chunkBuffers.remove(syncId);
      _chunkExpectedTotals.remove(syncId);

      try {
        final fullJson = buffer.toString();
        final snapshot = jsonDecode(fullJson) as Map<String, dynamic>;
        final digest = sha256.convert(utf8.encode(fullJson)).toString();

        final syntheticPayload = {
          'type': 'sync_data',
          'to': message['to'],
          'from': message['from'],
          'syncId': syncId,
          'isDelta': snapshot['isDelta'] ?? false,
          'recordCounts': snapshot['tableCounts'] ?? {},
          'snapshot': snapshot,
          'payloadDigest': digest,
        };

        await _handleIncomingSyncData(syntheticPayload);
      } catch (e) {
        print('[ERROR_CHUNK_ASSEMBLY] Failed to parse reassembled sync data: $e');
      }
    }
  }

  Future<void> _handleIncomingSyncData(Map<String, dynamic> message) async {
    final fromDeviceId = (message['from'] ?? 'MASTER') as String;
    final syncId = (message['syncId'] ?? 'sync_${DateTime.now().millisecondsSinceEpoch}') as String;
    final isDelta = message['isDelta'] as bool? ?? false;
    final snapshot = message['snapshot'] as Map<String, dynamic>?;
    final payloadDigest = message['payloadDigest'] as String? ?? '';
    final countsRaw = message['recordCounts'] as Map<String, dynamic>? ?? {};

    if (snapshot == null) return;

    final myDeviceId = await DeviceService.instance.getDeviceId();
    final counts = countsRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    try {
      isSyncing.value = true;
      syncStatusText.value = 'डेटा मिळाला, तपासत आहे...';

      // STAGE 6: TARGET_RECEIVED
      print('[TARGET_RECEIVED] from=$fromDeviceId, ${formatCounts(counts)}');

      // STAGE 7: DATA_VALIDATED
      final jsonString = jsonEncode(snapshot);
      final computedDigest = sha256.convert(utf8.encode(jsonString)).toString();

      final tables = snapshot['tables'] as Map<String, dynamic>?;
      if (tables == null) {
        throw const FormatException('Snapshot missing tables field');
      }

      if (computedDigest != payloadDigest) {
        throw const FormatException('Payload checksum mismatch');
      }

      print('[DATA_VALIDATED] ${formatCounts(counts)}');

      // STAGE 8: SQLITE_TRANSACTION_STARTED
      print('[SQLITE_TRANSACTION_STARTED] ${formatCounts(counts)}');

      // STAGE 9 & 10: DATA_INSERTED/UPDATED & SQLITE_COMMITTED
      bool success = false;
      if (isDelta) {
        success = await DatabaseHelper.instance.importDeltaSnapshot(
          syncId: syncId,
          deltaTables: tables,
          payloadDigest: payloadDigest,
        );
      } else {
        success = await DatabaseHelper.instance.importFinancialSnapshot(
          syncId: syncId,
          tables: tables,
          payloadDigest: payloadDigest,
        );
      }

      if (!success) {
        throw StateError('Database transaction failed and was rolled back');
      }

      // Query actual counts saved in local SQLite
      final actualLocalCounts = await DatabaseHelper.instance.getTableRecordCounts();

      print('[DATA_INSERTED/UPDATED] ${formatCounts(actualLocalCounts)}');
      print('[SQLITE_COMMITTED] ${formatCounts(actualLocalCounts)}');

      // Send ACK back to Master
      SignalingService.instance.sendSyncAck(
        toDeviceId: fromDeviceId,
        fromDeviceId: myDeviceId,
        syncId: syncId,
        status: 'SUCCESS',
        recordCounts: actualLocalCounts,
      );

      // STAGE 11: SYNC_COMPLETED
      print('[SYNC_COMPLETED] ${formatCounts(actualLocalCounts)}');

      // STAGE 12: UI_REFRESHED
      _syncCompletedController.add(actualLocalCounts);
      print('[UI_REFRESHED] ${formatCounts(actualLocalCounts)}');

      syncStatusText.value = 'डेटा यशस्वीपणे सिंक झाला!';
      if (_activeSyncCompleter != null && !_activeSyncCompleter!.isCompleted) {
        _activeSyncCompleter!.complete(true);
      }
    } catch (e) {
      print('[SYNC_ERROR] Sync application failed with rollback: $e');
      syncStatusText.value = 'सिंक अयशस्वी झाले: $e';
      SignalingService.instance.sendSyncAck(
        toDeviceId: fromDeviceId,
        fromDeviceId: myDeviceId,
        syncId: syncId,
        status: 'FAILED',
        message: e.toString(),
      );
      if (_activeSyncCompleter != null && !_activeSyncCompleter!.isCompleted) {
        _activeSyncCompleter!.complete(false);
      }
    } finally {
      isSyncing.value = false;
    }
  }

  // ============================================================
  // PUBLIC CLIENT METHOD: REQUEST SYNC FROM MASTER
  // ============================================================

  Future<bool> requestSyncFromMaster({
    bool forceFull = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!AuthService.instance.canView) {
      throw StateError('माहिती पाहण्याची किंवा सिंक करण्याची परवानगी (View Permission) नाही.');
    }

    if (isMaster) {
      // Master phone already holds the master SQLite database
      return true;
    }

    isSyncing.value = true;
    syncStatusText.value = 'मास्टर फोनकडून डेटा मागवत आहे...';

    final myDeviceId = await DeviceService.instance.getDeviceId();
    final user = AuthService.instance.currentUser;

    final localCounts = await DatabaseHelper.instance.getTableRecordCounts();
    final hasExistingRecords = localCounts.values.any((c) => c > 0);
    final isDelta = hasExistingRecords && !forceFull;

    Map<String, int>? lastKnownIds;
    if (isDelta) {
      lastKnownIds = await DatabaseHelper.instance.getLatestKnownIds();
    }

    // STAGE 1: SYNC_STARTED
    final reqSyncId = 'req_sync_${DateTime.now().millisecondsSinceEpoch}';
    print('[SYNC_STARTED] requestId=$reqSyncId requester=$myDeviceId target=MASTER (isDelta=$isDelta)');

    _activeSyncCompleter = Completer<bool>();

    if (!SignalingService.instance.isConnected) {
      final connected = await SignalingService.instance.connect();
      if (!connected) {
        isSyncing.value = false;
        syncStatusText.value = 'PC सर्व्हरशी संपर्क होऊ शकला नाही.';
        return false;
      }
    }

    SignalingService.instance.sendSyncRequest(
      requesterDeviceId: myDeviceId,
      requesterUserId: user?.userId ?? '',
      requesterRole: user?.role ?? 'CLIENT',
      isDelta: isDelta,
      lastKnownIds: lastKnownIds,
    );

    try {
      final result = await _activeSyncCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          syncStatusText.value = 'सिंक वेळ संपली (Timeout). कृपया पुन्हा प्रयत्न करा.';
          return false;
        },
      );
      return result;
    } catch (_) {
      return false;
    } finally {
      isSyncing.value = false;
    }
  }

  // ============================================================
  // METHODS FOR TESTING & DIRECT USE
  // ============================================================

  /// Creates a validated sync package on the Master phone
  Future<Map<String, dynamic>> prepareSyncPackage() async {
    final snapshot = await DatabaseHelper.instance.createFinancialSnapshot();
    final jsonString = jsonEncode(snapshot);
    final digest = sha256.convert(utf8.encode(jsonString)).toString();
    final counts = await DatabaseHelper.instance.getTableRecordCounts();

    return {
      'sync_id': 'sync_${DateTime.now().millisecondsSinceEpoch}',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'master_device_id': await DeviceService.instance.getDeviceId(),
      'payload_digest': digest,
      'record_counts': counts,
      'snapshot': snapshot,
    };
  }

  /// Creates a lightweight delta sync package containing only changed records
  Future<Map<String, dynamic>> prepareDeltaSyncPackage({Map<String, int>? lastKnownIds}) async {
    final deltaSnapshot = await DatabaseHelper.instance.createDeltaSnapshot(lastKnownIds: lastKnownIds);
    final jsonString = jsonEncode(deltaSnapshot);
    final digest = sha256.convert(utf8.encode(jsonString)).toString();
    final counts = await DatabaseHelper.instance.getTableRecordCounts();

    return {
      'sync_id': 'delta_sync_${DateTime.now().millisecondsSinceEpoch}',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'master_device_id': await DeviceService.instance.getDeviceId(),
      'payload_digest': digest,
      'is_delta': true,
      'delta_record_count': deltaSnapshot['totalDeltaCount'] ?? 0,
      'record_counts': counts,
      'snapshot': deltaSnapshot,
    };
  }

  /// Validates incoming sync package before database modification
  bool validateSyncPackage(Map<String, dynamic> package) {
    try {
      if (!package.containsKey('snapshot') ||
          !package.containsKey('payload_digest')) {
        return false;
      }

      final snapshot = package['snapshot'] as Map<String, dynamic>;
      final expectedDigest = package['payload_digest'] as String;

      final jsonString = jsonEncode(snapshot);
      final computedDigest = sha256.convert(utf8.encode(jsonString)).toString();

      if (computedDigest != expectedDigest) {
        return false;
      }

      final tables = snapshot['tables'] as Map<String, dynamic>?;
      if (tables == null) return false;

      // Ensure all required financial tables exist in snapshot
      for (final table in DatabaseHelper.migrationDataTables) {
        if (!tables.containsKey(table)) {
          return false;
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Safely applies sync package with automatic rollback on error
  Future<bool> applySyncPackageSafely(Map<String, dynamic> package) async {
    if (!validateSyncPackage(package)) {
      throw const FormatException('सिंक पॅकेज अवैध किंवा दूषित आहे. ट्रान्सफर रद्द केले.');
    }

    final syncId = package['sync_id'] as String? ?? 'sync_${DateTime.now().millisecondsSinceEpoch}';
    final snapshot = package['snapshot'] as Map<String, dynamic>;
    final tables = Map<String, dynamic>.from(snapshot['tables'] as Map);
    final digest = package['payload_digest'] as String;

    final success = await DatabaseHelper.instance.importFinancialSnapshot(
      syncId: syncId,
      tables: tables,
      payloadDigest: digest,
    );

    if (!success) {
      throw StateError('डेटाबेस ट्रॅन्झॅक्शन अयशस्वी झाले. आधीचा डेटा सुरक्षित ठेवला आहे.');
    }

    final counts = await DatabaseHelper.instance.getTableRecordCounts();
    _syncCompletedController.add(counts);

    return true;
  }

  /// Validates incoming delta sync package
  bool validateDeltaSyncPackage(Map<String, dynamic> package) {
    try {
      if (!package.containsKey('snapshot') ||
          !package.containsKey('payload_digest') ||
          !package.containsKey('sync_id')) {
        return false;
      }

      final snapshot = package['snapshot'] as Map<String, dynamic>;
      final expectedDigest = package['payload_digest'] as String;

      final jsonString = jsonEncode(snapshot);
      final computedDigest = sha256.convert(utf8.encode(jsonString)).toString();

      if (computedDigest != expectedDigest) {
        return false;
      }

      final tables = snapshot['tables'] as Map<String, dynamic>?;
      return tables != null;
    } catch (_) {
      return false;
    }
  }

  /// Safely applies delta sync package without wiping existing records
  Future<bool> applyDeltaSyncPackageSafely(Map<String, dynamic> package) async {
    if (!validateDeltaSyncPackage(package)) {
      throw const FormatException('डेल्टा सिंक पॅकेज अवैध किंवा दूषित आहे. ट्रान्सफर रद्द केले.');
    }

    final syncId = package['sync_id'] as String? ?? 'delta_sync_${DateTime.now().millisecondsSinceEpoch}';
    final snapshot = package['snapshot'] as Map<String, dynamic>;
    final tables = Map<String, dynamic>.from(snapshot['tables'] as Map);
    final digest = package['payload_digest'] as String;

    final success = await DatabaseHelper.instance.importDeltaSnapshot(
      syncId: syncId,
      deltaTables: tables,
      payloadDigest: digest,
    );

    if (!success) {
      throw StateError('डेल्टा सिंक अयशस्वी झाले.');
    }

    final counts = await DatabaseHelper.instance.getTableRecordCounts();
    _syncCompletedController.add(counts);

    return true;
  }
}
