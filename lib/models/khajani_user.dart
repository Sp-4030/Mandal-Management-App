class KhajaniRole {
  static const String developer = 'DEVELOPER';
  static const String latestKhajani = 'LATEST_KHAJANI';
  static const String oldKhajani = 'OLD_KHAJANI';

  static bool isDeveloper(String? role) => role == developer;
  static bool isLatest(String? role) => role == latestKhajani;
  static bool isOld(String? role) => role == oldKhajani;

  static String marathiTitle(String? role) {
    switch (role) {
      case developer:
        return 'डेव्हलपर (Admin)';
      case latestKhajani:
        return 'चालू खजानी';
      case oldKhajani:
        return 'माजी खजानी';
      default:
        return 'अनोळखी';
    }
  }
}

class KhajaniStatus {
  static const String pending = 'PENDING';
  static const String approved = 'APPROVED';

  static bool isPending(String? status) => status == pending;
  static bool isApproved(String? status) =>
      status == approved || status == null || status.isEmpty;

  static String marathiTitle(String? status) {
    switch (status) {
      case pending:
        return 'प्रलंबित (Pending)';
      case approved:
        return 'मंजूर (Approved)';
      default:
        return status ?? 'अनोळखी';
    }
  }
}

class KhajaniPermissions {
  final bool canView;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final bool canSearch;
  final bool canPdf;
  final bool canManageKhajani;
  final bool canSync;
  final bool isCustomized;

  const KhajaniPermissions({
    this.canView = true,
    this.canAdd = true,
    this.canEdit = true,
    this.canDelete = true,
    this.canSearch = true,
    this.canPdf = true,
    this.canManageKhajani = true,
    this.canSync = true,
  }) : isCustomized = true;

  const KhajaniPermissions.unspecified()
      : canView = true,
        canAdd = true,
        canEdit = true,
        canDelete = true,
        canSearch = true,
        canPdf = true,
        canManageKhajani = true,
        canSync = true,
        isCustomized = false;

  const KhajaniPermissions.developer()
      : canView = true,
        canAdd = true,
        canEdit = true,
        canDelete = true,
        canSearch = true,
        canPdf = true,
        canManageKhajani = true,
        canSync = true,
        isCustomized = true;

  const KhajaniPermissions.latestDefault()
      : canView = true,
        canAdd = true,
        canEdit = true,
        canDelete = true,
        canSearch = true,
        canPdf = true,
        canManageKhajani = true,
        canSync = true,
        isCustomized = true;

  const KhajaniPermissions.oldDefault()
      : canView = true,
        canAdd = false,
        canEdit = false,
        canDelete = false,
        canSearch = true,
        canPdf = true,
        canManageKhajani = false,
        canSync = false,
        isCustomized = true;

  const KhajaniPermissions.pending()
      : canView = false,
        canAdd = false,
        canEdit = false,
        canDelete = false,
        canSearch = false,
        canPdf = false,
        canManageKhajani = false,
        canSync = false,
        isCustomized = true;

  KhajaniPermissions copyWith({
    bool? canView,
    bool? canAdd,
    bool? canEdit,
    bool? canDelete,
    bool? canSearch,
    bool? canPdf,
    bool? canManageKhajani,
    bool? canSync,
  }) {
    return KhajaniPermissions(
      canView: canView ?? this.canView,
      canAdd: canAdd ?? this.canAdd,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      canSearch: canSearch ?? this.canSearch,
      canPdf: canPdf ?? this.canPdf,
      canManageKhajani: canManageKhajani ?? this.canManageKhajani,
      canSync: canSync ?? this.canSync,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'can_view': canView ? 1 : 0,
      'can_add': canAdd ? 1 : 0,
      'can_edit': canEdit ? 1 : 0,
      'can_delete': canDelete ? 1 : 0,
      'can_search': canSearch ? 1 : 0,
      'can_pdf': canPdf ? 1 : 0,
      'can_manage_khajani': canManageKhajani ? 1 : 0,
      'can_sync': canSync ? 1 : 0,
    };
  }

  factory KhajaniPermissions.fromMap(Map<String, dynamic> map, {String? role}) {
    final isDeveloper = role == KhajaniRole.developer;
    final isOld = role == KhajaniRole.oldKhajani;
    final defaultForRole = isDeveloper
        ? const KhajaniPermissions.developer()
        : (isOld
            ? const KhajaniPermissions.oldDefault()
            : const KhajaniPermissions.latestDefault());

    return KhajaniPermissions(
      canView: map.containsKey('can_view')
          ? ((map['can_view'] as num?)?.toInt() == 1)
          : defaultForRole.canView,
      canAdd: map.containsKey('can_add')
          ? ((map['can_add'] as num?)?.toInt() == 1)
          : defaultForRole.canAdd,
      canEdit: map.containsKey('can_edit')
          ? ((map['can_edit'] as num?)?.toInt() == 1)
          : defaultForRole.canEdit,
      canDelete: map.containsKey('can_delete')
          ? ((map['can_delete'] as num?)?.toInt() == 1)
          : defaultForRole.canDelete,
      canSearch: map.containsKey('can_search')
          ? ((map['can_search'] as num?)?.toInt() == 1)
          : defaultForRole.canSearch,
      canPdf: map.containsKey('can_pdf')
          ? ((map['can_pdf'] as num?)?.toInt() == 1)
          : defaultForRole.canPdf,
      canManageKhajani: map.containsKey('can_manage_khajani')
          ? ((map['can_manage_khajani'] as num?)?.toInt() == 1)
          : defaultForRole.canManageKhajani,
      canSync: map.containsKey('can_sync')
          ? ((map['can_sync'] as num?)?.toInt() == 1)
          : defaultForRole.canSync,
    );
  }
}

class KhajaniUser {
  final String userId;
  final String name;
  final String passwordHash;
  final String salt;
  final String role;
  final String status;
  final bool isActive;
  final KhajaniPermissions permissions;
  final int createdAt;
  final int updatedAt;

  const KhajaniUser({
    required this.userId,
    required this.name,
    required this.passwordHash,
    required this.salt,
    required this.role,
    this.status = KhajaniStatus.approved,
    this.isActive = true,
    this.permissions = const KhajaniPermissions.unspecified(),
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDeveloper => KhajaniRole.isDeveloper(role);
  bool get isLatestKhajani => KhajaniRole.isLatest(role);
  bool get isOldKhajani => KhajaniRole.isOld(role);
  bool get isPending => KhajaniStatus.isPending(status);
  bool get isApproved => !isPending;

  KhajaniPermissions get effectivePermissions {
    if (isPending) {
      return const KhajaniPermissions.pending();
    }
    if (permissions.isCustomized) {
      return permissions;
    }
    if (isDeveloper) return const KhajaniPermissions.developer();
    if (isOldKhajani) return const KhajaniPermissions.oldDefault();
    return const KhajaniPermissions.latestDefault();
  }

  bool get canModify =>
      !isPending &&
      (isDeveloper ||
          (isLatestKhajani &&
              effectivePermissions.canAdd &&
              effectivePermissions.canEdit));

  String get marathiRole => KhajaniRole.marathiTitle(role);
  String get marathiStatus => KhajaniStatus.marathiTitle(status);

  KhajaniUser copyWith({
    String? userId,
    String? name,
    String? passwordHash,
    String? salt,
    String? role,
    String? status,
    bool? isActive,
    KhajaniPermissions? permissions,
    int? createdAt,
    int? updatedAt,
  }) {
    final nextRole = role ?? this.role;
    KhajaniPermissions nextPerms;
    if (permissions != null) {
      nextPerms = permissions;
    } else if (role != null && role != this.role) {
      nextPerms = KhajaniRole.isDeveloper(nextRole)
          ? const KhajaniPermissions.developer()
          : (KhajaniRole.isOld(nextRole)
              ? const KhajaniPermissions.oldDefault()
              : const KhajaniPermissions.latestDefault());
    } else {
      nextPerms = this.permissions;
    }

    return KhajaniUser(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      role: nextRole,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      permissions: nextPerms,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    final perms = effectivePermissions;
    return {
      'user_id': userId,
      'name': name,
      'password_hash': passwordHash,
      'salt': salt,
      'role': role,
      'status': status,
      'is_active': isActive ? 1 : 0,
      'can_view': perms.canView ? 1 : 0,
      'can_add': perms.canAdd ? 1 : 0,
      'can_edit': perms.canEdit ? 1 : 0,
      'can_delete': perms.canDelete ? 1 : 0,
      'can_search': perms.canSearch ? 1 : 0,
      'can_pdf': perms.canPdf ? 1 : 0,
      'can_manage_khajani': perms.canManageKhajani ? 1 : 0,
      'can_sync': perms.canSync ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory KhajaniUser.fromMap(Map<String, dynamic> map) {
    final role = map['role'] as String;
    final status = (map['status'] as String?) ?? KhajaniStatus.approved;
    return KhajaniUser(
      userId: map['user_id'] as String,
      name: map['name'] as String,
      passwordHash: map['password_hash'] as String,
      salt: map['salt'] as String,
      role: role,
      status: status,
      isActive: map.containsKey('is_active')
          ? ((map['is_active'] as num?)?.toInt() == 1)
          : true,
      permissions: KhajaniPermissions.fromMap(map, role: role),
      createdAt: (map['created_at'] as num).toInt(),
      updatedAt: (map['updated_at'] as num).toInt(),
    );
  }
}
