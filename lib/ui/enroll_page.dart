import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/pairing_qr.dart';
import '../state/app_state.dart';
import 'qr_scan_view.dart';

/// Pairing flow. The employee scans the QR the admin generated in the portal (it
/// carries the one-time pairing code and the server address). On a successful
/// scan the code is filled in and locked, and they only add an optional device
/// name. They can also skip scanning and type the code by hand.
///
/// When the scan already happened on the server-setup screen, its code arrives
/// through [AppState.takePendingPairingCode] and this page opens straight on the
/// form.
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
  late _Step _step;

  /// Non-null once the code came from a QR scan; in that case the code field is
  /// pre-filled and locked. Null means the employee chose to type it manually.
  String? _scannedCode;

  /// Bumped to rebuild [QrScanView] with a fresh state: the scanner stops after
  /// its first hit, so re-scanning (e.g. after a connect-only QR) needs a new one.
  int _scanNonce = 0;

  @override
  void initState() {
    super.initState();
    _scannedCode = context.read<AppState>().takePendingPairingCode();
    _step = _scannedCode == null ? _Step.scan : _Step.form;
  }

  /// A QR scanned here also carries the server address (the admin may have
  /// re-issued the code from a server that moved); adopt it so the enroll call
  /// goes to the server that actually issued the code.
  ///
  /// A connect-only QR (address, no code) is not enough to pair: the address is
  /// kept and the employee stays on the scanner to read the real pairing QR.
  Future<void> _onScanned(PairingQr payload) async {
    final error = await context.read<AppState>().applyPairingQr(payload);
    if (!mounted) return;
    if (payload.code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ??
              'QR này chỉ chứa địa chỉ máy chủ. Hãy quét QR mã ghép cặp do '
                  'quản trị viên cấp.'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      setState(() {
        _step = _Step.scan;
        _scanNonce++; // fresh scanner state, otherwise it stays latched shut
      });
      return;
    }
    setState(() {
      _scannedCode = payload.code;
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
      _scanNonce++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    switch (_step) {
      case _Step.scan:
        return QrScanView(
          key: ValueKey(_scanNonce),
          title: 'Quét QR ghép cặp',
          hint: 'Hướng camera vào mã QR do quản trị viên cấp.',
          skipLabel: 'Bỏ qua, nhập mã thủ công',
          onScanned: _onScanned,
          onSkip: _enterManually,
          actions: [
            IconButton(
              tooltip: 'Đổi máy chủ',
              icon: const Icon(Icons.settings_outlined),
              onPressed: state.busy
                  ? null
                  : () => context.read<AppState>().changeServer(),
            ),
          ],
        );
      case _Step.form:
        return _FormStep(lockedCode: _scannedCode, onRescan: _backToScan);
    }
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
