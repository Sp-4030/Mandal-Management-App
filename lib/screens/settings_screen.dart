import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/remote_sync_service.dart';
import '../services/signaling_service.dart';
import 'app_update_screen.dart';
import 'khajani_management_screen.dart';
import 'login_screen.dart';
import 'mandal_data_transfer_screen.dart';
import 'recovery_data_screen.dart';
import 'restore_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final AuthService _authService = AuthService.instance;

  DateTime? _lastBackupTime;
  bool _isLoadingLastBackup = true;
  String _currentDeviceId = '';

  @override
  void initState() {
    super.initState();
    _loadLastBackupTime();
    _loadDeviceId();
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await DeviceService.instance.getDeviceId();
      if (mounted) {
        setState(() => _currentDeviceId = id);
      }
    } catch (_) {}
  }

  Future<void> _loadLastBackupTime() async {
    try {
      final lastTime = await _databaseHelper.getLastBackupTime();
      if (mounted) {
        setState(() {
          _lastBackupTime = lastTime;
          _isLoadingLastBackup = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLastBackup = false);
    }
  }

  bool _isSyncingFinancial = false;

  Future<void> _handleRemoteFinancialSync() async {
    if (!_authService.canView && !_authService.canSync && !_authService.isDeveloper) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('माहिती पाहण्याची किंवा सिंक करण्याची परवानगी नाही.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (RemoteSyncService.instance.isMaster) {
      final counts = await _databaseHelper.getTableRecordCounts();
      if (!mounted) return;
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('हा फोन MASTER डेटाबेस आहे. सर्व $total नोंदी सुरक्षित आहेत.'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    setState(() => _isSyncingFinancial = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('मास्टर फोनवरून सर्व आर्थिक नोंदी सिंक करत आहे...'),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final success = await RemoteSyncService.instance.requestSyncFromMaster();
      if (!mounted) return;
      if (success) {
        final counts = await _databaseHelper.getTableRecordCounts();
        if (!mounted) return;
        final total = counts.values.fold<int>(0, (a, b) => a + b);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('डेटा सिंक यशस्वी! एकूण $total नोंदी स्थानिक डेटाबेसमध्ये सुरक्षित झाल्या.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(RemoteSyncService.instance.syncStatusText.value),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('सिंक त्रुटी: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncingFinancial = false);
    }
  }

  String _formatDateTime(DateTime dt) {
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
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${marathiMonths[dt.month - 1]} ${dt.year}, $hour12:$minuteStr $period';
  }

  void _showBackupBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return _BackupBottomSheetContent(
          onBackupComplete: () {
            _loadLastBackupTime();
          },
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('लॉगआउट पुष्टी'),
          content: const Text(
            'तुम्हाला खरोखर खात्यातून लॉगआउट करायचे आहे का?\n\n'
            'लॉगआउट केल्यावर पुन्हा नाव व पासवर्ड टाकून लॉगिन करावे लागेल.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('लॉगआउट करा'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _authService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const KhajaniLoginScreen(),
      ),
      (route) => false,
    );
  }

  void _showSignalingServerDialog() {
    final urlController = TextEditingController(
      text: SignalingService.instance.serverUrl,
    );

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.computer, color: Color(0xFFB94D00)),
              SizedBox(width: 8),
              Expanded(
                child: Text('PC Signaling Server', style: TextStyle(fontSize: 17)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<bool>(
                stream: SignalingService.instance.isConnectedStream,
                initialData: SignalingService.instance.isConnected,
                builder: (context, snapshot) {
                  final isOnline = snapshot.data ?? false;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          isOnline
                              ? 'Server is ON 🟢'
                              : 'Server is OFF 🔴',
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
                'PC वरील WebSocket Signaling Server URL:\n(उदा: wss://amino-dropkick-resample.ngrok-free.dev किंवा ws://10.X.X.X:8080)',
                style: TextStyle(fontSize: 12, color: Color(0xFF756A5D)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: 'wss://amino-dropkick-resample.ngrok-free.dev',
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
                  await SignalingService.instance.setServerUrl(newUrl);
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
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7A00)),
              child: const Text('जतन करा'),
            ),
          ],
        );
      },
    );
  }

  void _showDeviceInfoDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.perm_device_information_outlined, color: Color(0xFFB94D00)),
              SizedBox(width: 8),
              Expanded(
                child: Text('डिव्हाइस ओळख (Device ID)', style: TextStyle(fontSize: 17)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'या उपकरणाला प्रणालीद्वारे एक कायमचा युनिक Device ID दिलेला आहे. '
                'हा ID युजर खात्यापेक्षा वेगळा असून Developer कडून मंजुरी व नियंत्रणासाठी वापरला जातो.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF756A5D), height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD57A)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Permanent Device ID:',
                            style: TextStyle(fontSize: 11, color: Color(0xFF856404)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentDeviceId.isNotEmpty ? _currentDeviceId : 'शोधत आहे...',
                            style: const TextStyle(
                              fontSize: 15,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF533F03),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFF856404)),
                      tooltip: 'Device ID कॉपी करा',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _currentDeviceId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device ID कॉपी केला!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('बंद करा'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const deepSaffron = Color(0xFFB94D00);
    final currentUser = _authService.currentUser;
    final isDeveloper = _authService.isDeveloper;
    final isLatest = _authService.isLatestKhajani;

    return Scaffold(
      appBar: AppBar(
        title: const Text('सेटिंग्ज'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Section 1: डेटा व्यवस्थापन
          Text(
            'डेटा व्यवस्थापन',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF25231F),
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'मंडळाच्या सर्व डेटाचे सुरक्षित व्यवस्थापन, बॅकअप आणि ट्रान्सफर पर्याय.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF756A5D),
            ),
          ),
          const SizedBox(height: 16),

          // 1.1 मंडळ डेटा ट्रान्सफर
          _settingsOptionTile(
            context: context,
            icon: Icons.sync_alt,
            title: 'मंडळ डेटा ट्रान्सफर',
            description:
                'जुन्या फोनमधील संपूर्ण मंडळ डेटा नवीन फोनमध्ये सुरक्षितपणे ट्रान्सफर करा.',
            onTap: () {
              if (!_authService.canSync) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'मंडळ डेटा ट्रान्सफर / सिंक करण्याची परवानगी आपल्या खात्याला नाही. कृपया Developer शी संपर्क साधा.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MandalDataTransferScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 1.2 बॅकअप
          _settingsOptionTile(
            context: context,
            icon: Icons.backup_outlined,
            title: 'बॅकअप',
            description: 'मंडळाच्या डेटाचा सुरक्षित बॅकअप तयार करा.',
            badge: _isLoadingLastBackup
                ? null
                : (_lastBackupTime != null
                    ? 'शेवटचा: ${_formatDateTime(_lastBackupTime!)}'
                    : 'अद्याप बॅकअप नाही'),
            onTap: _showBackupBottomSheet,
          ),
          const SizedBox(height: 12),

          // 1.3 रिस्टोर
          _settingsOptionTile(
            context: context,
            icon: Icons.restore,
            title: 'रिस्टोर',
            description: 'पूर्वी तयार केलेल्या बॅकअपमधून डेटा परत मिळवा.',
            onTap: () {
              if (!_authService.canSync) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'डेटाबेस रिस्टोर करण्याची परवानगी आपल्या खात्याला नाही. कृपया Developer शी संपर्क साधा.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RestoreScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 1.4 जुना / Recovery Data
          _settingsOptionTile(
            context: context,
            icon: Icons.history,
            title: 'जुना / Recovery Data',
            description:
                'Restore प्रक्रियेमध्ये तयार झालेले जुने database सुरक्षितपणे पहा किंवा manage करा.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RecoveryDataScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 1.5 App Update
          _settingsOptionTile(
            context: context,
            icon: Icons.system_update_rounded,
            title: 'App Update',
            description:
                'नवीन अपडेट तपासा आणि थेट अॅपमधून सुरक्षितपणे अपडेट करा.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppUpdateScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Section 2: खजानी खाते व व्यवस्थापन
          Text(
            'खजानी व्यवस्थापन',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF25231F),
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'खजानी माहिती, अधिकार हस्तांतरण आणि खाते नियंत्रण.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF756A5D),
            ),
          ),
          const SizedBox(height: 14),

          // 2.1 Khajani Management Tile
          _settingsOptionTile(
            context: context,
            icon: Icons.manage_accounts_outlined,
            title: 'खजानी व्यवस्थापन',
            description: isDeveloper
                ? 'Developer Control: सर्व खाती, भूमिका व परवानग्या व्यवस्थापित करा.'
                : 'चालू व माजी खजानींची यादी पहा आणि नवीन खजानी सेट करून अधिकार हस्तांतरित करा.',
            badge: currentUser != null
                ? (isDeveloper
                    ? 'Developer (सर्वोच्च ॲडमिन)'
                    : '${currentUser.name} (${isLatest ? "चालू" : "माजी"})')
                : null,
            onTap: () {
              if (!_authService.canManageKhajani && !isDeveloper) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'खजानी व्यवस्थापन पाहण्याची किंवा बदलण्याची परवानगी आपल्या खात्याला नाही. कृपया Developer शी संपर्क साधा.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const KhajaniManagementScreen(),
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          const SizedBox(height: 24),

          // Section 3: रिमोट संप्रेषण व डिव्हाइस माहिती
          Text(
            'रिमोट संप्रेषण व डिव्हाइस',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF25231F),
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'PC WebSocket सर्व्हर जोडणी व या उपकरणाचा कायमचा Device ID.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF756A5D),
            ),
          ),
          const SizedBox(height: 14),

          // 3.1 PC Signaling Server Tile
          StreamBuilder<bool>(
            stream: SignalingService.instance.isConnectedStream,
            initialData: SignalingService.instance.isConnected,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              return _settingsOptionTile(
                context: context,
                icon: Icons.computer,
                title: 'PC Signaling Server',
                description:
                    'सर्व्हर: ${SignalingService.instance.serverUrl}\n(टॅप करून IP किंवा पोर्ट बदला)',
                badge: isOnline ? 'Server is ON 🟢' : 'Server is OFF 🔴',
                onTap: _showSignalingServerDialog,
              );
            },
          ),
          const SizedBox(height: 12),

          // 3.2 रिमोट डेटा सिंक (Master DB Sync) Tile
          _settingsOptionTile(
            context: context,
            icon: Icons.cloud_sync_outlined,
            title: 'रिमोट डेटा सिंक (Master DB Sync)',
            description: RemoteSyncService.instance.isMaster
                ? 'हा फोन MASTER डेटाबेस आहे. इतर फोनला इथून डेटा मिळतो.'
                : 'Master फोनवरून सर्व आर्थिक नोंदी स्थानिक SQLite मध्ये सुरक्षितपणे सिंक करा.',
            badge: _isSyncingFinancial
                ? 'सिंक चालू...'
                : (RemoteSyncService.instance.isMaster ? 'Master Phone 👑' : 'Target Phone 📱'),
            onTap: () {
              if (!_isSyncingFinancial) {
                _handleRemoteFinancialSync();
              }
            },
          ),
          const SizedBox(height: 12),

          // 3.3 Device Info Tile
          _settingsOptionTile(
            context: context,
            icon: Icons.perm_device_information_outlined,
            title: 'या उपकरणाचा Device ID',
            description: _currentDeviceId.isNotEmpty
                ? 'Device ID: $_currentDeviceId\n(टॅप करून कॉपी करा किंवा तपशील पहा)'
                : 'उपकरण ओळख तयार करत आहे...',
            badge: _currentDeviceId.isNotEmpty ? _currentDeviceId : null,
            onTap: _showDeviceInfoDialog,
          ),
          const SizedBox(height: 24),

          // 2.2 Logout Tile
          _settingsOptionTile(
            context: context,
            icon: Icons.logout_rounded,
            title: 'लॉगआउट',
            description: 'खजानी खात्यातून सुरक्षितपणे बाहेर पडा.',
            badge: currentUser?.name,
            onTap: _handleLogout,
          ),
          const SizedBox(height: 28),

          // Info / Storage path summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7EE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE0BE)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_special_outlined,
                        color: deepSaffron, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'डेटा स्टोरेज माहिती',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: deepSaffron,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'सक्रिय डेटाबेस:\n/storage/emulated/0/हिंदवी/hindvi_latest.db',
                  style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                ),
                SizedBox(height: 6),
                Text(
                  'सुरक्षित Recovery फोल्डर:\n/storage/emulated/0/हिंदवी/Old/',
                  style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'हिंदवी स्वराज्य • offline-first',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9E9283),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsOptionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    String? badge,
    required VoidCallback onTap,
  }) {
    const deepSaffron = Color(0xFFB94D00);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 26, color: deepSaffron),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF25231F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF756A5D),
                        height: 1.35,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EBE3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5A5248),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: deepSaffron,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupBottomSheetContent extends StatefulWidget {
  final VoidCallback onBackupComplete;

  const _BackupBottomSheetContent({required this.onBackupComplete});

  @override
  State<_BackupBottomSheetContent> createState() =>
      _BackupBottomSheetContentState();
}

class _BackupBottomSheetContentState extends State<_BackupBottomSheetContent> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isBusy = false;
  String? _statusText;
  File? _createdBackupFile;
  DateTime? _lastBackupTime;

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
  }

  Future<void> _loadBackupInfo() async {
    try {
      final time = await _databaseHelper.getLastBackupTime();
      if (mounted) {
        setState(() {
          _lastBackupTime = time;
        });
      }
    } catch (_) {}
  }

  String _formatDateTime(DateTime dt) {
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
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${marathiMonths[dt.month - 1]} ${dt.year}, $hour12:$minuteStr $period';
  }

  Future<void> _backupNow() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _statusText = 'बॅकअप तयार करत आहे...';
    });

    try {
      final backup = await _databaseHelper.createExplicitBackup();

      if (!mounted) return;

      setState(() {
        _createdBackupFile = backup;
        _isBusy = false;
        _statusText = 'बॅकअप यशस्वीरीत्या तयार झाला!';
      });

      widget.onBackupComplete();
      await _loadBackupInfo();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusText = 'बॅकअप तयार करता आला नाही. कृपया पुन्हा प्रयत्न करा.';
      });
    }
  }

  Future<void> _shareBackup() async {
    if (_createdBackupFile == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_createdBackupFile!.path)],
          subject: path.basename(_createdBackupFile!.path),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('बॅकअप शेअर करता आला नाही.')),
        );
      }
    }
  }

  Future<void> _saveBackupToStorage() async {
    if (_createdBackupFile == null) return;
    try {
      final bytes = await _createdBackupFile!.readAsBytes();
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save database backup',
        fileName: path.basename(_createdBackupFile!.path),
        bytes: bytes,
      );
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('बॅकअप यशस्वीरीत्या जतन झाला.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('बॅकअप जतन करता आला नाही.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const deepSaffron = Color(0xFFB94D00);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.backup_outlined, color: deepSaffron, size: 26),
                SizedBox(width: 10),
                Text(
                  'डेटा बॅकअप',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'मंडळाच्या डेटाचा सुरक्षित बॅकअप तयार करा.',
              style: TextStyle(fontSize: 13, color: Color(0xFF756A5D)),
            ),
            const SizedBox(height: 18),

            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF3E3D1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: deepSaffron),
                      const SizedBox(width: 6),
                      Text(
                        'डेटाबेस स्थिती: सुरक्षित',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'स्थान: /storage/emulated/0/हिंदवी/hindvi_latest.db',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF555555)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'बॅकअप फोल्डर: /storage/emulated/0/हिंदवी/Old/',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF555555)),
                  ),
                  const Divider(height: 16),
                  Text(
                    'Last Backup:\n${_lastBackupTime != null ? _formatDateTime(_lastBackupTime!) : 'अद्याप बॅकअप तयार केलेला नाही'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF25231F),
                    ),
                  ),
                ],
              ),
            ),

            if (_statusText != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _createdBackupFile != null
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _createdBackupFile != null
                        ? Colors.green.shade300
                        : Colors.orange.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _createdBackupFile != null
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      color: _createdBackupFile != null
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusText!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _createdBackupFile != null
                              ? Colors.green.shade900
                              : Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            if (_isBusy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: Color(0xFFFF7A00)),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _backupNow,
                icon: const Icon(Icons.backup),
                label: const Text(
                  'Backup Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

            if (_createdBackupFile != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareBackup,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('शेअर करा'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveBackupToStorage,
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('जतन करा'),
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
