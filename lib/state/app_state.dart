import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device_repository.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import '../data/pairing_qr.dart';

/// Which top-level screen the app should show.
enum AppScreen { serverSetup, enroll, attendance }

/// App-wide state: owns the store + repository and drives the UI through a
/// small set of async actions. Kept deliberately thin — the real work lives in
/// [DeviceRepository].
class AppState extends ChangeNotifier {
  AppState(this._store) : _repo = DeviceRepository(_store);

  final LocalStore _store;
  final DeviceRepository _repo;

  bool busy = false;
  AttendanceEvent? lastEvent;

  /// Pairing code captured from a QR scan that happened before the enroll screen
  /// existed (i.e. on the server-setup screen). [takePendingPairingCode] hands it
  /// to the enroll screen exactly once, so a later re-scan is not overridden.
  String? _pendingPairingCode;

  /// Today's attendance state, or null until loaded / on load failure. Drives
  /// which of the two punch buttons is enabled.
  AttendanceStatus? status;

  static Future<AppState> create() async => AppState(await LocalStore.open());

  /// Whether a check-in is allowed right now. Falls back to `true` while the
  /// status is unknown so the server stays the source of truth.
  bool get canCheckIn => status?.canCheckIn ?? true;

  /// Whether a check-out is allowed right now. Falls back to `true` while the
  /// status is unknown so the server stays the source of truth.
  bool get canCheckOut => status?.canCheckOut ?? true;

  String? get baseUrl => _store.baseUrl;
  int? get deviceId => _repo.deviceId;
  int? get employeeId => _repo.employeeId;
  String? get deviceName => _repo.deviceName;
  String? get employeeCode => _repo.employeeCode;
  String? get fullName => _repo.fullName;
  String? get position => _repo.position;
  String? get rank => _repo.rank;

  AppScreen get screen {
    if (baseUrl == null || baseUrl!.isEmpty) return AppScreen.serverSetup;
    if (!_repo.isEnrolled) return AppScreen.enroll;
    return AppScreen.attendance;
  }

  Future<void> saveBaseUrl(String url) async {
    await _store.setBaseUrl(_normalize(url));
    notifyListeners();
  }

  /// Applies a scanned QR: adopts the server address it carries (so the employee
  /// never types an IP) and, if it also carried a pairing code, remembers it for
  /// the enroll screen. A connect-only QR therefore just re-points an already
  /// paired device at the server's new address — the hardware key is untouched.
  ///
  /// Returns null on success, or a message when the QR carries neither a usable
  /// address nor anything to do with the current state.
  Future<String?> applyPairingQr(PairingQr qr) async {
    if (qr.baseUrl != null) {
      await _store.setBaseUrl(_normalize(qr.baseUrl!));
    } else if (baseUrl == null || baseUrl!.isEmpty) {
      return 'Mã QR này không chứa địa chỉ máy chủ. Hãy nhập địa chỉ thủ công, '
          'hoặc xin quản trị viên cấp lại mã QR mới.';
    }
    if (qr.code == null && !isEnrolled) {
      // Connect-only QR on a device that still has to pair: the address is saved,
      // but the employee also needs a pairing code.
      notifyListeners();
      return 'Đã lưu địa chỉ máy chủ. Thiết bị chưa ghép cặp — hãy quét QR mã '
          'ghép cặp do quản trị viên cấp.';
    }
    if (qr.code != null) _pendingPairingCode = qr.code;
    notifyListeners();
    return null;
  }

  /// True once this device holds a key paired with the server.
  bool get isEnrolled => _repo.isEnrolled;

  /// Returns the code from a pre-enroll scan (once), clearing it.
  String? takePendingPairingCode() {
    final code = _pendingPairingCode;
    _pendingPairingCode = null;
    return code;
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> enroll({required String pairingCode, String? deviceName}) =>
      _run(() => _repo.enroll(pairingCode: pairingCode, deviceName: deviceName));

  /// Returns null on success, or a user-facing error message. On success the
  /// local [status] flips optimistically (check-in -> open session) so the
  /// buttons update instantly; then it is reconciled with the server's
  /// authoritative state so the UI is correct even if the response was lost
  /// after the punch was recorded, or the guess ever diverges.
  Future<String?> recordAttendance(AttendanceType type) async {
    final error = await _run(() async {
      final event = await _repo.recordAttendance(type);
      lastEvent = event;
      status = AttendanceStatus(
        openSession: type == AttendanceType.checkIn,
        lastType: type.wireName,
        lastEventTime: event.eventTime,
      );
    });
    // Reconcile with the server's authoritative state in the background so the
    // snackbar/UI stay snappy; refreshStatus swallows its own errors.
    unawaited(refreshStatus());
    return error;
  }

  /// Loads today's attendance state so the UI can enable only the valid button.
  /// Failures are swallowed (status left unknown); the server still enforces the
  /// rule on submit.
  Future<void> refreshStatus() async {
    if (deviceId == null) return;
    try {
      status = await _repo.fetchStatus();
    } catch (_) {
      // Leave status as-is; buttons fall back to enabled and the server decides.
    }
    notifyListeners();
  }

  /// Loads the attendance history (most recent first). Throws [ApiException] on
  /// failure so callers (e.g. a FutureBuilder) can surface the message.
  Future<List<DailyHistory>> loadHistory() => _repo.fetchHistory();

  /// Saves the one-time shift-handover note on check-in [eventId]. Returns null
  /// on success, or a user-facing error message (e.g. the note already exists).
  Future<String?> saveShiftNote(int eventId, String note) async {
    try {
      await _repo.saveNote(eventId, note);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Đã xảy ra lỗi: $e';
    }
  }

  Future<void> unenroll() async {
    await _repo.unenroll();
    lastEvent = null;
    status = null;
    notifyListeners();
  }

  Future<void> changeServer() async {
    await _store.setBaseUrl('');
    _pendingPairingCode = null;
    notifyListeners();
  }

  /// Runs [action], mapping [ApiException] to its message and anything else to a
  /// generic string. Toggles [busy] and notifies listeners around the call.
  Future<String?> _run(Future<void> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      await action();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Đã xảy ra lỗi: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u;
  }
}
