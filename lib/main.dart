import 'package:flutter/material.dart';

import 'database/database_helper.dart';
import 'pdf/annual_report_pdf.dart';
import 'screens/app_update_screen.dart';
import 'screens/kharch_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mahaprasad_kharch_screen.dart';
import 'screens/prasad_dengani_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vargani_screen.dart';
import 'services/auth_service.dart';
import 'services/signaling_service.dart';
import 'services/update_service.dart';

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
  final bool checkUpdateOnStartup;
  final Widget? initialHome;

  const HindviApp({
    super.key,
    this.checkUpdateOnStartup = true,
    this.initialHome,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'हिंदवी स्वराज्य',
      theme: _hindviTheme,
      home: initialHome ??
          AuthGateScreen(checkUpdateOnStartup: checkUpdateOnStartup),
    );
  }
}

class AuthGateScreen extends StatefulWidget {
  final bool checkUpdateOnStartup;

  const AuthGateScreen({
    super.key,
    this.checkUpdateOnStartup = true,
  });

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  late Future<void> _initSessionFuture;

  @override
  void initState() {
    super.initState();
    if (AuthService.instance.isLoggedIn) {
      _initSessionFuture = Future.value();
    } else {
      _initSessionFuture = AuthService.instance.initSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.instance.isLoggedIn) {
      return DashboardScreen(
        checkUpdateOnStartup: widget.checkUpdateOnStartup,
      );
    }

    return FutureBuilder<void>(
      future: _initSessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (AuthService.instance.isLoggedIn) {
            return DashboardScreen(
              checkUpdateOnStartup: widget.checkUpdateOnStartup,
            );
          } else {
            return const KhajaniLoginScreen();
          }
        }
        return const Scaffold(
          backgroundColor: _warmPaper,
          body: SizedBox.shrink(),
        );
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final bool checkUpdateOnStartup;

  const DashboardScreen({
    super.key,
    this.checkUpdateOnStartup = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DatabaseHelper.instance.expireMigrationRecoveryIfNeeded();
    if (widget.checkUpdateOnStartup) {
      _checkStartupUpdate();
    }
  }

  Future<void> _checkStartupUpdate() async {
    try {
      final updateService = UpdateService();
      final result = await updateService.checkForUpdate();
      if (!mounted) return;

      if (result.status == UpdateCheckStatus.updateAvailable &&
          result.updateInfo != null) {
        // Mandatory blocking update screen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => AppUpdateScreen(
              isMandatory: true,
              initialCheckResult: result,
            ),
          ),
          (route) => false,
        );
      }
    } catch (_) {
      // Offline-first: if internet unavailable or check fails, do NOT block
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Text('लॉगआउट पुष्टी'),
          content: const Text(
            'तुम्हाला खरोखर खात्यातून लॉगआउट करायचे आहे का?\n\n'
            'लॉगआउट केल्यावर पुन्हा नाव व पासवर्ड टाकून लॉगिन करावे लागेल.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('लॉगआउट करा'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await AuthService.instance.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const KhajaniLoginScreen(),
      ),
      (route) => false,
    );
  }

  void _showServerStatusDialog() {
    final signaling = SignalingService.instance;
    final isOnline = signaling.isConnected;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.computer, color: isOnline ? Colors.green : Colors.red),
              const SizedBox(width: 8),
              Text(
                isOnline ? 'Server is ON 🟢' : 'Server is OFF 🔴',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOnline
                    ? 'PC Signaling Server शी यशस्वीरीत्या जोडले गेले आहे.'
                    : 'PC Signaling Server सध्या बंद किंवा ऑफलाइन आहे.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF756A5D)),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isOnline ? const Color(0xFFA5D6A7) : const Color(0xFFEF9A9A),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: Color(0xFF756A5D)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'URL: ${signaling.serverUrl}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('बंद करा'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: _saffron),
              child: const Text('सेटिंग्ज बदला'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DatabaseHelper.instance.expireMigrationRecoveryIfNeeded();
    }
  }

  Widget dashboardButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
                child: Icon(
                  icon,
                  size: 27,
                  color: _deepSaffron,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
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
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: _deepSaffron,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final currentUser = auth.currentUser;
    final isDeveloper = auth.isDeveloper;
    final isLatest = auth.isLatestKhajani;
    final isOld = auth.isOldKhajani;

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
        actions: [
          StreamBuilder<bool>(
            stream: SignalingService.instance.isConnectedStream,
            initialData: SignalingService.instance.isConnected,
            builder: (context, snapshot) {
              final isOnline = snapshot.data ?? false;
              return Tooltip(
                message: isOnline
                    ? 'Server is ON 🟢 (PC सर्व्हर जोडलेला आहे)'
                    : 'Server is OFF 🔴 (PC सर्व्हर बंद आहे)',
                child: InkWell(
                  onTap: _showServerStatusDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOnline
                            ? const Color(0xFFA5D6A7)
                            : const Color(0xFFEF9A9A),
                      ),
                    ),
                    child: Text(
                      isOnline ? 'Server is ON 🟢' : 'Server is OFF 🔴',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isOnline
                            ? const Color(0xFF1B5E20)
                            : const Color(0xFFC62828),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'सेटिंग्ज',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'लॉगआउट',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                // Top Mandal Banner
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
                      if (currentUser != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDeveloper
                                    ? Icons.shield
                                    : (isLatest
                                        ? Icons.verified
                                        : Icons.visibility_outlined),
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isDeveloper
                                    ? 'Developer (सर्वोच्च ॲडमिन)'
                                    : '${currentUser.name} (${currentUser.marathiRole})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Read-only notification banner for OLD_KHAJANI
                if (isOld && !auth.canModify) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFFB94D00),
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'आपण "माजी खजानी" म्हणून लॉग इन आहात. आपल्याला केवळ माहिती पाहण्याची व अहवाल PDF तयार करण्याची परवानगी आहे. नोंदी बदलणे बंद आहे.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8E410C),
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
                  subtitle: isOld
                      ? 'वर्गणीच्या जमा नोंदी आणि शिल्लक (फक्त वाचन)'
                      : 'वर्गणीच्या जमा नोंदी आणि शिल्लक',
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
                  subtitle: isOld
                      ? 'देणगी आणि आरती वर्गणी माहिती (फक्त वाचन)'
                      : 'देणगी आणि आरती वर्गणी व्यवस्थापन',
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
                  subtitle: isOld
                      ? 'साहित्य देणगीच्या नोंदी (फक्त वाचन)'
                      : 'साहित्य देणगीच्या नोंदी',
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
                  subtitle: isOld
                      ? 'वस्तू, खरेदीदार आणि एकूण खर्च (फक्त वाचन)'
                      : 'वस्तू, खरेदीदार आणि एकूण खर्च',
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
                  subtitle: isOld
                      ? 'बाजारातील वस्तू आणि खर्च (फक्त वाचन)'
                      : 'बाजारातील वस्तू आणि खर्च',
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
                  title: 'वार्षिक अहवाल',
                  subtitle: 'PDF तयार करा किंवा पूर्वावलोकन पाहा',
                  icon: Icons.picture_as_pdf,
                  onTap: () {
                    if (!auth.canPdf) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'वार्षिक अहवाल PDF पाहण्याची किंवा तयार करण्याची परवानगी नाही. कृपया Developer शी संपर्क साधा.',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
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
      appBar: AppBar(
        title: const Text('वार्षिक अहवाल'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF0E6D9)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0E1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf,
                          size: 38,
                          color: _deepSaffron,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'वार्षिक हिशोब अहवाल',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'निवडलेल्या वर्षाचा संपूर्ण जमा-खर्च आणि शिल्लक अहवाल तयार करा.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF756A5D),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Year selection dropdown
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'वर्ष निवडा: ',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<int>(
                            value: _selectedYear,
                            dropdownColor: Colors.white,
                            items: List.generate(10, (index) {
                              final year = DateTime.now().year - index + 1;
                              return DropdownMenuItem(
                                value: year,
                                child: Text(
                                  '$year',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedYear = val);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      if (_isBusy)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(color: _saffron),
                        )
                      else ...[
                        FilledButton.icon(
                          onPressed: () => _openReport(preview: true),
                          icon: const Icon(Icons.remove_red_eye_outlined),
                          label: const Text('पूर्वावलोकन पाहा (Preview)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _saffron,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openReport(preview: false),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('प्रिंट किंवा सेव्ह करा'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _deepSaffron,
                            side: const BorderSide(color: _deepSaffron),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
