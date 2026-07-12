import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'attendance_page.dart';
import 'history_page.dart';

/// Top-level shell for an enrolled device: a bottom navigation bar switching
/// between the "Chấm công" and "Lịch sử chấm công" tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final GlobalKey<HistoryViewState> _historyKey = GlobalKey<HistoryViewState>();

  static const _titles = ['Chấm công', 'Lịch sử chấm công'];

  static const _historyIndex = 1;

  Future<void> _confirmUnenroll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Huỷ ghép cặp?'),
        content: const Text(
          'Thiết bị sẽ tạo khoá mới khi ghép cặp lần sau. Bạn cần mã ghép cặp mới '
          'từ quản trị viên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().unenroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'server') context.read<AppState>().changeServer();
              if (v == 'unenroll') _confirmUnenroll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'server', child: Text('Đổi máy chủ')),
              PopupMenuItem(value: 'unenroll', child: Text('Huỷ ghép cặp')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [const AttendanceView(), HistoryView(key: _historyKey)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // Re-fetch history each time the tab is opened so a just-recorded
          // check-in/check-out is always shown.
          if (i == _historyIndex) _historyKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fingerprint_rounded),
            label: 'Chấm công',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'Lịch sử',
          ),
        ],
      ),
    );
  }
}
