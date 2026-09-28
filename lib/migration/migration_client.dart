import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/database_helper.dart';
import 'migration_models.dart';
import 'migration_security.dart';

class MigrationClient {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Fetches Mandal summary and schema info from the Old phone using the pairing info.
  Future<Map<String, dynamic>> fetchMandalInfo(
    MigrationPairingInfo pairing,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse('http://${pairing.ip}:${pairing.port}/api/migration/info');
      final request = await client.getUrl(uri);
      request.headers.set('X-Migration-Token', pairing.token);

      final response = await request.close().timeout(const Duration(seconds: 12));

      if (response.statusCode == HttpStatus.unauthorized) {
        throw const FormatException('अवैध ऑथेंटिकेशन टोकन. कृपया पुन्हा QR कोड स्कॅन करा.');
      }
      if (response.statusCode == HttpStatus.forbidden) {
        throw const FormatException('सत्र कालबाह्य झाले आहे. जुन्या फोनवर नवीन QR कोड तयार करा.');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'सर्व्हर त्रुटी: ${response.statusCode} ${response.reasonPhrase}',
        );
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;

      final summaryMap = decoded['summary'] as Map<String, dynamic>;
      final summary = MandalSummaryInfo.fromMap(summaryMap);

      return {
        'mandalName': decoded['mandalName'] as String? ?? 'मंडळ',
        'schemaVersion': (decoded['schemaVersion'] as num?)?.toInt() ?? 4,
        'summary': summary,
      };
    } on SocketException {
      throw SocketException(
        'जुन्या फोनशी संपर्क होऊ शकला नाही.\n\nकृपया खात्री करा:\n'
        '१. जुन्या फोनचा हॉटस्पॉट सुरू आहे.\n'
        '२. नवीन फोन त्या हॉटस्पॉटला जोडला आहे.\n'
        '३. दोन्ही फोन जवळ आहेत.',
      );
    } on TimeoutException {
      throw TimeoutException(
        'कनेक्शन वेळ संपली (Timeout).\nदोन्ही फोनचे Wi-Fi कनेक्शन तपासा.',
      );
    } finally {
      client.close();
    }
  }

  /// Downloads structured Mandal data, verifies SHA-256 checksum, executes
  /// an atomic SQLite transaction import, and notifies the Old phone.
  Future<void> executeMigration({
    required MigrationPairingInfo pairing,
    required void Function(double progress, String status) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      // ----------------------------------------------------
      // STEP 1: Download structured data from Old phone
      // ----------------------------------------------------
      onProgress(0.15, 'डेटा डाउनलोड करत आहे...');

      final dataUri = Uri.parse('http://${pairing.ip}:${pairing.port}/api/migration/data');
      final dataRequest = await client.getUrl(dataUri);
      dataRequest.headers.set('X-Migration-Token', pairing.token);

      final dataResponse = await dataRequest.close().timeout(const Duration(seconds: 30));

      if (dataResponse.statusCode != HttpStatus.ok) {
        throw HttpException('डेटा डाउनलोड अयशस्वी: ${dataResponse.statusCode}');
      }

      final body = await utf8.decoder.bind(dataResponse).join();
      final payloadMap = jsonDecode(body) as Map<String, dynamic>;
      final payload = MigrationPayload.fromMap(payloadMap);

      // ----------------------------------------------------
      // STEP 2: Validate SHA-256 Checksum
      // ----------------------------------------------------
      onProgress(0.40, 'डेटा अखंडता तपासत आहे (SHA-256 Checksum)...');

      final serializedTables = jsonEncode(payload.tables);
      final calculatedChecksum = MigrationSecurity.computeSha256(serializedTables);

      if (!MigrationSecurity.secureCompare(calculatedChecksum, payload.checksum)) {
        throw const FormatException(
          'डेटा पडताळणी अयशस्वी: Checksum जुळत नाही. डेटा करप्ट असू शकतो.',
        );
      }

      // ----------------------------------------------------
      // STEP 3: Create Safety Backup of current NEW PHONE database
      // ----------------------------------------------------
      onProgress(0.55, 'सध्याच्या डेटाची सुरक्षित प्रत तयार करत आहे...');
      await _databaseHelper.createSafetyBackupBeforeMigration();

      // ----------------------------------------------------
      // STEP 4: Atomic SQLite Transaction Import
      // ----------------------------------------------------
      onProgress(0.70, 'डेटाबेसमध्ये नोंदी सुरक्षितपणे साठवत आहे...');

      final alreadyImported = await _databaseHelper.importMigrationSnapshot(
        migrationId: payload.migrationId,
        tables: payload.tables,
        payloadDigest: payload.checksum,
      );

      if (alreadyImported) {
        onProgress(0.85, 'हा डेटा पूर्वीच आयात करण्यात आला आहे.');
      }

      // ----------------------------------------------------
      // STEP 4: Post Verification Report to Old Phone
      // ----------------------------------------------------
      onProgress(0.85, 'जुन्या फोनवर पडताळणी नोंदवत आहे...');

      final verifyUri =
          Uri.parse('http://${pairing.ip}:${pairing.port}/api/migration/verify');
      final verifyRequest = await client.postUrl(verifyUri);
      verifyRequest.headers.set('Content-Type', 'application/json');
      verifyRequest.headers.set('X-Migration-Token', pairing.token);

      final report = MigrationVerificationReport(
        migrationId: payload.migrationId,
        success: true,
        recordCounts: payload.recordCounts,
        checksum: payload.checksum,
        message: 'Imported and verified successfully',
      );

      verifyRequest.write(jsonEncode(report.toMap()));
      final verifyResponse =
          await verifyRequest.close().timeout(const Duration(seconds: 15));

      if (verifyResponse.statusCode != HttpStatus.ok) {
        // Even if ack fails, local data is already safe in SQLite
      }

      onProgress(1.0, 'मायग्रेशन यशस्वीरित्या पूर्ण झाले! ✓');
    } on SocketException {
      throw SocketException(
        'कनेक्शन तुटले. कृपया तपासा की हॉटस्पॉट चालू आहे आणि नवीन फोन कनेक्ट आहे.',
      );
    } catch (e) {
      rethrow;
    } finally {
      client.close();
    }
  }
}
