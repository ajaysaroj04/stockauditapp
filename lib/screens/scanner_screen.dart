import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/vehicle_scan.dart';
import '../services/barcode_parser.dart';
import 'review_screen.dart';

/// Live camera scanner. Pops with `true` once a scan has been saved.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _busy = false;
  bool _showHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _armHint();
  }

  /// If nothing is read for a while, tell the user how to improve the scan.
  void _armHint() {
    _hintTimer?.cancel();
    _showHint = false;
    _hintTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _showHint = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    // A label can carry several barcodes; keep every distinct value in the frame.
    final values = <String>[];
    for (final b in capture.barcodes) {
      final v = (b.rawValue ?? b.displayValue)?.trim();
      if (v != null && v.isNotEmpty && !values.contains(v)) values.add(v);
    }
    if (values.isEmpty) {
      _toast('Barcode found but could not be read. Hold steady and try again.');
      return;
    }
    await _handle(values.join(' | '));
  }

  Future<void> _handle(String raw) async {
    _busy = true;
    _hintTimer?.cancel();
    HapticFeedback.mediumImpact();
    await _controller.stop();

    final parsed = BarcodeParser.parse(raw);
    final scan = VehicleScan(
      rawData: parsed.rawData,
      vin: parsed.vin,
      specCode: parsed.specCode,
      fuelType: parsed.fuelType,
      scannedAt: DateTime.now(),
    );

    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          scan: scan,
          barcodeSerial: parsed.serial.isEmpty ? null : parsed.serial,
          warning: parsed.isComplete
              ? null
              : parsed.serial.isNotEmpty
                  ? 'The barcode only holds the serial number (${parsed.serial}). '
                      'Tap PHOTOGRAPH LABEL to read the VIN, spec and fuel type.'
                  : 'Some fields could not be read automatically. Please check them.',
        ),
      ),
    );

    if (!mounted) return;
    if (saved == true) {
      Navigator.pop(context, true);
      return;
    }
    // Discarded: go back to scanning.
    _busy = false;
    _armHint();
    try {
      await _controller.start();
    } catch (_) {
      _toast('Could not restart the camera. Close and reopen the scanner.');
    }
  }

  Future<void> _manualEntry() async {
    if (_busy) return;
    _busy = true;
    await _controller.stop();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          scan: VehicleScan(
            rawData: '',
            vin: '',
            specCode: '',
            fuelType: '',
            scannedAt: DateTime.now(),
          ),
          warning: 'Manual entry: type the details from the label.',
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      Navigator.pop(context, true);
      return;
    }
    _busy = false;
    _armHint();
    try {
      await _controller.start();
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 16))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final unavailable = state.torchState == TorchState.unavailable;
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: 'Torch',
                iconSize: 28,
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                onPressed: unavailable ? null : () => _controller.toggleTorch(),
              );
            },
          ),
          IconButton(
            tooltip: 'Switch camera',
            iconSize: 28,
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => _CameraError(
              error: error,
              onManual: _manualEntry,
            ),
          ),
          // Aiming frame
          IgnorePointer(
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                height: 190,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _showHint
                          ? 'Not reading? Move closer or back a little, avoid glare, '
                              'turn on the torch, or enter the details manually.'
                          : 'Align the barcode inside the frame',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _manualEntry,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Enter manually'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onManual;
  const _CameraError({required this.error, required this.onManual});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final title = denied ? 'Camera permission needed' : 'Camera unavailable';
    final body = denied
        ? 'Allow camera access so the app can scan barcodes. You can enable it '
            'in the app settings.'
        : 'The camera could not be started'
            '${error.errorDetails?.message != null ? ':\n${error.errorDetails!.message}' : '.'}';
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(denied ? Icons.no_photography : Icons.videocam_off,
                size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 24),
            if (denied)
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Open settings'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onManual,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              child: const Text('Enter details manually'),
            ),
          ],
        ),
      ),
    );
  }
}
