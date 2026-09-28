import 'package:flutter/material.dart';

import 'screens/vargani_screen.dart';
import 'screens/prasad_dengani_screen.dart';
import 'screens/kharch_screen.dart';
import 'screens/mahaprasad_kharch_screen.dart';
import 'screens/database_backup_restore_screen.dart';
import 'pdf/annual_report_pdf.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

final ThemeData _hindviTheme = ThemeData(
  useMaterial3: true,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: _saffron,
        brightness: Brightness.light,
      ).copyWith(
        primary: _saffron,
        onPrimary: Colors.white,
        secondary: _deepSaffron,
        surface: Colors.white,
        onSurface: _ink,
      ),
  fontFamily: 'HindviDevanagari',
  scaffoldBackgroundColor: _warmPaper,
  appBarTheme: const AppBarTheme(
    backgroundColor: _warmPaper,
    foregroundColor: _ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    titleTextStyle: TextStyle(
      color: _ink,
      fontSize: 19,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 1,
    margin: EdgeInsets.zero,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFF0E6D9)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE6D8C7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE6D8C7)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _saffron, width: 1.6),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(48, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: _saffron,
    foregroundColor: Colors.white,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

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
      theme: _hindviTheme,
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
  Widget dashboardButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    var pressed = false;
    return StatefulBuilder(
      builder: (context, setTileState) => AnimatedScale(
        scale: pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 110),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - value)),
              child: child,
            ),
          ),
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onHighlightChanged: (value) {
                if (pressed != value) setTileState(() => pressed = value);
              },
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0E1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, size: 27, color: _deepSaffron),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF756A5D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: _deepSaffron,
                    ),
                  ],
                ),
              ),
            ),
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_saffron, _deepSaffron],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26A74200),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/hindvi_logo.png',
                        width: 76,
                        height: 76,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'हिंदवी स्वराज्य',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'मंडळ व्यवस्थापन प्रणाली',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFFFFE6CF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'व्यवस्थापन विभाग',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800, color: _ink),
                  ),
                ),
                const SizedBox(height: 12),

                // ==================================================
                // वर्गणी
                // ==================================================
                dashboardButton(
                  context: context,
                  title: 'वर्गणी',
                  subtitle: 'वर्गणीच्या जमा नोंदी आणि शिल्लक',
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
                  subtitle: 'देणगी आणि आरती वर्गणी व्यवस्थापन',
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
                  subtitle: 'साहित्य देणगीच्या नोंदी',
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
                  subtitle: 'वस्तू, खरेदीदार आणि एकूण खर्च',
                  icon: Icons.receipt_long,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const KharchScreen(),
                      ),
                    );
                  },
                ),

                // ==================================================
                // महाप्रसाद बाजार
                // ==================================================
                dashboardButton(
                  context: context,
                  title: 'महाप्रसाद बाजार',
                  subtitle: 'बाजारातील वस्तू आणि खर्च',
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
                  title: 'बॅकअप आणि पुनर्स्थापना',
                  subtitle: 'डेटाबेसची सुरक्षित प्रत तयार किंवा परत आणा',
                  icon: Icons.storage,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const DatabaseBackupRestoreScreen(),
                      ),
                    );
                  },
                ),

                dashboardButton(
                  context: context,
                  title: 'वार्षिक अहवाल',
                  subtitle: 'PDF तयार करा किंवा पूर्वावलोकन पाहा',
                  icon: Icons.picture_as_pdf,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AnnualReportScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnnualReportScreen extends StatefulWidget {
  const AnnualReportScreen({super.key});

  @override
  State<AnnualReportScreen> createState() => _AnnualReportScreenState();
}

class _AnnualReportScreenState extends State<AnnualReportScreen> {
  int _selectedYear = DateTime.now().year;
  bool _isBusy = false;

  Future<void> _openReport({required bool preview}) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (preview) {
        await AnnualReportPdf.preview(year: _selectedYear, context: context);
      } else {
        await AnnualReportPdf.generateAndPrint(year: _selectedYear);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF तयार करताना त्रुटी आली: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('वार्षिक अहवाल')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0E1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: _deepSaffron,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'वार्षिक अहवाल',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'अहवालासाठी वर्ष निवडा',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF756A5D)),
                    ),
                    const SizedBox(height: 22),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'वर्ष',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                      items: List.generate(11, (index) {
                        final year = DateTime.now().year - 5 + index;
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        );
                      }),
                      onChanged: _isBusy
                          ? null
                          : (year) {
                              if (year != null) {
                                setState(() => _selectedYear = year);
                              }
                            },
                    ),
                    const SizedBox(height: 22),
                    if (_isBusy)
                      const Center(child: CircularProgressIndicator())
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final createButton = FilledButton.icon(
                            onPressed: () => _openReport(preview: false),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF तयार करा'),
                          );
                          final previewButton = OutlinedButton.icon(
                            onPressed: () => _openReport(preview: true),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('PDF Preview'),
                          );
                          if (constraints.maxWidth < 520) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                createButton,
                                const SizedBox(height: 10),
                                previewButton,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: createButton),
                              const SizedBox(width: 12),
                              Expanded(child: previewButton),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
