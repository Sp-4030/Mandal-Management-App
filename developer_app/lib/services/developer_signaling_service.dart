// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/developer_permissions.dart';
import '../models/user_request_model.dart';

enum DevConnectionState { disconnected, connecting, connected, error }

class DeveloperSignalingService {
  static final DeveloperSignalingService instance = DeveloperSignalingService._internal();

  DeveloperSignalingService._internal();

  static const String defaultNgrokUrl = 'wss://amino-dropkick-resample.ngrok-free.dev';
  static const String defaultLocalUrl = 'ws://127.0.0.1:8080';

  String _serverUrl = defaultNgrokUrl;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;

  final ValueNotifier<DevConnectionState> connectionState =
      ValueNotifier<DevConnectionState>(DevConnectionState.disconnected);

  final StreamController<bool> _connectionStreamController =
      StreamController<bool>.broadcast();
  Stream<bool> get isConnectedStream => _connectionStreamController.stream;
  bool get isConnected => connectionState.value == DevConnectionState.connected;

  String get serverUrl => _serverUrl;

  // Cached data lists
  final List<UserRequestModel> _pendingRequests = [];
  final List<UserRequestModel> _allRequests = [];
  final List<Map<String, dynamic>> _connectedClients = [];

  final StreamController<List<UserRequestModel>> _pendingController =
      StreamController<List<UserRequestModel>>.broadcast();
  Stream<List<UserRequestModel>> get onPendingRequests => _pendingController.stream;
  List<UserRequestModel> get pendingRequests => List.unmodifiable(_pendingRequests);

  final StreamController<List<UserRequestModel>> _allRequestsController =
      StreamController<List<UserRequestModel>>.broadcast();
  Stream<List<UserRequestModel>> get onAllRequests => _allRequestsController.stream;
  List<UserRequestModel> get allRequests => List.unmodifiable(_allRequests);

  final StreamController<List<Map<String, dynamic>>> _clientsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get onConnectedClients => _clientsController.stream;
  List<Map<String, dynamic>> get connectedClients => List.unmodifiable(_connectedClients);

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  Future<void> setServerUrl(String url) async {
    _serverUrl = url.trim();
    if (isConnected) {
      await disconnect();
      await connect();
    }
  }

  Future<bool> connect({Duration timeout = const Duration(seconds: 5), String? overrideUrl}) async {
    final targetUrl = overrideUrl?.trim() ?? _serverUrl;
    if (_socket != null) {
      try {
        await _socket?.close();
      } catch (_) {}
      _socket = null;
    }

    connectionState.value = DevConnectionState.connecting;

    try {
      final ws = await WebSocket.connect(targetUrl).timeout(timeout);
      _socket = ws;
      _serverUrl = targetUrl;
      _reconnectAttempts = 0;

      connectionState.value = DevConnectionState.connected;
      _connectionStreamController.add(true);

      _registerAsDeveloper();
      _startHeartbeat();

      ws.listen(
        _handleIncomingData,
        onDone: _handleSocketDone,
        onError: _handleSocketError,
        cancelOnError: true,
      );

      // Request fresh data lists from server
      requestRefresh();
      return true;
    } catch (e) {
      print('[DEV_SIGNALING] Connection failed to $targetUrl: $e');
      connectionState.value = DevConnectionState.error;
      _connectionStreamController.add(false);
      _scheduleReconnect();
      return false;
    }
  }

  void _registerAsDeveloper() {
    sendMessage({
      'type': 'register',
      'role': 'DEVELOPER',
      'deviceId': 'DEV_MGMT_CONSOLE',
      'userName': 'Developer',
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (isConnected) {
        sendMessage({'type': 'ping'});
      }
    });
  }

  void _handleIncomingData(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final type = map['type'] as String?;

      _messageController.add(map);

      switch (type) {
        case 'pending_requests_list':
          final list = map['requests'] as List<dynamic>? ?? [];
          _pendingRequests.clear();
          for (final item in list) {
            _pendingRequests.add(UserRequestModel.fromMap(Map<String, dynamic>.from(item as Map)));
          }
          _pendingController.add(List.unmodifiable(_pendingRequests));
          break;

        case 'all_requests_list':
          final list = map['requests'] as List<dynamic>? ?? [];
          _allRequests.clear();
          for (final item in list) {
            _allRequests.add(UserRequestModel.fromMap(Map<String, dynamic>.from(item as Map)));
          }
          _allRequestsController.add(List.unmodifiable(_allRequests));
          break;

        case 'new_pending_request':
          final reqMap = map['request'] as Map<String, dynamic>?;
          if (reqMap != null) {
            final model = UserRequestModel.fromMap(reqMap);
            _pendingRequests.removeWhere((r) => r.requestId == model.requestId);
            _pendingRequests.insert(0, model);
            _pendingController.add(List.unmodifiable(_pendingRequests));

            _allRequests.removeWhere((r) => r.requestId == model.requestId);
            _allRequests.insert(0, model);
            _allRequestsController.add(List.unmodifiable(_allRequests));
          }
          break;

        case 'connected_clients_list':
          final list = map['clients'] as List<dynamic>? ?? [];
          _connectedClients.clear();
          for (final item in list) {
            _connectedClients.add(Map<String, dynamic>.from(item as Map));
          }
          _clientsController.add(List.unmodifiable(_connectedClients));
          break;

        case 'approval_dispatched':
        case 'rejection_dispatched':
        case 'device_revoked_ack':
        case 'device_restored_ack':
        case 'latest_khajani_updated':
          requestRefresh();
          break;
      }
    } catch (e) {
      print('[DEV_SIGNALING] Error parsing message: $e');
    }
  }

  void _handleSocketDone() {
    print('[DEV_SIGNALING] Socket connection closed.');
    _cleanupSocket();
    _scheduleReconnect();
  }

  void _handleSocketError(dynamic error) {
    print('[DEV_SIGNALING] Socket error: $error');
    _cleanupSocket();
    _scheduleReconnect();
  }

  void _cleanupSocket() {
    _heartbeatTimer?.cancel();
    _socket = null;
    connectionState.value = DevConnectionState.disconnected;
    _connectionStreamController.add(false);
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delaySeconds = (_reconnectAttempts < 3) ? 5 : ((_reconnectAttempts < 6) ? 15 : 30);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!isConnected) {
        connect();
      }
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    _cleanupSocket();
  }

  void sendMessage(Map<String, dynamic> message) {
    if (_socket != null) {
      try {
        _socket!.add(jsonEncode(message));
      } catch (e) {
        print('[DEV_SIGNALING] Error sending message: $e');
      }
    }
  }

  void requestRefresh() {
    if (isConnected) {
      sendMessage({'type': 'get_pending_requests'});
      sendMessage({'type': 'get_all_requests'});
      sendMessage({'type': 'get_connected_clients'});
    }
  }

  // ============================================================
  // DEVELOPER ADMINISTRATION COMMANDS
  // ============================================================

  void approveRequest({
    required String requestId,
    required String userId,
    required String deviceId,
    required String role,
    required DeveloperPermissions permissions,
    String? userName,
  }) {
    sendMessage({
      'type': 'device_approval',
      'requestId': requestId,
      'userId': userId,
      'deviceId': deviceId,
      'userName': userName ?? '',
      'status': 'APPROVED',
      'role': role,
      'permissions': permissions.toMap(),
    });
  }

  void rejectRequest({
    required String requestId,
    required String userId,
    required String deviceId,
  }) {
    sendMessage({
      'type': 'device_rejection',
      'requestId': requestId,
      'userId': userId,
      'deviceId': deviceId,
      'status': 'REJECTED',
    });
  }

  void revokeDevice(String deviceId) {
    sendMessage({
      'type': 'device_revoke',
      'deviceId': deviceId,
    });
  }

  void restoreDevice(String deviceId) {
    sendMessage({
      'type': 'device_restore',
      'deviceId': deviceId,
    });
  }

  void updatePermissions({
    required String userId,
    required String deviceId,
    required DeveloperPermissions permissions,
  }) {
    sendMessage({
      'type': 'permission_update',
      'userId': userId,
      'deviceId': deviceId,
      'permissions': permissions.toMap(),
    });
  }

  void setLatestKhajani({
    required String userId,
    required String deviceId,
  }) {
    sendMessage({
      'type': 'set_latest_khajani',
      'userId': userId,
      'deviceId': deviceId,
    });
  }

  void setRequestsForTesting({
    List<UserRequestModel>? pending,
    List<UserRequestModel>? all,
    List<Map<String, dynamic>>? clients,
  }) {
    if (pending != null) {
      _pendingRequests.clear();
      _pendingRequests.addAll(pending);
      _pendingController.add(List.unmodifiable(_pendingRequests));
    }
    if (all != null) {
      _allRequests.clear();
      _allRequests.addAll(all);
      _allRequestsController.add(List.unmodifiable(_allRequests));
    }
    if (clients != null) {
      _connectedClients.clear();
      _connectedClients.addAll(clients);
      _clientsController.add(List.unmodifiable(_connectedClients));
    }
  }

  void resetForTesting() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer = null;
    _reconnectAttempts = 0;
    _socket = null;
    connectionState.value = DevConnectionState.disconnected;
    _pendingRequests.clear();
    _allRequests.clear();
    _connectedClients.clear();
  }
}
