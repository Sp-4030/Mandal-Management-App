import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class MigrationSecurity {
  static final Random _secureRandom = Random.secure();
  static const String _tokenAlphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// Generates a cryptographically strong random token for pairing authentication.
  static String generateSecureToken({int length = 32}) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_tokenAlphabet[_secureRandom.nextInt(_tokenAlphabet.length)]);
    }
    return buffer.toString();
  }

  /// Generates a unique, timestamped migration ID.
  static String generateMigrationId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = generateSecureToken(length: 6);
    return 'MIG_${timestamp}_$randomSuffix';
  }

  /// Computes a SHA-256 hexadecimal digest for a given UTF-8 string.
  static String computeSha256(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }

  /// Computes a SHA-256 hexadecimal digest for raw bytes.
  static String computeBytesSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Constant-time comparison to prevent timing attacks.
  static bool secureCompare(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
