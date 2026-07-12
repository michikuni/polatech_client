import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// The "Chấm công" tab: officer identity + check-in / check-out actions.
/// Body only — the [Scaffold]/[AppBar]/nav live in the parent shell.
class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  @override
  void initState() {
    super.initState();
    // Load today's state so only the valid button is enabled on first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshStatus();
    });
  }

  Future<void> _record(BuildContext context, AttendanceType type) async {
    final state = context.read<AppState>();
    final error = await state.recordAttendance(type);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error != null ? const Color(0xFF8B2F2F) : AppColors.primary,
        content: Text(
          error ?? 'Đã ghi nhận ${type.label.toLowerCase()} thành công',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: kScreenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OfficerCard(
              fullName: state.fullName,
              employeeCode: state.employeeCode,
              position: state.position,
              rank: state.rank,
              deviceName: state.deviceName,
              deviceId: state.deviceId,
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Ghi nhận chấm công',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            if (state.status != null) ...[
              _StateHint(openSession: state.status!.openSession),
              const SizedBox(height: 14),
            ],
            _PunchButton(
              label: 'Vào ca',
              icon: Icons.login_rounded,
              color: AppColors.checkIn,
              enabled: !state.busy && state.canCheckIn,
              onPressed: () => _record(context, AttendanceType.checkIn),
            ),
            const SizedBox(height: 14),
            _PunchButton(
              label: 'Tan ca',
              icon: Icons.logout_rounded,
              color: AppColors.checkOut,
              outlined: true,
              enabled: !state.busy && state.canCheckOut,
              onPressed: () => _record(context, AttendanceType.checkOut),
            ),
            const SizedBox(height: 24),
            if (state.busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (state.lastEvent != null)
              _LastPunchBanner(event: state.lastEvent!),
          ],
        ),
      ),
    );
  }
}

/// A one-line hint telling the officer which action is expected next, matching
/// the enabled button.
class _StateHint extends StatelessWidget {
  const _StateHint({required this.openSession});

  final bool openSession;

  @override
  Widget build(BuildContext context) {
    final color = openSession ? AppColors.checkOut : AppColors.checkIn;
    final text = openSession
        ? 'Đang trong ca trực.'
        : 'Đã tan ca.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(openSession ? Icons.timelapse_rounded : Icons.check_circle_outline,
              size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficerCard extends StatelessWidget {
  const _OfficerCard({
    this.fullName,
    this.employeeCode,
    this.position,
    this.rank,
    this.deviceName,
    this.deviceId,
  });

  final String? fullName;
  final String? employeeCode;
  final String? position;
  final String? rank;
  final String? deviceName;
  final int? deviceId;

  String get _initials {
    final name = (fullName ?? '').trim();
    if (name.isEmpty) return '#';
    final parts = name.split(RegExp(r'\s+'));
    return parts.last.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = (fullName?.trim().isNotEmpty ?? false)
        ? fullName!.trim()
        : 'Cán bộ đã xác minh';
    final meta = [
      if (position?.trim().isNotEmpty ?? false) position!.trim(),
      if (rank?.trim().isNotEmpty ?? false) rank!.trim(),
    ].join('  •  ');

    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (employeeCode?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Mã cán bộ: ${employeeCode!.trim()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 14),
            Text(
              meta,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 15, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    if (deviceName?.trim().isNotEmpty ?? false)
                      deviceName!.trim(),
                    'Thiết bị #${deviceId ?? '-'}',
                  ].join('  •  '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PunchButton extends StatelessWidget {
  const _PunchButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool outlined;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? color : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: outlined ? AppColors.surface : color,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadius),
          onTap: enabled ? onPressed : null,
          child: Ink(
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadius),
              border: outlined ? Border.all(color: color, width: 1.4) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 24),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LastPunchBanner extends StatelessWidget {
  const _LastPunchBanner({required this.event});

  final AttendanceEvent event;

  @override
  Widget build(BuildContext context) {
    final isCheckIn = event.type == AttendanceType.checkIn.wireName;
    final color = isCheckIn ? AppColors.checkIn : AppColors.checkOut;
    final localTime = DateTime.tryParse(event.eventTime)?.toLocal();
    final timeText = localTime == null
        ? event.eventTime
        : '${localTime.hour.toString().padLeft(2, '0')}:'
            '${localTime.minute.toString().padLeft(2, '0')}:'
            '${localTime.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
              color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Gần nhất: ${isCheckIn ? 'Vào ca' : 'Tan ca'} lúc $timeText',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
