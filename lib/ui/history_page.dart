import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// The "Lịch sử chấm công" tab: one row per day listing every check-in/check-out
/// of that day in order — the row grows with the number of punches. Body only —
/// shell owns the chrome.
class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => HistoryViewState();
}

class HistoryViewState extends State<HistoryView> {
  late Future<List<DailyHistory>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadHistory();
  }

  /// Re-fetches the history from the server. Called on pull-to-refresh, on retry,
  /// and by the shell every time the History tab is opened so a just-recorded
  /// check-in/check-out shows up without reopening the app.
  Future<void> reload() async {
    final future = context.read<AppState>().loadHistory();
    setState(() => _future = future);
    await future.catchError((_) => <DailyHistory>[]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: reload,
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
                onRetry: reload,
              );
            }
            final days = snapshot.data ?? const [];
            if (days.isEmpty) {
              return _Message(
                icon: Icons.event_busy_outlined,
                title: 'Chưa có dữ liệu chấm công',
                subtitle: 'Lịch sử vào/ra ca sẽ hiển thị ở đây.',
                onRetry: reload,
              );
            }
            return ListView.separated(
              padding: kScreenPadding,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _DayRow(day: days[i], onNoteSaved: () => setState(() {})),
            );
          },
        ),
      ),
    );
  }
}

/// "yyyy-MM-dd" -> "dd/MM"; falls back to the raw string if unexpected.
String _ddMM(String date) {
  final p = date.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}' : date;
}

/// ISO instant -> local "HH:mm", or "—" when unparseable.
String _hhmm(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '—';
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

/// One day: a date badge on the left and the full chronological list of that
/// day's punches on the right. Taller days simply have more punch rows.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.onNoteSaved});

  final DailyHistory day;
  final VoidCallback onNoteSaved;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ddMM(day.date),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.punches.length} lượt',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < _pairs.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.line),
                    const SizedBox(height: 12),
                  ],
                  _PairBlock(punches: _pairs[i], onNoteSaved: onNoteSaved),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Groups the day's punches into sessions: each check-in starts a pair that the
  /// following check-out closes. A trailing check-in with no check-out is an open
  /// pair; a stray check-out (shouldn't happen under the alternation rule) stands
  /// alone.
  List<List<DailyPunch>> get _pairs {
    final pairs = <List<DailyPunch>>[];
    for (final punch in day.punches) {
      final openPair = pairs.isNotEmpty &&
          pairs.last.length == 1 &&
          pairs.last.first.isCheckIn;
      if (punch.isCheckIn || !openPair) {
        pairs.add([punch]);
      } else {
        pairs.last.add(punch);
      }
    }
    return pairs;
  }
}

/// One session (a check-in + its check-out, or an open check-in): the punch lines
/// stacked on the left, with the shift-handover note button on the right spanning
/// the height of both lines.
class _PairBlock extends StatelessWidget {
  const _PairBlock({required this.punches, required this.onNoteSaved});

  /// One or two punches: the check-in (and its check-out when present).
  final List<DailyPunch> punches;
  final VoidCallback onNoteSaved;

  @override
  Widget build(BuildContext context) {
    // The note belongs to the check-in that opens the session.
    final checkIn = punches.first.isCheckIn ? punches.first : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            children: [
              for (var i = 0; i < punches.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _PunchLine(punch: punches[i]),
              ],
            ],
          ),
        ),
        if (checkIn != null) ...[
          const SizedBox(width: 10),
          _NoteButton(punch: checkIn, onNoteSaved: onNoteSaved),
        ],
      ],
    );
  }
}

/// A single punch line: type icon + label on the left, time on the right.
class _PunchLine extends StatelessWidget {
  const _PunchLine({required this.punch});

  final DailyPunch punch;

  @override
  Widget build(BuildContext context) {
    final isCheckIn = punch.isCheckIn;
    final color = isCheckIn ? AppColors.checkIn : AppColors.checkOut;
    return Row(
      children: [
        Icon(
          isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          isCheckIn ? 'Vào ca' : 'Ra ca',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          _hhmm(punch.eventTime),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The shift-handover note button for a session, keyed by its check-in [punch].
class _NoteButton extends StatelessWidget {
  const _NoteButton({required this.punch, required this.onNoteSaved});

  final DailyPunch punch;
  final VoidCallback onNoteSaved;

  Future<void> _openNote(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final savedNote = await showDialog<String>(
      context: context,
      builder: (_) => _ShiftNoteDialog(punch: punch),
    );
    if (savedNote != null) {
      // Reflect the saved note in place immediately (it already matches what the
      // server persisted), so the button locks to read-only without a reload.
      punch.note = savedNote;
      onNoteSaved();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary,
          content: Text('Đã lưu thông tin tiếp nhận ca trực'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
      tooltip: punch.hasNote
          ? 'Xem thông tin tiếp nhận ca trực'
          : 'Nhập thông tin tiếp nhận ca trực',
      icon: Icon(
        punch.hasNote ? Icons.sticky_note_2_rounded : Icons.note_add_outlined,
        size: 20,
        color: punch.hasNote ? AppColors.primary : AppColors.textMuted,
      ),
      onPressed: () => _openNote(context),
    );
  }
}

/// Dialog for the shift-handover note. Editable once (empty note), then locked to
/// read-only display so the recorded information can no longer be changed.
class _ShiftNoteDialog extends StatefulWidget {
  const _ShiftNoteDialog({required this.punch});

  final DailyPunch punch;

  @override
  State<_ShiftNoteDialog> createState() => _ShiftNoteDialogState();
}

class _ShiftNoteDialogState extends State<_ShiftNoteDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  bool get _readOnly => widget.punch.hasNote;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.punch.note ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Vui lòng nhập thông tin.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await context.read<AppState>().saveShiftNote(widget.punch.id, text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    // Return the saved (trimmed) note so the caller can lock the button in place.
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thông tin tiếp nhận ca trực'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_readOnly)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  widget.punch.note!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 5,
                maxLength: 1000,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Nhập thông tin tiếp nhận ca trực...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF8B2F2F)),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: _readOnly
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text('Lưu'),
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
