// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import '../services/security_enforcement_service.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

class NoInternetScreen extends StatefulWidget {
  final Future<void> Function()? onRetry;

  const NoInternetScreen({super.key, this.onRetry});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _isRetrying = false;
  String? _retryMessage;

  Future<void> _handleRetry() async {
    setState(() {
      _isRetrying = true;
      _retryMessage = null;
    });

    try {
      if (widget.onRetry != null) {
        await widget.onRetry!();
      } else {
        final isConnected =
            await SecurityEnforcementService.instance.checkInternetConnectivity();
        if (!mounted) return;
        if (!isConnected) {
          setState(() {
            _retryMessage = 'अद्याप इंटरनेट बंद आहे. कृपया वाय-फाय किंवा मोबाईल डेटा सुरू करा.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _retryMessage = 'त्रुटी: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back navigation while offline
      child: Scaffold(
        backgroundColor: _warmPaper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Saffron Icon Circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E1),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFFCC99), width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.wifi_off_rounded,
                        size: 54,
                        color: _deepSaffron,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Required English Headline
                  const Text(
                    'Internet connection required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Required English Subtitle
                  const Text(
                    'Please turn on Internet to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _deepSaffron,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Marathi Translation & Explanation Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFF0E6D9)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.security, size: 18, color: _deepSaffron),
                              SizedBox(width: 8),
                              Text(
                                'सुरक्षा नियम: अनिवार्य इंटरनेट प्रवेश',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'हिंदवी ॲपच्या सुरक्षेसाठी आणि अधिकृततेसाठी इंटरनेट कनेक्शन आवश्यक आहे.\n\n'
                            'इंटरनेट बंद असताना लॉगिन, डॅशबोर्ड, वर्गणी, प्रसाद, खर्च, शोध किंवा PDF अहवाल उघडता येणार नाही.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_retryMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _retryMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: Colors.red.shade900),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Retry Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isRetrying ? null : _handleRetry,
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh, color: Colors.white),
                      label: Text(
                        _isRetrying
                            ? 'तपासत आहे...'
                            : 'पुन्हा प्रयत्न करा (Retry)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _saffron,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
