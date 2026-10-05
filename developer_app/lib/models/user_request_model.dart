import 'developer_permissions.dart';

class UserRequestModel {
  final String requestId;
  final String userId;
  final String userName;
  final String deviceId;
  final String deviceName;
  final String requestType; // 'NEW_ACCOUNT', 'NEW_DEVICE', 'LOGIN'
  final String requestedRole; // 'LATEST_KHAJANI', 'OLD_KHAJANI'
  final String status; // 'PENDING', 'APPROVED', 'REJECTED', 'REVOKED'
  final String? approvedRole;
  final DeveloperPermissions permissions;
  final int createdAt;
  final int? updatedAt;
  final bool isOnline;

  const UserRequestModel({
    required this.requestId,
    required this.userId,
    required this.userName,
    required this.deviceId,
    this.deviceName = 'Android Device',
    this.requestType = 'NEW_ACCOUNT',
    this.requestedRole = 'OLD_KHAJANI',
    this.status = 'PENDING',
    String? role,
    String? approvedRole,
    this.permissions = const DeveloperPermissions.oldDefault(),
    required this.createdAt,
    this.updatedAt,
    this.isOnline = false,
  }) : approvedRole = role ?? approvedRole;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';
  bool get isRevoked => status == 'REVOKED';

  String get effectiveRole => approvedRole ?? requestedRole;
  String get role => effectiveRole;
  bool get isLatestKhajani => effectiveRole == 'LATEST_KHAJANI';
  bool get isOldKhajani => effectiveRole == 'OLD_KHAJANI';

  String get marathiStatus {
    switch (status) {
      case 'PENDING':
        return 'प्रलंबित (PENDING)';
      case 'APPROVED':
        return 'मंजूर (APPROVED)';
      case 'REJECTED':
        return 'नाकारले (REJECTED)';
      case 'REVOKED':
        return 'रद्द (REVOKED)';
      default:
        return status;
    }
  }

  String get marathiRole {
    if (effectiveRole == 'DEVELOPER') return 'डेव्हलपर (Developer)';
    if (effectiveRole == 'LATEST_KHAJANI') return 'चालू खजानी (Latest Khajani)';
    return 'माजी खजानी (Old Khajani)';
  }

  UserRequestModel copyWith({
    String? requestId,
    String? userId,
    String? userName,
    String? deviceId,
    String? deviceName,
    String? requestType,
    String? requestedRole,
    String? status,
    String? role,
    String? approvedRole,
    DeveloperPermissions? permissions,
    int? createdAt,
    int? updatedAt,
    bool? isOnline,
  }) {
    return UserRequestModel(
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      requestType: requestType ?? this.requestType,
      requestedRole: requestedRole ?? this.requestedRole,
      status: status ?? this.status,
      approvedRole: role ?? approvedRole ?? this.approvedRole,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
    );
  }

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
      if (approvedRole != null) 'approvedRole': approvedRole,
      'role': effectiveRole,
      'permissions': permissions.toMap(),
      'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory UserRequestModel.fromMap(Map<String, dynamic> map, {bool isOnline = false}) {
    final permsMap = map['permissions'] != null ? Map<String, dynamic>.from(map['permissions'] as Map) : null;
    return UserRequestModel(
      requestId: (map['requestId'] ?? map['request_id'] ?? '') as String,
      userId: (map['userId'] ?? map['user_id'] ?? '') as String,
      userName: (map['userName'] ?? map['user_name'] ?? 'वापरकर्ता') as String,
      deviceId: (map['deviceId'] ?? map['device_id'] ?? '') as String,
      deviceName: (map['deviceName'] ?? map['device_name'] ?? 'Android Device') as String,
      requestType: (map['requestType'] ?? map['request_type'] ?? 'NEW_ACCOUNT') as String,
      requestedRole: (map['requestedRole'] ?? map['requested_role'] ?? 'OLD_KHAJANI') as String,
      status: (map['status'] ?? 'PENDING') as String,
      approvedRole: (map['approvedRole'] ?? map['role']) as String?,
      permissions: DeveloperPermissions.fromMap(permsMap),
      createdAt: (map['createdAt'] ?? map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updatedAt'] ?? map['updated_at'] as num?)?.toInt(),
      isOnline: isOnline,
    );
  }

  factory UserRequestModel.fromJson(Map<String, dynamic> json, {bool isOnline = false}) =>
      UserRequestModel.fromMap(json, isOnline: isOnline);
}
