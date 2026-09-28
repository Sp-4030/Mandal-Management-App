import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../migration/migration_models.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    try {
      final pairingInfo = MigrationPairingInfo.fromJsonString(rawValue);
      if (pairingInfo.isExpired) {
        _showErrorSnackBar('हा QR कोड कालबाह्य (Expired) झाला आहे. जुन्या फोनवर नवीन QR तयार करा.');
        return;
      }

      setState(() => _isProcessing = true);
      _controller.stop();
      Navigator.pop(context, pairingInfo);
    } catch (_) {
      _showErrorSnackBar('अवैध QR कोड. कृपया जुन्या फोनवरील अचूक QR कोड स्कॅन करा.');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR कोड स्कॅन करा'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.amber);
                  case TorchState.off:
                  default:
                    return const Icon(Icons.flash_off);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF7A00), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(190),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'जुन्या फोनवर दाखवलेला QR कोड या चौकटीत धरा.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
