import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/pairing_qr.dart';

/// Camera screen that reads the admin's pairing QR. Shared by the first-run
/// server setup (where the QR also supplies the server address) and the pairing
/// step (where the address is already known).
///
/// [onSkip] is the manual fallback — always offered, and the only way forward if
/// the camera can't be opened.
class QrScanView extends StatefulWidget {
  const QrScanView({
    super.key,
    required this.title,
    required this.hint,
    required this.skipLabel,
    required this.onScanned,
    required this.onSkip,
    this.actions = const [],
  });

  final String title;
  final String hint;
  final String skipLabel;
  final void Function(PairingQr payload) onScanned;
  final VoidCallback onSkip;
  final List<Widget> actions;

  @override
  State<QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends State<QrScanView> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// Guards against the detection stream firing repeatedly for the same code.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final payload = PairingQr.parse(barcode.rawValue ?? '');
      if (payload != null) {
        _handled = true;
        widget.onScanned(payload);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: widget.actions),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) =>
                      _ScannerError(message: error.errorCode.message),
                ),
                // Simple viewfinder frame.
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.hint,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: widget.onSkip,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: Text(widget.skipLabel),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Shown when the camera can't be opened (no permission, no camera, etc.); the
/// employee can still fall back to manual entry via the button below the frame.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                'Không mở được camera.\n$message',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Bạn vẫn có thể nhập thủ công bằng nút bên dưới.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
