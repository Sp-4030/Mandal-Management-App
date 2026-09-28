import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/database_helper.dart';
import 'migration_models.dart';
import 'migration_security.dart';

enum MigrationServerState {
  idle,
  initializing,
  waitingForPeer,
  peerConnected,
  transferring,
  verifying,
  completed,
  cancelled,
  error,
}

class MigrationServer {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  HttpServer? _httpServer;
  MigrationPairingInfo? _pairingInfo;
  MigrationServerState _state = MigrationServerState.idle;
  String _statusMessage = 'तयार आहे';
  MandalSummaryInfo? _peerSummary;

  final StreamController<MigrationServerState> _stateController =
      StreamController<MigrationServerState>.broadcast();

  Stream<MigrationServerState> get stateStream => _stateController.stream;
  MigrationServerState get state => _state;
  String get statusMessage => _statusMessage;
  MigrationPairingInfo? get pairingInfo => _pairingInfo;
  MandalSummaryInfo? get peerSummary => _peerSummary;

  void _updateState(
    MigrationServerState newState,
    String message, [
    MandalSummaryInfo? summary,
  ]) {
    _state = newState;
    _statusMessage = message;
    if (summary != null) {
      _peerSummary = summary;
    }
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  /// Dynamically discovers the active local IPv4 address of the device.
  /// Does not assume or hardcode any IP address like 192.168.43.1.
  static Future<String?> discoverLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      if (interfaces.isEmpty) {
        return null;
      }

      // Prioritize hotspot and Wi-Fi interface names commonly found on Android
      // e.g. wlan0, ap0, swlan0, softap, rndis
      final preferredKeywords = ['ap', 'wlan', 'softap', 'swlan', 'rndis'];

      for (final keyword in preferredKeywords) {
        for (final iface in interfaces) {
          if (iface.name.toLowerCase().contains(keyword)) {
            for (final addr in iface.addresses) {
              if (_isValidPrivateIpv4(addr.address)) {
                return addr.address;
              }
            }
          }
        }
      }

      // Fallback: pick any valid private non-loopback IPv4 address
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isValidPrivateIpv4(addr.address)) {
            return addr.address;
          }
        }
      }

      if (!Platform.isAndroid && interfaces.isNotEmpty) {
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _isValidPrivateIpv4(String ip) {
    if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
      return false;
    }
    return ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        ip.startsWith('172.');
  }

  /// Starts the temporary local migration server.
  Future<MigrationPairingInfo> startServer() async {
    await stopServer();

    _updateState(
      MigrationServerState.initializing,
      'स्थानिक नेटवर्क तपासत आहे...',
    );

    final localIp = await discoverLocalIp();
    if (localIp == null) {
      _updateState(
        MigrationServerState.error,
        'मोबाईल हॉटस्पॉट सुरू नाही. कृपया हॉटस्पॉट सुरू करा.',
      );
      throw StateError(
        'No active local network interface found. Please turn ON Mobile Hotspot.',
      );
    }

    final migrationId = MigrationSecurity.generateMigrationId();
    final token = MigrationSecurity.generateSecureToken();
    final expiresAt =
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;

    // Bind to an ephemeral port (0 allows OS to allocate any available port)
    _httpServer = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );

    _pairingInfo = MigrationPairingInfo(
      migrationId: migrationId,
      ip: localIp,
      port: _httpServer!.port,
      token: token,
      protocolVersion: 1,
      expiresAt: expiresAt,
      mandalName: 'हिंदवी स्वराज्य',
    );

    _updateState(
      MigrationServerState.waitingForPeer,
      'नवीन फोन जोडणीची प्रतीक्षा करत आहे...',
    );

    _httpServer!.listen(
      _handleRequest,
      onError: (err) {
        _updateState(
          MigrationServerState.error,
          'नेटवर्क सर्व्हर त्रुटी: $err',
        );
      },
    );

    return _pairingInfo!;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Enable CORS for local cross-origin safety
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, Content-Type, X-Migration-Token, Authorization',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    final token = request.headers.value('X-Migration-Token') ??
        request.uri.queryParameters['token'];

    // Session validation
    if (_pairingInfo == null || _pairingInfo!.isExpired) {
      _respondJson(
        request.response,
        HttpStatus.forbidden,
        {'error': 'सत्र कालबाह्य झाले आहे. कृपया पुन्हा सुरू करा.'},
      );
      return;
    }

    if (token == null || !MigrationSecurity.secureCompare(token, _pairingInfo!.token)) {
      _respondJson(
        request.response,
        HttpStatus.unauthorized,
        {'error': 'अवैध टोकन.'},
      );
      return;
    }

    try {
      if (path == '/api/migration/info' && request.method == 'GET') {
        await _handleInfoRequest(request);
      } else if (path == '/api/migration/data' && request.method == 'GET') {
        await _handleDataRequest(request);
      } else if (path == '/api/migration/verify' && request.method == 'POST') {
        await _handleVerifyRequest(request);
      } else if (path == '/api/migration/cancel' && request.method == 'POST') {
        await _handleCancelRequest(request);
      } else {
        _respondJson(
          request.response,
          HttpStatus.notFound,
          {'error': 'अवैध विनंती.'},
        );
      }
    } catch (e) {
      _respondJson(
        request.response,
        HttpStatus.internalServerError,
        {'error': 'अंतर्गत सर्व्हर त्रुटी: $e'},
      );
    }
  }

  Future<void> _handleInfoRequest(HttpRequest request) async {
    final summaryMap = await _databaseHelper.getMandalDataSummary();
    final summary = MandalSummaryInfo.fromMap(summaryMap);

    _updateState(
      MigrationServerState.peerConnected,
      'नवीन फोन जोडला गेला ✓',
      summary,
    );

    _respondJson(request.response, HttpStatus.ok, {
      'migrationId': _pairingInfo!.migrationId,
      'mandalName': _pairingInfo!.mandalName,
      'protocolVersion': _pairingInfo!.protocolVersion,
      'schemaVersion': 4,
      'summary': summary.toMap(),
    });
  }

  Future<void> _handleDataRequest(HttpRequest request) async {
    _updateState(
      MigrationServerState.transferring,
      'डेटा ट्रान्सफर सुरू आहे...',
    );

    final snapshot = await _databaseHelper.createMigrationSnapshot();
    final tables = Map<String, List<Map<String, dynamic>>>.from(
      snapshot['tables'] as Map,
    );

    final recordCounts = <String, int>{};
    tables.forEach((key, list) {
      recordCounts[key] = list.length;
    });

    final serializedTables = jsonEncode(tables);
    final checksum = MigrationSecurity.computeSha256(serializedTables);

    final payload = MigrationPayload(
      migrationId: _pairingInfo!.migrationId,
      protocolVersion: _pairingInfo!.protocolVersion,
      databaseSchemaVersion: (snapshot['schemaVersion'] as num?)?.toInt() ?? 4,
      sourceDevice: 'Android (Old Treasurer Phone)',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      recordCounts: recordCounts,
      tables: tables,
      checksum: checksum,
    );

    _respondJson(request.response, HttpStatus.ok, payload.toMap());
  }

  Future<void> _handleVerifyRequest(HttpRequest request) async {
    _updateState(
      MigrationServerState.verifying,
      'डेटा पडताळणी सुरू आहे...',
    );

    final body = await utf8.decoder.bind(request).join();
    final reportMap = jsonDecode(body) as Map<String, dynamic>;
    final report = MigrationVerificationReport.fromMap(reportMap);

    if (report.migrationId != _pairingInfo!.migrationId) {
      _respondJson(request.response, HttpStatus.badRequest, {
        'status': 'error',
        'message': 'Migration ID जुळत नाही.',
      });
      return;
    }

    if (!report.success) {
      _updateState(
        MigrationServerState.error,
        'नवीन फोनवर डेटा आयात अयशस्वी झाला. जुना डेटा सुरक्षित आहे.',
      );
      _respondJson(request.response, HttpStatus.badRequest, {
        'status': 'error',
        'message': 'Migration validation failed on client.',
      });
      return;
    }

    // Capture complete snapshot to store in 7-day recovery
    final snapshot = await _databaseHelper.createMigrationSnapshot();
    final rawPayload = jsonEncode(snapshot);
    final payloadDigest = MigrationSecurity.computeSha256(rawPayload);

    // Safely move old data into 7-day recovery recycle bin
    await _databaseHelper.moveMigrationDataToRecovery(
      migrationId: _pairingInfo!.migrationId,
      destination: 'New Treasurer Phone',
      payload: rawPayload,
      payloadDigest: payloadDigest,
      migratedAt: DateTime.now(),
    );

    _updateState(
      MigrationServerState.completed,
      'मायग्रेशन यशस्वी पूर्ण झाले ✓\nजुना डेटा ७ दिवस रिकव्हरीमध्ये सुरक्षित आहे.',
    );

    _respondJson(request.response, HttpStatus.ok, {
      'status': 'ok',
      'message': 'Migration verified and confirmed by old device.',
    });
  }

  Future<void> _handleCancelRequest(HttpRequest request) async {
    _updateState(
      MigrationServerState.cancelled,
      'मायग्रेशन रद्द केले.',
    );
    _respondJson(request.response, HttpStatus.ok, {
      'status': 'cancelled',
    });
    await stopServer();
  }

  void _respondJson(HttpResponse response, int statusCode, Map<String, dynamic> data) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }

  /// Gracefully stops the server and frees resources.
  Future<void> stopServer() async {
    if (_httpServer != null) {
      try {
        await _httpServer!.close(force: true);
      } catch (_) {}
      _httpServer = null;
    }
    _pairingInfo = null;
  }

  void dispose() {
    stopServer();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
  }
}
