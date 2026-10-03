// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Hindvi App - PC WebSocket Signaling Server
/// 
/// Role: PC acts purely as a communication and signaling relay.
/// - NO financial data is permanently stored on PC.
/// - NO SQLite database is stored on PC.
/// - Used for:
///   * Device Requests
///   * Developer Approvals
///   * Permission Updates
///   * Device Revocations
///   * WebRTC P2P Signaling (Offer, Answer, ICE Candidates)
///   * Remote Sync Signaling

class ClientSession {
  final WebSocket socket;
  String? deviceId;
  String? userId;
  String? userName;
  String role; // 'DEVELOPER' or 'CLIENT'
  DateTime connectedAt;

  ClientSession({
    required this.socket,
    this.deviceId,
    this.userId,
    this.userName,
    this.role = 'CLIENT',
    required this.connectedAt,
  });

  bool get isDeveloper => role == 'DEVELOPER';
}

class PendingRequest {
  final String requestId;
  final String userId;
  final String userName;
  final String deviceId;
  final String deviceName;
  final String requestType; // 'NEW_DEVICE', 'NEW_ACCOUNT', 'LOGIN'
  final String requestedRole;
  final int createdAt;
  String status; // 'PENDING', 'APPROVED', 'REJECTED'

  PendingRequest({
    required this.requestId,
    required this.userId,
    required this.userName,
    required this.deviceId,
    required this.deviceName,
    required this.requestType,
    required this.requestedRole,
    required this.createdAt,
    this.status = 'PENDING',
  });

  Map<String, dynamic> toMap() {
    return {
      'request_id': requestId,
      'user_id': userId,
      'user_name': userName,
      'device_id': deviceId,
      'device_name': deviceName,
      'request_type': requestType,
      'requested_role': requestedRole,
      'status': status,
      'created_at': createdAt,
    };
  }
}

class SignalingServer {
  final int port;
  final Map<WebSocket, ClientSession> _clients = {};
  final Map<String, PendingRequest> _pendingRequests = {};
  HttpServer? _httpServer;

  SignalingServer({this.port = 8080});

  Future<void> start() async {
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      final localIps = await _getLocalIpv4Addresses();

      print('============================================================');
      print('       HINDVI APP - PC WEBSOCKET SIGNALING SERVER           ');
      print('============================================================');
      print('[OK] Server Started successfully!');
      print('[OK] Port: $port');
      print('[OK] Local IP Address(es):');
      if (localIps.isEmpty) {
        print('     - 127.0.0.1 (Localhost)');
      } else {
        for (final ip in localIps) {
          print('     - $ip (ws://$ip:$port)');
        }
      }
      print('------------------------------------------------------------');
      print('Waiting for connections...');
      print('(Keep this window open while using remote features)');
      print('Press Ctrl+C to stop the server.');
      print('============================================================');

      _httpServer!.listen(_handleHttpRequest);
    } catch (e) {
      print('[ERROR] Failed to start server on port $port: $e');
      rethrow;
    }
  }

  Future<List<String>> _getLocalIpv4Addresses() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return ips;
  }

  void _handleHttpRequest(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleNewClient(socket);
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('WebSocket upgrade error: $e');
        await request.response.close();
      }
    } else {
      // Simple health check endpoint for browsers or ping
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'status': 'RUNNING',
          'app': 'Hindvi Swarajya Mandal Signaling Server',
          'port': port,
          'connectedClients': _clients.length,
          'pendingRequests': _pendingRequests.length,
          'time': DateTime.now().toIso8601String(),
        }),
      );
      await request.response.close();
    }
  }

  void _handleNewClient(WebSocket socket) {
    final session = ClientSession(
      socket: socket,
      connectedAt: DateTime.now(),
    );
    _clients[socket] = session;

    print('[INFO] New client connected. Total clients: ${_clients.length}');

    socket.listen(
      (data) => _handleClientMessage(socket, data),
      onDone: () => _handleClientDisconnect(socket),
      onError: (err) {
        print('[ERROR] Client error: $err');
        _handleClientDisconnect(socket);
      },
      cancelOnError: true,
    );
  }

  void _handleClientDisconnect(WebSocket socket) {
    final session = _clients.remove(socket);
    if (session != null) {
      final info = session.deviceId ?? session.userName ?? 'Unknown';
      print('[INFO] Client disconnected: $info. Remaining clients: ${_clients.length}');
    }
    try {
      socket.close();
    } catch (_) {}
  }

  void _handleClientMessage(WebSocket socket, dynamic rawData) {
    try {
      final text = rawData is String ? rawData : utf8.decode(rawData as List<int>);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final type = map['type'] as String?;

      final session = _clients[socket];
      if (session == null) return;

      switch (type) {
        case 'ping':
          _send(socket, {'type': 'pong', 'timestamp': DateTime.now().millisecondsSinceEpoch});
          break;

        case 'register':
          session.deviceId = map['deviceId'] as String?;
          session.userId = map['userId'] as String?;
          session.userName = map['userName'] as String?;
          session.role = (map['role'] as String?) ?? 'CLIENT';

          print('[REGISTER] Client registered: Device=${session.deviceId}, User=${session.userName}, Role=${session.role}');

          _send(socket, {
            'type': 'registered',
            'deviceId': session.deviceId,
            'role': session.role,
            'status': 'OK',
            'serverTime': DateTime.now().millisecondsSinceEpoch,
          });

          // If developer connects, automatically send all pending requests
          if (session.isDeveloper) {
            _sendPendingRequestsToDeveloper(socket);
          }
          break;

        case 'get_pending_requests':
          _sendPendingRequestsToDeveloper(socket);
          break;

        case 'device_request':
          _handleDeviceRequest(socket, map);
          break;

        case 'device_approval':
          _handleDeviceApproval(socket, map);
          break;

        case 'permission_update':
          _handlePermissionUpdate(socket, map);
          break;

        case 'device_revoke':
          _handleDeviceRevoke(socket, map);
          break;

        case 'webrtc_offer':
        case 'webrtc_answer':
        case 'webrtc_candidate':
        case 'sync_signal':
          _routePeerMessage(socket, map);
          break;

        default:
          print('[WARN] Unknown message type received: $type');
      }
    } catch (e) {
      print('[ERROR] Error processing client message: $e');
    }
  }

  void _handleDeviceRequest(WebSocket socket, Map<String, dynamic> map) {
    final requestId = (map['requestId'] as String?) ?? 'req_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = map['deviceId'] as String? ?? '';
    final userId = map['userId'] as String? ?? '';
    final userName = map['userName'] as String? ?? '';
    final deviceName = map['deviceName'] as String? ?? 'Unknown Device';
    final requestType = map['requestType'] as String? ?? 'NEW_DEVICE';
    final requestedRole = map['requestedRole'] as String? ?? 'OLD_KHAJANI';
    final createdAt = (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    final req = PendingRequest(
      requestId: requestId,
      userId: userId,
      userName: userName,
      deviceId: deviceId,
      deviceName: deviceName,
      requestType: requestType,
      requestedRole: requestedRole,
      createdAt: createdAt,
    );

    _pendingRequests[requestId] = req;

    print('[REQUEST] New request received: from $userName ($deviceId) - $requestType');

    // Acknowledge receipt to the client
    _send(socket, {
      'type': 'device_request_ack',
      'requestId': requestId,
      'status': 'RECEIVED',
    });

    // Forward to all connected developers immediately
    final devMessage = {
      'type': 'new_pending_request',
      'request': req.toMap(),
    };
    _broadcastToDevelopers(devMessage);
  }

  void _handleDeviceApproval(WebSocket socket, Map<String, dynamic> map) {
    final requestId = map['requestId'] as String?;
    final targetDeviceId = map['deviceId'] as String?;
    final status = map['status'] as String? ?? 'APPROVED';
    final role = map['role'] as String? ?? 'OLD_KHAJANI';
    final permissions = map['permissions'] as Map<String, dynamic>?;

    print('[APPROVAL] Request $requestId for device $targetDeviceId -> $status ($role)');

    if (requestId != null && _pendingRequests.containsKey(requestId)) {
      _pendingRequests[requestId]!.status = status;
      if (status == 'APPROVED' || status == 'REJECTED') {
        _pendingRequests.remove(requestId);
      }
    }

    final approvalPayload = {
      'type': 'device_approval_result',
      'requestId': requestId,
      'deviceId': targetDeviceId,
      'userId': map['userId'],
      'status': status,
      'role': role,
      'permissions': permissions,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    // Forward to target device if connected
    bool delivered = false;
    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId) {
        _send(client.socket, approvalPayload);
        delivered = true;
      }
    }

    // Acknowledge to developer
    _send(socket, {
      'type': 'approval_dispatched',
      'requestId': requestId,
      'targetDeviceId': targetDeviceId,
      'deliveredDirectly': delivered,
    });
  }

  void _handlePermissionUpdate(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = map['deviceId'] as String?;
    final userId = map['userId'] as String?;
    final permissions = map['permissions'] as Map<String, dynamic>?;

    print('[PERMISSION] Updating permissions for device $targetDeviceId / user $userId');

    final payload = {
      'type': 'permissions_updated',
      'deviceId': targetDeviceId,
      'userId': userId,
      'permissions': permissions,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId || (userId != null && client.userId == userId)) {
        _send(client.socket, payload);
      }
    }
  }

  void _handleDeviceRevoke(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = map['deviceId'] as String?;
    print('[REVOKE] Revoking device $targetDeviceId');

    final payload = {
      'type': 'device_revoked',
      'deviceId': targetDeviceId,
      'revokedAt': DateTime.now().millisecondsSinceEpoch,
    };

    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId) {
        _send(client.socket, payload);
      }
    }
  }

  void _routePeerMessage(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = map['to'] as String?;
    if (targetDeviceId == null) return;

    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId) {
        _send(client.socket, map);
        return;
      }
    }
  }

  void _sendPendingRequestsToDeveloper(WebSocket socket) {
    final list = _pendingRequests.values.map((r) => r.toMap()).toList();
    _send(socket, {
      'type': 'pending_requests_list',
      'requests': list,
    });
  }

  void _broadcastToDevelopers(Map<String, dynamic> message) {
    for (final client in _clients.values) {
      if (client.isDeveloper) {
        _send(client.socket, message);
      }
    }
  }

  void _send(WebSocket socket, Map<String, dynamic> message) {
    try {
      socket.add(jsonEncode(message));
    } catch (_) {}
  }

  Future<void> stop() async {
    for (final socket in _clients.keys.toList()) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'Server stopping');
      } catch (_) {}
    }
    _clients.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
    print('[OK] Signaling server stopped cleanly.');
  }
}

void main(List<String> args) async {
  int port = 8080;
  if (args.isNotEmpty) {
    final parsed = int.tryParse(args[0]);
    if (parsed != null && parsed > 0 && parsed < 65536) {
      port = parsed;
    }
  } else if (Platform.environment.containsKey('PORT')) {
    final parsed = int.tryParse(Platform.environment['PORT']!);
    if (parsed != null && parsed > 0 && parsed < 65536) {
      port = parsed;
    }
  }

  final server = SignalingServer(port: port);
  await server.start();

  ProcessSignal.sigint.watch().listen((_) async {
    print('\n[INFO] Stopping signaling server...');
    await server.stop();
    exit(0);
  });
}
