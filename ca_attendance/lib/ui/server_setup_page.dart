import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// First-run screen: where is the attendance server on the LAN?
class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({super.key});

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ip = _controller.text.trim();
    await context.read<AppState>().saveBaseUrl('http://$ip:8080');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kết nối máy chủ')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lan_outlined, size: 72, color: Colors.indigo),
              const SizedBox(height: 16),
              Text(
                'Nhập địa chỉ IP của máy chủ chấm công trong mạng LAN.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller,
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Tiếp tục'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Kết nối dùng HTTP thường — phù hợp mạng nội bộ cô lập. '
                'Việc xác minh thiết bị dựa trên chữ ký số, không phụ thuộc HTTPS.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
