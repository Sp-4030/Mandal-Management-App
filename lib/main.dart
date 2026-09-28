import 'package:flutter/material.dart';

import 'screens/vargani_screen.dart';
import 'screens/prasad_dengani_screen.dart';
import 'screens/kharch_screen.dart';
import 'screens/mahaprasad_kharch_screen.dart';
import 'screens/database_backup_restore_screen.dart';
import 'pdf/annual_report_pdf.dart';

void main() {
  runApp(const HindviApp());
}

class HindviApp extends StatelessWidget {
  const HindviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'हिंदवी स्वराज्य',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedReportYear = DateTime.now().year;

  Widget dashboardButton({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/hindvi_logo.png',
              width: 34,
              height: 34,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Text('हिंदवी स्वराज्य'),
          ],
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 10),

            Image.asset(
              'assets/images/hindvi_logo.png',
              width: 100,
              height: 100,
              fit: BoxFit.contain,
            ),

            // ==================================================
            // APP TITLE
            // ==================================================
            const Text(
              'हिंदवी स्वराज्य',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 5),

            const Text(
              'मंडळ व्यवस्थापन प्रणाली',
              style: TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 25),

            // ==================================================
            // वर्गणी
            // ==================================================
            dashboardButton(
              context: context,
              title: 'वर्गणी',
              icon: Icons.account_balance_wallet,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VarganiScreen(),
                  ),
                );
              },
            ),

            // ==================================================
            // प्रसाद देणगी
            // ==================================================
            dashboardButton(
              context: context,
              title: 'प्रसाद देणगी',
              icon: Icons.volunteer_activism,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrasadDenganiScreen(),
                  ),
                );
              },
            ),

            // ==================================================
            // प्रसाद साहित्य
            // ==================================================
            dashboardButton(
              context: context,
              title: 'प्रसाद साहित्य',
              icon: Icons.inventory_2,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrasadDenganiScreen(),
                  ),
                );
              },
            ),

            // ==================================================
            // मागील वर्षाचा खर्च
            // ==================================================
            dashboardButton(
              context: context,
              title: 'मागील वर्षाचा खर्च',
              icon: Icons.receipt_long,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KharchScreen()),
                );
              },
            ),

            // ==================================================
            // महाप्रसाद बाजार
            // ==================================================
            dashboardButton(
              context: context,
              title: 'महाप्रसाद बाजार',
              icon: Icons.shopping_cart,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MahaprasadKharchScreen(),
                  ),
                );
              },
            ),

            dashboardButton(
              context: context,
              title: 'Database Backup & Restore',
              icon: Icons.storage,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DatabaseBackupRestoreScreen(),
                  ),
                );
              },
            ),

            // ==================================================
            // वार्षिक PDF Report
            // ==================================================
            Card(
              margin: const EdgeInsets.only(bottom: 15),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'अहवालाचे वर्ष',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DropdownButton<int>(
                      value: _selectedReportYear,
                      items: List.generate(11, (index) {
                        final year = DateTime.now().year - 5 + index;
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        );
                      }),
                      onChanged: (year) {
                        if (year == null) return;
                        setState(() {
                          _selectedReportYear = year;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            dashboardButton(
              context: context,
              title: 'वार्षिक PDF Report',
              icon: Icons.picture_as_pdf,
              onTap: () async {
                try {
                  await AnnualReportPdf.generateAndPrint(
                    year: _selectedReportYear,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF तयार करताना error आला: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
