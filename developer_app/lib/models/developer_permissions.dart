class DeveloperPermissions {
  final bool canView;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final bool canSearch;
  final bool canPdf;
  final bool canManageKhajani;
  final bool canSync;

  const DeveloperPermissions({
    this.canView = true,
    this.canAdd = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canSearch = true,
    this.canPdf = true,
    this.canManageKhajani = false,
    this.canSync = false,
  });

  const DeveloperPermissions.latestDefault()
      : canView = true,
        canAdd = true,
        canEdit = true,
        canDelete = true,
        canSearch = true,
        canPdf = true,
        canManageKhajani = true,
        canSync = true;

  const DeveloperPermissions.oldDefault()
      : canView = true,
        canAdd = false,
        canEdit = false,
        canDelete = false,
        canSearch = true,
        canPdf = true,
        canManageKhajani = false,
        canSync = false;

  const DeveloperPermissions.pending()
      : canView = false,
        canAdd = false,
        canEdit = false,
        canDelete = false,
        canSearch = false,
        canPdf = false,
        canManageKhajani = false,
        canSync = false;

  DeveloperPermissions copyWith({
    bool? canView,
    bool? canAdd,
    bool? canEdit,
    bool? canDelete,
    bool? canSearch,
    bool? canPdf,
    bool? canManageKhajani,
    bool? canSync,
  }) {
    return DeveloperPermissions(
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

  factory DeveloperPermissions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DeveloperPermissions.oldDefault();
    return DeveloperPermissions(
      canView: _asBool(map['can_view'] ?? map['canView'], defaultValue: true),
      canAdd: _asBool(map['can_add'] ?? map['canAdd'], defaultValue: false),
      canEdit: _asBool(map['can_edit'] ?? map['canEdit'], defaultValue: false),
      canDelete: _asBool(map['can_delete'] ?? map['canDelete'], defaultValue: false),
      canSearch: _asBool(map['can_search'] ?? map['canSearch'], defaultValue: true),
      canPdf: _asBool(map['can_pdf'] ?? map['canPdf'], defaultValue: true),
      canManageKhajani: _asBool(map['can_manage_khajani'] ?? map['canManageKhajani'], defaultValue: false),
      canSync: _asBool(map['can_sync'] ?? map['canSync'], defaultValue: false),
    );
  }

  static bool _asBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == '1' || lower == 'true') return true;
      if (lower == '0' || lower == 'false') return false;
    }
    return defaultValue;
  }
}
