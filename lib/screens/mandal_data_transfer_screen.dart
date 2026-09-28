import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import 'migration_send_screen.dart';
import 'migration_receive_screen.dart';
import 'recovery_data_screen.dart';

class MandalDataTransferScreen extends StatefulWidget {
  const MandalDataTransferScreen({super.key});

  @override
  State<MandalDataTransferScreen> createState() => _MandalDataTransferScreenState();
}

class _MandalDataTransferScreenState extends State<MandalDataTransferScreen> {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  Map<String, dynamic>? _migrationRecovery;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkRecoveryStatus();
  }

  Future<void> _checkRecoveryStatus() async {
    setState(() => _isLoading = true);
    try {
      await _databaseHelper.expireMigrationRecoveryIfNeeded();
      final recovery = await _databaseHelper.getMigrationRecovery();
      if (mounted) {
        setState(() {
          _migrationRecovery = recovery;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatRemainingTime(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'कालावधी पूर्ण झाला (Expired)';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return '$days दिवस $hours तास शिल्लक';
  }

  @override
  Widget build(BuildContext context) {
    const saffron = Color(0xFFFF7A00);
    const deepSaffron = Color(0xFFB94D00);

    return Scaffold(
      appBar: AppBar(
        title: const Text('मंडळ डेटा ट्रान्सफर'),
      ),
      body: RefreshIndicator(
        onRefresh: _checkRecoveryStatus,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Top Gradient Hero Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [saffron, deepSaffron],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24A74200),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sync_alt, color: Colors.white, size: 36),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'संपूर्ण मंडळ डेटा ट्रान्सफर',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'जुन्या फोनमधील संपूर्ण मंडळ डेटा (वर्गणी, देणगी, साहित्य, आरती, खर्च, महाप्रसाद, शिल्लक व सर्व वर्षांच्या नोंदी) नवीन फोनमध्ये सुरक्षितपणे ट्रान्सफर करा.',
                    style: TextStyle(
                      color: Color(0xFFFFE6CF),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'पूर्णपणे ऑफलाइन • हॉटस्पॉट / स्थानिक नेटवर्क',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 7-Day Safety Status Card if present
            if (!_isLoading && _migrationRecovery != null) ...[
              _buildRecoveryStatusCard(context, deepSaffron),
              const SizedBox(height: 20),
            ],

            Text(
              'ट्रान्सफर पर्याय',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            // OLD PHONE OPTION
            _buildActionTile(
              context: context,
              icon: Icons.qr_code_2,
              title: 'डेटा पाठवा (जुना फोन)',
              subtitle: 'या फोनमधील संपूर्ण मंडळ डेटा नवीन फोनवर ट्रान्सफर करण्यासाठी QR कोड तयार करा.',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MigrationSendScreen(),
                  ),
                );
                _checkRecoveryStatus();
              },
            ),
            const SizedBox(height: 12),

            // NEW PHONE OPTION
            _buildActionTile(
              context: context,
              icon: Icons.qr_code_scanner,
              title: 'डेटा स्वीकारा (नवीन फोन)',
              subtitle: 'जुन्या फोनवरील QR कोड स्कॅन करून संपूर्ण डेटा या नवीन फोनवर आणा.',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MigrationReceiveScreen(),
                  ),
                );
                _checkRecoveryStatus();
              },
            ),
            const SizedBox(height: 24),

            // Security Steps Infographic Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.security, color: Color(0xFFB94D00), size: 22),
                        SizedBox(width: 10),
                        Text(
                          'सुरक्षित ट्रान्सफर प्रक्रिया',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _stepItem('१', 'जुन्या फोनवर तात्पुरते ट्रान्सफर सत्र व QR कोड तयार होतो.'),
                    _stepItem('२', 'नवीन फोन QR कोड स्कॅन करून जुन्या फोनशी जोडला जातो.'),
                    _stepItem('३', 'डेटा पॅकेज व SQLite Integrity Check द्वारे पडताळणी होते.'),
                    _stepItem('४', 'नवीन फोनवर सध्याच्या डेटाचा Old फोल्डरमध्ये आधी सुरक्षित बॅकअप होतो.'),
                    _stepItem('५', 'डेटा सुरक्षित स्थापित झाल्यावर जुन्या फोनवर ७ दिवसांची Recovery प्रत ठेवली जाते.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: const Color(0xFFB94D00)),
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
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF756A5D),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Color(0xFFB94D00),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecoveryStatusCard(BuildContext context, Color deepSaffron) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      _migrationRecovery!['expires_at'] as int,
    );
    final isExpired = DateTime.now().isAfter(expiresAt);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isExpired ? Colors.orange.shade300 : Colors.green.shade400,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isExpired ? Icons.access_time : Icons.verified_user_outlined,
                  color: isExpired ? Colors.orange.shade800 : Colors.green.shade700,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isExpired
                        ? '7 दिवसांचा Recovery कालावधी पूर्ण झाला आहे. जुना डेटा हटवला जाऊ शकतो.'
                        : 'जुना डेटा 7 दिवसांसाठी सुरक्षित ठेवला आहे.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isExpired ? Colors.orange.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'शिल्लक मुदत: ${_formatRemainingTime(expiresAt)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isExpired ? Colors.red.shade700 : deepSaffron,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RecoveryDataScreen(),
                    ),
                  );
                  _checkRecoveryStatus();
                },
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Recovery व्यवस्थापन'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF0E1),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFB94D00),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
            ),
          ),
        ],
      ),
    );
  }
}
