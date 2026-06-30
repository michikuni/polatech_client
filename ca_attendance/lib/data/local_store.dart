import 'package:shared_preferences/shared_preferences.dart';

/// Persists the device's NON-secret settings only: the server URL, the public
/// key, and the server-assigned ids. The private key never touches storage — it
/// lives in secure hardware (Android Keystore / iOS Secure Enclave), see
/// [HardwareKeystore]. Hence there is no private-key field here anymore.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kBaseUrl = 'base_url';
  static const _kPublicKey = 'device_public_key';
  static const _kDeviceId = 'device_id';
  static const _kEmployeeId = 'employee_id';
  static const _kDeviceName = 'device_name';
  static const _kEmployeeCode = 'employee_code';
  static const _kFullName = 'full_name';
  static const _kPosition = 'position';
  static const _kRank = 'rank';

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  String? get baseUrl => _prefs.getString(_kBaseUrl);
  Future<void> setBaseUrl(String value) => _prefs.setString(_kBaseUrl, value);

  /// True once the device has successfully enrolled. The matching private key
  /// is held by the hardware keystore.
  bool get isEnrolled =>
      _prefs.getString(_kPublicKey) != null && _prefs.getInt(_kDeviceId) != null;

  String? get publicKey => _prefs.getString(_kPublicKey);
  int? get deviceId => _prefs.getInt(_kDeviceId);
  int? get employeeId => _prefs.getInt(_kEmployeeId);
  String? get deviceName => _prefs.getString(_kDeviceName);
  String? get employeeCode => _prefs.getString(_kEmployeeCode);
  String? get fullName => _prefs.getString(_kFullName);
  String? get position => _prefs.getString(_kPosition);
  String? get rank => _prefs.getString(_kRank);

  Future<void> saveEnrollment({
    required String publicKey,
    required int deviceId,
    required int employeeId,
    String? deviceName,
    String? employeeCode,
    String? fullName,
    String? position,
    String? rank,
  }) async {
    await _prefs.setString(_kPublicKey, publicKey);
    await _prefs.setInt(_kDeviceId, deviceId);
    await _prefs.setInt(_kEmployeeId, employeeId);
    if (deviceName != null && deviceName.isNotEmpty) {
      await _prefs.setString(_kDeviceName, deviceName);
    }
    await _setOrRemove(_kEmployeeCode, employeeCode);
    await _setOrRemove(_kFullName, fullName);
    await _setOrRemove(_kPosition, position);
    await _setOrRemove(_kRank, rank);
  }

  Future<void> _setOrRemove(String key, String? value) async {
    if (value != null && value.isNotEmpty) {
      await _prefs.setString(key, value);
    } else {
      await _prefs.remove(key);
    }
  }

  /// Forgets the device identity (keeps the base URL) — used to re-pair.
  Future<void> clearEnrollment() async {
    await _prefs.remove(_kPublicKey);
    await _prefs.remove(_kDeviceId);
    await _prefs.remove(_kEmployeeId);
    await _prefs.remove(_kDeviceName);
    await _prefs.remove(_kEmployeeCode);
    await _prefs.remove(_kFullName);
    await _prefs.remove(_kPosition);
    await _prefs.remove(_kRank);
  }
}
