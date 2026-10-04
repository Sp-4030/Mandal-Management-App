// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/device_model.dart';
import '../models/khajani_user.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'remote_sync_service.dart';

enum SignalingConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class SignalingService {
  static final SignalingService instance = SignalingService._internal();

  SignalingService._internal();

  static const String defaultServerUrl = 'wss://amino-dropkick-resample.ngrok-free.dev';

  /// Exponential backoff schedule as specified: 5s → 10s → 30s → 60s
  static const List<Duration> reconnectBackoffSchedule = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  /// Maximum allowed payload size (64 KB) for WebSocket frames (large transfers are chunked)
  static const int maxPayloadBytes = 65536;

  /// Lazy heartbeat check interval (60 seconds)
  static const Duration heartbeatInterval = Duration(seconds: 60);

  /// Idle connection timeout (2 minutes) for clients not in persistent mode
  static const Duration idleTimeout = Duration(minutes: 2);

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _idleTimer;

  bool _isDisposed = false;
  bool _manualDisconnect = false;
  bool _persistentMode = false;

  int _reconnectAttempt = 0;
  DateTime _lastTrafficTime = DateTime.now();

  // Deduplication caches to prevent duplicate network broadcasts and UI notifications
  final Set<String> _sentRequestIds = <String>{};
  final Set<String> _processedRequestIds = <String>{};

  final ValueNotifier<SignalingConnectionState> connectionState =
      ValueNotifier<SignalingConnectionState>(SignalingConnectionState.disconnected);

  final ValueNotifier<String> connectionStatusText =
      ValueNotifier<String>('सर्व्हर बंद आहे');

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  bool get isConnected => connectionState.value == SignalingConnectionState.connected;

  String get serverUrl => _serverUrl ?? defaultServerUrl;

  int get reconnectAttempt => _reconnectAttempt;

  bool get isPersistentMode => _persistentMode;

  Duration get currentBackoffDelay {
    if (_reconnectAttempt < reconnectBackoffSchedule.length) {
      return reconnectBackoffSchedule[_reconnectAttempt];
    }
    return reconnectBackoffSchedule.last;
  }

  Stream<bool> get isConnectedStream {
    late StreamController<bool> controller;
    void listener() {
      if (!controller.isClosed) {
        controller.add(isConnected);
      }
    }
    controller = StreamController<bool>.broadcast(
      onListen: () {
        controller.add(isConnected);
        connectionState.addListener(listener);
      },
      onCancel: () {
        connectionState.removeListener(listener);
      },
    );
    return controller.stream;
  }

  // Cached server URL
  String? _serverUrl;

  Future<String> getServerUrl() async {
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      return _serverUrl!;
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('server_config', where: 'id = 1', limit: 1);
      if (rows.isNotEmpty) {
        _serverUrl = rows.first['server_url'] as String?;
        if (_serverUrl != null && _serverUrl!.contains('192.168.1.100')) {
          _serverUrl = defaultServerUrl;
          await setServerUrl(defaultServerUrl);
        }
        if (_serverUrl != null && _serverUrl!.isNotEmpty) {
          return _serverUrl!;
        }
      }
    } catch (_) {}

    _serverUrl = defaultServerUrl;
    return defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    _serverUrl = cleanUrl;
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'server_config',
        {
          'id': 1,
          'server_url': cleanUrl,
          'auto_connect': 1,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}

    // Reconnect to new URL if currently connected or connecting
    if (isConnected) {
      disconnect();
      await connect();
    }
  }

  /// Sets whether this client requires a persistent connection (e.g. Developer waiting for requests)
  void setPersistentMode(bool persistent) {
    _persistentMode = persistent;
    if (_persistentMode) {
      _idleTimer?.cancel();
    } else if (isConnected) {
      _resetIdleTimer();
    }
  }

  Future<bool> connect({
    Duration timeout = const Duration(seconds: 5),
    String? overrideUrl,
  }) async {
    if (isConnected) return true;

    _manualDisconnect = false;
    connectionState.value = SignalingConnectionState.connecting;
    connectionStatusText.value = 'PC सर्व्हरशी जोडत आहे...';

    final targetUrl = overrideUrl ?? await getServerUrl();

    try {
      _socket = await WebSocket.connect(targetUrl).timeout(timeout);

      connectionState.value = SignalingConnectionState.connected;
      connectionStatusText.value = 'PC सर्व्हर जोडला आहे (Connected)';

      // Reset exponential backoff on successful connection
      _reconnectAttempt = 0;
      _lastTrafficTime = DateTime.now();

      _socket!.listen(
        _handleIncomingMessage,
        onDone: _handleSocketDone,
        onError: _handleSocketError,
        cancelOnError: true,
      );

      // Start lazy, low-traffic heartbeat (every 60s, only if idle)
      _startLazyPingHeartbeat();

      // Reset idle timer if not in persistent mode
      if (!_persistentMode) {
        _resetIdleTimer();
      }

      // Auto-register client with current deviceId, userId, requestId, role, isMaster
      try {
        final devId = await DeviceService.instance.getDeviceId();
        final user = AuthService.instance.currentUser;
        final pendingReq = await DeviceService.instance.getLatestPendingRequest();
        final isMasterPhone = (user?.isLatestKhajani ?? false) && !AuthService.instance.isOldKhajani;
        registerClient(
          role: AuthService.instance.isDeveloper ? 'DEVELOPER' : (isMasterPhone ? 'MASTER' : 'CLIENT'),
          deviceId: devId,
          userId: user?.userId ?? pendingReq?.userId,
          userName: user?.name ?? pendingReq?.userName,
          requestId: pendingReq?.requestId,
          isMaster: isMasterPhone,
          userRole: user?.role,
        );
      } catch (_) {}

      // Flush any offline requests that are pending locally
      _flushPendingLocalRequests();

      // Flush any pending financial sync queue
      try {
        RemoteSyncService.instance.processPendingSyncQueue();
      } catch (_) {}

      return true;
    } catch (e) {
      connectionState.value = SignalingConnectionState.error;
      connectionStatusText.value = 'सर्व्हरशी संपर्क होऊ शकला नाही';
      _scheduleReconnect();
      return false;
    }
  }

  /// Low-traffic lazy heartbeat: only sends ping if no traffic occurred in the last 60s
  void _startLazyPingHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(heartbeatInterval, (timer) {
      if (isConnected) {
        final elapsed = DateTime.now().difference(_lastTrafficTime);
        if (elapsed >= heartbeatInterval) {
          sendMessage({'type': 'ping'});
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _resetIdleTimer() {
    if (_persistentMode) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      if (!_persistentMode && isConnected) {
        print('[IDLE_DISCONNECT] Inactive for $idleTimeout. Cleanly closing connection to save network traffic.');
        disconnect();
      }
    });
  }

  void _handleIncomingMessage(dynamic raw) {
    try {
      _lastTrafficTime = DateTime.now();
      _resetIdleTimer();

      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final type = map['type'] as String?;

      if (type == 'pong') {
        return; // Lightweight heartbeat response
      }

      // Deduplicate incoming pending requests on client
      if (type == 'new_pending_request') {
        final reqData = map['request'] as Map<String, dynamic>?;
        final reqId = reqData != null
            ? (reqData['requestId'] ?? reqData['request_id']) as String?
            : null;
        if (reqId != null && _processedRequestIds.contains(reqId)) {
          return;
        }
        if (reqId != null) {
          _processedRequestIds.add(reqId);
        }
      }

      // Handle common signaling events and persistence
      _processSystemEvent(map);

      _messageController.add(map);
    } catch (_) {}
  }

  Future<void> _processSystemEvent(Map<String, dynamic> map) async {
    final type = map['type'] as String?;
    switch (type) {
      case 'new_pending_request':
        final reqData = map['request'] as Map<String, dynamic>?;
        if (reqData != null) {
          await DeviceService.instance.saveIncomingRequestFromSignaling(reqData);
        }
        break;

      case 'pending_requests_list':
        final reqs = map['requests'] as List<dynamic>?;
        if (reqs != null) {
          for (final item in reqs) {
            final reqMap = Map<String, dynamic>.from(item as Map);
            final rId = (reqMap['requestId'] ?? reqMap['request_id']) as String?;
            if (rId != null) {
              _processedRequestIds.add(rId);
            }
            await DeviceService.instance.saveIncomingRequestFromSignaling(reqMap);
          }
        }
        break;

      case 'device_approval_result':
        final status = (map['status'] ?? 'APPROVED') as String;
        final requestId = (map['requestId'] ?? map['request_id'] ?? '') as String;
        final userId = (map['userId'] ?? map['user_id'] ?? '') as String;
        final deviceId = (map['deviceId'] ?? map['device_id'] ?? '') as String;

        if (status == 'APPROVED') {
          // STEP 6: NEW_PHONE_RECEIVED_APPROVAL
          print('[NEW_PHONE_RECEIVED_APPROVAL] requestId=$requestId userId=$userId deviceId=$deviceId status=APPROVED');
          await _applyDeviceApprovalLocally(map);
        }
        break;

      case 'device_rejection_result':
        await _applyDeviceRejectionLocally(map);
        break;

      case 'permissions_updated':
        await _applyPermissionUpdateLocally(map);
        break;

      case 'device_revoked':
        await _applyDeviceRevokeLocally(map);
        break;
    }
  }

  Future<void> _applyDeviceApprovalLocally(Map<String, dynamic> map) async {
    try {
      final status = (map['status'] ?? 'APPROVED') as String;
      final role = (map['role'] ?? map['requestedRole'] ?? 'OLD_KHAJANI') as String;
      final userId = (map['userId'] ?? map['user_id'] ?? '') as String;
      final deviceId = (map['deviceId'] ?? map['device_id'] ?? '') as String;
      final requestId = (map['requestId'] ?? map['request_id'] ?? '') as String;
      final permissionsMap = map['permissions'] as Map<String, dynamic>?;

      if (status != 'APPROVED') return;

      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // STEP 7: Local SQLite transaction
      await db.transaction((txn) async {
        // 1. Update existing pending request in device_requests (DO NOT create duplicate)
        if (requestId.isNotEmpty) {
          await txn.update(
            'device_requests',
            {
              'status': 'APPROVED',
              'updated_at': now,
            },
            where: 'request_id = ?',
            whereArgs: [requestId],
          );
        } else if (userId.isNotEmpty) {
          await txn.update(
            'device_requests',
            {
              'status': 'APPROVED',
              'updated_at': now,
            },
            where: 'user_id = ?',
            whereArgs: [userId],
          );
        }

        // 2. Update user/account status in khajani_users to APPROVED
        if (userId.isNotEmpty) {
          final userUpdateData = <String, dynamic>{
            'role': role,
            'status': 'APPROVED',
            'is_active': 1,
            'updated_at': now,
          };
          if (permissionsMap != null) {
            userUpdateData.addAll(permissionsMap);
          }

          final existingUsers = await txn.query(
            'khajani_users',
            where: 'user_id = ?',
            whereArgs: [userId],
            limit: 1,
          );

          if (existingUsers.isNotEmpty) {
            await txn.update(
              'khajani_users',
              userUpdateData,
              where: 'user_id = ?',
              whereArgs: [userId],
            );
          } else {
            final reqRows = await txn.query(
              'device_requests',
              where: 'user_id = ?',
              whereArgs: [userId],
              limit: 1,
            );
            final userName = reqRows.isNotEmpty
                ? (reqRows.first['user_name'] as String? ?? 'नवीन वापरकर्ता')
                : 'नवीन वापरकर्ता';
            final salt = AuthService.generateSalt();
            userUpdateData['user_id'] = userId;
            userUpdateData['name'] = userName;
            userUpdateData['password_hash'] = '';
            userUpdateData['salt'] = salt;
            userUpdateData['created_at'] = now;
            await txn.insert(
              'khajani_users',
              userUpdateData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // 3. Update device status to APPROVED
        if (deviceId.isNotEmpty) {
          await txn.update(
            'devices',
            {
              'status': 'APPROVED',
              'updated_at': now,
              'last_seen_at': now,
            },
            where: 'device_id = ?',
            whereArgs: [deviceId],
          );
        }

        // 4. Update session in khajani_session
        if (userId.isNotEmpty) {
          await txn.insert(
            'khajani_session',
            {
              'id': 1,
              'user_id': userId,
              'keep_logged_in': 1,
              'logged_in_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      // STEP 7 LOG
      print('[NEW_PHONE_SAVED_APPROVAL_TO_SQLITE] requestId=$requestId userId=$userId deviceId=$deviceId status=APPROVED');

      // STEP 8: NEW_PHONE_REFRESHED_SESSION
      await AuthService.instance.initSession();
      print('[NEW_PHONE_REFRESHED_SESSION] requestId=$requestId userId=$userId deviceId=$deviceId status=APPROVED');
    } catch (e) {
      print('[ERROR] Error applying device approval locally: $e');
    }
  }

  Future<void> _applyDeviceRejectionLocally(Map<String, dynamic> map) async {
    try {
      final userId = map['userId'] as String?;
      final deviceId = map['deviceId'] as String?;
      final requestId = map['requestId'] as String?;

      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (requestId != null && requestId.isNotEmpty) {
        await db.update(
          'device_requests',
          {
            'status': DeviceStatus.rejected,
            'updated_at': now,
          },
          where: 'request_id = ?',
          whereArgs: [requestId],
        );
      } else if (userId != null && userId.isNotEmpty) {
        await db.update(
          'device_requests',
          {
            'status': DeviceStatus.rejected,
            'updated_at': now,
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }

      if (deviceId != null && deviceId.isNotEmpty) {
        await db.update(
          'devices',
          {
            'status': DeviceStatus.rejected,
            'updated_at': now,
          },
          where: 'device_id = ?',
          whereArgs: [deviceId],
        );
      }
    } catch (_) {}
  }

  Future<void> _applyPermissionUpdateLocally(Map<String, dynamic> map) async {
    try {
      final userId = map['userId'] as String?;
      final permissionsMap = map['permissions'] as Map<String, dynamic>?;

      if (userId != null && permissionsMap != null) {
        final db = await DatabaseHelper.instance.database;
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update(
          'khajani_users',
          {
            ...permissionsMap,
            'updated_at': now,
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }
    } catch (_) {}
  }

  Future<void> _applyDeviceRevokeLocally(Map<String, dynamic> map) async {
    try {
      final deviceId = map['deviceId'] as String?;
      if (deviceId != null) {
        final db = await DatabaseHelper.instance.database;
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update(
          'devices',
          {
            'status': DeviceStatus.revoked,
            'updated_at': now,
          },
          where: 'device_id = ?',
          whereArgs: [deviceId],
        );

        final myDeviceId = await DeviceService.instance.getDeviceId();
        if (deviceId == myDeviceId) {
          DatabaseHelper.instance.setDeviceRevokedState(true);
        }
      }
    } catch (_) {}
  }

  void _handleSocketDone() {
    _socket = null;
    _pingTimer?.cancel();
    _idleTimer?.cancel();
    if (!_manualDisconnect) {
      connectionState.value = SignalingConnectionState.disconnected;
      connectionStatusText.value = 'PC सर्व्हरशी संपर्क तुटला';
      _scheduleReconnect();
    }
  }

  void _handleSocketError(dynamic err) {
    _socket = null;
    _pingTimer?.cancel();
    _idleTimer?.cancel();
    connectionState.value = SignalingConnectionState.error;
    connectionStatusText.value = 'सर्व्हर त्रुटी (Server Error)';
    _scheduleReconnect();
  }

  /// Exponential backoff reconnect: 5s → 10s → 30s → 60s
  void _scheduleReconnect() {
    if (_manualDisconnect || _isDisposed) return;
    _reconnectTimer?.cancel();

    final delay = currentBackoffDelay;
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () {
      if (!_manualDisconnect && !isConnected && !_isDisposed) {
        connect();
      }
    });
  }

  /// Sends a JSON message with size protection and traffic timestamping
  void sendMessage(Map<String, dynamic> message) {
    if (!isConnected || _socket == null) return;
    try {
      final encoded = jsonEncode(message);
      if (encoded.length > maxPayloadBytes) {
        print('[REJECTED] Message exceeds 64KB limit. Large files/PDFs cannot be sent over WebSocket.');
        return;
      }
      _socket!.add(encoded);
      _lastTrafficTime = DateTime.now();
      _resetIdleTimer();
    } catch (_) {}
  }

  /// Register this client with signaling server
  void registerClient({
    required String role,
    required String deviceId,
    String? userId,
    String? userName,
    String? requestId,
    bool? isMaster,
    String? userRole,
  }) {
    final payload = <String, dynamic>{
      'type': 'register',
      'role': role,
      'deviceId': deviceId,
      'userId': userId,
      'userName': userName,
      'isMaster': isMaster ?? false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    if (userRole != null) {
      payload['userRole'] = userRole;
    }
    if (requestId != null) {
      payload['requestId'] = requestId;
    }
    sendMessage(payload);
  }

  /// Request pending requests list (for Developer)
  void requestPendingList() {
    sendMessage({'type': 'get_pending_requests'});
  }

  /// Query the current status of an existing request from the server (NO new request is created)
  void checkRequestStatus({
    required String requestId,
    required String userId,
    required String deviceId,
  }) {
    if (!isConnected) {
      connect();
    }
    sendMessage({
      'type': 'check_status',
      'requestId': requestId,
      'userId': userId,
      'deviceId': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send a device request to the server with duplicate transmission prevention
  void sendDeviceRequest(DeviceRequestModel request, {bool forceRetry = false}) {
    if (!forceRetry && _sentRequestIds.contains(request.requestId)) {
      print('[CLIENT_DEDUP] Request ${request.requestId} was already sent. Skipping duplicate transmission.');
      return;
    }

    _sentRequestIds.add(request.requestId);
    final now = DateTime.now().millisecondsSinceEpoch;
    // Standard debugging log: REQUEST_SENDING
    print('[REQUEST_SENDING] requestId=${request.requestId} userId=${request.userId} deviceId=${request.deviceId} timestamp=$now status=SENDING');

    if (!isConnected) {
      // Connect on demand; upon connection, _flushPendingLocalRequests() will forward
      connect();
      return;
    }

    sendMessage({
      'type': 'device_request',
      'requestId': request.requestId,
      'userId': request.userId,
      'userName': request.userName,
      'deviceId': request.deviceId,
      'deviceName': request.deviceName,
      'requestType': request.requestType,
      'requestedRole': request.requestedRole,
      'createdAt': request.createdAt,
    });
  }

  /// Flush local pending requests when WebSocket connects
  Future<void> _flushPendingLocalRequests() async {
    try {
      final pendingReqs = await DeviceService.instance.getDeviceRequests(pendingOnly: true);
      for (final req in pendingReqs) {
        if (!_sentRequestIds.contains(req.requestId)) {
          sendDeviceRequest(req);
        } else {
          // If already sent, check current status from server (Offline Recovery)
          checkRequestStatus(
            requestId: req.requestId,
            userId: req.userId,
            deviceId: req.deviceId,
          );
        }
      }
    } catch (_) {}
  }

  /// Send device approval result (by Developer)
  void sendDeviceApproval({
    required String requestId,
    required String deviceId,
    required String userId,
    required String status,
    required String role,
    required KhajaniPermissions permissions,
  }) {
    // STEP 2: APPROVAL_SENT_TO_SERVER
    print('[APPROVAL_SENT_TO_SERVER] requestId=$requestId userId=$userId deviceId=$deviceId status=APPROVED');

    if (!isConnected) {
      connect();
    }

    sendMessage({
      'type': 'device_approval',
      'requestId': requestId,
      'deviceId': deviceId,
      'userId': userId,
      'status': status,
      'role': role,
      'permissions': permissions.toMap(),
    });
  }

  /// Send device rejection result (by Developer)
  void sendDeviceRejection({
    required String requestId,
    required String deviceId,
    required String userId,
  }) {
    sendMessage({
      'type': 'device_rejection',
      'requestId': requestId,
      'deviceId': deviceId,
      'userId': userId,
      'status': 'REJECTED',
    });
  }

  /// Send permission update to a specific device/user (by Developer)
  void sendPermissionUpdate({
    required String deviceId,
    required String userId,
    required KhajaniPermissions permissions,
  }) {
    sendMessage({
      'type': 'permission_update',
      'deviceId': deviceId,
      'userId': userId,
      'permissions': permissions.toMap(),
    });
  }

  /// Revoke a device remotely (by Developer)
  void sendDeviceRevoke({required String deviceId}) {
    sendMessage({
      'type': 'device_revoke',
      'deviceId': deviceId,
    });
  }

  /// Forward WebRTC signals (offer, answer, ice candidates)
  void sendWebRtcSignal({
    required String toDeviceId,
    required String fromDeviceId,
    required String signalType,
    required dynamic payload,
  }) {
    sendMessage({
      'type': signalType,
      'to': toDeviceId,
      'from': fromDeviceId,
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send a sync request from Target Phone to Master Phone via PC server relay
  void sendSyncRequest({
    required String requesterDeviceId,
    required String requesterUserId,
    required String requesterRole,
    bool isDelta = false,
    Map<String, int>? lastKnownIds,
  }) {
    if (!isConnected) {
      connect();
    }
    final payload = <String, dynamic>{
      'type': 'sync_request',
      'requesterDeviceId': requesterDeviceId,
      'requesterUserId': requesterUserId,
      'requesterRole': requesterRole,
      'isDelta': isDelta,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    if (lastKnownIds != null) {
      payload['lastKnownIds'] = lastKnownIds;
    }
    sendMessage(payload);
  }

  /// Send financial sync data package from Master Phone to Target Phone
  void sendSyncData({
    required String toDeviceId,
    required String fromDeviceId,
    required String syncId,
    required bool isDelta,
    required Map<String, int> recordCounts,
    required int totalRecords,
    required Map<String, dynamic> snapshot,
    required String payloadDigest,
  }) {
    sendMessage({
      'type': 'sync_data',
      'to': toDeviceId,
      'from': fromDeviceId,
      'syncId': syncId,
      'isDelta': isDelta,
      'recordCounts': recordCounts,
      'totalRecords': totalRecords,
      'snapshot': snapshot,
      'payloadDigest': payloadDigest,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send chunked financial sync data
  void sendSyncChunk({
    required String toDeviceId,
    required String fromDeviceId,
    required String syncId,
    required int chunkIndex,
    required int totalChunks,
    required String chunkData,
  }) {
    sendMessage({
      'type': 'sync_chunk',
      'to': toDeviceId,
      'from': fromDeviceId,
      'syncId': syncId,
      'chunkIndex': chunkIndex,
      'totalChunks': totalChunks,
      'chunkData': chunkData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Send acknowledgment of sync back to Master Phone
  void sendSyncAck({
    required String toDeviceId,
    required String fromDeviceId,
    required String syncId,
    required String status,
    String? message,
    Map<String, int>? recordCounts,
  }) {
    final payload = <String, dynamic>{
      'type': 'sync_ack',
      'to': toDeviceId,
      'from': fromDeviceId,
      'syncId': syncId,
      'status': status,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    if (message != null) {
      payload['message'] = message;
    }
    if (recordCounts != null) {
      payload['recordCounts'] = recordCounts;
    }
    sendMessage(payload);
  }

  /// Sends a financial change (INSERT, UPDATE, DELETE) to all authorized peers via PC server
  void sendFinancialChange(Map<String, dynamic> change) {
    if (!isConnected) {
      connect();
    }
    sendMessage(change);
  }

  /// Sends financial change acknowledgment back to origin device
  void sendFinancialChangeAck({
    required String changeId,
    required String toDeviceId,
    required String status,
  }) {
    sendMessage({
      'type': 'sync_ack',
      'changeId': changeId,
      'toDeviceId': toDeviceId,
      'status': status,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _idleTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    connectionState.value = SignalingConnectionState.disconnected;
    connectionStatusText.value = 'सर्व्हर बंद केला आहे';
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _messageController.close();
  }

  // Testing helpers
  @visibleForTesting
  void setReconnectAttemptForTesting(int attempt) {
    _reconnectAttempt = attempt;
  }

  @visibleForTesting
  void resetDeduplicationStateForTesting() {
    _sentRequestIds.clear();
    _processedRequestIds.clear();
  }
}
