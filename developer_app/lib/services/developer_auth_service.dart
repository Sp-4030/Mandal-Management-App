// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import '../models/developer_user.dart';

class DeveloperAuthService {
  static final DeveloperAuthService instance = DeveloperAuthService._internal();

  DeveloperAuthService._internal();

  DeveloperUser? _currentDeveloper;
  bool _keepLoggedIn = true;

  DeveloperUser? get currentDeveloper => _currentDeveloper;
  bool get isLoggedIn => _currentDeveloper != null && _currentDeveloper!.isLoggedIn;
  bool get keepLoggedIn => _keepLoggedIn;

  // Stored password hash and salt for Developer
  String _storedSalt = '';
  String _storedHash = '';

  File get _sessionFile {
    final dir = Directory.systemTemp;
    return File('${dir.path}/.hindvi_developer_session.json');
  }

  void _ensureCredentials() {
    if (_storedSalt.isEmpty || _storedHash.isEmpty) {
      _storedSalt = DeveloperUser.generateSalt();
      _storedHash = DeveloperUser.hashPassword(DeveloperUser.developerDefaultPassword, _storedSalt);
    }
  }

  Future<void> initSession() async {
    _ensureCredentials();
    try {
      final file = _sessionFile;
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (content.isNotEmpty) {
          final map = jsonDecode(content) as Map<String, dynamic>;
          final keep = map['keepLoggedIn'] as bool? ?? true;
          final userId = map['userId'] as String?;
          final loggedInAt = (map['loggedInAt'] as num?)?.toInt() ?? 0;

          if (keep && userId == DeveloperUser.developerUserId) {
            _currentDeveloper = DeveloperUser(
              userId: DeveloperUser.developerUserId,
              name: DeveloperUser.developerName,
              passwordHash: _storedHash,
              salt: _storedSalt,
              isLoggedIn: true,
              loggedInAt: loggedInAt,
            );
          }
        }
      }
    } catch (_) {
      _currentDeveloper = null;
    }
  }

  Future<bool> login({
    required String name,
    required String password,
    bool keepLoggedIn = true,
  }) async {
    _ensureCredentials();
    final trimmedName = name.trim();

    if (trimmedName.toLowerCase() != DeveloperUser.developerName.toLowerCase()) {
      throw ArgumentError('केवळ Developer खात्यालाच या ॲपमध्ये प्रवेश आहे.');
    }

    final isValid = DeveloperUser.verifyPassword(
      password: password,
      salt: _storedSalt,
      hash: _storedHash,
    );

    if (!isValid) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _keepLoggedIn = keepLoggedIn;
    _currentDeveloper = DeveloperUser(
      userId: DeveloperUser.developerUserId,
      name: DeveloperUser.developerName,
      passwordHash: _storedHash,
      salt: _storedSalt,
      isLoggedIn: true,
      loggedInAt: now,
    );

    try {
      final file = _sessionFile;
      await file.writeAsString(jsonEncode({
        'userId': DeveloperUser.developerUserId,
        'name': DeveloperUser.developerName,
        'keepLoggedIn': keepLoggedIn,
        'loggedInAt': now,
      }));
    } catch (_) {}

    return true;
  }

  Future<void> logout() async {
    _currentDeveloper = null;
    try {
      final file = _sessionFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void setCurrentDeveloperForTesting(DeveloperUser? user) {
    _currentDeveloper = user;
  }

  void resetForTesting() {
    _currentDeveloper = null;
    _storedSalt = '';
    _storedHash = '';
  }
}
