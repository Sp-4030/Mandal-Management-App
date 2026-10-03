import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/khajani_user.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/signaling_service.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

class KhajaniLoginScreen extends StatefulWidget {
  final bool? isFirstSetupOverride;
  final List<KhajaniUser>? initialKhajanis;

  const KhajaniLoginScreen({
    super.key,
    this.isFirstSetupOverride,
    this.initialKhajanis,
  });

  @override
  State<KhajaniLoginScreen> createState() => _KhajaniLoginScreenState();
}

class _KhajaniLoginScreenState extends State<KhajaniLoginScreen> {
  final AuthService _authService = AuthService.instance;
  final DeviceService _deviceService = DeviceService.instance;
  final SignalingService _signalingService = SignalingService.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _isCheckingUsers = true;
  bool _isFirstSetup = false;
  bool _isRequestMode = false;
  bool _keepLoggedIn = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  String _deviceId = '';
  bool _isDeviceRevoked = false;

  List<KhajaniUser> _existingKhajanis = [];
  StreamSubscription? _signalingSub;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
    _initDeviceAndSignaling();
  }

  @override
  void dispose() {
    _signalingSub?.cancel();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _initDeviceAndSignaling() async {
    try {
      final devId = await _deviceService.getDeviceId();
      final isRevoked = await _deviceService.isCurrentDeviceRevoked();
      if (mounted) {
        setState(() {
          _deviceId = devId;
          _isDeviceRevoked = isRevoked;
        });
      }

      // Try connecting in the background (does not block local login)
      unawaited(_signalingService.connect(timeout: const Duration(seconds: 3)));

      _signalingSub = _signalingService.onMessage.listen((msg) {
        final type = msg['type'] as String?;
        final targetDev = msg['deviceId'] as String?;

        if (targetDev == _deviceId) {
          if (type == 'device_approval_result') {
            final status = msg['status'] as String? ?? 'APPROVED';
            if (status == 'APPROVED') {
              if (mounted) {
                setState(() {
                  _errorMessage = null;
                  _isDeviceRevoked = false;
                  _successMessage =
                      'अभिनंदन! आपले खाते व डिव्हाइस मंजूर झाले आहे. कृपया आता लॉगिन करा.';
                });
              }
            } else if (status == 'REJECTED') {
              if (mounted) {
                setState(() {
                  _errorMessage = 'आपली खाते विनंती नाकारण्यात (Rejected) आली आहे.';
                });
              }
            }
          } else if (type == 'device_revoked') {
            if (mounted) {
              setState(() {
                _isDeviceRevoked = true;
                _errorMessage =
                    'हे डिव्हाइस रद्द (REVOKED) केले आहे. ॲप वापरता येणार नाही.';
              });
            }
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _checkInitialState() async {
    if (widget.isFirstSetupOverride != null) {
      _isFirstSetup = widget.isFirstSetupOverride!;
      _existingKhajanis = widget.initialKhajanis ?? [];
      setState(() => _isCheckingUsers = false);
      return;
    }

    setState(() => _isCheckingUsers = true);
    try {
      final hasKhajanis = await _authService.hasAnyKhajanis();
      _isFirstSetup = !hasKhajanis;

      if (!_isFirstSetup) {
        try {
          final allUsers = await _authService.getAllKhajanis().timeout(
            const Duration(milliseconds: 600),
            onTimeout: () => [],
          );
          _existingKhajanis =
              allUsers
                  .where((u) => !u.isDeveloper && u.isActive && u.isApproved)
                  .toList();
        } catch (_) {
          _existingKhajanis = [];
        }
      }
    } catch (_) {
      _isFirstSetup = false;
    } finally {
      if (mounted) {
        setState(() => _isCheckingUsers = false);
      }
    }
  }

  Future<void> _handleFirstSetup() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.toLowerCase() == AuthService.developerName.toLowerCase()) {
      if (password == AuthService.developerDefaultPassword) {
        setState(() {
          _isSubmitting = true;
          _errorMessage = null;
          _successMessage = null;
        });
        try {
          final devUser = await _authService.login(
            name: AuthService.developerName,
            password: password,
            keepLoggedIn: _keepLoggedIn,
          );
          if (!mounted) return;
          if (devUser != null) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
              (route) => false,
            );
            return;
          }
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _errorMessage = e
                .toString()
                .replaceAll('Exception: ', '')
                .replaceAll('StateError: ', '')
                .replaceAll('Bad state: ', '')
                .replaceAll('ArgumentError: ', '');
          });
          return;
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
      }
      setState(
        () => _errorMessage =
            "'${AuthService.developerName}' हे नाव राखीव (Reserved) आहे. कृपया दुसरे नाव वापरा किंवा Developer पासवर्डने लॉगिन करा.",
      );
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = 'पासवर्ड आणि खात्री पासवर्ड जुळत नाहीत.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.registerFirstKhajani(
        name: name,
        password: password,
        keepLoggedIn: _keepLoggedIn,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('प्रथम खजानी खाते यशस्वीरीत्या तयार झाले!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('StateError: ', '')
            .replaceAll('Bad state: ', '')
            .replaceAll('ArgumentError: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleNewUserRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.toLowerCase() == AuthService.developerName.toLowerCase()) {
      setState(
        () => _errorMessage =
            "'${AuthService.developerName}' हे नाव राखीव (Reserved) आहे. कृपया दुसरे नाव वापरा.",
      );
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = 'पासवर्ड आणि खात्री पासवर्ड जुळत नाहीत.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _authService.requestNewAccount(
        name: name,
        password: password,
      );

      if (!mounted) return;

      setState(() {
        _isRequestMode = false;
        _passwordController.clear();
        _confirmPasswordController.clear();
        _successMessage =
            'आपली खाते विनंती यशस्वीरीत्या पाठवली गेली आहे! (Status: PENDING)\nडिव्हाइस आयडी: $_deviceId\nDeveloper च्या मंजुरीनंतरच ॲपमध्ये प्रवेश मिळेल.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'खाते विनंती नोंदवली गेली आहे. Developer मंजुरीनंतरच लॉगिन करता येईल.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('StateError: ', '')
            .replaceAll('Bad state: ', '')
            .replaceAll('ArgumentError: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = await _authService.login(
        name: name,
        password: password,
        keepLoggedIn: _keepLoggedIn,
      );

      if (!mounted) return;

      if (user != null) {
        // Register client on signaling server if connected
        if (_signalingService.isConnected) {
          _signalingService.registerClient(
            role: user.role,
            deviceId: _deviceId,
            userId: user.userId,
            userName: user.name,
          );
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _errorMessage =
              'नाव किंवा पासवर्ड चुकीचा आहे. कृपया पुन्हा प्रयत्न करा.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final rawError = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('StateError: ', '')
          .replaceAll('Bad state: ', '')
          .replaceAll('ArgumentError: ', '');
      setState(() {
        _errorMessage = rawError;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _recheckStatus() async {
    setState(() => _isSubmitting = true);
    try {
      final isRevoked = await _deviceService.isCurrentDeviceRevoked();
      _isDeviceRevoked = isRevoked;

      // Also try reconnecting to server
      if (!_signalingService.isConnected) {
        await _signalingService.connect(timeout: const Duration(seconds: 3));
      }

      // Check if user is now approved in local DB
      final name = _nameController.text.trim();
      if (name.isNotEmpty) {
        final allUsers = await _authService.getAllKhajanis();
        final match = allUsers.where((u) => u.name.toLowerCase() == name.toLowerCase()).toList();
        if (match.isNotEmpty && match.first.isApproved && !isRevoked) {
          setState(() {
            _errorMessage = null;
            _successMessage = 'अभिनंदन! आपले खाते मंजूर झाले आहे. कृपया आता पासवर्ड टाकून लॉगिन करा.';
          });
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _signalingService.isConnected
                  ? 'सर्व्हर जोडला आहे. अद्याप Developer मंजुरी मिळालेली नाही.'
                  : 'सर्व्हर ऑफलाइन आहे. स्थानिक मंजुरी तपासली गेली.',
            ),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showServerConfigDialog() async {
    final currentUrl = await _signalingService.getServerUrl();
    final urlController = TextEditingController(text: currentUrl);
    bool isTesting = false;
    String? testResult;

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (sbContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Row(
                children: [
                  Icon(Icons.router, color: _saffron),
                  SizedBox(width: 10),
                  Text(
                    'PC सर्व्हर सेटिंग्ज',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'रिमोट मंजुरी, परवानग्या आणि सिंकसाठी PC Signaling Server पत्ता द्या:',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF756A5D)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'WebSocket URL',
                        hintText: 'ws://192.168.1.100:8080 किंवा wss://...',
                        prefixIcon: Icon(Icons.link, color: _deepSaffron),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (testResult != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: testResult!.contains('यशस्वी')
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: testResult!.contains('यशस्वी')
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFFB00020),
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
                              final ok = await _signalingService.connect(
                                timeout: const Duration(seconds: 4),
                                overrideUrl: urlController.text.trim(),
                              );
                              setDialogState(() {
                                isTesting = false;
                                testResult = ok
                                    ? 'कनेक्शन यशस्वी! (Connected)'
                                    : 'कनेक्शन अयशस्वी. PC चालू आहे आणि URL बरोबर आहे का ते तपासा.';
                              });
                            },
                      icon: isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('कनेक्शन तपासा (Test)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('रद्द करा'),
                ),
                FilledButton(
                  onPressed: () async {
                    final newUrl = urlController.text.trim();
                    if (newUrl.isNotEmpty) {
                      await _signalingService.setServerUrl(newUrl);
                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('सर्व्हर पत्ता जतन केला!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() {});
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: _saffron),
                  child: const Text('जतन करा (Save)'),
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
    if (_isCheckingUsers) {
      return const Scaffold(
        backgroundColor: _warmPaper,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: _warmPaper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: Color(0xFFF0E6D9)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Server connection pill & Settings button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ValueListenableBuilder<SignalingConnectionState>(
                              valueListenable: _signalingService.connectionState,
                              builder: (context, state, _) {
                                final isConn =
                                    state == SignalingConnectionState.connected;
                                return InkWell(
                                  onTap: _showServerConfigDialog,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isConn
                                          ? const Color(0xFFE8F5E9)
                                          : const Color(0xFFFFEBEE),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isConn
                                            ? const Color(0xFFA5D6A7)
                                            : const Color(0xFFEF9A9A),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: isConn
                                                ? Colors.green
                                                : Colors.grey,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isConn
                                              ? 'Server is ON 🟢'
                                              : 'Server is OFF 🔴',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: isConn
                                                ? const Color(0xFF1B5E20)
                                                : const Color(0xFFC62828),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.settings_ethernet,
                                size: 20,
                                color: Color(0xFF756A5D),
                              ),
                              tooltip: 'PC सर्व्हर सेटिंग्ज',
                              onPressed: _showServerConfigDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // App Logo & Header
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0E1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Image.asset(
                              'assets/images/hindvi_logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'हिंदवी स्वराज्य',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRequestMode
                              ? 'नवीन खाते विनंती (New User Request)'
                              : (_isFirstSetup
                                  ? 'प्रथम खजानी नोंदणी (नवीन सुरूवात)'
                                  : 'खजानी लॉगिन'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _deepSaffron,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isRequestMode
                              ? 'मंडळ ॲप वापरण्यासाठी आपले नाव व पासवर्ड देऊन विनंती तयार करा. Developer च्या मंजुरीनंतरच ॲपमध्ये प्रवेश मिळेल.'
                              : (_isFirstSetup
                                  ? 'मंडळासाठी पहिला मुख्य खजानी खाते तयार करा. हा वापरकर्ता "चालू खजानी" (LATEST_KHAJANI) बनेल.'
                                  : 'मंडळ व्यवस्थापनात प्रवेश करण्यासाठी आपले नाव व पासवर्ड प्रविष्ट करा.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF756A5D),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Device ID badge
                        if (_deviceId.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F6F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFEBE0D2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.phone_android,
                                  size: 16,
                                  color: _deepSaffron,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'डिव्हाइस आयडी: $_deviceId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _ink,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _deviceId),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('डिव्हाइस आयडी कॉपी केला!'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: const Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: Color(0xFF8E8276),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 14),

                        // Revoked Device Banner
                        if (_isDeviceRevoked) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFECEC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFFCDCD)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.block, color: Colors.red, size: 24),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'हे डिव्हाइस रद्द (REVOKED) केले आहे. ॲप वापरता येणार नाही. कृपया Developer शी संपर्क साधा.',
                                    style: TextStyle(
                                      color: Color(0xFFB00020),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Success Banner
                        if (_successMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFA5D6A7),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _successMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFF1B5E20),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Error Banner
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _errorMessage!.contains(
                                        'Developer approval pending',
                                      )
                                  ? const Color(0xFFFFF8E1)
                                  : const Color(0xFFFFECEC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _errorMessage!.contains(
                                          'Developer approval pending',
                                        )
                                    ? const Color(0xFFFFE082)
                                    : const Color(0xFFFFCDCD),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      _errorMessage!.contains(
                                                'Developer approval pending',
                                              )
                                          ? Icons.pending_actions
                                          : Icons.error_outline,
                                      color: _errorMessage!.contains(
                                                'Developer approval pending',
                                              )
                                          ? Colors.amber.shade900
                                          : Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _errorMessage!,
                                            style: TextStyle(
                                              color: _errorMessage!.contains(
                                                        'Developer approval pending',
                                                      )
                                                  ? const Color(0xFFB78103)
                                                  : const Color(0xFFB00020),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (_errorMessage!.contains(
                                            'Developer approval pending',
                                          )) ...[
                                            const SizedBox(height: 4),
                                            const Text(
                                              'आपली विनंती प्रलंबित आहे. Developer ने मंजूर केल्यावरच आपण डॅशबोर्ड पाहू शकता.',
                                              style: TextStyle(
                                                color: Color(0xFF756A5D),
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (_errorMessage!.contains(
                                  'Developer approval pending',
                                )) ...[
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed:
                                        _isSubmitting ? null : _recheckStatus,
                                    icon: const Icon(
                                      Icons.refresh,
                                      size: 16,
                                      color: Color(0xFFB78103),
                                    ),
                                    label: const Text(
                                      'मंजुरी स्थिती तपासा (Check Status)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFB78103),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFFFFB300),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Quick selection chips if existing approved khajanis exist in login mode
                        if (!_isRequestMode &&
                            !_isFirstSetup &&
                            _existingKhajanis.isNotEmpty) ...[
                          const Text(
                            'नोंदणीकृत खजानी निवडा किंवा नाव टाईप करा:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF756A5D),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children:
                                _existingKhajanis.map((u) {
                                  final isSelected =
                                      _nameController.text
                                          .trim()
                                          .toLowerCase() ==
                                      u.name.trim().toLowerCase();
                                  return ChoiceChip(
                                    label: Text(
                                      '${u.name} (${u.isLatestKhajani ? "चालू" : "माजी"})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                        color: isSelected ? Colors.white : _ink,
                                      ),
                                    ),
                                    selected: isSelected,
                                    selectedColor: _saffron,
                                    backgroundColor: const Color(0xFFFFF0E1),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _nameController.text = u.name;
                                          _errorMessage = null;
                                        });
                                      }
                                    },
                                  );
                                }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Name Field
                        TextFormField(
                          controller: _nameController,
                          enabled: !_isDeviceRevoked,
                          decoration: InputDecoration(
                            labelText: _isRequestMode
                                ? 'आपले नाव'
                                : 'खजानीचे नाव',
                            hintText: 'उदा. सागर पाटील किंवा Developer',
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              color: _deepSaffron,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'कृपया नाव प्रविष्ट करा';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          enabled: !_isDeviceRevoked,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'पासवर्ड',
                            hintText: 'पासवर्ड टाका',
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: _deepSaffron,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFF756A5D),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'कृपया पासवर्ड टाका';
                            }
                            if ((_isFirstSetup || _isRequestMode) &&
                                value.length < 4) {
                              return 'पासवर्ड किमान ४ अक्षरांचा असावा';
                            }
                            return null;
                          },
                        ),

                        // Confirm Password Field (On First Setup or New Request)
                        if (_isFirstSetup || _isRequestMode) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPasswordController,
                            enabled: !_isDeviceRevoked,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'पासवर्ड पुन्हा टाका (Confirm)',
                              hintText: 'पासवर्डची खात्री करा',
                              prefixIcon: const Icon(
                                Icons.lock_reset,
                                color: _deepSaffron,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                color: const Color(0xFF756A5D),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'कृपया पासवर्ड पुन्हा टाका';
                              }
                              return null;
                            },
                          ),
                        ],

                        // Keep me logged in checkbox (Only in Login or First Setup)
                        if (!_isRequestMode) ...[
                          const SizedBox(height: 10),
                          Theme(
                            data: Theme.of(context).copyWith(
                              unselectedWidgetColor: const Color(0xFF8E8276),
                            ),
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'लॉगिन कायम ठेवा (Keep me logged in)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                              subtitle: const Text(
                                'चालू ठेवल्यास पुढच्या वेळी थेट डॅशबोर्ड उघडेल',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF756A5D),
                                ),
                              ),
                              value: _keepLoggedIn,
                              activeColor: _saffron,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: _isDeviceRevoked
                                  ? null
                                  : (val) {
                                      setState(() {
                                        _keepLoggedIn = val ?? true;
                                      });
                                    },
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Submit Button
                        if (_isSubmitting)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(color: _saffron),
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _isDeviceRevoked
                                ? null
                                : (_isRequestMode
                                    ? _handleNewUserRequest
                                    : (_isFirstSetup
                                        ? _handleFirstSetup
                                        : _handleLogin)),
                            icon: Icon(
                              _isRequestMode
                                  ? Icons.send_rounded
                                  : (_isFirstSetup
                                      ? Icons.person_add
                                      : Icons.login),
                            ),
                            label: Text(
                              _isRequestMode
                                  ? 'खाते विनंती पाठवा (Submit Request)'
                                  : (_isFirstSetup
                                      ? 'पहिला खजानी तयार करा'
                                      : 'लॉगिन करा'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _saffron,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),

                        const SizedBox(height: 12),

                        // Navigation buttons between Request Mode / Login / Developer Login / First Setup
                        if (_isRequestMode) ...[
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isRequestMode = false;
                                _errorMessage = null;
                                _passwordController.clear();
                                _confirmPasswordController.clear();
                              });
                            },
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text(
                              'आधीच खाते आहे? लॉगिन करा',
                              style: TextStyle(
                                color: _deepSaffron,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ] else if (_isFirstSetup) ...[
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isFirstSetup = false;
                                _errorMessage = null;
                                _nameController.text =
                                    AuthService.developerName;
                                _passwordController.clear();
                              });
                            },
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 18,
                              color: _deepSaffron,
                            ),
                            label: const Text(
                              'Developer / नोंदणीकृत लॉगिन',
                              style: TextStyle(
                                color: _deepSaffron,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ] else ...[
                          // Normal Login Mode Actions
                          OutlinedButton.icon(
                            onPressed: _isDeviceRevoked
                                ? null
                                : () {
                                    setState(() {
                                      _isRequestMode = true;
                                      _errorMessage = null;
                                      _successMessage = null;
                                      _nameController.clear();
                                      _passwordController.clear();
                                      _confirmPasswordController.clear();
                                    });
                                  },
                            icon: const Icon(Icons.person_add_alt_1, size: 18),
                            label: const Text(
                              'नवीन वापरकर्ता? खात्याची विनंती करा (New Request)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _deepSaffron,
                              side: const BorderSide(color: _deepSaffron),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (widget.isFirstSetupOverride == null)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isFirstSetup = true;
                                  _errorMessage = null;
                                  _nameController.clear();
                                  _passwordController.clear();
                                  _confirmPasswordController.clear();
                                });
                              },
                              child: const Text(
                                'नवीन खजानी खाते तयार करा (First Setup)',
                                style: TextStyle(
                                  color: _deepSaffron,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],

                        const SizedBox(height: 12),
                        const Center(
                          child: Text(
                            '१००% ऑफलाइन आणि सुरक्षित • local encryption',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9E9283),
                            ),
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
