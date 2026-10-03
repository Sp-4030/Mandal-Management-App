import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Semantic App Version representation for reliable version comparisons.
class AppVersion implements Comparable<AppVersion> {
  final List<int> numbers;
  final String? suffix;
  final String raw;

  AppVersion._(this.numbers, this.suffix, this.raw);

  factory AppVersion.parse(String versionString) {
    final raw = versionString.trim();
    var clean = raw;

    // Strip leading 'v' or 'V' (e.g. v1.1.0 -> 1.1.0)
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1).trim();
    }

    // Strip build metadata (+...) or prerelease tags (-...)
    String? suffix;
    if (clean.contains('+')) {
      final parts = clean.split('+');
      clean = parts[0];
      suffix = parts.sublist(1).join('+');
    } else if (clean.contains('-')) {
      final parts = clean.split('-');
      clean = parts[0];
      suffix = parts.sublist(1).join('-');
    }

    // Split by '.' and parse numerical components
    final segments = clean.split('.');
    final numbers = <int>[];
    for (final seg in segments) {
      final num = int.tryParse(seg);
      if (num != null) {
        numbers.add(num);
      } else {
        // Extract leading digits if segment is alphanumeric
        final match = RegExp(r'^\d+').firstMatch(seg);
        numbers.add(match != null ? int.parse(match.group(0)!) : 0);
      }
    }

    // Ensure at least major, minor, patch (e.g. 1.0 -> 1.0.0)
    while (numbers.length < 3) {
      numbers.add(0);
    }

    return AppVersion._(numbers, suffix, raw);
  }

  @override
  int compareTo(AppVersion other) {
    final maxLen = numbers.length > other.numbers.length
        ? numbers.length
        : other.numbers.length;
    for (int i = 0; i < maxLen; i++) {
      final a = i < numbers.length ? numbers[i] : 0;
      final b = i < other.numbers.length ? other.numbers[i] : 0;
      if (a != b) {
        return a.compareTo(b);
      }
    }
    return 0;
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  String get displayVersion {
    if (numbers.length >= 3) {
      return '${numbers[0]}.${numbers[1]}.${numbers[2]}';
    }
    return numbers.join('.');
  }

  @override
  String toString() => displayVersion;
}

/// Information about a GitHub release.
class UpdateInfo {
  final String tagName;
  final String versionName;
  final String title;
  final String body;
  final String? apkDownloadUrl;
  final int apkSizeBytes;
  final String? apkFileName;

  const UpdateInfo({
    required this.tagName,
    required this.versionName,
    required this.title,
    required this.body,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
    required this.apkFileName,
  });

  bool get hasApk => apkDownloadUrl != null && apkDownloadUrl!.isNotEmpty;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String?) ?? '';
    final name = (json['name'] as String?) ?? '';
    final body = (json['body'] as String?) ?? '';

    // Clean version from tagName (e.g. v1.1.0 -> 1.1.0)
    final parsedVersion = AppVersion.parse(tagName.isNotEmpty ? tagName : name);

    // Search release assets for app-release.apk or any .apk
    String? downloadUrl;
    String? fileName;
    int sizeBytes = 0;

    final assets = json['assets'] as List<dynamic>?;
    if (assets != null && assets.isNotEmpty) {
      // 1. Try to find exact 'app-release.apk'
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final assetName = (asset['name'] as String?) ?? '';
          if (assetName.toLowerCase() == 'app-release.apk') {
            downloadUrl = asset['browser_download_url'] as String?;
            fileName = assetName;
            sizeBytes = (asset['size'] as num?)?.toInt() ?? 0;
            break;
          }
        }
      }

      // 2. If not found, pick the first .apk asset
      if (downloadUrl == null) {
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final assetName = (asset['name'] as String?) ?? '';
            if (assetName.toLowerCase().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String?;
              fileName = assetName;
              sizeBytes = (asset['size'] as num?)?.toInt() ?? 0;
              break;
            }
          }
        }
      }
    }

    return UpdateInfo(
      tagName: tagName,
      versionName: parsedVersion.displayVersion,
      title: name.isNotEmpty ? name : tagName,
      body: body,
      apkDownloadUrl: downloadUrl,
      apkSizeBytes: sizeBytes,
      apkFileName: fileName,
    );
  }
}

/// Status of update check result.
enum UpdateCheckStatus {
  upToDate,
  updateAvailable,
  noApkAvailable,
  error,
}

/// Result returned from checking updates.
class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String currentVersion;
  final String? latestVersion;
  final UpdateInfo? updateInfo;
  final String? errorMessage;

  const UpdateCheckResult._({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.updateInfo,
    this.errorMessage,
  });

  factory UpdateCheckResult.upToDate({
    required String currentVersion,
    required String latestVersion,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.upToDate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
    );
  }

  factory UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required String latestVersion,
    required UpdateInfo updateInfo,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.updateAvailable,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      updateInfo: updateInfo,
    );
  }

  factory UpdateCheckResult.noApkAvailable({
    required String currentVersion,
    required String latestVersion,
    required UpdateInfo updateInfo,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.noApkAvailable,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      updateInfo: updateInfo,
      errorMessage: 'या आवृत्तीसाठी APK उपलब्ध नाही.',
    );
  }

  factory UpdateCheckResult.error({
    required String currentVersion,
    required String errorMessage,
  }) {
    return UpdateCheckResult._(
      status: UpdateCheckStatus.error,
      currentVersion: currentVersion,
      errorMessage: errorMessage,
    );
  }
}

/// Token to allow cancelling an ongoing APK download.
class UpdateCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

/// Service handling App Updates using GitHub Releases and native Android installer.
class UpdateService {
  static const MethodChannel _channel = MethodChannel('com.hindvi.app/updater');
  static const String githubRepo = 'Sp-4030/Mandal-Management-App';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  // Standard fallback version if not retrieved from native platform
  static const String defaultVersion = '1.0.0';

  /// Retrieves the current app version from the native Android package.
  Future<String> getCurrentVersion() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getAppVersion');
      if (result != null && result['versionName'] != null) {
        return AppVersion.parse(result['versionName'].toString()).displayVersion;
      }
    } catch (_) {
      // Fallback on platform channel error (e.g. desktop/unit test)
    }
    return defaultVersion;
  }

  /// Checks GitHub Releases API for the latest version.
  Future<UpdateCheckResult> checkForUpdate({
    String? currentVersionOverride,
    HttpClient? httpClientOverride,
  }) async {
    final currentVerStr = currentVersionOverride ?? await getCurrentVersion();
    final currentAppVersion = AppVersion.parse(currentVerStr);

    final client = httpClientOverride ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final uri = Uri.parse(latestReleaseApiUrl);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Hindvi-Mandal-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response =
          await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final responseBody =
            await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        final updateInfo = UpdateInfo.fromJson(json);
        final latestAppVersion = AppVersion.parse(updateInfo.versionName);

        if (latestAppVersion.isNewerThan(currentAppVersion)) {
          if (!updateInfo.hasApk) {
            return UpdateCheckResult.noApkAvailable(
              currentVersion: currentAppVersion.displayVersion,
              latestVersion: latestAppVersion.displayVersion,
              updateInfo: updateInfo,
            );
          }
          return UpdateCheckResult.updateAvailable(
            currentVersion: currentAppVersion.displayVersion,
            latestVersion: latestAppVersion.displayVersion,
            updateInfo: updateInfo,
          );
        } else {
          return UpdateCheckResult.upToDate(
            currentVersion: currentAppVersion.displayVersion,
            latestVersion: latestAppVersion.displayVersion,
          );
        }
      } else if (response.statusCode == 404) {
        return UpdateCheckResult.error(
          currentVersion: currentAppVersion.displayVersion,
          errorMessage: 'कोणतेही नवीन अपडेट सापडले नाही.',
        );
      } else if (response.statusCode == 403) {
        final rateLimitRemaining =
            response.headers.value('x-ratelimit-remaining');
        if (rateLimitRemaining == '0') {
          return UpdateCheckResult.error(
            currentVersion: currentAppVersion.displayVersion,
            errorMessage:
                'GitHub विनंती मर्यादा संपली आहे. कृपया थोड्या वेळाने प्रयत्न करा.',
          );
        }
        return UpdateCheckResult.error(
          currentVersion: currentAppVersion.displayVersion,
          errorMessage: 'सर्व्हरशी संपर्क होऊ शकला नाही. (HTTP 403)',
        );
      } else {
        return UpdateCheckResult.error(
          currentVersion: currentAppVersion.displayVersion,
          errorMessage:
              'सर्व्हरशी संपर्क होऊ शकला नाही. (HTTP ${response.statusCode})',
        );
      }
    } on SocketException {
      return UpdateCheckResult.error(
        currentVersion: currentAppVersion.displayVersion,
        errorMessage: 'इंटरनेट कनेक्शन उपलब्ध नाही.',
      );
    } on TimeoutException {
      return UpdateCheckResult.error(
        currentVersion: currentAppVersion.displayVersion,
        errorMessage: 'नेटवर्क टाइमआउट झाले. कृपया पुन्हा प्रयत्न करा.',
      );
    } catch (e) {
      return UpdateCheckResult.error(
        currentVersion: currentAppVersion.displayVersion,
        errorMessage:
            'अपडेट तपासताना त्रुटी आढळली. कृपया थोड्या वेळाने प्रयत्न करा.',
      );
    } finally {
      if (httpClientOverride == null) {
        client.close();
      }
    }
  }

  /// Downloads the APK directly inside the app while reporting progress.
  /// Validates that the downloaded file is a valid APK before returning.
  Future<File> downloadApk({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes)
        onProgress,
    UpdateCancelToken? cancelToken,
  }) async {
    // 1. Resolve safe download directory in cache
    String targetDirPath;
    try {
      final dir =
          await _channel.invokeMethod<String>('getUpdateDirectory');
      if (dir != null && dir.isNotEmpty) {
        targetDirPath = dir;
      } else {
        targetDirPath = Directory.systemTemp.path;
      }
    } catch (_) {
      targetDirPath = Directory.systemTemp.path;
    }

    final targetDir = Directory(targetDirPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final finalApkFile = File('${targetDir.path}/app-release.apk');
    final tempApkFile = File('${targetDir.path}/app-release.apk.download');

    // Clean up any stale partial files
    if (await tempApkFile.exists()) {
      await tempApkFile.delete();
    }
    if (await finalApkFile.exists()) {
      await finalApkFile.delete();
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    IOSink? sink;
    try {
      final uri = Uri.parse(downloadUrl);
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response =
          await request.close().timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw HttpException(
            'डाउनलोड अयशस्वी झाले (HTTP ${response.statusCode})');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      sink = tempApkFile.openWrite();

      await for (final chunk in response) {
        if (cancelToken?.isCancelled == true) {
          throw Exception('डाउनलोड वापरकर्त्याने रद्द केले.');
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        final double progress = totalBytes > 0
            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
            : 0.0;
        onProgress(progress, receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (cancelToken?.isCancelled == true) {
        if (await tempApkFile.exists()) await tempApkFile.delete();
        throw Exception('डाउनलोड रद्द केले.');
      }

      // 2. Validate the downloaded file
      if (!await tempApkFile.exists()) {
        throw Exception('डाउनलोड केलेली फाइल सापडली नाही.');
      }

      final fileSize = await tempApkFile.length();
      if (fileSize == 0) {
        await tempApkFile.delete();
        throw Exception('डाउनलोड केलेली फाइल रिकामी आहे.');
      }

      if (totalBytes > 0 && fileSize < totalBytes) {
        await tempApkFile.delete();
        throw Exception('डाउनलोड खंडित झाले. कृपया पुन्हा प्रयत्न करा.');
      }

      // Check APK/ZIP magic header: 0x50, 0x4B, 0x03, 0x04 ('PK\x03\x04')
      final headerBytes = await tempApkFile.openRead(0, 4).first;
      if (headerBytes.length < 4 ||
          headerBytes[0] != 0x50 ||
          headerBytes[1] != 0x4B ||
          headerBytes[2] != 0x03 ||
          headerBytes[3] != 0x04) {
        await tempApkFile.delete();
        throw Exception('अवैध APK फाइल.');
      }

      // 3. Rename verified temp file to final APK
      await tempApkFile.rename(finalApkFile.path);
      return finalApkFile;
    } on SocketException {
      if (await tempApkFile.exists()) await tempApkFile.delete();
      throw Exception('इंटरनेट कनेक्शन उपलब्ध नाही.');
    } on TimeoutException {
      if (await tempApkFile.exists()) await tempApkFile.delete();
      throw Exception('नेटवर्क टाइमआउट झाले. कृपया पुन्हा प्रयत्न करा.');
    } catch (e) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (await tempApkFile.exists()) {
        try {
          await tempApkFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Checks if the app has permission to install unknown apps on Android 8.0+.
  Future<bool> canInstallPackages() async {
    try {
      final canInstall =
          await _channel.invokeMethod<bool>('canInstallPackages');
      return canInstall ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the Android system settings screen for "Install unknown apps".
  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  /// Launches the Android system package installer for the given APK file path.
  Future<void> installApk(String filePath) async {
    try {
      await _channel.invokeMethod('installApk', {'filePath': filePath});
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'इन्स्टॉलर उघडताना त्रुटी आढळली.');
    }
  }
}
