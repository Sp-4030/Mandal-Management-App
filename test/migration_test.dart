import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hindvi_app/migration/migration_models.dart';
import 'package:hindvi_app/migration/migration_security.dart';

void main() {
  group('Migration Models & Security Tests', () {
    test('MigrationPairingInfo serializes and deserializes correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final original = MigrationPairingInfo(
        migrationId: 'MIG_12345_TEST',
        ip: '192.168.43.1',
        port: 8089,
        token: 'secretToken123',
        protocolVersion: 1,
        expiresAt: now + 600000,
        mandalName: 'हिंदवी स्वराज्य',
      );

      final jsonString = original.toJsonString();
      final restored = MigrationPairingInfo.fromJsonString(jsonString);

      expect(restored.migrationId, equals(original.migrationId));
      expect(restored.ip, equals(original.ip));
      expect(restored.port, equals(original.port));
      expect(restored.token, equals(original.token));
      expect(restored.protocolVersion, equals(original.protocolVersion));
      expect(restored.expiresAt, equals(original.expiresAt));
      expect(restored.mandalName, equals(original.mandalName));
      expect(restored.isExpired, isFalse);
    });

    test('MigrationPairingInfo correctly identifies expired sessions', () {
      final past = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      final expired = MigrationPairingInfo(
        migrationId: 'MIG_EXPIRED',
        ip: '192.168.1.10',
        port: 9000,
        token: 'token',
        expiresAt: past,
      );

      expect(expired.isExpired, isTrue);
      expect(expired.remainingDuration, equals(Duration.zero));
    });

    test('MigrationSecurity generates secure tokens and computes correct SHA-256', () {
      final token1 = MigrationSecurity.generateSecureToken();
      final token2 = MigrationSecurity.generateSecureToken();

      expect(token1.length, equals(32));
      expect(token2.length, equals(32));
      expect(token1, isNot(equals(token2)));

      const sampleData = '{"members":10,"income":50000}';
      final digest1 = MigrationSecurity.computeSha256(sampleData);
      final digest2 = MigrationSecurity.computeSha256(sampleData);

      expect(digest1, equals(digest2));
      expect(digest1.length, equals(64)); // SHA-256 produces 64 hex characters

      expect(MigrationSecurity.secureCompare(digest1, digest2), isTrue);
      expect(MigrationSecurity.secureCompare(digest1, 'different'), isFalse);
    });

    test('MigrationPayload serialization and verification', () {
      final tables = {
        'vargani': [
          {'id': 1, 'name': 'रमेश पवार', 'amount': 1000.0, 'year': 2026},
          {'id': 2, 'name': 'सुरेश काळे', 'amount': 500.0, 'year': 2026},
        ],
        'kharch': [
          {'id': 1, 'item': 'मंडप', 'buyer_name': 'गणेश सावंत', 'amount': 2500.0, 'year': 2026},
        ],
      };

      final serialized = jsonEncode(tables);
      final checksum = MigrationSecurity.computeSha256(serialized);

      final payload = MigrationPayload(
        migrationId: 'MIG_TEST_PAYLOAD',
        protocolVersion: 1,
        databaseSchemaVersion: 4,
        sourceDevice: 'Android (Test Phone)',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        recordCounts: {'vargani': 2, 'kharch': 1},
        tables: tables,
        checksum: checksum,
      );

      final payloadJson = payload.toJsonString();
      final decodedPayload = MigrationPayload.fromMap(jsonDecode(payloadJson) as Map<String, dynamic>);

      expect(decodedPayload.migrationId, equals('MIG_TEST_PAYLOAD'));
      expect(decodedPayload.recordCounts['vargani'], equals(2));
      expect(decodedPayload.recordCounts['kharch'], equals(1));
      expect(decodedPayload.tables['vargani']!.length, equals(2));

      // Verify payload checksum matches
      final recomputed = MigrationSecurity.computeSha256(jsonEncode(decodedPayload.tables));
      expect(MigrationSecurity.secureCompare(recomputed, decodedPayload.checksum), isTrue);
    });
  });

  group('Offline Local HTTP Protocol Mock Flow Tests', () {
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    test('Local HTTP handshake and security token validation', () async {
      final token = MigrationSecurity.generateSecureToken();

      // Bind local test server on loopback
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      server!.listen((HttpRequest request) async {
        final reqToken = request.headers.value('X-Migration-Token');
        if (reqToken == null || !MigrationSecurity.secureCompare(reqToken, token)) {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write(jsonEncode({'error': 'Unauthorized'}));
          await request.response.close();
          return;
        }

        if (request.uri.path == '/api/migration/info') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'mandalName': 'हिंदवी स्वराज्य',
            'protocolVersion': 1,
            'schemaVersion': 4,
            'summary': {
              'membersCount': 50,
              'incomeCount': 75,
              'expensesCount': 30,
              'transactionsCount': 105,
              'otherCount': 10,
              'totalRecords': 115,
              'tableCounts': {'vargani': 50, 'kharch': 30},
            },
          }));
          await request.response.close();
        }
      });

      final client = HttpClient();

      // 1. Test unauthorized request without token -> should receive 401
      final unauthReq = await client.getUrl(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server!.port}/api/migration/info'),
      );
      final unauthRes = await unauthReq.close();
      expect(unauthRes.statusCode, equals(HttpStatus.unauthorized));

      // 2. Test authorized request with valid token -> should receive 200 and data
      final authReq = await client.getUrl(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server!.port}/api/migration/info'),
      );
      authReq.headers.set('X-Migration-Token', token);
      final authRes = await authReq.close();
      expect(authRes.statusCode, equals(HttpStatus.ok));

      final body = await utf8.decoder.bind(authRes).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      expect(data['mandalName'], equals('हिंदवी स्वराज्य'));

      final summary = MandalSummaryInfo.fromMap(data['summary'] as Map<String, dynamic>);
      expect(summary.membersCount, equals(50));
      expect(summary.totalRecords, equals(115));

      client.close();
    });
  });
}
