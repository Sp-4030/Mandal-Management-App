// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/developer_permissions.dart';
import '../models/user_request_model.dart';
import '../services/developer_auth_service.dart';
import '../services/developer_signaling_service.dart';
import 'developer_login_screen.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

class DeveloperDashboardScreen extends StatefulWidget {
  const DeveloperDashboardScreen({super.key});

  @override
  State<DeveloperDashboardScreen> createState() => _DeveloperDashboardScreenState();
}

class _DeveloperDashboardScreenState extends State<DeveloperDashboardScreen>
    with SingleTickerProviderStateMixin {
  final DeveloperSignalingService _signaling = DeveloperSignalingService.instance;
  final DeveloperAuthService _auth = DeveloperAuthService.instance;

  TabController? _tabController;
  StreamSubscription? _allRequestsSub;
  StreamSubscription? _pendingRequestsSub;
  StreamSubscription? _clientsSub;

  List<UserRequestModel> _allRequests = [];
  List<UserRequestModel> _pendingRequests = [];
  List<Map<String, dynamic>> _connectedClients = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController!.addListener(() {
      if (mounted) setState(() {});
    });

    _allRequests = List.from(_signaling.allRequests);
    _pendingRequests = List.from(_signaling.pendingRequests);
    _connectedClients = List.from(_signaling.connectedClients);

    _pendingRequestsSub = _signaling.onPendingRequests.listen((list) {
      if (mounted) setState(() => _pendingRequests = List.from(list));
    });

    _allRequestsSub = _signaling.onAllRequests.listen((list) {
      if (mounted) setState(() => _allRequests = List.from(list));
    });

    _clientsSub = _signaling.onConnectedClients.listen((list) {
      if (mounted) setState(() => _connectedClients = List.from(list));
    });

    // Make sure we connect and request fresh data
    if (!_signaling.isConnected) {
      _signaling.connect();
    } else {
      _signaling.requestRefresh();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _pendingRequestsSub?.cancel();
    _allRequestsSub?.cancel();
    _clientsSub?.cancel();
    super.dispose();
  }

  List<UserRequestModel> get _approvedUsers =>
      _allRequests.where((r) => r.isApproved).toList();

  List<UserRequestModel> get _revokedDevices =>
      _allRequests.where((r) => r.isRevoked).toList();

  UserRequestModel? get _currentLatestKhajani {
    for (final r in _allRequests) {
      if (r.isApproved && r.isLatestKhajani) return r;
    }
    return null;
  }

  String _formatDate(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    const months = ['जानेवारी', 'फेब्रुवारी', 'मार्च', 'एप्रिल', 'मे', 'जून', 'जुलै', 'ऑगस्ट', 'सप्टेंबर', 'ऑक्टोबर', 'नोव्हेंबर', 'डिसेंबर'];
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour12:$minuteStr $period';
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('Developer लॉगआउट'),
          content: const Text('तुम्हाला Developer खात्यातून लॉगआउट करायचे आहे का?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('लॉगआउट करा'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _auth.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DeveloperLoginScreen()),
        (route) => false,
      );
    }
  }

  // ============================================================
  // DIALOG: APPROVE USER REQUEST (Role & 8 Permissions)
  // ============================================================
  void _showApproveDialog(UserRequestModel req) {
    String selectedRole = req.requestedRole.isNotEmpty ? req.requestedRole : 'OLD_KHAJANI';
    DeveloperPermissions perms = selectedRole == 'LATEST_KHAJANI'
        ? const DeveloperPermissions.latestDefault()
        : const DeveloperPermissions.oldDefault();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Row(
                children: [
                  Icon(Icons.how_to_reg, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('खाते विनंती मंजूर करा (Approve Request)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                      // User summary card
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
                            Text('नाव: ${req.userName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _ink)),
                            const SizedBox(height: 4),
                            Text('User ID: ${req.userId}', style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D))),
                            Text('Device ID: ${req.deviceId}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF756A5D))),
                            Text('Device Name: ${req.deviceName}', style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D))),
                            Text('विनंती दिनांक: ${_formatDate(req.createdAt)}', style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Role selection
                      const Text('भूमिका (Role) निवडा:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _ink)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        items: const [
                          DropdownMenuItem(value: 'LATEST_KHAJANI', child: Text('चालू खजानी (LATEST_KHAJANI)')),
                          DropdownMenuItem(value: 'OLD_KHAJANI', child: Text('माजी खजानी (OLD_KHAJANI)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedRole = val;
                              perms = val == 'LATEST_KHAJANI'
                                  ? const DeveloperPermissions.latestDefault()
                                  : const DeveloperPermissions.oldDefault();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Permissions toggles
                      const Text('परवानग्या व्यवस्थापन (Permissions ON/OFF):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _ink)),
                      const SizedBox(height: 6),
                      _buildPermSwitch('View (माहिती पाहणे)', perms.canView, (v) => setDialogState(() => perms = perms.copyWith(canView: v))),
                      _buildPermSwitch('Add (नवीन नोंद जोडणे)', perms.canAdd, (v) => setDialogState(() => perms = perms.copyWith(canAdd: v))),
                      _buildPermSwitch('Edit (नोंद बदलणे)', perms.canEdit, (v) => setDialogState(() => perms = perms.copyWith(canEdit: v))),
                      _buildPermSwitch('Delete (नोंद हटवणे)', perms.canDelete, (v) => setDialogState(() => perms = perms.copyWith(canDelete: v))),
                      _buildPermSwitch('Search (नोंद शोधणे)', perms.canSearch, (v) => setDialogState(() => perms = perms.copyWith(canSearch: v))),
                      _buildPermSwitch('PDF (अहवाल PDF)', perms.canPdf, (v) => setDialogState(() => perms = perms.copyWith(canPdf: v))),
                      _buildPermSwitch('Khajani Management (व्यवस्थापन)', perms.canManageKhajani, (v) => setDialogState(() => perms = perms.copyWith(canManageKhajani: v))),
                      _buildPermSwitch('Sync (रिमोट सिंक)', perms.canSync, (v) => setDialogState(() => perms = perms.copyWith(canSync: v))),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    _signaling.approveRequest(
                      requestId: req.requestId,
                      userId: req.userId,
                      deviceId: req.deviceId,
                      userName: req.userName,
                      role: selectedRole,
                      permissions: perms,
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('"${req.userName}" यांचे खाते मंजूर केले!'), backgroundColor: Colors.green),
                    );
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('मंजूर करा (APPROVE)'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DIALOG: REJECT USER REQUEST
  // ============================================================
  Future<void> _handleRejectRequest(UserRequestModel req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('विनंती नाकारा (Reject Request)')),
            ],
          ),
          content: Text(
            'तुम्हाला खरोखर "${req.userName}" (ID: ${req.userId}) यांची विनंती नाकारायची आहे का?\n\n'
            'यामुळे वापरकर्त्याला ॲपमध्ये प्रवेश मिळणार नाही.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('नाकारा (REJECT)'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _signaling.rejectRequest(
        requestId: req.requestId,
        userId: req.userId,
        deviceId: req.deviceId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${req.userName}" यांची विनंती नाकारली.'), backgroundColor: Colors.red),
      );
    }
  }

  // ============================================================
  // DIALOG: EDIT PERMISSIONS FOR APPROVED USER
  // ============================================================
  void _showEditPermissionsDialog(UserRequestModel user) {
    DeveloperPermissions perms = user.permissions;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: Row(
                children: [
                  const Icon(Icons.security, color: _deepSaffron),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('परवानग्या: ${user.userName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPermSwitch('View (माहिती पाहणे)', perms.canView, (v) => setDialogState(() => perms = perms.copyWith(canView: v))),
                    _buildPermSwitch('Add (नवीन नोंद जोडणे)', perms.canAdd, (v) => setDialogState(() => perms = perms.copyWith(canAdd: v))),
                    _buildPermSwitch('Edit (नोंद बदलणे)', perms.canEdit, (v) => setDialogState(() => perms = perms.copyWith(canEdit: v))),
                    _buildPermSwitch('Delete (नोंद हटवणे)', perms.canDelete, (v) => setDialogState(() => perms = perms.copyWith(canDelete: v))),
                    _buildPermSwitch('Search (नोंद शोधणे)', perms.canSearch, (v) => setDialogState(() => perms = perms.copyWith(canSearch: v))),
                    _buildPermSwitch('PDF (अहवाल PDF)', perms.canPdf, (v) => setDialogState(() => perms = perms.copyWith(canPdf: v))),
                    _buildPermSwitch('Khajani Management (व्यवस्थापन)', perms.canManageKhajani, (v) => setDialogState(() => perms = perms.copyWith(canManageKhajani: v))),
                    _buildPermSwitch('Sync (रिमोट सिंक)', perms.canSync, (v) => setDialogState(() => perms = perms.copyWith(canSync: v))),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton(
                  onPressed: () {
                    _signaling.updatePermissions(
                      userId: user.userId,
                      deviceId: user.deviceId,
                      permissions: perms,
                    );
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('"${user.userName}" यांच्या परवानग्या अपडेट केल्या!'), backgroundColor: Colors.green),
                    );
                  },
                  style: FilledButton.styleFrom(backgroundColor: _saffron),
                  child: const Text('जतन करा (Save)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DIALOG: REVOKE DEVICE
  // ============================================================
  Future<void> _handleRevokeDevice(String deviceId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Expanded(child: Text('डिव्हाइस रद्द करा (Revoke Device)')),
            ],
          ),
          content: Text(
            'तुम्हाला खरोखर डिव्हाइस "$deviceId" ($userName) रद्द (REVOKE) करायचे आहे का?\n\n'
            'परिणाम:\n'
            '• लक्ष्य फोनवरील चालू सेशन लगेच बंद होईल.\n'
            '• डॅशबोर्ड बंद होऊन लॉगिन ब्लॉक होईल.\n'
            '• आर्थिक डेटा पाहणे किंवा बदलणे पूर्णपणे ब्लॉक होईल.\n'
            '• इंटरनेट बंद असतानाही फोन ब्लॉक राहील.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('रद्द करा (REVOKE)'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _signaling.revokeDevice(deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('डिव्हाइस "$deviceId" रद्द (REVOKED) केले!'), backgroundColor: Colors.red),
      );
    }
  }

  // ============================================================
  // DIALOG: RESTORE DEVICE
  // ============================================================
  void _handleRestoreDevice(String deviceId) {
    _signaling.restoreDevice(deviceId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('डिव्हाइस "$deviceId" पुनर्स्थापित केले!'), backgroundColor: Colors.green),
    );
  }

  // ============================================================
  // DIALOG: SET LATEST KHAJANI
  // ============================================================
  Future<void> _handleSetLatestKhajani(UserRequestModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.verified, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('चालू खजानी नियुक्त करा')),
            ],
          ),
          content: Text(
            'तुम्हाला "${user.userName}" (ID: ${user.userId}) यांना मंडळाचे "चालू खजानी (LATEST_KHAJANI)" बनवायचे आहे का?\n\n'
            '• हे खाते मास्टर फोन म्हणून नियुक्त होईल.\n'
            '• पूर्वीचे चालू खजानी आपोआप "माजी खजानी" बनतील.',
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('रद्द करा'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _saffron),
              child: const Text('चालू खजानी बनवा'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _signaling.setLatestKhajani(userId: user.userId, deviceId: user.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${user.userName}" चालू खजानी म्हणून नियुक्त झाले!'), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildPermSwitch(String title, bool val, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
      value: val,
      activeThumbColor: _saffron,
      dense: true,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = _currentLatestKhajani;

    return Scaffold(
      backgroundColor: _warmPaper,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: _deepSaffron),
            SizedBox(width: 8),
            Text('Developer Management Console', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          // Server status badge
          ValueListenableBuilder<DevConnectionState>(
            valueListenable: _signaling.connectionState,
            builder: (context, state, _) {
              final isOnline = state == DevConnectionState.connected;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isOnline ? const Color(0xFFA5D6A7) : const Color(0xFFEF9A9A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isOnline ? Icons.check_circle : Icons.error_outline, size: 14, color: isOnline ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Server ON 🟢' : 'Server OFF 🔴',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOnline ? Colors.green.shade900 : Colors.red.shade900),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: _deepSaffron),
            tooltip: 'रिफ्रेश करा',
            onPressed: () => _signaling.requestRefresh(),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: 'लॉगआउट',
            onPressed: _handleLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _deepSaffron,
          unselectedLabelColor: const Color(0xFF756A5D),
          indicatorColor: _saffron,
          tabs: [
            Tab(icon: const Icon(Icons.hourglass_top), text: 'लंबित (${_pendingRequests.length})'),
            Tab(icon: const Icon(Icons.people), text: 'वापरकर्ते (${_approvedUsers.length})'),
            Tab(icon: const Icon(Icons.phonelink_setup), text: 'डिव्हाइस (${_allRequests.length})'),
            const Tab(icon: Icon(Icons.verified), text: 'चालू खजानी'),
          ],
        ),
      ),
      body: Column(
        children: [
          // KPI Metric cards strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFFFFF7EE),
            child: Row(
              children: [
                _buildKpiCard('प्रलंबित', '${_pendingRequests.length}', Colors.orange),
                const SizedBox(width: 10),
                _buildKpiCard('मंजूर', '${_approvedUsers.length}', Colors.green),
                const SizedBox(width: 10),
                _buildKpiCard('रद्द डिव्हाइस', '${_revokedDevices.length}', Colors.red),
                const SizedBox(width: 10),
                _buildKpiCard('चालू खजानी', latest != null ? latest.userName : 'नाही', _deepSaffron),
              ],
            ),
          ),

          // Main Tabs Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPendingTab(),
                _buildApprovedUsersTab(),
                _buildDevicesTab(),
                _buildLatestKhajaniTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D))),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TAB 1: PENDING REQUESTS
  // ============================================================
  Widget _buildPendingTab() {
    if (_pendingRequests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 54, color: Colors.green),
            SizedBox(height: 12),
            Text('कोणतीही नवीन प्रलंबित विनंती नाही.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
            SizedBox(height: 4),
            Text('नवीन Hindvi App नोंदणी आल्यास इथे थेट दिसेल.', style: TextStyle(fontSize: 13, color: Color(0xFF756A5D))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingRequests.length,
      itemBuilder: (ctx, idx) {
        final req = _pendingRequests[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(req.userName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _ink)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text('PENDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('User ID: ${req.userId}', style: const TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                Text('Device ID: ${req.deviceId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF756A5D))),
                Text('प्रकार: ${req.requestType} • तारीख: ${_formatDate(req.createdAt)}', style: const TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _handleRejectRequest(req),
                      icon: const Icon(Icons.close, size: 16, color: Colors.red),
                      label: const Text('नाकारा', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showApproveDialog(req),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('मंजूर करा (APPROVE)'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // TAB 2: APPROVED USERS & PERMISSIONS
  // ============================================================
  Widget _buildApprovedUsersTab() {
    final users = _approvedUsers;
    if (users.isEmpty) {
      return const Center(child: Text('अद्याप कोणतेही मंजूर खाते नाही.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (ctx, idx) {
        final user = users[idx];
        final isLatest = user.isLatestKhajani;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isLatest ? Colors.amber.shade100 : const Color(0xFFFFF0E1),
                      child: Icon(isLatest ? Icons.verified : Icons.person, color: _deepSaffron),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
                          Text('ID: ${user.userId}', style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLatest ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isLatest ? '👑 चालू खजानी' : 'माजी खजानी',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLatest ? const Color(0xFF1B5E20) : const Color(0xFFB94D00),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildPermBadge('View', user.permissions.canView),
                    _buildPermBadge('Add', user.permissions.canAdd),
                    _buildPermBadge('Edit', user.permissions.canEdit),
                    _buildPermBadge('Delete', user.permissions.canDelete),
                    _buildPermBadge('Search', user.permissions.canSearch),
                    _buildPermBadge('PDF', user.permissions.canPdf),
                    _buildPermBadge('Sync', user.permissions.canSync),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isLatest)
                      TextButton.icon(
                        onPressed: () => _handleSetLatestKhajani(user),
                        icon: const Icon(Icons.arrow_upward, size: 16, color: _deepSaffron),
                        label: const Text('चालू खजानी बनवा', style: TextStyle(color: _deepSaffron)),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showEditPermissionsDialog(user),
                      icon: const Icon(Icons.lock_open, size: 16, color: _ink),
                      label: const Text('परवानग्या बदला', style: TextStyle(color: _ink)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermBadge(String label, bool isGranted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isGranted ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isGranted ? Colors.green.shade300 : Colors.grey.shade300),
      ),
      child: Text(
        '$label: ${isGranted ? "✓" : "✗"}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isGranted ? Colors.green.shade900 : Colors.grey.shade600),
      ),
    );
  }

  // ============================================================
  // TAB 3: DEVICE MANAGEMENT & REVOCATION
  // ============================================================
  Widget _buildDevicesTab() {
    final devices = _allRequests;
    if (devices.isEmpty) {
      return const Center(child: Text('कोणतीही डिव्हाइस नोंद नाही.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      itemBuilder: (ctx, idx) {
        final dev = devices[idx];
        final isRevoked = dev.isRevoked;
        final isApproved = dev.isApproved;
        final isOnline = _connectedClients.any((c) => c['deviceId'] == dev.deviceId);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.smartphone, color: isRevoked ? Colors.red : (isApproved ? Colors.green : Colors.orange)),
                        const SizedBox(width: 8),
                        Text(dev.deviceName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _ink)),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isOnline ? Colors.green.shade300 : Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 8, color: isOnline ? Colors.green : Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isOnline ? Colors.green.shade900 : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isRevoked ? Colors.red.shade100 : (isApproved ? Colors.green.shade100 : Colors.orange.shade100),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            dev.status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isRevoked ? Colors.red.shade900 : (isApproved ? Colors.green.shade900 : Colors.orange.shade900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Device ID: ${dev.deviceId}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: _ink)),
                Text('वापरकर्ता: ${dev.userName} (User ID: ${dev.userId})', style: const TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                Text('तारीख: ${_formatDate(dev.createdAt)}', style: const TextStyle(fontSize: 11, color: Color(0xFF756A5D))),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isRevoked)
                      FilledButton.icon(
                        onPressed: () => _handleRestoreDevice(dev.deviceId),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('पुनर्स्थापित करा (Restore)'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      )
                    else if (isApproved)
                      ElevatedButton.icon(
                        onPressed: () => _handleRevokeDevice(dev.deviceId, dev.userName),
                        icon: const Icon(Icons.block, size: 16),
                        label: const Text('डिव्हाइस रद्द करा (REVOKE)'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // TAB 4: LATEST KHAJANI MANAGEMENT
  // ============================================================
  Widget _buildLatestKhajaniTab() {
    final latest = _currentLatestKhajani;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0E1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(Icons.verified, size: 44, color: _deepSaffron),
                      ),
                      const SizedBox(height: 14),
                      const Text('सक्रिय चालू खजानी (Active Master)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _ink)),
                      const SizedBox(height: 6),
                      Text(
                        latest != null ? latest.userName : 'सध्या कोणताही चालू खजानी नियुक्त नाही',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _deepSaffron),
                      ),
                      if (latest != null) ...[
                        const SizedBox(height: 8),
                        Text('User ID: ${latest.userId}', style: const TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                        Text('Device ID: ${latest.deviceId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF756A5D))),
                      ],
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9E6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('महत्त्वाचे नियम (Rules):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _ink)),
                            SizedBox(height: 4),
                            Text('• चालू खजानी फोन हा मास्टर आर्थिक डेटाबेस असतो.', style: TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                            Text('• नवीन फोन सिंक करताना चालू खजानी फोनवरून डेटा प्राप्त होतो.', style: TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                            Text('• एका वेळी एकच चालू खजानी सक्रिय राहू शकतो.', style: TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                            Text('• Developer स्वतःचे खाते रद्द किंवा हटवू शकत नाही.', style: TextStyle(fontSize: 12, color: Color(0xFF756A5D))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Switch Latest Khajani selector
              const Text('दुसऱ्या वापरकर्त्यास चालू खजानी बनवा:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _ink)),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _approvedUsers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final u = _approvedUsers[idx];
                    final isCurrentLatest = u.isLatestKhajani;

                    return ListTile(
                      title: Text(u.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('ID: ${u.userId} • ${u.deviceId}', style: const TextStyle(fontSize: 11)),
                      trailing: isCurrentLatest
                          ? const Chip(
                              label: Text('सध्या चालू खजानी', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                              backgroundColor: Color(0xFFE8F5E9),
                            )
                          : FilledButton(
                              onPressed: () => _handleSetLatestKhajani(u),
                              style: FilledButton.styleFrom(backgroundColor: _saffron),
                              child: const Text('नियुक्त करा', style: TextStyle(fontSize: 12)),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
