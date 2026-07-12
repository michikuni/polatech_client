import 'dart:convert';

import 'package:flutter/services.dart';

/// Thrown when a hardware-keystore / biometric operation fails. [code] is the
/// platform error code (see the native handlers); [message] is user-facing.
class KeystoreException implements Exception {
  KeystoreException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => code == null ? message : '$message ($code)';
}

/// Wraps the native, hardware-backed signing identity:
///  * Android — a P-256 key in the **AndroidKeyStore** (`UserAuthenticationRequired`),
///  * iOS — a P-256 key in the **Secure Enclave** (biometry access control).
///
/// The private key is generated inside secure hardware and is **non-exportable**;
/// signing happens inside the hardware after a fingerprint/Face ID check. The
/// Dart side only ever sees the public key (SPKI, Base64) and DER signatures —
/// exactly the formats the backend already verifies.
class HardwareKeystore {
  const HardwareKeystore();

  static const MethodChannel _ch =
      MethodChannel('com.mpcorp.ca_attendance/keystore');

  /// True only if this device has secure-hardware keys AND an enrolled biometric
  /// the OS will accept. Enrollment is blocked when this is false.
  Future<bool> isAvailable() async {
    try {
      return (await _ch.invokeMethod<bool>('isAvailable')) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false; // unsupported platform (desktop/web)
    }
  }

  /// Generates a fresh hardware key (replacing any previous one) and returns its
  /// public key as Base64 X.509 SubjectPublicKeyInfo.
  Future<String> createKey() => _str('createKey');

  /// The current public key (Base64 SPKI), or null if no key exists yet.
  Future<String?> getPublicKey() async {
    try {
      return await _ch.invokeMethod<String>('getPublicKey');
    } on PlatformException catch (e) {
      throw _map(e);
    } on MissingPluginException {
      throw _unsupported();
    }
  }

  /// Signs [message] with SHA256withECDSA **inside the secure hardware**, after a
  /// biometric prompt showing [reason]. Returns the DER signature, Base64.
  Future<String> sign(Uint8List message, {required String reason}) =>
      _str('sign', {'message': base64Encode(message), 'reason': reason});

  /// Permanently removes the hardware key (used when re-pairing).
  Future<void> deleteKey() async {
    try {
      await _ch.invokeMethod<void>('deleteKey');
    } on PlatformException catch (e) {
      throw _map(e);
    } on MissingPluginException {
      throw _unsupported();
    }
  }

  Future<String> _str(String method, [Map<String, dynamic>? args]) async {
    try {
      final v = await _ch.invokeMethod<String>(method, args);
      if (v == null) throw KeystoreException('Lỗi khoá bảo mật: thiếu kết quả.');
      return v;
    } on PlatformException catch (e) {
      throw _map(e);
    } on MissingPluginException {
      throw _unsupported();
    }
  }

  KeystoreException _unsupported() => KeystoreException(
        'Thiết bị/nền tảng này không hỗ trợ khoá bảo mật phần cứng.',
        code: 'unsupported',
      );

  KeystoreException _map(PlatformException e) {
    final msg = switch (e.code) {
      'unavailable' =>
        'Thiết bị không có khoá bảo mật phần cứng hoặc chưa cài vân tay/Face ID.',
      'user_canceled' => 'Đã huỷ xác thực sinh trắc học.',
      'auth_failed' => 'Xác thực sinh trắc học thất bại.',
      'no_key' => 'Chưa có khoá thiết bị. Hãy ghép cặp lại.',
      'lockout' =>
        'Sinh trắc học tạm khoá do thử sai nhiều lần. Thử lại sau.',
      _ => e.message ?? 'Lỗi khoá bảo mật.',
    };
    return KeystoreException(msg, code: e.code);
  }
}
