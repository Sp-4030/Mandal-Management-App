import 'dart:convert';

/// Encapsulates connection and authentication parameters encoded in the QR code.
/// Financial data is NEVER included in this object.
class MigrationPairingInfo {
  final String migrationId;
  final String ip;
  final int port;
  final String token;
  final int protocolVersion;
  final int expiresAt;
  final String mandalName;

  const MigrationPairingInfo({
    required this.migrationId,
    required this.ip,
    required this.port,
    required this.token,
    this.protocolVersion = 1,
    required this.expiresAt,
    this.mandalName = 'हिंदवी स्वराज्य',
  });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;

  Duration get remainingDuration {
    final diff = expiresAt - DateTime.now().millisecondsSinceEpoch;
    return diff > 0 ? Duration(milliseconds: diff) : Duration.zero;
  }

  Map<String, dynamic> toMap() => {
        'migrationId': migrationId,
        'ip': ip,
        'port': port,
        'token': token,
        'protocolVersion': protocolVersion,
        'expiresAt': expiresAt,
        'mandalName': mandalName,
      };

  String toJsonString() => jsonEncode(toMap());

  factory MigrationPairingInfo.fromMap(Map<String, dynamic> map) {
    return MigrationPairingInfo(
      migrationId: map['migrationId'] as String,
      ip: map['ip'] as String,
      port: (map['port'] as num).toInt(),
      token: map['token'] as String,
      protocolVersion: (map['protocolVersion'] as num?)?.toInt() ?? 1,
      expiresAt: (map['expiresAt'] as num).toInt(),
      mandalName: (map['mandalName'] as String?) ?? 'हिंदवी स्वराज्य',
    );
  }

  factory MigrationPairingInfo.fromJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    return MigrationPairingInfo.fromMap(decoded);
  }
}

/// High-level summary of Mandal records for user verification.
class MandalSummaryInfo {
  final int membersCount;
  final int incomeCount;
  final int expensesCount;
  final int transactionsCount;
  final int otherCount;
  final int totalRecords;
  final Map<String, int> tableCounts;

  const MandalSummaryInfo({
    required this.membersCount,
    required this.incomeCount,
    required this.expensesCount,
    required this.transactionsCount,
    required this.otherCount,
    required this.totalRecords,
    required this.tableCounts,
  });

  Map<String, dynamic> toMap() => {
        'membersCount': membersCount,
        'incomeCount': incomeCount,
        'expensesCount': expensesCount,
        'transactionsCount': transactionsCount,
        'otherCount': otherCount,
        'totalRecords': totalRecords,
        'tableCounts': tableCounts,
      };

  factory MandalSummaryInfo.fromMap(Map<String, dynamic> map) {
    final rawTableCounts = map['tableCounts'] as Map? ?? {};
    final tableCounts = rawTableCounts.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    return MandalSummaryInfo(
      membersCount: (map['membersCount'] as num?)?.toInt() ?? 0,
      incomeCount: (map['incomeCount'] as num?)?.toInt() ?? 0,
      expensesCount: (map['expensesCount'] as num?)?.toInt() ?? 0,
      transactionsCount: (map['transactionsCount'] as num?)?.toInt() ?? 0,
      otherCount: (map['otherCount'] as num?)?.toInt() ?? 0,
      totalRecords: (map['totalRecords'] as num?)?.toInt() ?? 0,
      tableCounts: tableCounts,
    );
  }
}

/// Structured payload containing all Mandal database records.
class MigrationPayload {
  final String migrationId;
  final int protocolVersion;
  final int databaseSchemaVersion;
  final String sourceDevice;
  final int createdAt;
  final Map<String, int> recordCounts;
  final Map<String, List<Map<String, dynamic>>> tables;
  final String checksum;

  const MigrationPayload({
    required this.migrationId,
    required this.protocolVersion,
    required this.databaseSchemaVersion,
    required this.sourceDevice,
    required this.createdAt,
    required this.recordCounts,
    required this.tables,
    required this.checksum,
  });

  Map<String, dynamic> toMap() => {
        'migrationId': migrationId,
        'protocolVersion': protocolVersion,
        'databaseSchemaVersion': databaseSchemaVersion,
        'sourceDevice': sourceDevice,
        'createdAt': createdAt,
        'recordCounts': recordCounts,
        'tables': tables,
        'checksum': checksum,
      };

  String toJsonString() => jsonEncode(toMap());

  factory MigrationPayload.fromMap(Map<String, dynamic> map) {
    final rawCounts = map['recordCounts'] as Map? ?? {};
    final recordCounts = rawCounts.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    final rawTables = map['tables'] as Map? ?? {};
    final tables = <String, List<Map<String, dynamic>>>{};
    rawTables.forEach((k, v) {
      if (v is List) {
        tables[k.toString()] = v
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      }
    });

    return MigrationPayload(
      migrationId: map['migrationId'] as String,
      protocolVersion: (map['protocolVersion'] as num?)?.toInt() ?? 1,
      databaseSchemaVersion: (map['databaseSchemaVersion'] as num?)?.toInt() ?? 4,
      sourceDevice: (map['sourceDevice'] as String?) ?? 'Android',
      createdAt: (map['createdAt'] as num).toInt(),
      recordCounts: recordCounts,
      tables: tables,
      checksum: (map['checksum'] as String?) ?? '',
    );
  }
}

/// Verification report sent by the New phone back to the Old phone.
class MigrationVerificationReport {
  final String migrationId;
  final bool success;
  final Map<String, int> recordCounts;
  final String checksum;
  final String message;

  const MigrationVerificationReport({
    required this.migrationId,
    required this.success,
    required this.recordCounts,
    required this.checksum,
    required this.message,
  });

  Map<String, dynamic> toMap() => {
        'migrationId': migrationId,
        'success': success,
        'recordCounts': recordCounts,
        'checksum': checksum,
        'message': message,
      };

  factory MigrationVerificationReport.fromMap(Map<String, dynamic> map) {
    final rawCounts = map['recordCounts'] as Map? ?? {};
    final recordCounts = rawCounts.map(
      (k, v) => MapEntry(k.toString(), (v as num).toInt()),
    );

    return MigrationVerificationReport(
      migrationId: map['migrationId'] as String,
      success: map['success'] as bool? ?? false,
      recordCounts: recordCounts,
      checksum: (map['checksum'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
    );
  }
}
