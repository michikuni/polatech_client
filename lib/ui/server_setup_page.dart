import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/pairing_qr.dart';
import '../state/app_state.dart';
import 'qr_scan_view.dart';

/// Server-address screen: shown on first run, and again whenever the employee
/// taps "Đổi máy chủ" (e.g. the server came back on a new IP).
///
/// The happy path is a single scan of a QR from the admin portal: the pairing QR
/// carries address + one-time code, while the portal's connect-only QR carries
/// just the address — enough for an already-paired phone to follow the server,
/// with its hardware key untouched. Typing the IP by hand stays available for
/// when the camera is unusable.
class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({super.key});

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// The IP form is hidden until the employee asks for it, so the scan stays the
  /// obvious action.
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    _controller.text = _extractIp(context.read<AppState>().baseUrl) ?? '192.168.1.10';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pulls just the IP/host out of a stored URL like `http://192.168.1.10:8080`.
  String? _extractIp(String? url) {
    if (url == null || url.isEmpty) return null;
    var host = url.trim().replaceFirst(RegExp(r'^https?://'), '');
    host = host.split('/').first.split(':').first;
    return host.isEmpty ? null : host;
  }

  /// Opens the scanner; on a successful scan the app adopts the server address
  /// from the QR and moves straight to enrollment with the code filled in.
  Future<void> _scan() async {
    final payload = await Navigator.of(context).push<PairingQr>(
      MaterialPageRoute(
        builder: (ctx) => QrScanView(
          title: 'Quét QR máy chủ',
          hint: 'Hướng camera vào mã QR trên trang quản trị.\n'
              'App tự nhận địa chỉ máy chủ (và mã ghép cặp, nếu QR có).',
          skipLabel: 'Nhập địa chỉ máy chủ thủ công',
          onScanned: (p) => Navigator.of(ctx).pop(p),
          onSkip: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (!mounted) return;
    if (payload == null) {
      setState(() => _manual = true); // employee chose manual entry
      return;
    }
    final error = await context.read<AppState>().applyPairingQr(payload);
    if (!mounted || error == null) return;
    setState(() => _manual = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ip = _controller.text.trim();
    await context.read<AppState>().saveBaseUrl('http://$ip:8080');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kết nối máy chủ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.qr_code_scanner, size: 72, color: Colors.indigo),
            const SizedBox(height: 16),
            Text(
              context.read<AppState>().isEnrolled
                  ? 'Quét mã QR ở tab "Máy chủ" trên trang quản trị để kết nối '
                      'tới địa chỉ mới. Thiết bị vẫn giữ nguyên ghép cặp — không '
                      'cần mã mới.'
                  : 'Quét mã QR do quản trị viên cấp để kết nối máy chủ và ghép '
                      'cặp thiết bị — không cần nhập địa chỉ.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Quét mã QR'),
            ),
            const SizedBox(height: 20),
            if (!_manual)
              TextButton.icon(
                onPressed: () => setState(() => _manual = true),
                icon: const Icon(Icons.keyboard_outlined, size: 18),
                label: const Text('Không quét được? Nhập địa chỉ thủ công'),
              )
            else
              _ManualForm(
                formKey: _formKey,
                controller: _controller,
                onSubmit: _save,
              ),
            const SizedBox(height: 16),
            const Text(
              'Kết nối dùng HTTP thường — phù hợp mạng nội bộ cô lập. '
              'Việc xác minh thiết bị dựa trên chữ ký số, không phụ thuộc HTTPS.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback: type the server's LAN IP (port 8080 is assumed, as before).
class _ManualForm extends StatelessWidget {
  const _ManualForm({
    required this.formKey,
    required this.controller,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Nhập địa chỉ IP của máy chủ chấm công trong mạng LAN.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Địa chỉ IP máy chủ',
              hintText: '192.168.1.10',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns_outlined),
              prefixText: 'http://',
              suffixText: ':8080',
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Vui lòng nhập địa chỉ IP';
              if (t.contains('://') || t.contains('/')) {
                return 'Chỉ nhập IP, ví dụ 192.168.1.10';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
  }
}
