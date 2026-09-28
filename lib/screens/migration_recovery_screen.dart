import 'dart:convert';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';

class MigrationRecoveryScreen extends StatefulWidget {
  const MigrationRecoveryScreen({super.key});

  @override
  State<MigrationRecoveryScreen> createState() => _MigrationRecoveryScreenState();
}

class _MigrationRecoveryScreenState extends State<MigrationRecoveryScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool _isLoading = true;
  Map<String, dynamic>? _recoveryData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecoveryData();
  }

  Future<void> _loadRecoveryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _databaseHelper.expireMigrationRecoveryIfNeeded();
      final data = await _databaseHelper.getMigrationRecovery();
      if (mounted) {
        setState(() {
          _recoveryData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  String _formatDate(DateTime dt) {
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
    return '${dt.day} ${marathiMonths[dt.month - 1]} ${dt.year}';
  }

  String _formatRemainingTime(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'कालबाह्य झाले (Expired)';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return '$days दिवस $hours तास शिल्लक';
  }

  Future<void> _restoreData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('डेटा पुनर्स्थापित करायचा?'),
        content: const Text(
          'या फोनवरील सध्याचा डेटा बदलून जुना बॅकअप घेतलेला मंडळ डेटा परत स्थापित केला जाईल.\n\nतुम्हाला खात्री आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द करा'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('पुनर्स्थापित करा'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await _databaseHelper.restoreMigrationRecovery();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('मायग्रेशन रद्द केले. जुना डेटा यशस्वीरीत्या परत आणला! ✓'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadRecoveryData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('डेटा पुनर्स्थापित करता आला नाही: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('सावधान! (Warning)'),
        content: const Text(
          'या फोनवरील जुना मंडळ डेटा कायमस्वरूपी नष्ट केला जाईल.\n\nही कृती पूर्ववत केली जाऊ शकत नाही.\n\nतुम्हाला खात्री आहे का?',
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

    setState(() => _isLoading = true);

    try {
      await _databaseHelper.deleteMigrationRecoveryNow();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('जुना डेटा कायमस्वरूपी हटवला गेला.'),
        ),
      );

      await _loadRecoveryData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('डेटा हटवताना त्रुटी: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मायग्रेशन पुनर्प्राप्ती (७ दिवस)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(36),
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFFF7A00)),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 40, color: Colors.red.shade700),
              const SizedBox(height: 12),
              Text('त्रुटी: $_errorMessage'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadRecoveryData,
                child: const Text('पुन्हा प्रयत्न करा'),
              ),
            ],
          ),
        ),
      );
    }

    if (_recoveryData == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0E1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inventory_2_outlined, size: 34, color: Color(0xFFB94D00)),
              ),
              const SizedBox(height: 18),
              const Text(
                'सध्या कोणतीही पुनर्प्राप्ती प्रत उपलब्ध नाही',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'जेव्हा जुन्या फोनवरून नवीन फोनवर डेटा ट्रान्सफर केला जातो, तेव्हा ७ दिवसांसाठी येथे सुरक्षित प्रत ठेवली जाते.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF756A5D), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final migratedAt =
        DateTime.fromMillisecondsSinceEpoch(_recoveryData!['migrated_at'] as int);
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(_recoveryData!['expires_at'] as int);
    final countsMap = jsonDecode(_recoveryData!['record_counts'] as String) as Map;

    int totalRecords = 0;
    countsMap.forEach((_, v) {
      if (v is num) totalRecords += v.toInt();
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified, color: Colors.green.shade700, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'मायग्रेशन यशस्वी झालेले आहे ✓',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        'पुनर्प्राप्ती प्रत ७ दिवसांसाठी सुरक्षित आहे',
                        style: TextStyle(fontSize: 12, color: Color(0xFF756A5D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            _infoRow('मायग्रेशन दिनांक:', _formatDate(migratedAt)),
            _infoRow('डेटा स्थिती:', 'संपूर्ण मंडळ डेटा ($totalRecords नोंदी)'),
            _infoRow('पुनर्प्राप्ती शिल्लक मुदत:', _formatRemainingTime(expiresAt), isHighlighted: true),
            _infoRow('कायमस्वरूपी नष्ट होण्याची तारीख:', _formatDate(expiresAt)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD4A8)),
              ),
              child: const Text(
                'टीप: नवीन खजिनदारांना डेटा व्यवस्थित मिळाल्याची खात्री पटल्यास '
                'तुम्ही "आता नष्ट करा" दाबू शकता किंवा ७ दिवसांनंतर ही प्रत आपोआप नष्ट होईल.',
                style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _restoreData,
              icon: const Icon(Icons.restore),
              label: const Text('डेटा परत आणा (Restore Data)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
              ),
              onPressed: _deleteNow,
              icon: const Icon(Icons.delete_forever),
              label: const Text('आता नष्ट करा (Delete Now)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                color: isHighlighted ? const Color(0xFFB94D00) : const Color(0xFF25231F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
