import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Pairing flow. The employee first scans the QR the admin generated in the
/// portal (it carries the one-time pairing code). On a successful scan the code
/// is filled in and locked, and they only add an optional device name. They can
/// also skip scanning and type the code by hand.
///
/// The device then generates its key pair and proves possession by signing the
/// code (see [DeviceRepository.enroll]).
class EnrollPage extends StatefulWidget {
  const EnrollPage({super.key});

  @override
  State<EnrollPage> createState() => _EnrollPageState();
}

enum _Step { scan, form }

class _EnrollPageState extends State<EnrollPage> {
  _Step _step = _Step.scan;

  /// Non-null once the code came from a QR scan; in that case the code field is
  /// pre-filled and locked. Null means the employee chose to type it manually.
  String? _scannedCode;

  void _onScanned(String code) {
    setState(() {
      _scannedCode = code;
      _step = _Step.form;
    });
  }

  void _enterManually() {
    setState(() {
      _scannedCode = null;
      _step = _Step.form;
    });
  }

  void _backToScan() {
    setState(() {
      _scannedCode = null;
      _step = _Step.scan;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.scan:
        return _ScanStep(onScanned: _onScanned, onSkip: _enterManually);
      case _Step.form:
        return _FormStep(lockedCode: _scannedCode, onRescan: _backToScan);
    }
  }
}

/// Camera screen that reads the admin QR (which encodes the raw pairing code).
class _ScanStep extends StatefulWidget {
  const _ScanStep({required this.onScanned, required this.onSkip});

  final void Function(String code) onScanned;
  final VoidCallback onSkip;

  @override
  State<_ScanStep> createState() => _ScanStepState();
}

class _ScanStepState extends State<_ScanStep> {
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
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handled = true;
        // The admin QR carries the raw pairing code; normalise to the server
        // alphabet (trimmed, upper-case) just like typed input.
        widget.onScanned(raw.trim().toUpperCase());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét QR ghép cặp'),
        actions: [
          IconButton(
            tooltip: 'Đổi máy chủ',
            icon: const Icon(Icons.settings_outlined),
            onPressed:
                state.busy ? null : () => context.read<AppState>().changeServer(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => _ScannerError(
                    message: error.errorCode.message,
                  ),
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
                  'Hướng camera vào mã QR do quản trị viên cấp.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: widget.onSkip,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Bỏ qua, nhập mã thủ công'),
                ),
              ],
            ),
          ),
          SizedBox(height: 40)
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
                'Bạn vẫn có thể bỏ qua và nhập mã thủ công.',
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

/// The pairing form. When [lockedCode] is non-null it was filled from a QR scan
/// and the code field is read-only; the employee only adds an optional name.
class _FormStep extends StatefulWidget {
  const _FormStep({required this.lockedCode, required this.onRescan});

  final String? lockedCode;
  final VoidCallback onRescan;

  @override
  State<_FormStep> createState() => _FormStepState();
}

class _FormStepState extends State<_FormStep> {
  late final TextEditingController _codeController =
      TextEditingController(text: widget.lockedCode ?? '');
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool get _codeLocked => widget.lockedCode != null;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final state = context.read<AppState>();
    final error = await state.enroll(
      pairingCode: _codeController.text,
      deviceName: _nameController.text.trim(),
    );
    if (!mounted) return;
    if (error != null) {
      _showSnack(error, isError: true);
    } else {
      _showSnack('Ghép cặp thành công!');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghép cặp thiết bị'),
        actions: [
          IconButton(
            tooltip: 'Quét lại QR',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: state.busy ? null : widget.onRescan,
          ),
          IconButton(
            tooltip: 'Đổi máy chủ',
            icon: const Icon(Icons.settings_outlined),
            onPressed:
                state.busy ? null : () => context.read<AppState>().changeServer(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.key_outlined, size: 72, color: Colors.indigo),
              const SizedBox(height: 8),
              Text('Máy chủ: ${state.baseUrl}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 16),
              Text(
                _codeLocked
                    ? 'Mã ghép cặp đã được điền từ QR.'
                    : 'Nhập mã ghép cặp do quản trị viên cấp.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.fingerprint, size: 18, color: Colors.black45),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Khoá thiết bị được tạo & bảo vệ trong phần cứng; bạn sẽ '
                      'xác thực bằng vân tay/Face ID.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _codeController,
                readOnly: _codeLocked,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [UpperCaseFormatter()],
                decoration: InputDecoration(
                  labelText: 'Mã ghép cặp',
                  hintText: 'VD: ABCDEFGH23',
                  border: const OutlineInputBorder(),
                  filled: _codeLocked,
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: _codeLocked
                      ? const Icon(Icons.lock_outline, color: Colors.green)
                      : null,
                  helperText: _codeLocked ? 'Đã quét từ QR' : null,
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Vui lòng nhập mã ghép cặp' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên thiết bị (tuỳ chọn)',
                  hintText: 'VD: iPhone của An',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.smartphone_outlined),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: state.busy ? null : _enroll,
                icon: state.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.link),
                label: Text(state.busy ? 'Đang ghép cặp...' : 'Ghép cặp thiết bị'),
              ),
              if (_codeLocked) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: state.busy ? null : widget.onRescan,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Quét lại mã khác'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Forces typed text to upper case so pairing codes match the server alphabet.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
