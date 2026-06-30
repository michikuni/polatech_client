import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// The "Lịch sử chấm công" tab: one row per day showing the earliest punch
/// (vào ca) and the latest punch (ra ca). Body only — shell owns the chrome.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  late Future<List<DailyHistory>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadHistory();
  }

  Future<void> _refresh() async {
    final future = context.read<AppState>().loadHistory();
    setState(() => _future = future);
    await future.catchError((_) => <DailyHistory>[]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<DailyHistory>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              );
            }
            if (snapshot.hasError) {
              return _Message(
                icon: Icons.cloud_off_rounded,
                title: 'Không tải được lịch sử',
                subtitle: '${snapshot.error}',
                onRetry: _refresh,
              );
            }
            final days = snapshot.data ?? const [];
            if (days.isEmpty) {
              return _Message(
                icon: Icons.event_busy_outlined,
                title: 'Chưa có dữ liệu chấm công',
                subtitle: 'Lịch sử vào/ra ca sẽ hiển thị ở đây.',
                onRetry: _refresh,
              );
            }
            return ListView.separated(
              padding: kScreenPadding,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _DayRow(day: days[i]),
            );
          },
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final DailyHistory day;

  /// "yyyy-MM-dd" -> "dd/MM"; falls back to the raw string if unexpected.
  String get _ddMM {
    final p = day.date.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}' : day.date;
  }

  /// ISO instant -> local "HH:mm", or "—" when absent.
  static String _hhmm(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _ddMM,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _TimeCell(
              label: 'Vào ca',
              time: _hhmm(day.checkIn),
              color: AppColors.checkIn,
              icon: Icons.login_rounded,
            ),
          ),
          Container(width: 1, height: 34, color: AppColors.line),
          Expanded(
            child: _TimeCell(
              label: 'Ra ca',
              time: _hhmm(day.checkOut),
              color: AppColors.checkOut,
              icon: Icons.logout_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({
    required this.label,
    required this.time,
    required this.color,
    required this.icon,
  });

  final String label;
  final String time;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    // Wrapped in a scroll view so RefreshIndicator still works when empty.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(icon, size: 56, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Tải lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
