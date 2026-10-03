import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/device_model.dart';
import '../models/khajani_user.dart';

enum SignalingConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class SignalingService {
  static final SignalingService instance = SignalingService._internal();

  SignalingService._internal();

  static const String defaultServerUrl = 'ws://192.168.1.100:8080';

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  bool _isDisposed = false;
  bool _manualDisconnect = false;

  final ValueNotifier<SignalingConnectionState> connectionState =
      ValueNotifier<SignalingConnectionState>(SignalingConnectionState.disconnected);

  final ValueNotifier<String> connectionStatusText =
      ValueNotifier<String>('सर्व्हर बंद आहे');

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  bool get isConnected => connectionState.value == SignalingConnectionState.connected;

  String get serverUrl => _serverUrl ?? defaultServerUrl;

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

  Future<bool> connect({
    Duration timeout = const Duration(seconds: 4),
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

      _socket!.listen(
        _handleIncomingMessage,
        onDone: _handleSocketDone,
        onError: _handleSocketError,
        cancelOnError: true,
      );

      _startPingHeartbeat();
      return true;
    } catch (e) {
      connectionState.value = SignalingConnectionState.error;
      connectionStatusText.value = 'सर्व्हरशी संपर्क होऊ शकला नाही';
      _scheduleReconnect();
      return false;
    }
  }

  void _startPingHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (isConnected) {
        sendMessage({'type': 'ping'});
      } else {
        timer.cancel();
      }
    });
  }

  void _handleIncomingMessage(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final type = map['type'] as String?;

      if (type == 'pong') {
        return; // heartbeat response
      }

      _messageController.add(map);

      // Handle common signaling events
      _processSystemEvent(map);
    } catch (_) {}
  }

  Future<void> _processSystemEvent(Map<String, dynamic> map) async {
    final type = map['type'] as String?;
    switch (type) {
      case 'device_approval_result':
        await _applyDeviceApprovalLocally(map);
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
      final status = map['status'] as String? ?? 'APPROVED';
      final role = map['role'] as String? ?? 'OLD_KHAJANI';
      final userId = map['userId'] as String?;
      final permissionsMap = map['permissions'] as Map<String, dynamic>?;

      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (userId != null && userId.isNotEmpty) {
        final updateData = <String, dynamic>{
          'role': role,
          'status': status,
          'updated_at': now,
        };

        if (permissionsMap != null) {
          updateData.addAll(permissionsMap);
        }

        await db.update(
          'khajani_users',
          updateData,
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }

      final deviceId = map['deviceId'] as String?;
      if (deviceId != null && deviceId.isNotEmpty) {
        await db.update(
          'devices',
          {
            'status': status,
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
      }
    } catch (_) {}
  }

  void _handleSocketDone() {
    _socket = null;
    _pingTimer?.cancel();
    if (!_manualDisconnect) {
      connectionState.value = SignalingConnectionState.disconnected;
      connectionStatusText.value = 'PC सर्व्हरशी संपर्क तुटला';
      _scheduleReconnect();
    }
  }

  void _handleSocketError(dynamic err) {
    _socket = null;
    _pingTimer?.cancel();
    connectionState.value = SignalingConnectionState.error;
    connectionStatusText.value = 'सर्व्हर त्रुटी (Server Error)';
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _isDisposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!_manualDisconnect && !isConnected) {
        connect();
      }
    });
  }

  void sendMessage(Map<String, dynamic> message) {
    if (!isConnected || _socket == null) return;
    try {
      _socket!.add(jsonEncode(message));
    } catch (_) {}
  }

  /// Register this client with signaling server
  void registerClient({
    required String role,
    required String deviceId,
    String? userId,
    String? userName,
  }) {
    sendMessage({
      'type': 'register',
      'role': role,
      'deviceId': deviceId,
      'userId': userId,
      'userName': userName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Request pending requests list (for Developer)
  void requestPendingList() {
    sendMessage({'type': 'get_pending_requests'});
  }

  /// Send a device request to the server
  void sendDeviceRequest(DeviceRequestModel request) {
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

  /// Send device approval result (by Developer)
  void sendDeviceApproval({
    required String requestId,
    required String deviceId,
    required String userId,
    required String status,
    required String role,
    required KhajaniPermissions permissions,
  }) {
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

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
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
}
