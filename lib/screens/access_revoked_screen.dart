// ignore_for_file: avoid_print
import 'package:flutter/material.dart';

const Color _warmPaper = Color(0xFFFFFAF3);
const Color _ink = Color(0xFF25231F);

class AccessRevokedScreen extends StatelessWidget {
  final String? deviceId;
  final String? reason;

  const AccessRevokedScreen({
    super.key,
    this.deviceId,
    this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Strict block - cannot pop or go back to financial screens
      child: Scaffold(
        backgroundColor: _warmPaper,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Red Alert Icon Circle
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFEF9A9A), width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.block_rounded,
                        size: 54,
                        color: Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Required English Headline
                  const Text(
                    'Access Revoked. Contact Developer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.red,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Marathi Headline
                  const Text(
                    'प्रवेश रद्द केला आहे. कृपया डेव्हलपरशी संपर्क साधा.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Information Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFFFCDD2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'डिव्हाइस ब्लॉक सुरक्षा (Revoke Security)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          const Text(
                            '• Developer Management App द्वारे हे डिव्हाइस रद्द (REVOKED) केले आहे.\n'
                            '• चालू सत्र व Keep Me Logged In पूर्णपणे नष्ट करण्यात आले आहे.\n'
                            '• जुना स्थानिक डेटा किंवा जुने सत्र वापरून ॲप उघडता येणार नाही.\n'
                            '• आर्थिक माहिती (वर्गणी, खर्च, PDF) पूर्णपणे ब्लॉक करण्यात आली आहे.',
                            style: TextStyle(fontSize: 13, height: 1.5, color: _ink),
                          ),
                          if (deviceId != null && deviceId!.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'तुमचा डिव्हाइस आयडी (Device ID):',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF756A5D)),
                                  ),
                                  const SizedBox(height: 2),
                                  SelectableText(
                                    deviceId!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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
