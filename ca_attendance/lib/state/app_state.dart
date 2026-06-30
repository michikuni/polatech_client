import 'package:flutter/foundation.dart';

import '../data/device_repository.dart';
import '../data/local_store.dart';
import '../data/models.dart';

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

  static Future<AppState> create() async => AppState(await LocalStore.open());

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

  /// Returns null on success, or a user-facing error message.
  Future<String?> enroll({required String pairingCode, String? deviceName}) =>
      _run(() => _repo.enroll(pairingCode: pairingCode, deviceName: deviceName));

  /// Returns null on success, or a user-facing error message.
  Future<String?> recordAttendance(AttendanceType type) => _run(() async {
        lastEvent = await _repo.recordAttendance(type);
      });

  /// Loads the attendance history (most recent first). Throws [ApiException] on
  /// failure so callers (e.g. a FutureBuilder) can surface the message.
  Future<List<DailyHistory>> loadHistory() => _repo.fetchHistory();

  Future<void> unenroll() async {
    await _repo.unenroll();
    lastEvent = null;
    notifyListeners();
  }

  Future<void> changeServer() async {
    await _store.setBaseUrl('');
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
