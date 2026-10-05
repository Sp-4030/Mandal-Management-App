import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class DeveloperUser {
  static const String developerName = 'Developer';
  static const String developerDefaultPassword = 'Dev@4030';
  static const String developerUserId = 'developer_root';

  final String userId;
  final String name;
  final String passwordHash;
  final String salt;
  final String role; // 'DEVELOPER'
  final bool isLoggedIn;
  final int loggedInAt;

  const DeveloperUser({
    required this.userId,
    required this.name,
    required this.passwordHash,
    required this.salt,
    this.role = 'DEVELOPER',
    this.isLoggedIn = true,
    required this.loggedInAt,
  });

  bool get isDeveloper => role == 'DEVELOPER';

  static String generateSalt([int length = 16]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  static bool verifyPassword({
    required String password,
    required String salt,
    required String hash,
  }) {
    return hashPassword(password, salt) == hash;
  }

  static bool canDeleteOrRevoke(String targetUserId) {
    if (targetUserId == developerUserId ||
        targetUserId.toLowerCase() == developerName.toLowerCase()) {
      return false; // Developer cannot be deleted or revoked
    }
    return true;
  }
}
