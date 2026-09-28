import 'dart:io';
import 'package:flutter/material.dart';

import '../migration/migration_client.dart';
import '../migration/migration_models.dart';
import 'qr_scanner_screen.dart';

enum _ReceiveState {
  initial,
  connecting,
  connected,
  migrating,
  verifying,
  success,
  error,
}

class MigrationReceiveScreen extends StatefulWidget {
  const MigrationReceiveScreen({super.key});

  @override
  State<MigrationReceiveScreen> createState() => _MigrationReceiveScreenState();
}

class _MigrationReceiveScreenState extends State<MigrationReceiveScreen> {
  final MigrationClient _client = MigrationClient();

  _ReceiveState _state = _ReceiveState.initial;
  MigrationPairingInfo? _pairingInfo;
  MandalSummaryInfo? _mandalSummary;
  String _mandalName = 'हिंदवी स्वराज्य';

  double _progressValue = 0.0;
  String _statusMessage = '';
  String _errorMessage = '';

  Future<void> _scanQr() async {
    final result = await Navigator.push<MigrationPairingInfo>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (result == null || !mounted) return;

    _pairingInfo = result;
    await _connectToOldPhone();
  }

  Future<void> _connectToOldPhone() async {
    if (_pairingInfo == null) return;

    setState(() {
      _state = _ReceiveState.connecting;
      _statusMessage = 'जुन्या फोनशी संपर्क साधत आहे...';
      _errorMessage = '';
    });

    try {
      final info = await _client.fetchMandalInfo(_pairingInfo!);
      if (!mounted) return;

      setState(() {
        _state = _ReceiveState.connected;
        _mandalName = info['mandalName'] as String;
        _mandalSummary = info['summary'] as MandalSummaryInfo;
        _statusMessage = 'जुना फोन जोडला गेला ✓';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ReceiveState.error;
        _errorMessage = e is SocketException
            ? e.message
            : e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _startMigration() async {
    if (_pairingInfo == null || _mandalSummary == null) return;

    // Confirm dialog before starting import
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('मायग्रेशन सुरू करायचे?'),
        content: Text(
          'या प्रक्रियेद्वारे "$_mandalName" चा सर्व डेटा (${_mandalSummary!.totalRecords} नोंदी) या फोनवर आयात केला जाईल.\n\nतुम्ही खात्री केली आहे का?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द करा'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('होय, सुरू करा'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _state = _ReceiveState.migrating;
      _progressValue = 0.05;
      _statusMessage = 'डेटा ट्रान्सफर सुरू करत आहे...';
      _errorMessage = '';
    });

    try {
      await _client.executeMigration(
        pairing: _pairingInfo!,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _progressValue = progress;
              _statusMessage = status;
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _state = _ReceiveState.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ReceiveState.error;
        _errorMessage = e is SocketException
            ? e.message
            : e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const deepSaffron = Color(0xFFB94D00);

    return Scaffold(
      appBar: AppBar(
        title: const Text('डेटा स्वीकारा (नवीन फोन)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildBody(context, deepSaffron),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color deepSaffron) {
    switch (_state) {
      case _ReceiveState.initial:
        return _buildInitialCard(context);

      case _ReceiveState.connecting:
        return _buildLoadingCard('जुन्या फोनशी संपर्क साधत आहे...');

      case _ReceiveState.connected:
        return _buildConnectedCard(context, deepSaffron);

      case _ReceiveState.migrating:
      case _ReceiveState.verifying:
        return _buildProgressCard(context);

      case _ReceiveState.success:
        return _buildSuccessCard(context);

      case _ReceiveState.error:
        return _buildErrorCard(context);
    }
  }

  Widget _buildInitialCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0E1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  size: 38,
                  color: Color(0xFFB94D00),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'मंडळ डेटा स्वीकारा',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'जुन्या खजिनदारांच्या फोनवरील संपूर्ण डेटा या फोनवर आणण्यासाठी:',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF666666), fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD4A8)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'महत्त्वाच्या सूचना:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 8),
                  Text('१. जुन्या फोनवर Mobile Hotspot चालू करा.'),
                  Text('२. हा नवीन फोन त्या Wi-Fi Hotspot शी कनेक्ट करा.'),
                  Text('३. खालील बटण दाबून जुन्या फोनवरील QR कोड स्कॅन करा.'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('QR कोड स्कॅन करा'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF7A00)),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedCard(BuildContext context, Color deepSaffron) {
    final summary = _mandalSummary;

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
                  child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_mandalName सापडले ✓',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Text(
                        'जुना फोन जोडला गेला ✓',
                        style: TextStyle(fontSize: 13, color: Color(0xFF756A5D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'आयात होणारा मंडळ डेटा तपशील:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (summary != null) ...[
              _statRow('सदस्य (वर्गणी नोंदी)', '${summary.membersCount}'),
              _statRow('जमा / देणगी नोंदी', '${summary.incomeCount}'),
              _statRow('खर्च नोंदी', '${summary.expensesCount}'),
              _statRow('एकूण व्यवहार नोंदी', '${summary.transactionsCount}'),
              _statRow('इतर नोंदी (साहित्य/शिल्लक)', '${summary.otherCount}'),
              const Divider(height: 24),
              _statRow('एकूण रेकॉर्ड्स', '${summary.totalRecords}', isBold: true),
            ],
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _startMigration,
              icon: const Icon(Icons.download),
              label: const Text('मायग्रेशन सुरू करा'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                setState(() => _state = _ReceiveState.initial);
              },
              child: const Text('रद्द करा'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final percentage = (_progressValue * 100).toInt();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'मंडळ डेटा आयात करत आहे...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _progressValue,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: const Color(0xFFF0E5D8),
              color: const Color(0xFFFF7A00),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '$percentage%',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB94D00),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7EF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF2DFC7)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('कृपया दोन्ही फोन जवळ ठेवा.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('प्रक्रिया पूर्ण होईपर्यंत Wi-Fi डिस्कनेक्ट करू नका किंवा ॲप बंद करू नका.', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard(BuildContext context) {
    final summary = _mandalSummary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.verified, size: 44, color: Colors.green.shade700),
            ),
            const SizedBox(height: 18),
            const Text(
              'मायग्रेशन यशस्वी पूर्ण झाले! ✓',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'मंडळाचा संपूर्ण डेटा या फोनवर सुरक्षितपणे आयात आणि सत्यापित झाला आहे.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF444444)),
            ),
            const SizedBox(height: 18),
            if (summary != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F5EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _verificationRow('सदस्य नोंदी', '${summary.membersCount} ✓'),
                    _verificationRow('जमा नोंदी', '${summary.incomeCount} ✓'),
                    _verificationRow('खर्च नोंदी', '${summary.expensesCount} ✓'),
                    _verificationRow('इतर नोंदी', '${summary.otherCount} ✓'),
                    const Divider(height: 16),
                    _verificationRow('डेटा अखंडता (Integrity)', 'सत्यापित ✓', isBold: true),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('मुख्य डॅशबोर्डवर जा'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 36, color: Colors.red.shade700),
            ),
            const SizedBox(height: 16),
            const Text(
              'मायग्रेशन अयशस्वी',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'तुमचा मूळ डेटा सुरक्षित आहे.',
              style: TextStyle(color: Color(0xFF756A5D), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD4D4)),
              ),
              child: Text(
                _errorMessage.isEmpty ? 'अपेक्षित त्रुटी आली. कृपया पुन्हा प्रयत्न करा.' : _errorMessage,
                style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _state = _ReceiveState.initial);
                    },
                    child: const Text('रद्द करा'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _connectToOldPhone,
                    icon: const Icon(Icons.refresh),
                    label: const Text('पुन्हा प्रयत्न करा'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: const Color(0xFF444444),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isBold ? const Color(0xFFB94D00) : const Color(0xFF25231F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        ],
      ),
    );
  }
}
