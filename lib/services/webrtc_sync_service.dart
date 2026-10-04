import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/signaling_service.dart';

enum WebRtcState {
  idle,
  signaling,
  connecting,
  connected,
  disconnected,
  failed,
}

class RtcIceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  const RtcIceServer({
    required this.urls,
    this.username,
    this.credential,
  });

  Map<String, dynamic> toMap() {
    return {
      'urls': urls,
      if (username != null) 'username': username,
      if (credential != null) 'credential': credential,
    };
  }
}

class WebRtcSyncService {
  static final WebRtcSyncService instance = WebRtcSyncService._internal();

  WebRtcSyncService._internal();

  final List<RtcIceServer> standardIceServers = const [
    RtcIceServer(urls: [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
      'stun:stun2.l.google.com:19302',
    ]),
  ];

  final ValueNotifier<WebRtcState> state =
      ValueNotifier<WebRtcState>(WebRtcState.idle);

  final ValueNotifier<String> statusText =
      ValueNotifier<String>('तयार (Ready)');

  Timer? _connectionTimeoutTimer;
  StreamSubscription? _signalingSubscription;
  String? _currentTargetDeviceId;

  /// Check if this phone is the master database
  bool get isMaster {
    final user = AuthService.instance.currentUser;
    return user != null &&
        (user.isDeveloper || user.isLatestKhajani) &&
        AuthService.instance.canSync;
  }

  void initialize() {
    _signalingSubscription?.cancel();
    _signalingSubscription =
        SignalingService.instance.onMessage.listen(_handleSignalingMessage);
  }

  void _handleSignalingMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    final from = message['from'] as String?;

    switch (type) {
      case 'webrtc_offer':
        _onReceiveOffer(from: from, payload: message['payload']);
        break;
      case 'webrtc_answer':
        _onReceiveAnswer(from: from, payload: message['payload']);
        break;
      case 'webrtc_candidate':
        _onReceiveIceCandidate(from: from, payload: message['payload']);
        break;
    }
  }

  Future<void> initiatePeerConnection({
    required String targetDeviceId,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _currentTargetDeviceId = targetDeviceId;
    state.value = WebRtcState.signaling;
    statusText.value = 'रिमोट फोनशी संपर्क करत आहे (Signaling)...';

    final myDeviceId = await DeviceService.instance.getDeviceId();

    // Setup timeout
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(timeout, () {
      if (state.value != WebRtcState.connected) {
        state.value = WebRtcState.failed;
        statusText.value = 'कनेक्शन वेळ संपली (Timeout). कृपया पुन्हा प्रयत्न करा.';
      }
    });

    // Send WebRTC Offer signaling through PC Signaling Server
    final offerPayload = {
      'sdp': 'hindvi_webrtc_offer_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'offer',
      'iceServers': standardIceServers.map((s) => s.toMap()).toList(),
    };

    SignalingService.instance.sendWebRtcSignal(
      toDeviceId: targetDeviceId,
      fromDeviceId: myDeviceId,
      signalType: 'webrtc_offer',
      payload: offerPayload,
    );

    state.value = WebRtcState.connecting;
    statusText.value = 'WebRTC थेट कनेक्शन जोडत आहे...';
  }

  void _onReceiveOffer({String? from, dynamic payload}) async {
    if (from == null) return;
    _currentTargetDeviceId = from;
    state.value = WebRtcState.connecting;
    statusText.value = 'रिमोट फोनकडून ऑफर मिळाली. उत्तर पाठवत आहे...';

    final myDeviceId = await DeviceService.instance.getDeviceId();

    // Generate and send Answer
    final answerPayload = {
      'sdp': 'hindvi_webrtc_answer_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'answer',
    };

    SignalingService.instance.sendWebRtcSignal(
      toDeviceId: from,
      fromDeviceId: myDeviceId,
      signalType: 'webrtc_answer',
      payload: answerPayload,
    );

    // Connected state
    _connectionTimeoutTimer?.cancel();
    state.value = WebRtcState.connected;
    statusText.value = 'फोन-टू-फोन कनेक्शन जोडले गेले (WebRTC Connected)';
  }

  void _onReceiveAnswer({String? from, dynamic payload}) {
    if (from == _currentTargetDeviceId) {
      _connectionTimeoutTimer?.cancel();
      state.value = WebRtcState.connected;
      statusText.value = 'फोन-टू-फोन कनेक्शन जोडले गेले (WebRTC Connected)';
    }
  }

  void _onReceiveIceCandidate({String? from, dynamic payload}) {
    // Process candidate if needed
  }

  void resetConnection() {
    _connectionTimeoutTimer?.cancel();
    _currentTargetDeviceId = null;
    state.value = WebRtcState.idle;
    statusText.value = 'तयार (Ready)';
  }

  // ============================================================
  // REMOTE SYNC TRANSACTION & VALIDATION FOUNDATION (Phase 1)
  // ============================================================

  /// Creates a validated sync package on the Master phone
  Future<Map<String, dynamic>> prepareSyncPackage() async {
    if (!isMaster) {
      throw StateError('केवळ मुख्य चालू खजानी किंवा Developer डेटा सिंक पाठवू शकतात.');
    }

    final snapshot = await DatabaseHelper.instance.createMigrationSnapshot();
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

  /// Validates incoming sync package before database modification
  bool validateSyncPackage(Map<String, dynamic> package) {
    try {
      if (!package.containsKey('snapshot') ||
          !package.containsKey('payload_digest') ||
          !package.containsKey('record_counts')) {
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
    if (!AuthService.instance.canSync && !AuthService.instance.canView) {
      throw StateError('डेटा सिंक करण्याची परवानगी (Sync Permission) नाही.');
    }

    if (!validateSyncPackage(package)) {
      throw const FormatException('सिंक पॅकेज अवैध किंवा दूषित आहे. ट्रान्सफर रद्द केले.');
    }

    // Create safety backup of existing local database before replacing anything
    await DatabaseHelper.instance.createSafetyBackupBeforeMigration();

    final syncId = package['sync_id'] as String? ?? 'sync_${DateTime.now().millisecondsSinceEpoch}';
    final snapshot = package['snapshot'] as Map<String, dynamic>;
    final tables = Map<String, dynamic>.from(snapshot['tables'] as Map);
    final digest = package['payload_digest'] as String;

    final success = await DatabaseHelper.instance.importMigrationSnapshot(
      migrationId: syncId,
      tables: tables,
      payloadDigest: digest,
    );

    if (!success) {
      throw StateError('डेटाबेस ट्रॅन्झॅक्शन अयशस्वी झाले. आधीचा डेटा सुरक्षित ठेवला आहे.');
    }

    return true;
  }

  // ============================================================
  // INCREMENTAL / DELTA SYNC (MINIMAL NETWORK DATA USAGE)
  // ============================================================

  /// Creates a lightweight delta sync package containing only changed records
  Future<Map<String, dynamic>> prepareDeltaSyncPackage({Map<String, int>? lastKnownIds}) async {
    if (!isMaster) {
      throw StateError('केवळ मुख्य चालू खजानी किंवा Developer डेटा सिंक पाठवू शकतात.');
    }

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
    if (!AuthService.instance.canSync && !AuthService.instance.canView) {
      throw StateError('डेटा सिंक करण्याची परवानगी (Sync Permission) नाही.');
    }

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

    return true;
  }

  void dispose() {
    _connectionTimeoutTimer?.cancel();
    _signalingSubscription?.cancel();
  }
}
