// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import '../models/developer_user.dart';
import '../services/developer_auth_service.dart';
import '../services/developer_signaling_service.dart';
import 'developer_dashboard_screen.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

class DeveloperLoginScreen extends StatefulWidget {
  final bool autoConnect;
  const DeveloperLoginScreen({super.key, this.autoConnect = true});

  @override
  State<DeveloperLoginScreen> createState() => _DeveloperLoginScreenState();
}

class _DeveloperLoginScreenState extends State<DeveloperLoginScreen> {
  final TextEditingController _nameController =
      TextEditingController(text: DeveloperUser.developerName);
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _keepLoggedIn = true;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Try background connection to signaling server if enabled
    if (widget.autoConnect) {
      DeveloperSignalingService.instance.connect();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await DeveloperAuthService.instance.login(
        name: name,
        password: password,
        keepLoggedIn: _keepLoggedIn,
      );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DeveloperDashboardScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage = 'पासवर्ड चुकीचा आहे. कृपया योग्य Developer पासवर्ड प्रविष्ट करा.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('ArgumentError: ', '').replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showServerSettingsDialog() {
    final signaling = DeveloperSignalingService.instance;
    final urlController = TextEditingController(text: signaling.serverUrl);
    bool isTesting = false;
    String? testResult;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.router, color: _saffron),
                  SizedBox(width: 10),
                  Text('PC Server पत्ता', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'रिमोट Developer व्यवस्थापनासाठी WebSocket पत्ता सेट करा:',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF756A5D)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'WebSocket URL',
                        hintText: 'wss://amino-dropkick-resample.ngrok-free.dev',
                        prefixIcon: Icon(Icons.link, color: _deepSaffron),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (testResult != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: testResult!.contains('यशस्वी') ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: testResult!.contains('यशस्वी') ? Colors.green.shade900 : Colors.red.shade900,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isTesting
                          ? null
                          : () async {
                              setDialogState(() {
                                isTesting = true;
                                testResult = 'तपासत आहे...';
                              });
                              final ok = await signaling.connect(
                                timeout: const Duration(seconds: 4),
                                overrideUrl: urlController.text.trim(),
                              );
                              setDialogState(() {
                                isTesting = false;
                                testResult = ok ? 'जोडणी यशस्वी! (Connected)' : 'जोडणी अयशस्वी. PC चालू आहे का ते तपासा.';
                              });
                            },
                      icon: isTesting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('जोडणी तपासा'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('रद्द करा'),
                ),
                FilledButton(
                  onPressed: () async {
                    final newUrl = urlController.text.trim();
                    if (newUrl.isNotEmpty) {
                      await signaling.setServerUrl(newUrl);
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() {});
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: _saffron),
                  child: const Text('जतन करा'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmPaper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: Color(0xFFF0E6D9)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Server connection status pill
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ValueListenableBuilder<DevConnectionState>(
                              valueListenable: DeveloperSignalingService.instance.connectionState,
                              builder: (context, state, _) {
                                final isOnline = state == DevConnectionState.connected;
                                return InkWell(
                                  onTap: _showServerSettingsDialog,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isOnline ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isOnline ? const Color(0xFFA5D6A7) : const Color(0xFFEF9A9A),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isOnline ? Icons.check_circle : Icons.error_outline,
                                          size: 14,
                                          color: isOnline ? Colors.green : Colors.red,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isOnline ? 'Server ON 🟢' : 'Server OFF 🔴',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isOnline ? Colors.green.shade900 : Colors.red.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined, size: 20, color: _deepSaffron),
                              tooltip: 'सर्व्हर सेटिंग्ज',
                              onPressed: _showServerSettingsDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Logo & Header
                        Center(
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0E1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.admin_panel_settings, size: 40, color: _deepSaffron),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'हिंदवी स्वराज्य',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Developer Management App',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _deepSaffron,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'वापरकर्ता, डिव्हाइस, परवानग्या व चालू खजानी प्रशासन',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF756A5D)),
                        ),
                        const SizedBox(height: 22),

                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFECEC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFFCDCD)),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Color(0xFFB00020), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Developer Name Field
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Developer Name',
                            prefixIcon: Icon(Icons.shield_outlined, color: _deepSaffron),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'नाव आवश्यक आहे.';
                            if (val.trim().toLowerCase() != DeveloperUser.developerName.toLowerCase()) {
                              return 'केवळ Developer खात्यालाच या ॲपमध्ये प्रवेश आहे.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Developer Password',
                            prefixIcon: const Icon(Icons.lock_outline, color: _deepSaffron),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: const Color(0xFF756A5D),
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'पासवर्ड आवश्यक आहे.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),

                        // Keep Me Logged In
                        Row(
                          children: [
                            Checkbox(
                              value: _keepLoggedIn,
                              activeColor: _saffron,
                              onChanged: (val) => setState(() => _keepLoggedIn = val ?? true),
                            ),
                            const Expanded(
                              child: Text(
                                'लॉगिन कायम ठेवा (Keep me logged in)',
                                style: TextStyle(fontSize: 13, color: _ink),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Login Button
                        FilledButton(
                          onPressed: _isSubmitting ? null : _handleLogin,
                          style: FilledButton.styleFrom(
                            backgroundColor: _saffron,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                )
                              : const Text(
                                  'Developer लॉगिन',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
