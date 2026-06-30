import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import '../crypto/hardware_keystore.dart';
import 'api_client.dart';
import 'local_store.dart';
import 'models.dart';

/// Orchestrates the device-verification flows on top of the hardware keystore,
/// HTTP and storage layers. This is the only class the UI talks to.
///
/// The signing key lives in secure hardware (Android Keystore / iOS Secure
/// Enclave) and never leaves it; every signature is gated by a fingerprint /
/// Face ID check. Storage only keeps the public key + the server-assigned ids.
class DeviceRepository {
  DeviceRepository(this._store, [this._keystore = const HardwareKeystore()]);

  final LocalStore _store;
  final HardwareKeystore _keystore;

  String get _platform => Platform.isIOS ? 'IOS' : 'ANDROID';

  bool get isEnrolled => _store.isEnrolled;
  int? get deviceId => _store.deviceId;
  int? get employeeId => _store.employeeId;
  String? get deviceName => _store.deviceName;
  String? get employeeCode => _store.employeeCode;
  String? get fullName => _store.fullName;
  String? get position => _store.position;
  String? get rank => _store.rank;

  /// True only if this device can host a hardware-backed, biometric-gated key.
  Future<bool> biometricAvailable() => _keystore.isAvailable();

  /// Runs [op], converting hardware-keystore failures into [ApiException] so the
  /// UI can show them uniformly.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on KeystoreException catch (e) {
      throw ApiException(e.message, code: e.code);
    }
  }

  AttendanceApi _api() {
    final base = _store.baseUrl;
    if (base == null || base.isEmpty) {
      throw ApiException('Chưa cấu hình địa chỉ máy chủ.');
    }
    return AttendanceApi(baseUrl: base);
  }

  /// Pairs this device:
  ///  1. generate a fresh P-256 key **inside secure hardware**,
  ///  2. prove possession by signing the pairing code (biometric prompt),
  ///  3. send the public key to the backend,
  ///  4. persist the public key + returned ids (never the private key).
  Future<EnrollResult> enroll({
    required String pairingCode,
    String? deviceName,
  }) async {
    if (!await biometricAvailable()) {
      throw ApiException(
        'Thiết bị không hỗ trợ khoá bảo mật phần cứng, hoặc bạn chưa cài '
        'vân tay/Face ID. Hãy thiết lập sinh trắc học rồi thử lại.',
        code: 'unavailable',
      );
    }
    final code = pairingCode.trim();

    final publicKey = await _guard(() => _keystore.createKey());
    final proof = await _guard(() => _keystore.sign(
          Uint8List.fromList(utf8.encode(code)),
          reason: 'Xác thực để ghép cặp thiết bị',
        ));

    final api = _api();
    try {
      final result = await api.enroll(
        pairingCode: code,
        publicKeyBase64: publicKey,
        platform: _platform,
        proofSignatureBase64: proof,
        deviceName: deviceName,
      );
      await _store.saveEnrollment(
        publicKey: publicKey,
        deviceId: result.deviceId,
        employeeId: result.employeeId,
        deviceName: deviceName,
        employeeCode: result.employeeCode,
        fullName: result.fullName,
        position: result.position,
        rank: result.rank,
      );
      return result;
    } catch (_) {
      // Enrollment failed server-side: drop the orphan hardware key so the next
      // attempt starts clean.
      await _guard(() => _keystore.deleteKey());
      rethrow;
    } finally {
      api.close();
    }
  }

  /// Records an attendance event:
  ///  1. ask the backend for a fresh challenge,
  ///  2. sign (nonce bytes || type) in hardware after a biometric check,
  ///  3. submit the signed challenge.
  Future<AttendanceEvent> recordAttendance(AttendanceType type) async {
    final deviceId = _store.deviceId;
    if (deviceId == null) {
      throw ApiException('Thiết bị chưa được ghép cặp.');
    }

    final api = _api();
    try {
      final challenge = await api.requestChallenge(deviceId);

      // Sign exactly what the backend re-builds: Base64decode(nonce) || UTF8(type).
      final signedMessage = Uint8List.fromList(<int>[
        ...base64Decode(challenge.challenge),
        ...utf8.encode(type.wireName),
      ]);
      final signature = await _guard(() => _keystore.sign(
            signedMessage,
            reason: 'Xác thực để ${type.label.toLowerCase()}',
          ));

      return await api.recordAttendance(
        challengeId: challenge.challengeId,
        type: type,
        signatureBase64: signature,
      );
    } finally {
      api.close();
    }
  }

  /// Daily check-in/out history for this device's officer (most recent first).
  Future<List<DailyHistory>> fetchHistory({int days = 30}) async {
    final deviceId = _store.deviceId;
    if (deviceId == null) {
      throw ApiException('Thiết bị chưa được ghép cặp.');
    }
    final api = _api();
    try {
      return await api.fetchHistory(deviceId, days: days);
    } finally {
      api.close();
    }
  }

  Future<void> unenroll() async {
    await _guard(() => _keystore.deleteKey());
    await _store.clearEnrollment();
  }
}
