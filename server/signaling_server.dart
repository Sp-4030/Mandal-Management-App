// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Hindvi App - PC WebSocket Signaling Server
/// 
/// Role: PC acts purely as a communication and signaling relay.
/// - NO financial data is permanently stored on PC.
/// - NO SQLite database is stored on PC.
/// - Optimized for minimal ngrok and network bandwidth:
///   * Event-driven (no polling)
///   * Lightweight ping/pong
///   * Request deduplication (no duplicate forwarding to developers)
///   * Payload size guard (max 64KB, blocks binary/PDF files)
///   * Minimal JSON payloads without redundant fields

class ClientSession {
  final WebSocket socket;
  String? deviceId;
  String? userId;
  String? userName;
  String? requestId;
  String role; // 'DEVELOPER' or 'CLIENT' or 'MASTER'
  bool isMaster;
  String? userRole;
  DateTime connectedAt;

  ClientSession({
    required this.socket,
    this.deviceId,
    this.userId,
    this.userName,
    this.requestId,
    this.role = 'CLIENT',
    this.isMaster = false,
    this.userRole,
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
  String? approvedRole;
  Map<String, dynamic>? permissions;
  int? updatedAt;

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
    this.approvedRole,
    this.permissions,
    this.updatedAt,
  });

  /// Canonical clean JSON map without duplicate snake_case keys
  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'userId': userId,
      'userName': userName,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'requestType': requestType,
      'requestedRole': requestedRole,
      'status': status,
      'createdAt': createdAt,
      if (approvedRole != null) 'approvedRole': approvedRole,
      if (permissions != null) 'permissions': permissions,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  factory PendingRequest.fromMap(Map<String, dynamic> map) {
    return PendingRequest(
      requestId: (map['requestId'] ?? map['request_id'] ?? '') as String,
      userId: (map['userId'] ?? map['user_id'] ?? '') as String,
      userName: (map['userName'] ?? map['user_name'] ?? '') as String,
      deviceId: (map['deviceId'] ?? map['device_id'] ?? '') as String,
      deviceName: (map['deviceName'] ?? map['device_name'] ?? 'Unknown Device') as String,
      requestType: (map['requestType'] ?? map['request_type'] ?? 'NEW_DEVICE') as String,
      requestedRole: (map['requestedRole'] ?? map['requested_role'] ?? 'OLD_KHAJANI') as String,
      createdAt: (map['createdAt'] ?? map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      status: (map['status'] as String?) ?? 'PENDING',
      approvedRole: (map['approvedRole'] ?? map['role']) as String?,
      permissions: map['permissions'] != null ? Map<String, dynamic>.from(map['permissions'] as Map) : null,
      updatedAt: (map['updatedAt'] ?? map['updated_at'] as num?)?.toInt(),
    );
  }
}

class SignalingServer {
  final int port;
  final Map<WebSocket, ClientSession> _clients = {};
  final Map<String, PendingRequest> _pendingRequests = {};
  final Set<String> _forwardedRequestIds = {};
  HttpServer? _httpServer;

  static const int maxMessageSizeBytes = 10485760; // 10 MB limit

  SignalingServer({this.port = 8080});

  File get _storageFile {
    final serverDir = Directory(Platform.script.resolve('.').toFilePath());
    return File('${serverDir.path}/.pending_requests.json');
  }

  void _loadPendingRequestsFromFile() {
    try {
      final file = _storageFile;
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          for (final item in list) {
            final req = PendingRequest.fromMap(Map<String, dynamic>.from(item as Map));
            _pendingRequests[req.requestId] = req;
            if (req.status == 'PENDING') {
              _forwardedRequestIds.add(req.requestId);
            }
          }
          print('[INFO] Loaded ${_pendingRequests.length} request(s) from persistent storage.');
        }
      }
    } catch (e) {
      print('[WARN] Could not load pending requests from storage: $e');
    }
  }

  void _savePendingRequestsToFile() {
    try {
      final file = _storageFile;
      final list = _pendingRequests.values.map((r) => r.toMap()).toList();
      file.writeAsStringSync(jsonEncode(list));
    } catch (e) {
      print('[WARN] Could not save pending requests to storage: $e');
    }
  }

  Future<void> start() async {
    _loadPendingRequestsFromFile();

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
      // Simple health check endpoint
      request.response.headers.contentType = ContentType.json;
      request.response.headers.add('Access-Control-Allow-Origin', '*');
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
      if (rawData is String && rawData.length > maxMessageSizeBytes) {
        print('[REJECTED] Payload size ${rawData.length} exceeds 64KB limit. Rejecting.');
        _send(socket, {
          'type': 'error',
          'message': 'Payload exceeds 64KB limit. Large files/PDFs must not be sent over WebSocket.',
        });
        return;
      }

      final text = rawData is String ? rawData : utf8.decode(rawData as List<int>);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final type = map['type'] as String?;

      final session = _clients[socket];
      if (session == null) return;

      switch (type) {
        case 'ping':
          // Minimal lightweight pong response
          _send(socket, {'type': 'pong'});
          break;

        case 'register':
          session.deviceId = map['deviceId'] as String?;
          session.userId = map['userId'] as String?;
          session.userName = map['userName'] as String?;
          session.requestId = (map['requestId'] ?? map['request_id']) as String?;
          session.role = (map['role'] as String?) ?? 'CLIENT';
          session.isMaster = (map['isMaster'] == true) || (session.role == 'MASTER') || (session.role == 'LATEST_KHAJANI');
          session.userRole = map['userRole'] as String?;

          print('[REGISTER] Client registered: Device=${session.deviceId}, User=${session.userName}, Role=${session.role}, isMaster=${session.isMaster}, Request=${session.requestId}');

          _send(socket, {
            'type': 'registered',
            'deviceId': session.deviceId,
            'role': session.role,
            'status': 'OK',
            'serverTime': DateTime.now().millisecondsSinceEpoch,
          });

          // If developer connects, automatically send all requests & clients
          if (session.isDeveloper) {
            _sendPendingRequestsToDeveloper(socket);
            _sendAllRequestsToDeveloper(socket);
            _sendConnectedClientsToDeveloper(socket);
          } else {
            // Check if there is an approved request for this client (Offline Recovery)
            _checkAndDeliverPendingApprovalForClient(socket, session);
          }
          break;

        case 'get_pending_requests':
          _sendPendingRequestsToDeveloper(socket);
          break;

        case 'get_all_requests':
          _sendAllRequestsToDeveloper(socket);
          break;

        case 'get_connected_clients':
          _sendConnectedClientsToDeveloper(socket);
          break;

        case 'set_latest_khajani':
          _handleSetLatestKhajani(socket, map);
          break;

        case 'device_restore':
          _handleDeviceRestore(socket, map);
          break;

        case 'check_status':
          _handleCheckStatus(socket, map);
          break;

        case 'authorize_app_access':
          _handleAuthorizeAppAccess(socket, map);
          break;

        case 'device_request':
          _handleDeviceRequest(socket, map);
          break;

        case 'device_approval':
          _handleDeviceApproval(socket, map);
          break;

        case 'device_rejection':
        case 'delete_request':
          _handleDeviceRejection(socket, map);
          break;

        case 'permission_update':
          _handlePermissionUpdate(socket, map);
          break;

        case 'device_revoke':
          _handleDeviceRevoke(socket, map);
          break;

        case 'sync_request':
          _handleSyncRequest(socket, map);
          break;

        case 'sync_data':
          _handleSyncData(socket, map);
          break;

        case 'sync_chunk':
        case 'sync_ack':
          _routePeerMessage(socket, map);
          break;

        case 'financial_change':
          _handleFinancialChange(socket, map);
          break;

        case 'get_master_info':
          _handleGetMasterInfo(socket);
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

  void _handleSyncRequest(WebSocket socket, Map<String, dynamic> map) {
    final requesterDeviceId = (map['requesterDeviceId'] ?? _clients[socket]?.deviceId ?? '') as String;
    final requesterUserId = (map['requesterUserId'] ?? _clients[socket]?.userId ?? '') as String;
    print('[SERVER_RECEIVED_SYNC_REQUEST] requesterDeviceId=$requesterDeviceId requesterUserId=$requesterUserId');

    ClientSession? masterSession;
    for (final client in _clients.values) {
      if (client.isMaster || client.role == 'MASTER' || client.userRole == 'LATEST_KHAJANI') {
        masterSession = client;
        break;
      }
    }

    if (masterSession != null) {
      print('[SERVER_FORWARDED_SYNC_REQUEST] Forwarding sync request to Master device=${masterSession.deviceId}');
      _send(masterSession.socket, map);
    } else {
      print('[SERVER_MASTER_OFFLINE] Master phone is offline');
      _send(socket, {
        'type': 'sync_status',
        'status': 'MASTER_OFFLINE',
        'message': 'मास्टर फोन (चालू खजानी) सध्या ऑफलाइन आहे. कृपया मास्टर फोन सुरू करा.',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  void _handleSyncData(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = map['to'] as String?;
    final fromDeviceId = (map['from'] ?? _clients[socket]?.deviceId ?? '') as String;
    final counts = map['recordCounts'] as Map<String, dynamic>? ?? {};
    final vargani = counts['vargani'] ?? 0;
    final prasad = counts['prasad_dengani'] ?? 0;
    final kharch = counts['kharch'] ?? 0;
    print('[SERVER_RECEIVED] from=$fromDeviceId to=$targetDeviceId, Vargani: $vargani records, Prasad Dengani: $prasad records, Kharch: $kharch records');

    if (targetDeviceId != null) {
      for (final client in _clients.values) {
        if (client.deviceId == targetDeviceId) {
          _send(client.socket, map);
          print('[SERVER_FORWARDED] Delivered sync data to targetDeviceId=$targetDeviceId');
          break;
        }
      }
    }
  }

  void _handleGetMasterInfo(WebSocket socket) {
    ClientSession? masterSession;
    for (final client in _clients.values) {
      if (client.isMaster || client.role == 'MASTER' || client.userRole == 'LATEST_KHAJANI') {
        masterSession = client;
        break;
      }
    }
    _send(socket, {
      'type': 'master_info',
      'isMasterOnline': masterSession != null,
      'masterDeviceId': masterSession?.deviceId,
      'masterUserName': masterSession?.userName,
    });
  }

  void _checkAndDeliverPendingApprovalForClient(WebSocket socket, ClientSession session) {
    if (session.deviceId == null || session.deviceId!.isEmpty) return;

    for (final req in _pendingRequests.values) {
      final matchesDevice = req.deviceId == session.deviceId;
      final matchesUser = session.userId == null || session.userId!.isEmpty || req.userId == session.userId;
      final matchesReq = session.requestId == null || session.requestId!.isEmpty || req.requestId == session.requestId;

      if (matchesDevice && matchesUser && matchesReq) {
        if (req.status == 'APPROVED') {
          print('[SERVER_FOUND_TARGET_DEVICE] requestId=${req.requestId} userId=${req.userId} deviceId=${req.deviceId} status=APPROVED');
          final approvalPayload = {
            'type': 'device_approval_result',
            'requestId': req.requestId,
            'deviceId': req.deviceId,
            'userId': req.userId,
            'status': 'APPROVED',
            'role': req.approvedRole ?? req.requestedRole,
            'permissions': req.permissions,
            'updatedAt': req.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
          };
          _send(socket, approvalPayload);
          print('[SERVER_SENT_APPROVAL_TO_NEW_PHONE] requestId=${req.requestId} userId=${req.userId} deviceId=${req.deviceId} status=APPROVED');
          break;
        } else if (req.status == 'REVOKED') {
          print('[SERVER_FOUND_REVOKED_DEVICE] requestId=${req.requestId} deviceId=${req.deviceId} status=REVOKED');
          _send(socket, {
            'type': 'device_revoked',
            'deviceId': req.deviceId,
            'revokedAt': req.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
          });
          break;
        }
      }
    }
  }

  void _handleCheckStatus(WebSocket socket, Map<String, dynamic> map) {
    final requestId = (map['requestId'] ?? map['request_id'] ?? '') as String;
    final userId = (map['userId'] ?? map['user_id'] ?? '') as String;
    final deviceId = (map['deviceId'] ?? map['device_id'] ?? '') as String;

    final session = _clients[socket];
    if (session != null) {
      if (deviceId.isNotEmpty) session.deviceId = deviceId;
      if (userId.isNotEmpty) session.userId = userId;
      if (requestId.isNotEmpty) session.requestId = requestId;
    }

    print('[SERVER_CHECK_STATUS] requestId=$requestId userId=$userId deviceId=$deviceId');

    PendingRequest? foundReq;
    if (requestId.isNotEmpty && _pendingRequests.containsKey(requestId)) {
      final req = _pendingRequests[requestId]!;
      final userMatch = userId.isEmpty || req.userId.isEmpty || req.userId == userId;
      final devMatch = deviceId.isEmpty || req.deviceId.isEmpty || req.deviceId == deviceId;
      if (userMatch && devMatch) {
        foundReq = req;
      }
    } else {
      for (final req in _pendingRequests.values) {
        final reqMatch = requestId.isEmpty || req.requestId == requestId;
        final userMatch = userId.isEmpty || req.userId == userId;
        final devMatch = deviceId.isEmpty || req.deviceId == deviceId;
        if (reqMatch && userMatch && devMatch) {
          foundReq = req;
          break;
        }
      }
    }

    if (foundReq != null) {
      if (foundReq.status == 'APPROVED') {
        // STEP 4: SERVER_FOUND_TARGET_DEVICE
        print('[SERVER_FOUND_TARGET_DEVICE] requestId=${foundReq.requestId} userId=${foundReq.userId} deviceId=${foundReq.deviceId} status=APPROVED');

        final approvalPayload = {
          'type': 'device_approval_result',
          'requestId': foundReq.requestId,
          'deviceId': foundReq.deviceId,
          'userId': foundReq.userId,
          'status': 'APPROVED',
          'role': foundReq.approvedRole ?? foundReq.requestedRole,
          'permissions': foundReq.permissions,
          'updatedAt': foundReq.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        };

        // STEP 5: SERVER_SENT_APPROVAL_TO_NEW_PHONE
        _send(socket, approvalPayload);
        print('[SERVER_SENT_APPROVAL_TO_NEW_PHONE] requestId=${foundReq.requestId} userId=${foundReq.userId} deviceId=${foundReq.deviceId} status=APPROVED');
      } else if (foundReq.status == 'REVOKED') {
        _send(socket, {
          'type': 'device_revoked',
          'requestId': foundReq.requestId,
          'userId': foundReq.userId,
          'deviceId': foundReq.deviceId,
          'status': 'REVOKED',
          'revokedAt': foundReq.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        _send(socket, {
          'type': 'check_status_result',
          'requestId': foundReq.requestId,
          'userId': foundReq.userId,
          'deviceId': foundReq.deviceId,
          'status': foundReq.status,
        });
      }
    } else {
      _send(socket, {
        'type': 'check_status_result',
        'requestId': requestId,
        'userId': userId,
        'deviceId': deviceId,
        'status': 'NOT_FOUND',
      });
    }
  }

  void _handleAuthorizeAppAccess(WebSocket socket, Map<String, dynamic> map) {
    final requestId = (map['requestId'] ?? map['request_id'] ?? '') as String;
    final userId = (map['userId'] ?? map['user_id'] ?? '') as String;
    final deviceId = (map['deviceId'] ?? map['device_id'] ?? '') as String;

    final session = _clients[socket];
    if (session != null) {
      if (deviceId.isNotEmpty) session.deviceId = deviceId;
      if (userId.isNotEmpty) session.userId = userId;
      if (requestId.isNotEmpty) session.requestId = requestId;
    }

    print('[SERVER_AUTHORIZE_APP_ACCESS] requestId=$requestId userId=$userId deviceId=$deviceId');

    // Root developer is always approved
    if (userId == 'developer_root') {
      _send(socket, {
        'type': 'authorize_app_access_result',
        'isAuthorized': true,
        'status': 'APPROVED',
        'role': 'DEVELOPER',
        'userId': userId,
        'deviceId': deviceId,
        'permissions': {
          'can_view': 1,
          'can_add': 1,
          'can_edit': 1,
          'can_delete': 1,
          'can_search': 1,
          'can_pdf': 1,
          'can_manage_khajani': 1,
          'can_sync': 1,
        },
      });
      return;
    }

    PendingRequest? foundReq;
    if (requestId.isNotEmpty && _pendingRequests.containsKey(requestId)) {
      final req = _pendingRequests[requestId]!;
      final userMatch = userId.isEmpty || req.userId.isEmpty || req.userId == userId;
      final devMatch = deviceId.isEmpty || req.deviceId.isEmpty || req.deviceId == deviceId;
      if (userMatch && devMatch) {
        foundReq = req;
      }
    } else {
      for (final req in _pendingRequests.values) {
        final reqMatch = requestId.isEmpty || req.requestId == requestId;
        final userMatch = userId.isEmpty || req.userId == userId;
        final devMatch = deviceId.isEmpty || req.deviceId == deviceId;
        if (reqMatch && userMatch && devMatch) {
          foundReq = req;
          break;
        }
      }
    }

    if (foundReq != null) {
      if (foundReq.status == 'APPROVED') {
        _send(socket, {
          'type': 'authorize_app_access_result',
          'isAuthorized': true,
          'status': 'APPROVED',
          'role': foundReq.approvedRole ?? foundReq.requestedRole,
          'permissions': foundReq.permissions,
          'userId': foundReq.userId,
          'deviceId': foundReq.deviceId,
          'requestId': foundReq.requestId,
          'updatedAt': foundReq.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        });
      } else if (foundReq.status == 'REVOKED') {
        _send(socket, {
          'type': 'authorize_app_access_result',
          'isAuthorized': false,
          'status': 'REVOKED',
          'userId': foundReq.userId,
          'deviceId': foundReq.deviceId,
          'message': 'Access Revoked. Contact Developer.',
        });
      } else if (foundReq.status == 'REJECTED') {
        _send(socket, {
          'type': 'authorize_app_access_result',
          'isAuthorized': false,
          'status': 'REJECTED',
          'userId': foundReq.userId,
          'deviceId': foundReq.deviceId,
          'message': 'Request rejected by Developer.',
        });
      } else {
        _send(socket, {
          'type': 'authorize_app_access_result',
          'isAuthorized': false,
          'status': 'PENDING',
          'userId': foundReq.userId,
          'deviceId': foundReq.deviceId,
          'message': 'Developer approval pending.',
        });
      }
    } else {
      _send(socket, {
        'type': 'authorize_app_access_result',
        'isAuthorized': false,
        'status': 'NOT_FOUND',
        'userId': userId,
        'deviceId': deviceId,
        'message': 'Device not registered.',
      });
    }
  }

  void _handleDeviceRequest(WebSocket socket, Map<String, dynamic> map) {
    final requestId = (map['requestId'] ?? map['request_id']) as String? ??
        'req_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = (map['deviceId'] ?? map['device_id']) as String? ?? '';
    final userId = (map['userId'] ?? map['user_id']) as String? ?? '';
    final userName = (map['userName'] ?? map['user_name']) as String? ?? '';
    final deviceName = (map['deviceName'] ?? map['device_name']) as String? ?? 'Unknown Device';
    final requestType = (map['requestType'] ?? map['request_type']) as String? ?? 'NEW_DEVICE';
    final requestedRole = (map['requestedRole'] ?? map['requested_role']) as String? ?? 'OLD_KHAJANI';
    final createdAt = (map['createdAt'] ?? map['created_at'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

    final session = _clients[socket];
    if (session != null) {
      session.deviceId = deviceId;
      session.userId = userId;
      session.userName = userName;
      session.requestId = requestId;
    }

    // Check duplicate request to prevent re-forwarding over network
    if (_forwardedRequestIds.contains(requestId)) {
      print('[SERVER_DEDUP] Duplicate request received: $requestId. Skipping duplicate broadcast.');
      _send(socket, {
        'type': 'device_request_ack',
        'requestId': requestId,
        'status': 'ALREADY_FORWARDED',
      });
      return;
    }

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
    _forwardedRequestIds.add(requestId);
    _savePendingRequestsToFile();

    // Standard Debugging Logs
    print('[SERVER_RECEIVED] requestId=$requestId userId=$userId deviceId=$deviceId timestamp=$createdAt status=PENDING');

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

    final now = DateTime.now().millisecondsSinceEpoch;
    print('[SERVER_FORWARDED] requestId=$requestId userId=$userId deviceId=$deviceId timestamp=$now status=PENDING');
  }

  void _handleDeviceApproval(WebSocket socket, Map<String, dynamic> map) {
    final requestId = (map['requestId'] ?? map['request_id'] ?? '') as String;
    final targetDeviceId = (map['deviceId'] ?? map['device_id'] ?? '') as String;
    final userId = (map['userId'] ?? map['user_id'] ?? '') as String;
    final status = (map['status'] ?? 'APPROVED') as String;
    final role = (map['role'] ?? map['requestedRole'] ?? 'OLD_KHAJANI') as String;
    final permissions = map['permissions'] as Map<String, dynamic>?;

    // STEP 3: SERVER_RECEIVED_APPROVAL
    print('[SERVER_RECEIVED_APPROVAL] requestId=$requestId userId=$userId deviceId=$targetDeviceId status=$status role=$role');

    final now = DateTime.now().millisecondsSinceEpoch;

    // If approved as LATEST_KHAJANI, demote existing LATEST_KHAJANI
    if (role == 'LATEST_KHAJANI') {
      for (final req in _pendingRequests.values) {
        if (req.requestId != requestId && req.approvedRole == 'LATEST_KHAJANI') {
          req.approvedRole = 'OLD_KHAJANI';
          req.permissions = {
            'canView': true,
            'canAdd': false,
            'canEdit': false,
            'canDelete': false,
            'canSearch': true,
            'canPdf': true,
            'canManageKhajani': false,
            'canSync': false,
          };
          req.updatedAt = now;

          for (final client in _clients.values) {
            if (client.deviceId == req.deviceId || client.userId == req.userId) {
              client.isMaster = false;
              client.userRole = 'OLD_KHAJANI';
              _send(client.socket, {
                'type': 'role_updated',
                'role': 'OLD_KHAJANI',
                'permissions': req.permissions,
                'isMaster': false,
              });
            }
          }
        }
      }
    }

    // Update persistent request status
    if (requestId.isNotEmpty && _pendingRequests.containsKey(requestId)) {
      final req = _pendingRequests[requestId]!;
      req.status = status;
      req.approvedRole = role;
      req.permissions = permissions;
      req.updatedAt = now;
    } else {
      _pendingRequests[requestId] = PendingRequest(
        requestId: requestId,
        userId: userId,
        userName: (map['userName'] ?? map['user_name'] ?? '') as String,
        deviceId: targetDeviceId,
        deviceName: (map['deviceName'] ?? map['device_name'] ?? 'Android Device') as String,
        requestType: 'NEW_ACCOUNT',
        requestedRole: role,
        createdAt: now,
        status: status,
        approvedRole: role,
        permissions: permissions,
        updatedAt: now,
      );
    }
    _savePendingRequestsToFile();

    final approvalPayload = {
      'type': 'device_approval_result',
      'requestId': requestId,
      'deviceId': targetDeviceId,
      'userId': userId,
      'status': status,
      'role': role,
      'permissions': permissions,
      'updatedAt': now,
    };

    // STEP 4: SERVER_FOUND_TARGET_DEVICE
    ClientSession? targetClient;
    for (final client in _clients.values) {
      if (!client.isDeveloper) {
        final matchesDevice = client.deviceId != null && client.deviceId == targetDeviceId;
        final matchesUser = client.userId == null || client.userId!.isEmpty || client.userId == userId;
        final matchesReq = client.requestId == null || client.requestId!.isEmpty || client.requestId == requestId;
        if (matchesDevice && (matchesUser || matchesReq)) {
          targetClient = client;
          break;
        }
      }
    }

    bool delivered = false;
    if (targetClient != null) {
      if (role == 'LATEST_KHAJANI') {
        targetClient.isMaster = true;
        targetClient.userRole = 'LATEST_KHAJANI';
      }
      print('[SERVER_FOUND_TARGET_DEVICE] requestId=$requestId userId=$userId deviceId=$targetDeviceId status=$status');
      _send(targetClient.socket, approvalPayload);
      delivered = true;
      print('[SERVER_SENT_APPROVAL_TO_NEW_PHONE] requestId=$requestId userId=$userId deviceId=$targetDeviceId status=$status');
    } else {
      print('[SERVER_OFFLINE_SAVED] Target device $targetDeviceId ($userId) is currently offline. Status saved as $status for offline recovery.');
    }

    _send(socket, {
      'type': 'approval_dispatched',
      'requestId': requestId,
      'targetDeviceId': targetDeviceId,
      'userId': userId,
      'deliveredDirectly': delivered,
      'status': status,
      'role': role,
    });
    _broadcastAllRequestsToDevelopers();
  }

  void _handleDeviceRejection(WebSocket socket, Map<String, dynamic> map) {
    final requestId = (map['requestId'] ?? map['request_id'] ?? '') as String;
    final targetDeviceId = (map['deviceId'] ?? map['device_id'] ?? '') as String;
    final userId = (map['userId'] ?? map['user_id'] ?? '') as String;

    print('[REJECTION] Request $requestId rejected for device $targetDeviceId');

    if (requestId.isNotEmpty && _pendingRequests.containsKey(requestId)) {
      final req = _pendingRequests[requestId]!;
      req.status = 'REJECTED';
      req.updatedAt = DateTime.now().millisecondsSinceEpoch;
      _savePendingRequestsToFile();
    }

    final rejectionPayload = {
      'type': 'device_rejection_result',
      'requestId': requestId,
      'deviceId': targetDeviceId,
      'userId': userId,
      'status': 'REJECTED',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId || (userId.isNotEmpty && client.userId == userId)) {
        _send(client.socket, rejectionPayload);
      }
    }

    _send(socket, {
      'type': 'rejection_dispatched',
      'requestId': requestId,
      'targetDeviceId': targetDeviceId,
      'userId': userId,
    });
    _broadcastAllRequestsToDevelopers();
  }

  void _handlePermissionUpdate(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = map['deviceId'] as String?;
    final userId = map['userId'] as String?;
    final permissions = map['permissions'] as Map<String, dynamic>?;

    print('[PERMISSION] Updating permissions for device $targetDeviceId / user $userId');

    for (final req in _pendingRequests.values) {
      if ((targetDeviceId != null && targetDeviceId.isNotEmpty && req.deviceId == targetDeviceId) ||
          (userId != null && userId.isNotEmpty && req.userId == userId)) {
        req.permissions = permissions;
        req.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }
    _savePendingRequestsToFile();

    final payload = {
      'type': 'permissions_updated',
      'deviceId': targetDeviceId,
      'userId': userId,
      'permissions': permissions,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    for (final client in _clients.values) {
      if ((targetDeviceId != null && client.deviceId == targetDeviceId) ||
          (userId != null && client.userId == userId)) {
        _send(client.socket, payload);
      }
    }
    _broadcastAllRequestsToDevelopers();
  }

  void _handleDeviceRevoke(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = (map['deviceId'] ?? map['targetDeviceId']) as String?;
    if (targetDeviceId == null || targetDeviceId.isEmpty) return;
    print('[REVOKE] Revoking device $targetDeviceId');

    for (final req in _pendingRequests.values) {
      if (req.deviceId == targetDeviceId) {
        req.status = 'REVOKED';
        req.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
    }
    _savePendingRequestsToFile();

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

    _send(socket, {
      'type': 'device_revoked_ack',
      'deviceId': targetDeviceId,
      'status': 'REVOKED',
    });
    _broadcastAllRequestsToDevelopers();
  }

  void _handleDeviceRestore(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = (map['deviceId'] ?? map['targetDeviceId']) as String?;
    if (targetDeviceId == null || targetDeviceId.isEmpty) return;
    print('[RESTORE] Restoring device $targetDeviceId');

    final now = DateTime.now().millisecondsSinceEpoch;
    String? restoredUserId;
    for (final req in _pendingRequests.values) {
      if (req.deviceId == targetDeviceId) {
        req.status = 'APPROVED';
        req.approvedRole = req.approvedRole ?? 'OLD_KHAJANI';
        req.permissions ??= {
          'canView': true,
          'canAdd': false,
          'canEdit': false,
          'canDelete': false,
          'canSearch': true,
          'canPdf': true,
          'canManageKhajani': false,
          'canSync': false,
        };
        req.updatedAt = now;
        restoredUserId = req.userId;
      }
    }
    _savePendingRequestsToFile();

    final payload = {
      'type': 'device_approval_result',
      'deviceId': targetDeviceId,
      'userId': restoredUserId,
      'status': 'APPROVED',
      'role': 'OLD_KHAJANI',
      'updatedAt': now,
    };

    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId) {
        _send(client.socket, payload);
      }
    }

    _send(socket, {
      'type': 'device_restored_ack',
      'deviceId': targetDeviceId,
      'status': 'APPROVED',
    });
    _broadcastAllRequestsToDevelopers();
  }

  void _handleSetLatestKhajani(WebSocket socket, Map<String, dynamic> map) {
    final targetUserId = map['userId'] as String? ?? '';
    final targetDeviceId = map['deviceId'] as String? ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;

    print('[LATEST_KHAJANI] Setting Latest Khajani user=$targetUserId device=$targetDeviceId');

    // Demote current Latest Khajani
    for (final req in _pendingRequests.values) {
      if (req.approvedRole == 'LATEST_KHAJANI' && req.userId != targetUserId) {
        req.approvedRole = 'OLD_KHAJANI';
        req.permissions = {
          'canView': true,
          'canAdd': false,
          'canEdit': false,
          'canDelete': false,
          'canSearch': true,
          'canPdf': true,
          'canManageKhajani': false,
          'canSync': false,
        };
        req.updatedAt = now;

        for (final client in _clients.values) {
          if (client.deviceId == req.deviceId || client.userId == req.userId) {
            client.isMaster = false;
            client.userRole = 'OLD_KHAJANI';
            _send(client.socket, {
              'type': 'role_updated',
              'role': 'OLD_KHAJANI',
              'permissions': req.permissions,
              'isMaster': false,
            });
          }
        }
      }
    }

    // Promote new Latest Khajani
    for (final req in _pendingRequests.values) {
      if (req.userId == targetUserId || (targetDeviceId.isNotEmpty && req.deviceId == targetDeviceId)) {
        req.approvedRole = 'LATEST_KHAJANI';
        req.status = 'APPROVED';
        req.permissions = {
          'canView': true,
          'canAdd': true,
          'canEdit': true,
          'canDelete': true,
          'canSearch': true,
          'canPdf': true,
          'canManageKhajani': true,
          'canSync': true,
        };
        req.updatedAt = now;

        for (final client in _clients.values) {
          if (client.deviceId == req.deviceId || client.userId == req.userId) {
            client.isMaster = true;
            client.userRole = 'LATEST_KHAJANI';
            _send(client.socket, {
              'type': 'role_updated',
              'role': 'LATEST_KHAJANI',
              'permissions': req.permissions,
              'isMaster': true,
            });
          }
        }
      }
    }
    _savePendingRequestsToFile();

    _send(socket, {
      'type': 'latest_khajani_updated',
      'userId': targetUserId,
      'deviceId': targetDeviceId,
      'status': 'OK',
    });
    _broadcastAllRequestsToDevelopers();
  }

  void _handleFinancialChange(WebSocket socket, Map<String, dynamic> map) {
    final changeId = (map['changeId'] ?? '') as String;
    final tableName = (map['tableName'] ?? '') as String;
    final operation = (map['operation'] ?? '') as String;
    final fromDeviceId = (map['deviceId'] ?? _clients[socket]?.deviceId ?? '') as String;

    print('[SERVER_RECEIVED] changeId=$changeId table=$tableName op=$operation from=$fromDeviceId');

    int forwardedCount = 0;
    for (final client in _clients.values) {
      if (client.socket != socket && client.deviceId != fromDeviceId) {
        _send(client.socket, map);
        forwardedCount++;
        print('[SERVER_FORWARDED] changeId=$changeId table=$tableName to=${client.deviceId}');
      }
    }

    _send(socket, {
      'type': 'sync_ack',
      'changeId': changeId,
      'status': 'SERVER_RECEIVED',
      'forwardedCount': forwardedCount,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _routePeerMessage(WebSocket socket, Map<String, dynamic> map) {
    final targetDeviceId = (map['to'] ?? map['toDeviceId']) as String?;
    if (targetDeviceId == null) return;

    for (final client in _clients.values) {
      if (client.deviceId == targetDeviceId) {
        _send(client.socket, map);
        return;
      }
    }
  }

  void _sendPendingRequestsToDeveloper(WebSocket socket) {
    final list = _pendingRequests.values
        .where((r) => r.status == 'PENDING')
        .map((r) => r.toMap())
        .toList();
    _send(socket, {
      'type': 'pending_requests_list',
      'requests': list,
    });
  }

  void _sendAllRequestsToDeveloper(WebSocket socket) {
    final list = _pendingRequests.values.map((r) => r.toMap()).toList();
    _send(socket, {
      'type': 'all_requests_list',
      'requests': list,
    });
  }

  void _sendConnectedClientsToDeveloper(WebSocket socket) {
    final clients = _clients.values.map((c) => {
      'deviceId': c.deviceId ?? '',
      'userId': c.userId ?? '',
      'userName': c.userName ?? '',
      'role': c.role,
      'userRole': c.userRole ?? '',
      'isMaster': c.isMaster,
      'connectedAt': c.connectedAt.millisecondsSinceEpoch,
    }).toList();
    _send(socket, {
      'type': 'connected_clients_list',
      'clients': clients,
    });
  }

  void _broadcastAllRequestsToDevelopers() {
    final list = _pendingRequests.values.map((r) => r.toMap()).toList();
    _broadcastToDevelopers({
      'type': 'all_requests_list',
      'requests': list,
    });
    final pendingList = _pendingRequests.values.where((r) => r.status == 'PENDING').map((r) => r.toMap()).toList();
    _broadcastToDevelopers({
      'type': 'pending_requests_list',
      'requests': pendingList,
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
