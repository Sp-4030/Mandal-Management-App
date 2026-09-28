import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
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

  DateTime? _lastBackupTime;
  bool _isLoadingLastBackup = true;

  @override
  void initState() {
    super.initState();
    _loadLastBackupTime();
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
      'डिसेंबर'
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

  @override
  Widget build(BuildContext context) {
    const deepSaffron = Color(0xFFB94D00);

    return Scaffold(
      appBar: AppBar(
        title: const Text('सेटिंग्ज'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Section Header
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

          // 1. मंडळ डेटा ट्रान्सफर
          _settingsOptionTile(
            context: context,
            icon: Icons.sync_alt,
            title: 'मंडळ डेटा ट्रान्सफर',
            description:
                'जुन्या फोनमधील संपूर्ण मंडळ डेटा नवीन फोनमध्ये सुरक्षितपणे ट्रान्सफर करा.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MandalDataTransferScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 2. बॅकअप
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

          // 3. रिस्टोर
          _settingsOptionTile(
            context: context,
            icon: Icons.restore,
            title: 'रिस्टोर',
            description: 'पूर्वी तयार केलेल्या बॅकअपमधून डेटा परत मिळवा.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RestoreScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // 4. जुना / Recovery Data
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
          const SizedBox(height: 28),

          // Info / Storage path summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7EE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE0BE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
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
                const SizedBox(height: 8),
                const Text(
                  'सक्रिय डेटाबेस:\n/storage/emulated/0/हिंदवी/hindvi_latest.db',
                  style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                ),
                const SizedBox(height: 6),
                const Text(
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
      'डिसेंबर'
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
                  Text(
                    'स्थान: /storage/emulated/0/हिंदवी/hindvi_latest.db',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF555555)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'बॅकअप फोल्डर: /storage/emulated/0/हिंदवी/Old/',
                    style: const TextStyle(
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
