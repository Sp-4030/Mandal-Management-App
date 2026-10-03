import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device_model.dart';
import '../models/khajani_user.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/signaling_service.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _ink = Color(0xFF25231F);

class KhajaniManagementScreen extends StatefulWidget {
  final bool initialLoading;
  final List<KhajaniUser>? initialKhajanis;
  final int initialTabIndex;

  const KhajaniManagementScreen({
    super.key,
    this.initialLoading = true,
    this.initialKhajanis,
    this.initialTabIndex = 0,
  });

  @override
  State<KhajaniManagementScreen> createState() =>
      _KhajaniManagementScreenState();
}

class _KhajaniManagementScreenState extends State<KhajaniManagementScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService.instance;
  final DeviceService _deviceService = DeviceService.instance;
  final SignalingService _signalingService = SignalingService.instance;

  List<KhajaniUser> _khajaniList = [];
  List<HindviDevice> _devicesList = [];
  List<DeviceRequestModel> _deviceRequestsList = [];
  StreamSubscription? _signalingSub;

  late bool _isLoading;
  String _searchQuery = '';
  String _selectedFilter = 'ALL'; // ALL, LATEST, OLD, INACTIVE

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _isLoading = widget.initialLoading;
    if (widget.initialKhajanis != null) {
      _khajaniList = widget.initialKhajanis!;
    }

    if (_authService.isDeveloper) {
      _tabController = TabController(
        length: 3,
        vsync: this,
        initialIndex: widget.initialTabIndex.clamp(0, 2),
      );
      _tabController!.addListener(() {
        if (mounted) setState(() {});
      });
    }

    _signalingSub = _signalingService.onMessage.listen((msg) {
      final type = msg['type'] as String?;
      if (type == 'new_pending_request' || type == 'pending_requests_list') {
        _loadKhajanis();
      }
    });

    if (widget.initialLoading) {
      _loadKhajanis();
    }
  }

  @override
  void dispose() {
    _signalingSub?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadKhajanis() async {
    setState(() => _isLoading = true);
    try {
      final list = await _authService.getAllKhajanis(includePending: true);
      final devices = await _deviceService.getAllDevices();
      final reqs = await _deviceService.getDeviceRequests();
      if (mounted) {
        setState(() {
          _khajaniList = list;
          _devicesList = devices;
          _deviceRequestsList = reqs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    const marathiMonths = [
      'जानेवारी',
      'फेब्रुवारी',
      'मार्च',
      'एप्रिल',
      'मे',
      'जून',
      'जुलै',
      'ऑगस्ट',
      'सप्टेंबर',
      'ऑक्टोबर',
      'नोव्हेंबर',
      'डिसेंबर',
    ];
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${marathiMonths[dt.month - 1]} ${dt.year}, $hour12:$minuteStr $period';
  }

  List<KhajaniUser> get _pendingRequests =>
      _khajaniList.where((u) => u.isPending).toList();

  List<KhajaniUser> get _approvedUsers =>
      _khajaniList.where((u) => u.isApproved).toList();

  List<KhajaniUser> get _filteredApprovedList {
    return _approvedUsers.where((u) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = u.name.toLowerCase().contains(q);
        final matchesId = u.userId.toLowerCase().contains(q);
        if (!matchesName && !matchesId) return false;
      }

      if (_selectedFilter == 'LATEST') {
        return u.isLatestKhajani;
      } else if (_selectedFilter == 'OLD') {
        return u.isOldKhajani;
      } else if (_selectedFilter == 'INACTIVE') {
        return !u.isActive;
      }
      return true;
    }).toList();
  }

  List<KhajaniUser> get _filteredPendingList {
    return _pendingRequests.where((u) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = u.name.toLowerCase().contains(q);
        final matchesId = u.userId.toLowerCase().contains(q);
        if (!matchesName && !matchesId) return false;
      }
      return true;
    }).toList();
  }

  // ============================================================
  // DEVELOPER: APPROVE PENDING REQUEST DIALOG
  // ============================================================

  void _showApprovePendingRequestDialog(
    KhajaniUser user, {
    String? deviceId,
    String? requestType,
  }) {
    String selectedRole = KhajaniRole.latestKhajani;
    KhajaniPermissions permissions = const KhajaniPermissions.latestDefault();
    String? dialogError;
    bool isSaving = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Row(
                children: [
                  Icon(Icons.how_to_reg, color: Colors.green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'विनंती मंजूर करा (Approve Request)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // User Info Summary Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9E6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person,
                                    size: 18, color: _deepSaffron),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'वापरकर्ता: ${user.name}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.amber.shade700),
                                  ),
                                  child: Text(
                                    user.status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'User ID: ${user.userId}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF756A5D),
                              ),
                            ),
                            Text(
                              'Device ID: ${deviceId ?? "D-Unknown"}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF756A5D),
                              ),
                            ),
                            if (requestType != null)
                              Text(
                                'Request Type: $requestType',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF756A5D),
                                ),
                              ),
                            Text(
                              'विनंती दिनांक: ${_formatDate(user.createdAt)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF756A5D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (dialogError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFECEC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFCDCD)),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB00020),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Role Selection
                      const Text(
                        'भूमिका (Role) निवडा:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: KhajaniRole.latestKhajani,
                            child: Text('चालू खजानी (LATEST_KHAJANI)'),
                          ),
                          DropdownMenuItem(
                            value: KhajaniRole.oldKhajani,
                            child: Text('माजी खजानी (OLD_KHAJANI)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedRole = val;
                              permissions = val == KhajaniRole.latestKhajani
                                  ? const KhajaniPermissions.latestDefault()
                                  : const KhajaniPermissions.oldDefault();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Permissions Header
                      const Text(
                        'परवानग्या चालू/बंद करा (Permissions ON/OFF):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Permissions Toggles
                      _buildDialogSwitchTile(
                        'View (माहिती पाहणे)',
                        permissions.canView,
                        (v) => setDialogState(
                            () => permissions = permissions.copyWith(canView: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Add (नवीन नोंद जोडणे)',
                        permissions.canAdd,
                        (v) => setDialogState(
                            () => permissions = permissions.copyWith(canAdd: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Edit (नोंद बदलणे)',
                        permissions.canEdit,
                        (v) => setDialogState(
                            () => permissions = permissions.copyWith(canEdit: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Delete (नोंद हटवणे)',
                        permissions.canDelete,
                        (v) => setDialogState(
                            () => permissions = permissions.copyWith(canDelete: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Search (नोंद शोधणे)',
                        permissions.canSearch,
                        (v) => setDialogState(() => permissions =
                            permissions.copyWith(canSearch: v)),
                      ),
                      _buildDialogSwitchTile(
                        'PDF (अहवाल डाऊनलोड)',
                        permissions.canPdf,
                        (v) => setDialogState(
                            () => permissions = permissions.copyWith(canPdf: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Manage (खजानी व्यवस्थापन)',
                        permissions.canManageKhajani,
                        (v) => setDialogState(() => permissions =
                            permissions.copyWith(canManageKhajani: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Sync (डेटा सिंक/ट्रान्सफर)',
                        permissions.canSync,
                        (v) => setDialogState(
                            () => permissions = permissions.copyWith(canSync: v)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogCtx);

                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });
                          try {
                            await _authService.approveKhajaniRequest(
                              userId: user.userId,
                              role: selectedRole,
                              permissions: permissions,
                              deviceId: deviceId,
                            );

                            if (!mounted) return;
                            nav.pop();

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '"${user.name}" यांचे खाते यशस्वीरीत्या मंजूर (APPROVED) झाले. रोल: ${KhajaniRole.marathiTitle(selectedRole)}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );

                            _loadKhajanis();
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              dialogError = e
                                  .toString()
                                  .replaceAll('Exception: ', '')
                                  .replaceAll('StateError: ', '')
                                  .replaceAll('ArgumentError: ', '');
                            });
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('मंजूर करा (APPROVE)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DEVELOPER: DELETE PENDING REQUEST CONFIRMATION
  // ============================================================

  Future<void> _handleDeletePendingRequest(KhajaniUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text('विनंती हटवा (Delete Request)'),
              ),
            ],
          ),
          content: Text(
            'तुम्हाला खरोखर "${user.name}" (ID: ${user.userId}) यांची खाते विनंती कायमची हटवायची आहे का?\n\n'
            '• ही कृती पूर्ववत करता येणार नाही.\n'
            '• त्या वापरकर्त्याला पुढे लॉगिन करता येणार नाही.\n'
            '• त्याला कोणताही ॲप किंवा डेटा ॲक्सेस राहणार नाही.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('कायमचे हटवा (DELETE)'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _authService.deleteKhajani(userId: user.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${user.name}" यांची खाते विनंती कायमची हटवली.'),
          backgroundColor: Colors.red,
        ),
      );
      _loadKhajanis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // DEVELOPER: CREATE NEW KHAJANI DIALOG
  // ============================================================

  void _showCreateKhajaniByDeveloperDialog() {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String selectedRole = KhajaniRole.latestKhajani;
    KhajaniPermissions permissions = const KhajaniPermissions.latestDefault();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    String? dialogError;
    bool isSaving = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: _deepSaffron),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'नवीन खजानी तयार करा',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (dialogError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFECEC),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFFFCDCD)),
                            ),
                            child: Text(
                              dialogError!,
                              style: const TextStyle(
                                color: Color(0xFFB00020),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'खजानीचे नाव',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'नाव आवश्यक आहे'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'पासवर्ड (किमान ४ अक्षरे)',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setDialogState(
                                  () => obscurePassword = !obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'पासवर्ड आवश्यक आहे';
                            if (v.length < 4) return 'किमान ४ अक्षरे आवश्यक';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'पासवर्डची खात्री करा',
                            prefixIcon: const Icon(Icons.lock_reset),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setDialogState(
                                  () => obscureConfirm = !obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (v != passwordController.text) {
                              return 'पासवर्ड जुळत नाही';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'भूमिका (Role) निवडा:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: selectedRole,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: KhajaniRole.latestKhajani,
                              child: Text('चालू खजानी (LATEST_KHAJANI)'),
                            ),
                            DropdownMenuItem(
                              value: KhajaniRole.oldKhajani,
                              child: Text('माजी खजानी (OLD_KHAJANI)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedRole = val;
                                permissions = val == KhajaniRole.latestKhajani
                                    ? const KhajaniPermissions.latestDefault()
                                    : const KhajaniPermissions.oldDefault();
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'परवानग्या (Permissions):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildDialogSwitchTile(
                          'View (माहिती पाहणे)',
                          permissions.canView,
                          (v) => setDialogState(() =>
                              permissions = permissions.copyWith(canView: v)),
                        ),
                        _buildDialogSwitchTile(
                          'Add (नवीन नोंद जोडणे)',
                          permissions.canAdd,
                          (v) => setDialogState(() =>
                              permissions = permissions.copyWith(canAdd: v)),
                        ),
                        _buildDialogSwitchTile(
                          'Edit (नोंद बदलणे)',
                          permissions.canEdit,
                          (v) => setDialogState(() =>
                              permissions = permissions.copyWith(canEdit: v)),
                        ),
                        _buildDialogSwitchTile(
                          'Delete (नोंद हटवणे)',
                          permissions.canDelete,
                          (v) => setDialogState(() =>
                              permissions = permissions.copyWith(canDelete: v)),
                        ),
                        _buildDialogSwitchTile(
                          'Search (नोंद शोधणे)',
                          permissions.canSearch,
                          (v) => setDialogState(() => permissions =
                              permissions.copyWith(canSearch: v)),
                        ),
                        _buildDialogSwitchTile(
                          'PDF (अहवाल डाऊनलोड)',
                          permissions.canPdf,
                          (v) => setDialogState(() =>
                              permissions = permissions.copyWith(canPdf: v)),
                        ),
                        _buildDialogSwitchTile(
                          'Manage (खजानी व्यवस्थापन)',
                          permissions.canManageKhajani,
                          (v) => setDialogState(() => permissions =
                              permissions.copyWith(canManageKhajani: v)),
                        ),
                        _buildDialogSwitchTile(
                          'Sync (डेटा सिंक/ट्रान्सफर)',
                          permissions.canSync,
                          (v) => setDialogState(() =>
                              permissions = permissions.copyWith(canSync: v)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogCtx);
                          try {
                            await _authService.createKhajaniByDeveloper(
                              name: nameController.text.trim(),
                              password: passwordController.text,
                              role: selectedRole,
                              permissions: permissions,
                            );
                            if (!mounted) return;
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('नवीन खजानी यशस्वीरीत्या तयार झाला.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadKhajanis();
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              dialogError = e
                                  .toString()
                                  .replaceAll('Exception: ', '')
                                  .replaceAll('StateError: ', '')
                                  .replaceAll('ArgumentError: ', '');
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _deepSaffron,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('तयार करा'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DEVELOPER: EDIT ROLE & PERMISSIONS DIALOG
  // ============================================================

  void _showEditRoleAndPermissionsDialog(KhajaniUser user) {
    if (user.isDeveloper) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Developer खात्याची भूमिका किंवा परवानग्या बदलता येत नाहीत.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String selectedRole = user.role;
    KhajaniPermissions perms = user.permissions;
    bool isSaving = false;
    String? dialogError;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Row(
                children: [
                  const Icon(Icons.security, color: _deepSaffron),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${user.name} - अधिकार संपादन',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (dialogError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFECEC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFCDCD)),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                              color: Color(0xFFB00020),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'भूमिका (Role):',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: KhajaniRole.latestKhajani,
                            child: Text('चालू खजानी (LATEST_KHAJANI)'),
                          ),
                          DropdownMenuItem(
                            value: KhajaniRole.oldKhajani,
                            child: Text('माजी खजानी (OLD_KHAJANI)'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedRole = val;
                              perms = val == KhajaniRole.latestKhajani
                                  ? const KhajaniPermissions.latestDefault()
                                  : const KhajaniPermissions.oldDefault();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'विस्तृत परवानग्या (Granular Permissions):',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      _buildDialogSwitchTile(
                        'View (माहिती पाहणे)',
                        perms.canView,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canView: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Add (नवीन नोंद जोडणे)',
                        perms.canAdd,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canAdd: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Edit (नोंद बदलणे)',
                        perms.canEdit,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canEdit: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Delete (नोंद हटवणे)',
                        perms.canDelete,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canDelete: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Search (नोंद शोधणे)',
                        perms.canSearch,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canSearch: v)),
                      ),
                      _buildDialogSwitchTile(
                        'PDF (अहवाल डाऊनलोड)',
                        perms.canPdf,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canPdf: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Manage (खजानी व्यवस्थापन)',
                        perms.canManageKhajani,
                        (v) => setDialogState(() =>
                            perms = perms.copyWith(canManageKhajani: v)),
                      ),
                      _buildDialogSwitchTile(
                        'Sync (डेटा सिंक/ट्रान्सफर)',
                        perms.canSync,
                        (v) => setDialogState(
                            () => perms = perms.copyWith(canSync: v)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogCtx);
                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });
                          try {
                            if (selectedRole != user.role) {
                              await _authService.updateKhajaniRole(
                                userId: user.userId,
                                newRole: selectedRole,
                              );
                            }
                            await _authService.updateKhajaniPermissions(
                              userId: user.userId,
                              permissions: perms,
                            );

                            if (!mounted) return;
                            nav.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'भूमिका व परवानग्या यशस्वीरीत्या अद्ययावत झाल्या.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadKhajanis();
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              dialogError = e.toString();
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _deepSaffron,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('जतन करा'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DEVELOPER: TOGGLE STATUS (ACTIVE / INACTIVE)
  // ============================================================

  Future<void> _handleToggleStatus(KhajaniUser user) async {
    if (user.isDeveloper) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Developer खाते निष्क्रिय करता येत नाही.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final willDeactivate = user.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(willDeactivate ? 'खाते निष्क्रिय करा' : 'खाते सक्रिय करा'),
          content: Text(
            willDeactivate
                ? 'तुम्हाला खरोखर "${user.name}" यांचे खाते तात्पुरते निष्क्रिय करायचे आहे का? ते ॲपमध्ये प्रवेश करू शकणार नाहीत.'
                : 'तुम्हाला खरोखर "${user.name}" यांचे खाते पुन्हा सक्रिय करायचे आहे का?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: willDeactivate ? Colors.orange : Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text(willDeactivate ? 'निष्क्रिय करा' : 'सक्रिय करा'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _authService.toggleKhajaniStatus(
        userId: user.userId,
        isActive: !user.isActive,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willDeactivate
                ? 'खाते यशस्वीरीत्या निष्क्रिय केले.'
                : 'खाते यशस्वीरीत्या सक्रिय केले.',
          ),
          backgroundColor: willDeactivate ? Colors.orange : Colors.green,
        ),
      );
      _loadKhajanis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // DEVELOPER: DELETE KHAJANI
  // ============================================================

  Future<void> _handleDeleteKhajani(KhajaniUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('खाते हटवा (Delete Account)'),
          content: Text(
            'तुम्हाला खरोखर "${user.name}" (ID: ${user.userId}) यांचे खाते कायमचे हटवायचे आहे का?\n\n'
            'ही कृती पूर्ववत करता येणार नाही.',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('कायमचे हटवा'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _authService.deleteKhajani(userId: user.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('खाते यशस्वीरीत्या हटवले.'),
          backgroundColor: Colors.red,
        ),
      );
      _loadKhajanis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // REGULAR KHAJANI: SET NEW KHAJANI HANDOVER DIALOG
  // ============================================================

  void _showSetNewKhajaniDialog() {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscurePassword = true;
    bool obscureConfirm = true;
    String? dialogError;
    bool isSaving = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (sbContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: _deepSaffron),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'नवीन खजानी सेट करा',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7EE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD8B3)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  color: _deepSaffron, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'सूचना: नवीन खजानी सेट केल्यावर, तुमचे अधिकार "माजी खजानी" (केवळ वाचन) असे होतील आणि नवीन खजानी "चालू खजानी" (पूर्ण अधिकार) बनतील.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF756A5D),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (dialogError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFECEC),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFFFCDCD)),
                            ),
                            child: Text(
                              dialogError!,
                              style: const TextStyle(
                                color: Color(0xFFB00020),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'नवीन खजानीचे नाव',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'नाव आवश्यक आहे'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'नवीन पासवर्ड (किमान ४ अक्षरे)',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setDialogState(
                                  () => obscurePassword = !obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'पासवर्ड आवश्यक आहे';
                            if (v.length < 4) return 'किमान ४ अक्षरे आवश्यक';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: confirmPasswordController,
                          obscureText: obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'पासवर्ड पुन्हा टाका (Confirm)',
                            prefixIcon: const Icon(Icons.lock_reset),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setDialogState(
                                  () => obscureConfirm = !obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (v != passwordController.text) {
                              return 'पासवर्ड जुळत नाही';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() {
                            isSaving = true;
                            dialogError = null;
                          });
                          try {
                            await _authService.setNewKhajani(
                              name: nameController.text.trim(),
                              password: passwordController.text,
                            );
                            if (!mounted) return;
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('नवीन खजानी यशस्वीरीत्या सेट झाले.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _loadKhajanis();
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              dialogError = e
                                  .toString()
                                  .replaceAll('Exception: ', '')
                                  .replaceAll('StateError: ', '')
                                  .replaceAll('ArgumentError: ', '');
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _deepSaffron,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('नवीन खजानी सेट करा'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogSwitchTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 12.5, color: _ink)),
          Switch(
            value: value,
            activeThumbColor: _deepSaffron,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBadge(String label, bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFE8F5E9) : const Color(0xFFFFECEC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: enabled ? const Color(0xFFA5D6A7) : const Color(0xFFFFCDCD),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.check : Icons.close,
            size: 11,
            color: enabled ? Colors.green.shade800 : Colors.red.shade800,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.green.shade900 : Colors.red.shade900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDeveloper = _authService.isDeveloper;
    final canManageKhajani = _authService.canManageKhajani;
    final isLatest = _authService.isLatestKhajani;

    if (!canManageKhajani && !isDeveloper) {
      return Scaffold(
        appBar: AppBar(title: const Text('खजानी व्यवस्थापन')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'परवानगी नाही',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: _ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  'खजानी व्यवस्थापन पाहण्याची किंवा बदलण्याची परवानगी आपल्या खात्याला दिलेली नाही.\nकृपया Developer शी संपर्क साधा.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF756A5D), height: 1.4),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('मागे जा'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('खजानी व्यवस्थापन'),
        actions: [
          StreamBuilder<bool>(
            stream: _signalingService.isConnectedStream,
            initialData: _signalingService.isConnected,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              return Tooltip(
                message: isOnline
                    ? 'PC Signaling Server जोडलेला आहे (Online)'
                    : 'PC Signaling Server ऑफलाइन (Offline)',
                child: InkWell(
                  onTap: _showSignalingConfigDialog,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOnline
                            ? const Color(0xFFA5D6A7)
                            : const Color(0xFFEF9A9A),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOnline ? Icons.circle : Icons.circle_outlined,
                          size: 10,
                          color: isOnline
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOnline ? 'Server is ON 🟢' : 'Server is OFF 🔴',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOnline
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFFC62828),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'रिफ्रेश',
            onPressed: _loadKhajanis,
          ),
        ],
        bottom: isDeveloper && _tabController != null
            ? TabBar(
                controller: _tabController,
                indicatorColor: _deepSaffron,
                labelColor: _deepSaffron,
                unselectedLabelColor: const Color(0xFF756A5D),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(
                    text: 'खाती (${_approvedUsers.length})',
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Pending'),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _pendingRequests.isNotEmpty
                                ? Colors.red
                                : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_pendingRequests.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('उपकरणे'),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_devicesList.length}',
                            style: TextStyle(
                              color: Colors.blueGrey.shade900,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _saffron))
          : RefreshIndicator(
              onRefresh: _loadKhajanis,
              color: _saffron,
              child: isDeveloper && _tabController != null
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _buildApprovedUsersView(isDeveloper, isLatest),
                        _buildPendingRequestsView(),
                        _buildDevicesView(),
                      ],
                    )
                  : _buildApprovedUsersView(isDeveloper, isLatest),
            ),
    );
  }

  // ============================================================
  // PENDING REQUESTS TAB VIEW
  // ============================================================

  Widget _buildPendingRequestsView() {
    final pendingList = _filteredPendingList;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pending Header Notice
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD57A)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.pending_actions,
                  color: _deepSaffron, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'प्रलंबित विनंत्या (Pending User Requests)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'नवीन युजर्सनी लॉगिनसाठी पाठवलेल्या विनंत्या खाली दिल्या आहेत. '
                      'Developer च्या मंजुरीनंतरच युजरला ॲपमध्ये प्रवेश मिळेल. '
                      'अमान्य विनंत्या DELETE करून कायमच्या हटवता येतील.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF756A5D),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Search Bar in Pending Tab
        TextField(
          decoration: InputDecoration(
            hintText: 'प्रलंबित युजरचे नाव किंवा User ID शोधा...',
            prefixIcon: const Icon(Icons.search, color: _deepSaffron),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
            });
          },
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'एकूण प्रलंबित विनंत्या: ${pendingList.length}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF756A5D),
              ),
            ),
            if (pendingList.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'APPROVAL PENDING',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        if (pendingList.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 48, color: Color(0xFFB0A294)),
                SizedBox(height: 10),
                Text(
                  'कोणतीही प्रलंबित विनंती उपलब्ध नाही.',
                  style: TextStyle(
                    color: Color(0xFF756A5D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'नवीन युजर्स लॉगिन स्क्रीनवरून विनंती पाठवू शकतात.',
                  style: TextStyle(
                    color: Color(0xFF9E9283),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          )
        else
          ...pendingList.map((user) => _buildPendingUserCard(user)),
      ],
    );
  }

  // ============================================================
  // DEVICES TAB VIEW
  // ============================================================

  Widget _buildDevicesView() {
    final devList = _devicesList.where((d) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesId = d.deviceId.toLowerCase().contains(q);
        final matchesName = d.deviceName.toLowerCase().contains(q);
        final matchesUser = (d.userId ?? '').toLowerCase().contains(q);
        if (!matchesId && !matchesName && !matchesUser) return false;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Device Header Notice
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEBF3FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBCE0FD)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.devices, color: Colors.blueAccent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'उपकरण व्यवस्थापन (Device Management)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'प्रत्येक इन्स्टॉलेशनला वेगळा Device ID आहे. '
                      'Developer उपकरणाचा ॲक्सेस मंजूर (Approved) किंवा रद्द (Revoked) करू शकतो. '
                      'Revoke केलेल्या उपकरणावरून डॅशबोर्ड, वित्तीय डेटा व सिंक त्वरित बंद होईल.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF55606E),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Search Bar in Devices Tab
        TextField(
          decoration: InputDecoration(
            hintText: 'Device ID, नाव किंवा User ID शोधा...',
            prefixIcon: const Icon(Icons.search, color: _deepSaffron),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
            });
          },
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'नोंदणीकृत उपकरणे: ${devList.length}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF756A5D),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'रिफ्रेश',
              onPressed: _loadKhajanis,
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (devList.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.phonelink_off, size: 48, color: Color(0xFFB0A294)),
                SizedBox(height: 10),
                Text(
                  'कोणतेही उपकरण आढळले नाही.',
                  style: TextStyle(
                    color: Color(0xFF756A5D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          ...devList.map((dev) => _buildDeviceCard(dev)),
      ],
    );
  }

  Widget _buildDeviceCard(HindviDevice dev) {
    final isCurrent = dev.deviceId == _deviceService.currentDeviceId;
    final isApproved = dev.isApproved;
    final isRevoked = dev.isRevoked;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRevoked
              ? Colors.red.shade300
              : (isCurrent ? _saffron : const Color(0xFFF0E6D9)),
          width: isCurrent || isRevoked ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isRevoked
                      ? Colors.red.shade50
                      : (isApproved ? Colors.green.shade50 : Colors.amber.shade50),
                  child: Icon(
                    isRevoked
                        ? Icons.block
                        : (isApproved ? Icons.phone_android : Icons.hourglass_top),
                    color: isRevoked
                        ? Colors.red
                        : (isApproved ? Colors.green.shade700 : Colors.amber.shade800),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dev.deviceName.isNotEmpty ? dev.deviceName : 'Hindvi Device',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _saffron.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _saffron.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'हे उपकरण',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _deepSaffron,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isRevoked
                                  ? Colors.red.shade100
                                  : (isApproved ? Colors.green.shade100 : Colors.amber.shade100),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              dev.marathiStatus,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isRevoked
                                    ? Colors.red.shade900
                                    : (isApproved ? Colors.green.shade900 : Colors.amber.shade900),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'ID: ${dev.deviceId}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFF55606E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: dev.deviceId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Device ID कॉपी केला!'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.copy, size: 13, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // User Info & Timestamps
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF8F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: Color(0xFF756A5D)),
                  const SizedBox(width: 6),
                  Text(
                    'User ID: ${dev.userId != null && dev.userId!.isNotEmpty ? dev.userId : "जोडलेला नाही"}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D)),
                  ),
                  const Spacer(),
                  const Icon(Icons.access_time, size: 14, color: Color(0xFF756A5D)),
                  const SizedBox(width: 4),
                  Text(
                    dev.createdAt > 0 ? _formatDate(dev.createdAt) : '',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Actions: Revoke / Restore / Delete
            Row(
              children: [
                if (isApproved)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRevokeDeviceConfirmation(dev),
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('REVOKE'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  )
                else if (isRevoked)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showRestoreDeviceConfirmation(dev),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('RESTORE'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                  tooltip: 'उपकरण हटवा',
                  onPressed: () => _showDeleteDeviceConfirmation(dev),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRevokeDeviceConfirmation(HindviDevice dev) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('डिव्हाइस रद्द करा (Revoke Device)')),
            ],
          ),
          content: Text(
            'तुम्हाला खात्री आहे का की या उपकरणाचा ऍक्सेस रद्द (Revoke) करायचा आहे?\n\n'
            '• Device ID: ${dev.deviceId}\n'
            '• नाव: ${dev.deviceName}\n\n'
            'या उपकरणावरून डॅशबोर्ड, वित्तीय व्यवहार, नवीन नोंदी आणि सिंक त्वरित बंद होईल.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('REVOKE करा'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _authService.revokeDevice(dev.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('डिव्हाइस ${dev.deviceId} रद्द (Revoked) करण्यात आले.'),
          backgroundColor: Colors.red,
        ),
      );
      _loadKhajanis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showRestoreDeviceConfirmation(HindviDevice dev) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('डिव्हाइस पुन्हा मंजूर करा (Restore)')),
            ],
          ),
          content: Text(
            'तुम्हाला डिव्हाइस ${dev.deviceId} चा ऍक्सेस पुन्हा मंजूर (Restore) करायचा आहे का?\n\n'
            'यामुळे हे उपकरण पुन्हा वैध ठरेल आणि मंजुरीनुसार ऍक्सेस मिळेल.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('मंजूर करा (RESTORE)'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _authService.restoreDevice(dev.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('डिव्हाइस ${dev.deviceId} पुन्हा मंजूर करण्यात आले.'),
          backgroundColor: Colors.green,
        ),
      );
      _loadKhajanis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showDeleteDeviceConfirmation(HindviDevice dev) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('उपकरण हटवा')),
            ],
          ),
          content: Text(
            'तुम्हाला डिव्हाइस ${dev.deviceId} कायमचे हटवायचे आहे का?\n\n'
            'भविष्यात या डिव्हाइसवरून पुन्हा विनंती आल्यास ती नवीन डिव्हाइस म्हणून नोंदवली जाईल.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('हटवा (DELETE)'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _authService.deleteDevice(dev.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('डिव्हाइस ${dev.deviceId} हटवले.'),
          backgroundColor: Colors.red,
        ),
      );
      _loadKhajanis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSignalingConfigDialog() {
    final urlController = TextEditingController(text: _signalingService.serverUrl);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.computer, color: _deepSaffron),
              SizedBox(width: 8),
              Expanded(child: Text('PC Signaling Server', style: TextStyle(fontSize: 17))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<bool>(
                stream: _signalingService.isConnectedStream,
                initialData: _signalingService.isConnected,
                builder: (context, snapshot) {
                  final isOnline = snapshot.data ?? false;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isOnline ? Colors.green.shade300 : Colors.red.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOnline ? Icons.check_circle : Icons.error_outline,
                          color: isOnline ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isOnline ? 'सर्व्हर जोडलेला आहे (Online)' : 'सर्व्हर ऑफलाइन (Offline)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOnline ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Text(
                'PC वरील WebSocket Signaling Server URL (उदा: ws://192.168.1.100:8080):',
                style: TextStyle(fontSize: 12, color: Color(0xFF756A5D)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: 'ws://192.168.1.X:8080',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('रद्द करा'),
            ),
            FilledButton(
              onPressed: () async {
                final newUrl = urlController.text.trim();
                if (newUrl.isNotEmpty) {
                  await _signalingService.setServerUrl(newUrl);
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('सर्व्हर पत्ता जतन केला!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    setState(() {});
                  }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: _saffron),
              child: const Text('जतन करा'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // PENDING USER CARD
  // ============================================================

  Widget _buildPendingUserCard(KhajaniUser user) {
    DeviceRequestModel? matchingReq;
    for (final r in _deviceRequestsList) {
      if (r.userId == user.userId) {
        matchingReq = r;
        break;
      }
    }
    final deviceId = matchingReq?.deviceId ?? 'N/A';
    final requestType = matchingReq?.requestType ?? 'NEW_ACCOUNT';
    final requestTime = matchingReq != null && matchingReq.requestedAt > 0
        ? _formatDate(matchingReq.requestedAt)
        : _formatDate(user.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFD57A), width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar, Name, Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFFFF3CD),
                  child: const Icon(
                    Icons.hourglass_top,
                    color: Colors.amber,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3CD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amber.shade700,
                              ),
                            ),
                            child: Text(
                              user.status, // "PENDING"
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // User ID & Device ID Row
                      Row(
                        children: [
                          Text(
                            'User ID: ${user.userId}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF756A5D),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Device ID: $deviceId',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF55606E),
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Request Type & Date/Time
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE7F6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Type: $requestType',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF512DA8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.schedule,
                              size: 13, color: Color(0xFF9E9283)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Request Date: $requestTime',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF756A5D),
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF0E6D9)),
            const SizedBox(height: 10),

            // Action Buttons: APPROVE and DELETE
            Row(
              children: [
                // APPROVE Button
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showApprovePendingRequestDialog(
                      user,
                      deviceId: deviceId != 'N/A' ? deviceId : null,
                      requestType: requestType,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text(
                      'APPROVE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // DELETE Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleDeletePendingRequest(user),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text(
                      'DELETE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // APPROVED USERS TAB VIEW
  // ============================================================

  Widget _buildApprovedUsersView(bool isDeveloper, bool isLatest) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Developer Header Banner
        if (isDeveloper) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF0DC), Color(0xFFFFE0B8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFCCA0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Developer Control Panel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                          Text(
                            'सर्वोच्च ॲडमिन नियंत्रण • खाती, भूमिका व परवानग्या व्यवस्थापित करा.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF756A5D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Pending Notification Banner inside Developer Banner if any
                if (_pendingRequests.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () {
                      _tabController?.animateTo(1);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEEEE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFCDCD)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_pendingRequests.length} नवीन वापरकर्ता विनंत्या मंजुरीसाठी प्रलंबित आहेत.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB00020),
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 13, color: Color(0xFFB00020)),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _showCreateKhajaniByDeveloperDialog,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('नवीन खजानी तयार करा'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _deepSaffron,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          // Regular Khajani Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7EE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD8B3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_alt_outlined, color: _deepSaffron),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isLatest
                            ? 'आपण "चालू खजानी" आहात'
                            : 'आपण "माजी खजानी" आहात',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'चालू खजानी नवीन खजानीकडे जबाबदारी सोपवू शकतात. परवानग्या बदलण्याचे अधिकार केवळ Developer कडे आहेत.',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF756A5D), height: 1.35),
                ),
                if (isLatest) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showSetNewKhajaniDialog,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('नवीन खजानी सेट करा (हस्तांतरण)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _saffron,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Search & Filter
        TextField(
          decoration: InputDecoration(
            hintText: 'नाव किंवा User ID शोधा...',
            prefixIcon: const Icon(Icons.search, color: _deepSaffron),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
            });
          },
        ),
        const SizedBox(height: 10),

        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('सर्व खाती', 'ALL'),
              const SizedBox(width: 8),
              _filterChip('चालू खजानी', 'LATEST'),
              const SizedBox(width: 8),
              _filterChip('माजी खजानी', 'OLD'),
              const SizedBox(width: 8),
              _filterChip('निष्क्रिय', 'INACTIVE'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'एकूण नोंदणीकृत खाती: ${_filteredApprovedList.length}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF756A5D),
          ),
        ),
        const SizedBox(height: 10),

        // User Cards
        if (_filteredApprovedList.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            child: const Column(
              children: [
                Icon(Icons.person_search,
                    size: 48, color: Color(0xFFB0A294)),
                SizedBox(height: 8),
                Text(
                  'कोणतेही खाते सापडले नाही.',
                  style: TextStyle(color: Color(0xFF756A5D)),
                ),
              ],
            ),
          )
        else
          ..._filteredApprovedList
              .map((user) => _buildUserCard(user, isDeveloper)),
      ],
    );
  }

  Widget _filterChip(String title, String filterKey) {
    final isSelected = _selectedFilter == filterKey;
    return ChoiceChip(
      label: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : _ink,
        ),
      ),
      selected: isSelected,
      selectedColor: _saffron,
      backgroundColor: const Color(0xFFFFF7EE),
      onSelected: (sel) {
        if (sel) {
          setState(() {
            _selectedFilter = filterKey;
          });
        }
      },
    );
  }

  Widget _buildUserCard(KhajaniUser user, bool isDeveloperSession) {
    final isUserDev = user.isDeveloper;
    final isUserLatest = user.isLatestKhajani;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: isUserDev ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isUserDev
              ? const Color(0xFFFFB84D)
              : (user.isActive
                  ? const Color(0xFFF0E6D9)
                  : const Color(0xFFFFCDCD)),
          width: isUserDev ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar, Name, Role Badge, Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isUserDev
                      ? const Color(0xFFFFF0D0)
                      : (isUserLatest
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFF2E2)),
                  child: Icon(
                    isUserDev
                        ? Icons.shield
                        : (isUserLatest
                            ? Icons.verified_user
                            : Icons.history_edu),
                    color: isUserDev
                        ? Colors.amber.shade800
                        : (isUserLatest ? Colors.green : _deepSaffron),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                          ),
                          if (isUserDev)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0D0),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.amber.shade700),
                              ),
                              child: Text(
                                'सर्वोच्च ॲडमिन',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isUserLatest
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isUserLatest
                                      ? Colors.green.shade400
                                      : Colors.orange.shade400,
                                ),
                              ),
                              child: Text(
                                user.marathiRole,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isUserLatest
                                      ? Colors.green.shade900
                                      : Colors.orange.shade900,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'ID: ${user.userId}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF756A5D),
                        ),
                      ),
                      if (user.createdAt > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'नोंदणी: ${_formatDate(user.createdAt)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF9E9283),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Active / Inactive status indicator
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: user.isActive ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  user.isActive ? 'सक्रिय (Active)' : 'निष्क्रिय (Deactivated)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: user.isActive ? Colors.green.shade800 : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Permissions Badges
            const Text(
              'परवानग्या:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF756A5D),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                _buildPermissionBadge('View', user.permissions.canView),
                _buildPermissionBadge('Add', user.permissions.canAdd),
                _buildPermissionBadge('Edit', user.permissions.canEdit),
                _buildPermissionBadge('Delete', user.permissions.canDelete),
                _buildPermissionBadge('Search', user.permissions.canSearch),
                _buildPermissionBadge('PDF', user.permissions.canPdf),
                _buildPermissionBadge(
                    'Manage', user.permissions.canManageKhajani),
                _buildPermissionBadge('Sync', user.permissions.canSync),
              ],
            ),

            // Developer Actions for non-developer users
            if (isDeveloperSession) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF0E6D9)),
              const SizedBox(height: 8),

              if (isUserDev)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: Colors.amber),
                      SizedBox(width: 6),
                      Text(
                        'हे Developer खाते सुरक्षित आहे. हे खाते बदलता वा हटवता येत नाही.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF756A5D),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showEditRoleAndPermissionsDialog(user),
                      icon: const Icon(Icons.edit_note, size: 16),
                      label: const Text('भूमिका व परवानग्या',
                          style: TextStyle(fontSize: 11.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _deepSaffron,
                        side: const BorderSide(color: _deepSaffron),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _handleToggleStatus(user),
                      icon: Icon(
                        user.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 16,
                      ),
                      label: Text(
                        user.isActive ? 'निष्क्रिय करा' : 'सक्रिय करा',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: user.isActive
                            ? Colors.orange.shade800
                            : Colors.green,
                        side: BorderSide(
                          color: user.isActive
                              ? Colors.orange.shade800
                              : Colors.green,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _handleDeleteKhajani(user),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label:
                          const Text('हटवा', style: TextStyle(fontSize: 11.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
