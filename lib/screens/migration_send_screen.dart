import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../migration/migration_models.dart';
import '../migration/migration_server.dart';
import 'migration_recovery_screen.dart';

class MigrationSendScreen extends StatefulWidget {
  const MigrationSendScreen({super.key});

  @override
  State<MigrationSendScreen> createState() => _MigrationSendScreenState();
}

class _MigrationSendScreenState extends State<MigrationSendScreen> {
  final MigrationServer _server = MigrationServer();
  StreamSubscription<MigrationServerState>? _subscription;

  MigrationPairingInfo? _pairingInfo;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _subscription = _server.stateStream.listen((state) {
      if (mounted) setState(() {});
    });
    _startServer();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _server.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pairing = await _server.startServer();
      if (mounted) {
        setState(() {
          _pairingInfo = pairing;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFFF7A00);
    const deepSaffron = Color(0xFFB94D00);

    return Scaffold(
      appBar: AppBar(
        title: const Text('मंडळ डेटा ट्रान्सफर (जुना फोन)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildBody(context, primaryColor, deepSaffron),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color primaryColor, Color deepSaffron) {
    if (_isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFFF7A00)),
              const SizedBox(height: 20),
              Text(
                _server.statusMessage,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
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
                child: Icon(Icons.wifi_off, size: 36, color: Colors.red.shade700),
              ),
              const SizedBox(height: 16),
              const Text(
                'कनेक्शन सुरू करता आले नाही',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7EF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF2DFC7)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('कृपया पुढील गोष्टी तपासा:', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 6),
                    Text('✓ जुन्या फोनचा मोबाईल हॉटस्पॉट (Mobile Hotspot) चालू करा'),
                    Text('✓ नवीन फोनला या हॉटस्पॉटशी जोडा (Wi-Fi द्वारे)'),
                    Text('✓ दोन्ही फोन जवळ ठेवा'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('रद्द करा'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _startServer,
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

    switch (_server.state) {
      case MigrationServerState.completed:
        return _buildCompletedCard(context);

      case MigrationServerState.transferring:
      case MigrationServerState.verifying:
        return _buildProgressCard(context);

      case MigrationServerState.peerConnected:
        return _buildConnectedCard(context, deepSaffron);

      case MigrationServerState.waitingForPeer:
      default:
        return _buildWaitingCard(context, primaryColor, deepSaffron);
    }
  }

  Widget _buildWaitingCard(BuildContext context, Color primaryColor, Color deepSaffron) {
    final qrData = _pairingInfo?.toJsonString() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD4A8)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'डेटा ट्रान्सफर पायऱ्या:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text('१. या फोनचा Mobile Hotspot चालू करा.'),
                  Text('२. नवीन फोन या हॉटस्पॉटशी Wi-Fi ने जोडा.'),
                  Text('३. नवीन फोनवर "डेटा स्वीकारा" उघडून हा QR स्कॅन करा.'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 230,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFFB94D00),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF25231F),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    'स्थानिक IP: ${_pairingInfo?.ip ?? ""}:${_pairingInfo?.port ?? ""}',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFFFF7A00)),
                ),
                const SizedBox(width: 12),
                Text(
                  _server.statusMessage,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                _server.stopServer();
                Navigator.pop(context);
              },
              child: const Text('रद्द करा'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedCard(BuildContext context, Color deepSaffron) {
    final summary = _server.peerSummary;

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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'नवीन फोन जोडला गेला ✓',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                      Text(
                        'नवीन फोनवरून ट्रान्सफर सुरू होण्याची प्रतीक्षा करत आहे...',
                        style: TextStyle(fontSize: 13, color: Color(0xFF756A5D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'ट्रान्सफर होणारा मंडळ डेटा:',
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
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFB94D00), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'नवीन फोनवर "मायग्रेशन सुरू करा" बटण दाबा.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                _server.stopServer();
                Navigator.pop(context);
              },
              child: const Text('रद्द करा'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF7A00)),
            const SizedBox(height: 24),
            Text(
              _server.statusMessage,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'कृपया दोन्ही फोन जवळ ठेवा आणि ॲप बंद करू नका.',
              style: TextStyle(color: Color(0xFF756A5D), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedCard(BuildContext context) {
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
              'सर्व मंडळ डेटा नवीन खजिनदारांच्या फोनवर सुरक्षितपणे ट्रान्सफर झाला आहे.\n\n'
              'सुरक्षिततेसाठी जुन्या फोनवरील डेटा तात्काळ नष्ट न करता "मायग्रेशन पुनर्प्राप्ती (7 दिवस)" मध्ये सुरक्षित ठेवण्यात आला आहे.',
              style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF333333)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const MigrationRecoveryScreen()),
                );
              },
              icon: const Icon(Icons.restore_from_trash),
              label: const Text('मायग्रेशन पुनर्प्राप्ती पाहा (७ दिवस)'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('मुख्य मेनूवर जा'),
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
}
