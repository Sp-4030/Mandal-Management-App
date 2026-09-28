import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../database/database_helper.dart';

class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isLoading = true;
  bool _isOperating = false;
  String _operatingMessage = 'प्रक्रिया सुरू आहे...';
  List<File> _backupFiles = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
  }

  Future<void> _loadBackupFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final files = await _databaseHelper.getOldBackupFiles();
      if (mounted) {
        setState(() {
          _backupFiles = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'फाइल्स लोड करता आल्या नाहीत: $e';
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

  Future<void> _pickExternalFileAndRestore() async {
    if (_isOperating) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) {
        _showSnackBar('अवैध फाइल निवडली.');
        return;
      }

      final file = File(filePath);
      await _confirmAndRestore(file);
    } catch (_) {
      _showSnackBar('फाइल निवडताना त्रुटी आली.');
    }
  }

  Future<void> _confirmAndRestore(File file) async {
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
      await _loadBackupFiles();
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
        title: const Text('रिस्टोर'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadBackupFiles,
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
                          child: const Icon(Icons.restore, color: deepSaffron, size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'डेटा रिस्टोर (Restore)',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'पूर्वी तयार केलेल्या बॅकअपमधून डेटा परत मिळवा.',
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
                const SizedBox(height: 16),

                // Pick from storage button
                Card(
                  child: InkWell(
                    onTap: _isOperating ? null : _pickExternalFileAndRestore,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0E1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.file_open_outlined, color: deepSaffron, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'बाहेरील बॅकअप फाइल निवडा',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'स्टोरेज, WhatsApp किंवा Drive वरून .db फाईल निवडून रिस्टोर करा',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF756A5D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFF756A5D)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'उपलब्ध बॅकअप फाइल्स (Old Folder)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                            onPressed: _loadBackupFiles,
                            child: const Text('पुन्हा प्रयत्न करा'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_backupFiles.isEmpty)
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
                            'कोणतीही बॅकअप फाइल आढळली नाही',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '/storage/emulated/0/हिंदवी/Old/ मध्ये अद्याप कोणत्याही बॅकअप फाइल्स नाहीत. तुम्ही सेटिंग्जमधून "बॅकअप तयार करा" करू शकता किंवा वरील पर्यायातून बाहेरील फाइल निवडू शकता.',
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
                  ..._backupFiles.map((file) {
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
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: _isOperating
                                    ? null
                                    : () => _confirmAndRestore(file),
                                icon: const Icon(Icons.restore, size: 18),
                                label: const Text('Restore करा'),
                              ),
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
}
