import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

enum _ExportAction { save, share }

class DatabaseBackupRestoreScreen extends StatefulWidget {
  const DatabaseBackupRestoreScreen({super.key});

  @override
  State<DatabaseBackupRestoreScreen> createState() =>
      _DatabaseBackupRestoreScreenState();
}

class _DatabaseBackupRestoreScreenState
    extends State<DatabaseBackupRestoreScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isBusy = false;
  String _busyMessage = 'डेटाबेस प्रक्रिया सुरू आहे...';
  String? _lastBackupName;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportDatabase() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Backup तयार करत आहे...';
    });

    try {
      final backup = await _databaseHelper.createExportBackup();
      if (!mounted) return;

      setState(() => _lastBackupName = path.basename(backup.path));
      final action = await showModalBottomSheet<_ExportAction>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save backup'),
                onTap: () => Navigator.pop(sheetContext, _ExportAction.save),
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share backup'),
                onTap: () => Navigator.pop(sheetContext, _ExportAction.share),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (!mounted) return;
      if (action == _ExportAction.save) {
        await _saveBackup(backup);
      } else if (action == _ExportAction.share) {
        await _shareBackup(backup);
      } else {
        _showMessage('बॅकअप तयार झाला: ${path.basename(backup.path)}');
      }
    } catch (_) {
      _showMessage('बॅकअप तयार करता आला नाही. कृपया पुन्हा प्रयत्न करा.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _saveBackup(File backup) async {
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save database backup',
        fileName: path.basename(backup.path),
        bytes: await backup.readAsBytes(),
      );
      if (destination == null) {
        _showMessage('बॅकअप जतन करणे रद्द केले.');
      } else {
        _showMessage('बॅकअप यशस्वीरीत्या जतन झाला.');
      }
    } catch (_) {
      _showMessage('बॅकअप जतन करता आला नाही.');
    }
  }

  Future<void> _shareBackup(File backup) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(backup.path)],
          subject: path.basename(backup.path),
        ),
      );
    } catch (_) {
      _showMessage('बॅकअप शेअर करता आला नाही.');
    }
  }

  Future<void> _importDatabase() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Backup तपासत आहे...';
    });

    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['db'],
        allowMultiple: false,
      );
      if (selection == null || selection.files.isEmpty) return;

      final selectedPath = selection.files.single.path;
      if (selectedPath == null) {
        _showMessage('Invalid or unsupported database backup.');
        return;
      }

      final backup = File(selectedPath);
      try {
        await _databaseHelper.validateBackupFile(backup);
      } catch (_) {
        _showMessage('Invalid or unsupported database backup.');
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: const Text(
            'तुमचा सध्याचा डेटा replace होईल. तुम्हाला हा backup restore करायचा आहे का?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _busyMessage = 'Database restore करत आहे...');
      final safetyBackup = await _databaseHelper.restoreDatabaseFromFile(backup);
      if (mounted) {
        setState(() => _lastBackupName = path.basename(safetyBackup.path));
        _showMessage('Database restore successful.');
      }
    } catch (_) {
      _showMessage('डेटाबेस restore करता आला नाही. सध्याचा डेटा सुरक्षित आहे.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Database Backup & Restore')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _actionButton(
                icon: Icons.save_alt,
                title: 'Export Database',
                subtitle: 'संपूर्ण डेटाबेसचा बॅकअप तयार करा',
                onPressed: _isBusy ? null : _exportDatabase,
              ),
              const SizedBox(height: 16),
              _actionButton(
                icon: Icons.settings_backup_restore,
                title: 'Import / Restore Database',
                subtitle: 'बॅकअपमधून डेटाबेस restore करा',
                onPressed: _isBusy ? null : _importDatabase,
              ),
              const SizedBox(height: 24),
              Text(
                'Last Backup: ${_lastBackupName ?? 'अद्याप उपलब्ध नाही'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          if (_isBusy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _busyMessage,
                            style: Theme.of(context).textTheme.bodyLarge,
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

  Widget _actionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
        style: FilledButton.styleFrom(alignment: Alignment.centerLeft),
      ),
    );
  }
}