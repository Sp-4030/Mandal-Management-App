class DeviceStatus {
  static const String pending = 'PENDING';
  static const String approved = 'APPROVED';
  static const String rejected = 'REJECTED';
  static const String revoked = 'REVOKED';

  static bool isPending(String? status) => status == pending;
  static bool isApproved(String? status) => status == approved;
  static bool isRejected(String? status) => status == rejected;
  static bool isRevoked(String? status) => status == revoked;

  static String marathiTitle(String? status) {
    switch (status) {
      case pending:
        return 'प्रलंबित (Pending)';
      case approved:
        return 'मंजूर (Approved)';
      case rejected:
        return 'नाकारले (Rejected)';
      case revoked:
        return 'रद्द (Revoked)';
      default:
        return status ?? 'अनोळखी';
    }
  }
}

class HindviDevice {
  final String deviceId;
  final String deviceName;
  final String? userId;
  final String status;
  final int createdAt;
  final int updatedAt;
  final int lastSeenAt;

  const HindviDevice({
    required this.deviceId,
    required this.deviceName,
    this.userId,
    this.status = DeviceStatus.approved,
    required this.createdAt,
    required this.updatedAt,
    required this.lastSeenAt,
  });

  bool get isApproved => DeviceStatus.isApproved(status);
  bool get isPending => DeviceStatus.isPending(status);
  bool get isRevoked => DeviceStatus.isRevoked(status);
  bool get isRejected => DeviceStatus.isRejected(status);

  String get marathiStatus => DeviceStatus.marathiTitle(status);

  HindviDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? userId,
    String? status,
    int? createdAt,
    int? updatedAt,
    int? lastSeenAt,
  }) {
    return HindviDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'user_id': userId,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_seen_at': lastSeenAt,
    };
  }

  factory HindviDevice.fromMap(Map<String, dynamic> map) {
    return HindviDevice(
      deviceId: map['device_id'] as String,
      deviceName: (map['device_name'] as String?) ?? 'Unknown Device',
      userId: map['user_id'] as String?,
      status: (map['status'] as String?) ?? DeviceStatus.approved,
      createdAt: (map['created_at'] as num).toInt(),
      updatedAt: (map['updated_at'] as num).toInt(),
      lastSeenAt: (map['last_seen_at'] as num?)?.toInt() ??
          (map['updated_at'] as num).toInt(),
    );
  }
}

class DeviceRequestModel {
  final String requestId;
  final String userId;
  final String userName;
  final String deviceId;
  final String deviceName;
  final String requestType; // 'NEW_DEVICE', 'NEW_ACCOUNT', 'LOGIN'
  final String status; // 'PENDING', 'APPROVED', 'REJECTED', 'REVOKED'
  final String? requestedRole;
  final int createdAt;
  final int updatedAt;

  const DeviceRequestModel({
    required this.requestId,
    required this.userId,
    required this.userName,
    required this.deviceId,
    required this.deviceName,
    this.requestType = 'NEW_DEVICE',
    this.status = DeviceStatus.pending,
    this.requestedRole,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPending => DeviceStatus.isPending(status);
  bool get isApproved => DeviceStatus.isApproved(status);
  bool get isRejected => DeviceStatus.isRejected(status);
  bool get isRevoked => DeviceStatus.isRevoked(status);

  int get requestedAt => createdAt;

  String get marathiStatus => DeviceStatus.marathiTitle(status);

  String get marathiRequestType {
    switch (requestType) {
      case 'NEW_ACCOUNT':
        return 'नवीन खाते';
      case 'NEW_DEVICE':
        return 'नवीन डिव्हाइस';
      case 'LOGIN':
        return 'लॉगिन विनंती';
      default:
        return requestType;
    }
  }

  DeviceRequestModel copyWith({
    String? requestId,
    String? userId,
    String? userName,
    String? deviceId,
    String? deviceName,
    String? requestType,
    String? status,
    String? requestedRole,
    int? createdAt,
    int? updatedAt,
  }) {
    return DeviceRequestModel(
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      requestType: requestType ?? this.requestType,
      status: status ?? this.status,
      requestedRole: requestedRole ?? this.requestedRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'request_id': requestId,
      'user_id': userId,
      'user_name': userName,
      'device_id': deviceId,
      'device_name': deviceName,
      'request_type': requestType,
      'status': status,
      'requested_role': requestedRole,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory DeviceRequestModel.fromMap(Map<String, dynamic> map) {
    return DeviceRequestModel(
      requestId: map['request_id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      userName: (map['user_name'] as String?) ?? '',
      deviceId: (map['device_id'] as String?) ?? '',
      deviceName: (map['device_name'] as String?) ?? 'Unknown Device',
      requestType: (map['request_type'] as String?) ?? 'NEW_DEVICE',
      status: (map['status'] as String?) ?? DeviceStatus.pending,
      requestedRole: map['requested_role'] as String?,
      createdAt: (map['created_at'] as num).toInt(),
      updatedAt: (map['updated_at'] as num).toInt(),
    );
  }
}
