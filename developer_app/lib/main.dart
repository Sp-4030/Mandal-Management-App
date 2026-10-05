// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'screens/developer_login_screen.dart';
import 'screens/developer_dashboard_screen.dart';
import 'services/developer_auth_service.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeveloperAuthService.instance.initSession();
  runApp(const DeveloperApp());
}

class DeveloperApp extends StatelessWidget {
  final bool autoConnect;
  const DeveloperApp({super.key, this.autoConnect = true});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = DeveloperAuthService.instance.isLoggedIn;

    return MaterialApp(
      title: 'Hindvi Developer Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: _saffron,
          primary: _saffron,
          secondary: _deepSaffron,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _warmPaper,
        appBarTheme: const AppBarTheme(
          backgroundColor: _warmPaper,
          foregroundColor: _ink,
          elevation: 0,
          centerTitle: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _saffron,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: isLoggedIn
          ? const DeveloperDashboardScreen()
          : DeveloperLoginScreen(autoConnect: autoConnect),
    );
  }
}
