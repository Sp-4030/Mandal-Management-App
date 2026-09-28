import 'package:flutter/material.dart';

import 'migration_send_screen.dart';
import 'migration_receive_screen.dart';
import 'migration_recovery_screen.dart';

class MigrationMenuScreen extends StatelessWidget {
  const MigrationMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मंडळ डेटा ट्रान्सफर / मायग्रेशन'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7A00), Color(0xFFB94D00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.swap_horizontal_circle_outlined, color: Colors.white, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'खजिनदार बदल प्रणाली',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'इंटरनेट किंवा क्लाउड शिवाय संपूर्ण मंडळ डेटा थेट फोन-टू-फोन सुरक्षित ट्रान्सफर करा.',
                        style: TextStyle(
                          color: Color(0xFFFFE6CF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _menuTile(
            context: context,
            icon: Icons.qr_code,
            title: 'डेटा पाठवा (जुना खजिनदार फोन)',
            subtitle: 'मोबाईल हॉटस्पॉट सुरू करून नवीन फोनला सर्व डेटा ट्रान्सफर करा',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MigrationSendScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _menuTile(
            context: context,
            icon: Icons.qr_code_scanner,
            title: 'डेटा स्वीकारा (नवीन खजिनदार फोन)',
            subtitle: 'जुन्या फोनच्या हॉटस्पॉटशी जोडून QR कोड स्कॅन करा आणि डेटा मिळवा',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MigrationReceiveScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _menuTile(
            context: context,
            icon: Icons.restore_from_trash,
            title: 'मायग्रेशन पुनर्प्राप्ती (७ दिवस)',
            subtitle: 'मायग्रेशननंतर ७ दिवसांसाठी सुरक्षित ठेवलेला डेटा पाहा किंवा परत आणा',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MigrationRecoveryScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _menuTile({
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 26, color: const Color(0xFFB94D00)),
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
                        fontSize: 12,
                        color: Color(0xFF756A5D),
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
}
