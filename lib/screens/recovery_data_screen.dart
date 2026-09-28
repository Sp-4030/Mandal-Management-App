import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';

class RecoveryDataScreen extends StatefulWidget {
  const RecoveryDataScreen({super.key});

  @override
  State<RecoveryDataScreen> createState() => _RecoveryDataScreenState();
}

class _RecoveryDataScreenState extends State<RecoveryDataScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isLoading = true;
  bool _isOperating = false;
  String _operatingMessage = 'प्रक्रिया सुरू आहे...';

  List<File> _oldFiles = [];
  Map<String, dynamic>? _migrationRecovery;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _databaseHelper.expireMigrationRecoveryIfNeeded();
      final recovery = await _databaseHelper.getMigrationRecovery();
      final files = await _databaseHelper.getOldBackupFiles();

      if (mounted) {
        setState(() {
          _migrationRecovery = recovery;
          _oldFiles = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'डेटा लोड करताना त्रुटी आली: $e';
        });
      }
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatRemainingTime(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'कालावधी पूर्ण झाला (Expired)';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return '$days दिवस $hours तास शिल्लक';
  }

  Future<void> _confirmAndRestoreFile(File file) async {
    if (_isOperating) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('डेटा Restore करा'),
        content: const Text(
          'सध्याचा डेटा बदलला जाईल. Restore करण्यापूर्वी सध्याच्या डेटाची सुरक्षित प्रत तयार केली जाईल. पुढे जायचे आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द करा'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore करा'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isOperating = true;
      _operatingMessage = 'डेटाबेस तपासला जात आहे...';
    });

    try {
      await _databaseHelper.validateBackupFile(file);

      if (!mounted) return;
      setState(() {
        _operatingMessage = 'Restore सुरू आहे...';
      });

      await _databaseHelper.restoreDatabaseFromFile(file);

      if (!mounted) return;
      _showSnackBar('डेटाबेस यशस्वीरीत्या Restore झाला.');
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('डेटाबेस सुरक्षितपणे Restore करता आला नाही.');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _confirmAndDeleteFile(File file) async {
    if (_isOperating) return;

    final fileName = path.basename(file.path);

    // Safety precaution check
    if (fileName == _databaseHelper.databaseFileName) {
      _showSnackBar('सक्रिय डेटाबेस हटवता येत नाही.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('सावधान! जुनी फाइल हटवायची?'),
        content: Text(
          '"$fileName" ही जुनी बॅकअप प्रत कायमस्वरूपी हटवली जाईल.\n\nतुम्हाला खात्री आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द करा'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('हटवा'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isOperating = true;
      _operatingMessage = 'फाइल हटवत आहे...';
    });

    try {
      await _databaseHelper.deleteOldBackupFile(file);
      if (!mounted) return;
      _showSnackBar('जुनी फाइल यशस्वीरीत्या हटवली.');
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('फाइल हटवताना त्रुटी: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _restoreMigrationSnapshot() async {
    if (_isOperating || _migrationRecovery == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('मायग्रेशन डेटा परत आणायचा?'),
        content: const Text(
          'सध्याचा डेटा बदलला जाईल. Restore करण्यापूर्वी सध्याच्या डेटाची सुरक्षित प्रत तयार केली जाईल. पुढे जायचे आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द करा'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore करा'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isOperating = true;
      _operatingMessage = 'Restore सुरू आहे...';
    });

    try {
      await _databaseHelper.createSafetyBackupBeforeMigration();
      await _databaseHelper.restoreMigrationRecovery();

      if (!mounted) return;
      _showSnackBar('जुना डेटा यशस्वीरीत्या परत आणला!');
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('डेटाबेस सुरक्षितपणे Restore करता आला नाही.');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  Future<void> _deleteMigrationSnapshotNow() async {
    if (_isOperating || _migrationRecovery == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('सावधान! (Warning)'),
        content: const Text(
          '७ दिवसांची सुरक्षित मायग्रेशन प्रत कायमस्वरूपी नष्ट केली जाईल.\n\nतुम्हाला खात्री आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द करा'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('कायमस्वरूपी हटवा'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isOperating = true;
      _operatingMessage = 'डेटा हटवत आहे...';
    });

    try {
      await _databaseHelper.deleteMigrationRecoveryNow();
      if (!mounted) return;
      _showSnackBar('मायग्रेशन प्रत हटवली गेली.');
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('त्रुटी: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isOperating = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const deepSaffron = Color(0xFFB94D00);

    return Scaffold(
      appBar: AppBar(
        title: const Text('जुना / Recovery Data'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Top Header Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0E1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.history, color: deepSaffron, size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'जुना व Recovery डेटा व्यवस्थापन',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Restore प्रक्रियेमध्ये तयार झालेले जुने database सुरक्षितपणे पहा किंवा manage करा.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF756A5D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 7-Day Migration Recovery Banner if available
                if (_migrationRecovery != null) ...[
                  _buildMigrationRecoveryCard(context, deepSaffron),
                  const SizedBox(height: 24),
                ],

                // Old / Recovery files section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'जुने डेटाबेस फाइल्स (Old Folder)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${_oldFiles.length} फाइल्स',
                      style: const TextStyle(color: Color(0xFF756A5D), fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFFFF7A00)),
                    ),
                  )
                else if (_errorMessage != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 36),
                          const SizedBox(height: 10),
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _loadData,
                            child: const Text('पुन्हा प्रयत्न करा'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_oldFiles.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF0E1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.folder_open_outlined,
                              color: deepSaffron,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'कोणतीही जुनी प्रत आढळली नाही',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '/storage/emulated/0/हिंदवी/Old/ फोल्डर रिकामे आहे. प्रत्येक Restore आणि मायग्रेशन प्रक्रियेपूर्वी सध्याच्या डेटाची प्रत येथे आपोआप सुरक्षित ठेवली जाते.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF756A5D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._oldFiles.map((file) {
                    final fileName = path.basename(file.path);
                    DateTime? fileTime;
                    int fileSize = 0;
                    try {
                      fileTime = file.lastModifiedSync();
                      fileSize = file.lengthSync();
                    } catch (_) {}

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF0E1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.storage_rounded,
                                    color: deepSaffron,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fileName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${fileTime != null ? _formatDateTime(fileTime) : ''} • ${_formatFileSize(fileSize)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF756A5D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(color: Colors.red.shade300),
                                  ),
                                  onPressed: _isOperating
                                      ? null
                                      : () => _confirmAndDeleteFile(file),
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('हटवा'),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.tonalIcon(
                                  onPressed: _isOperating
                                      ? null
                                      : () => _confirmAndRestoreFile(file),
                                  icon: const Icon(Icons.restore, size: 18),
                                  label: const Text('Restore करा'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          if (_isOperating)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Color(0xFFFF7A00)),
                          const SizedBox(height: 18),
                          Text(
                            _operatingMessage,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMigrationRecoveryCard(BuildContext context, Color deepSaffron) {
    final migratedAt = DateTime.fromMillisecondsSinceEpoch(
      _migrationRecovery!['migrated_at'] as int,
    );
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      _migrationRecovery!['expires_at'] as int,
    );
    final isExpired = DateTime.now().isAfter(expiresAt);

    final countsMap = jsonDecode(_migrationRecovery!['record_counts'] as String) as Map;
    int totalRecords = 0;
    countsMap.forEach((_, v) {
      if (v is num) totalRecords += v.toInt();
    });

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isExpired ? Colors.orange.shade300 : Colors.green.shade300,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isExpired ? Icons.access_time : Icons.verified_user_outlined,
                  color: isExpired ? Colors.orange.shade800 : Colors.green.shade700,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isExpired
                        ? '7 दिवसांचा Recovery कालावधी पूर्ण झाला आहे. जुना डेटा हटवला जाऊ शकतो.'
                        : 'जुना डेटा 7 दिवसांसाठी सुरक्षित ठेवला आहे.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isExpired ? Colors.orange.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'मायग्रेशन तारीख: ${_formatDateTime(migratedAt)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 4),
            Text(
              'एकूण नोंदी: $totalRecords नोंदी',
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 4),
            Text(
              'शिल्लक मुदत: ${_formatRemainingTime(expiresAt)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isExpired ? Colors.red.shade700 : deepSaffron,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  onPressed: _isOperating ? null : _deleteMigrationSnapshotNow,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('कायमस्वरूपी हटवा'),
                ),
                if (!isExpired)
                  FilledButton.icon(
                    onPressed: _isOperating ? null : _restoreMigrationSnapshot,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('डेटा परत आणा'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
