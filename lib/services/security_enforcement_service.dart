// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'signaling_service.dart';

enum SecurityAction {
  view,
  add,
  edit,
  delete,
  search,
  pdf,
  khajaniManagement,
  sync,
}

enum SecurityAccessStatus {
  checking,
  noInternet,
  revoked,
  pendingApproval,
  rejected,
  authorized,
  serverUnreachable,
  loginRequired,
}

class SecurityEnforcementService {
  static final SecurityEnforcementService instance =
      SecurityEnforcementService._internal();

  SecurityEnforcementService._internal();

  bool? _mockInternetOnline;
  Map<String, dynamic>? _mockServerAuthResponse;
  bool _mockBypassEnabled = false;

  final ValueNotifier<bool> isInternetOnlineNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<SecurityAccessStatus> accessStatusNotifier =
      ValueNotifier<SecurityAccessStatus>(SecurityAccessStatus.checking);

  final StreamController<void> _revokedStreamController =
      StreamController<void>.broadcast();
  Stream<void> get onRevoked => _revokedStreamController.stream;

  bool get isInternetOnline => _mockInternetOnline ?? isInternetOnlineNotifier.value;
  SecurityAccessStatus get accessStatus => accessStatusNotifier.value;

  // Testing helpers
  void setMockConnectivity(bool? isOnline) {
    _mockInternetOnline = isOnline;
    if (isOnline != null) {
      isInternetOnlineNotifier.value = isOnline;
      if (!isOnline) {
        accessStatusNotifier.value = SecurityAccessStatus.noInternet;
      }
    }
  }

  void setMockServerAuthResponse(Map<String, dynamic>? response) {
    _mockServerAuthResponse = response;
  }

  void setMockBypassEnabled(bool enabled) {
    _mockBypassEnabled = enabled;
  }

  void resetForTesting() {
    _mockInternetOnline = null;
    _mockServerAuthResponse = null;
    _mockBypassEnabled = false;
    isInternetOnlineNotifier.value = true;
    accessStatusNotifier.value = SecurityAccessStatus.checking;
  }

  /// Check active Internet connectivity using DNS lookup or test ping.
  /// Throws or returns false if offline.
  Future<bool> checkInternetConnectivity({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_mockInternetOnline != null) {
      isInternetOnlineNotifier.value = _mockInternetOnline!;
      return _mockInternetOnline!;
    }

    try {
      final lookup = await InternetAddress.lookup('dns.google')
          .timeout(timeout);
      final hasNet = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      isInternetOnlineNotifier.value = hasNet;
      if (!hasNet) {
        accessStatusNotifier.value = SecurityAccessStatus.noInternet;
      }
      return hasNet;
    } catch (_) {
      try {
        final lookupFallback = await InternetAddress.lookup('google.com')
            .timeout(timeout);
        final hasNet = lookupFallback.isNotEmpty &&
            lookupFallback[0].rawAddress.isNotEmpty;
        isInternetOnlineNotifier.value = hasNet;
        if (!hasNet) {
          accessStatusNotifier.value = SecurityAccessStatus.noInternet;
        }
        return hasNet;
      } catch (_) {
        isInternetOnlineNotifier.value = false;
        accessStatusNotifier.value = SecurityAccessStatus.noInternet;
        return false;
      }
    }
  }

  /// Triggers device revoked state immediately:
  /// - Clears local session
  /// - Marks DatabaseHelper device revoked
  /// - Notifies all UI listeners
  Future<void> triggerRevoked([String reason = 'Access Revoked. Contact Developer.']) async {
    print('[SECURITY] Device REVOKED event triggered: $reason');
    DatabaseHelper.instance.setDeviceRevokedState(true);
    try {
      await DeviceService.instance.revokeDevice(await DeviceService.instance.getDeviceId());
    } catch (_) {}
    try {
      await AuthService.instance.logout();
    } catch (_) {}
    accessStatusNotifier.value = SecurityAccessStatus.revoked;
    _revokedStreamController.add(null);
  }

  /// Connects to PC WebSocket server, authenticates with userId + deviceId,
  /// and retrieves the latest status, role, and permissions from the server.
  Future<Map<String, dynamic>> verifyServerAuthorization({
    String? userId,
    String? deviceId,
    String? requestId,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_mockBypassEnabled) {
      return {
        'isAuthorized': true,
        'status': 'APPROVED',
        'role': 'LATEST_KHAJANI',
      };
    }

    if (_mockServerAuthResponse != null) {
      final resp = _mockServerAuthResponse!;
      final status = (resp['status'] as String?) ?? 'APPROVED';
      if (status == 'REVOKED') {
        await triggerRevoked();
        return resp;
      }
      return resp;
    }

    // 1. Mandatory Internet Check
    final hasNet = await checkInternetConnectivity();
    if (!hasNet) {
      accessStatusNotifier.value = SecurityAccessStatus.noInternet;
      throw StateError(
        'Internet connection required\nPlease turn on Internet to continue.',
      );
    }

    final devId = deviceId ?? await DeviceService.instance.getDeviceId();
    final uId = userId ?? AuthService.instance.currentUser?.userId ?? '';

    // Check if locally marked revoked
    final isRevokedLocally = await DeviceService.instance.isCurrentDeviceRevoked();
    if (isRevokedLocally) {
      await triggerRevoked();
      return {
        'isAuthorized': false,
        'status': 'REVOKED',
        'message': 'Access Revoked. Contact Developer.',
      };
    }

    // 2. Query PC Server for latest status
    try {
      final response = await SignalingService.instance.authorizeAppAccess(
        deviceId: devId,
        userId: uId,
        requestId: requestId,
        timeout: timeout,
      );

      final status = (response['status'] as String?) ?? 'NOT_FOUND';

      if (status == 'REVOKED') {
        await triggerRevoked();
        return response;
      }

      if (status == 'APPROVED') {
        accessStatusNotifier.value = SecurityAccessStatus.authorized;

        // Apply latest roles and permissions from server
        final role = response['role'] as String?;
        final permissionsMap = response['permissions'] as Map<String, dynamic>?;

        if (uId.isNotEmpty && role != null) {
          final db = await DatabaseHelper.instance.database;
          final now = DateTime.now().millisecondsSinceEpoch;
          final updateData = <String, dynamic>{
            'role': role,
            'status': 'APPROVED',
            'updated_at': now,
          };
          if (permissionsMap != null) {
            updateData.addAll(permissionsMap);
          }
          await db.update(
            'khajani_users',
            updateData,
            where: 'user_id = ?',
            whereArgs: [uId],
          );

          // Update current user in memory
          final updatedUser = await AuthService.instance.getKhajaniById(uId);
          if (updatedUser != null) {
            AuthService.instance.setCurrentUserForTesting(updatedUser);
          }
        }

        return response;
      }

      if (status == 'PENDING') {
        accessStatusNotifier.value = SecurityAccessStatus.pendingApproval;
        return response;
      }

      if (status == 'REJECTED') {
        accessStatusNotifier.value = SecurityAccessStatus.rejected;
        return response;
      }

      return response;
    } on TimeoutException {
      accessStatusNotifier.value = SecurityAccessStatus.serverUnreachable;
      return {
        'isAuthorized': false,
        'status': 'SERVER_TIMEOUT',
        'message': 'PC सर्व्हरशी संपर्क होऊ शकला नाही. कृपया सर्व्हर सुरू असल्याची खात्री करा.',
      };
    } catch (e) {
      accessStatusNotifier.value = SecurityAccessStatus.serverUnreachable;
      return {
        'isAuthorized': false,
        'status': 'SERVER_ERROR',
        'message': 'सर्व्हर त्रुटी: $e',
      };
    }
  }

  /// Mandatory guard that MUST be called before any financial or app operation.
  /// Enforces:
  /// 1. Internet connection is ON.
  /// 2. Device is NOT revoked.
  /// 3. Specific permission is granted.
  void assertOnlineAndAuthorized({SecurityAction? action}) {
    if (_mockBypassEnabled) return;

    // Check Internet
    if (!isInternetOnline) {
      throw StateError(
        'Internet connection required\nPlease turn on Internet to continue.',
      );
    }

    // Check Revoked
    if (DatabaseHelper.instance.isDeviceRevoked) {
      throw StateError('Access Revoked. Contact Developer.');
    }

    // Check Permissions if an action is specified
    if (action != null) {
      final auth = AuthService.instance;
      if (auth.isDeveloper) return;

      switch (action) {
        case SecurityAction.view:
          if (!auth.canView) {
            throw StateError('आर्थिक माहिती पाहण्याची परवानगी (View Permission) नाही.');
          }
          break;
        case SecurityAction.add:
          if (!auth.canAdd) {
            throw StateError('नवीन नोंद जोडण्याची परवानगी (Add Permission) नाही.');
          }
          break;
        case SecurityAction.edit:
          if (!auth.canEdit) {
            throw StateError('नोंद बदलण्याची परवानगी (Edit Permission) नाही.');
          }
          break;
        case SecurityAction.delete:
          if (!auth.canDelete) {
            throw StateError('नोंद हटवण्याची परवानगी (Delete Permission) नाही.');
          }
          break;
        case SecurityAction.search:
          if (!auth.canSearch) {
            throw StateError('नोंद शोधण्याची परवानगी (Search Permission) नाही.');
          }
          break;
        case SecurityAction.pdf:
          if (!auth.canPdf) {
            throw StateError('अहवाल PDF तयार करण्याची परवानगी (PDF Permission) नाही.');
          }
          break;
        case SecurityAction.khajaniManagement:
          throw StateError('Developer Management is now handled exclusively by the separate Developer App.');
        case SecurityAction.sync:
          if (!auth.canSync) {
            throw StateError('डेटा सिंक करण्याची परवानगी (Sync Permission) नाही.');
          }
          break;
      }
    }
  }
}
