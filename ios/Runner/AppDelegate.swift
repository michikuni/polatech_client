import CryptoKit
import Flutter
import LocalAuthentication
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeystorePlugin") {
      KeystorePlugin.register(with: registrar)
    }
  }
}

/// Hardware-backed P-256 signing identity in the **Secure Enclave**.
///
/// The private key is generated inside the Secure Enclave with a biometry access
/// control, so it never leaves hardware and every `SecKeyCreateSignature` is
/// gated by Face ID / Touch ID. Public key and signatures use the exact formats
/// the backend verifies: SPKI (X.509) Base64, and DER `SEQUENCE { r, s }` Base64.
///
/// Kept in AppDelegate.swift (already a member of the Runner target) so no Xcode
/// project edits are needed to compile it.
final class KeystorePlugin: NSObject, FlutterPlugin {

  private let tag = "com.mpcorp.ca_attendance.devicekey".data(using: .utf8)!

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.mpcorp.ca_attendance/keystore",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(KeystorePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(isAvailable())
    case "getPublicKey":
      // Deriving the public key does not require authentication.
      offload(result) { try self.publicKeyBase64() }
    case "createKey":
      offload(result) { try self.createKey() }
    case "deleteKey":
      deleteKey()
      result(nil)
    case "sign":
      guard
        let args = call.arguments as? [String: Any],
        let b64 = args["message"] as? String,
        let message = Data(base64Encoded: b64)
      else {
        result(FlutterError(code: "bad_args", message: "missing message", details: nil))
        return
      }
      let reason = (call.arguments as? [String: Any])?["reason"] as? String ?? "Xác thực"
      offload(result) { try self.sign(message, reason: reason) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Runs [work] off the main thread (Keychain auth blocks) and replies on it.
  private func offload(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      let reply: Any?
      do {
        reply = try work()
      } catch let e as KeystoreError {
        DispatchQueue.main.async { result(e.asFlutterError) }
        return
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "key_error", message: "\(error)", details: nil))
        }
        return
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  private func isAvailable() -> Bool {
    guard SecureEnclave.isAvailable else { return false }
    var error: NSError?
    return LAContext().canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &error)
  }

  private func createKey() throws -> String {
    deleteKey()
    var acError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
      &acError)
    else {
      throw KeystoreError("unavailable", "Không tạo được điều kiện truy cập sinh trắc học.")
    }

    let attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessControl as String: access,
      ],
    ]

    var error: Unmanaged<CFError>?
    guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
      throw KeystoreError("key_error", "Tạo khoá Secure Enclave thất bại: \(describe(error))")
    }
    guard let pub = SecKeyCopyPublicKey(priv) else {
      throw KeystoreError("key_error", "Không lấy được public key.")
    }
    return try spkiBase64(pub)
  }

  private func publicKeyBase64() throws -> String? {
    guard let priv = loadPrivateKey(context: nil),
          let pub = SecKeyCopyPublicKey(priv)
    else { return nil }
    return try spkiBase64(pub)
  }

  private func sign(_ message: Data, reason: String) throws -> String {
    let context = LAContext()
    context.localizedReason = reason
    guard let priv = loadPrivateKey(context: context) else {
      throw KeystoreError("no_key", "Chưa có khoá thiết bị.")
    }
    var error: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(
      priv, .ecdsaSignatureMessageX962SHA256, message as CFData, &error) as Data?
    else {
      throw mapSignError(error)
    }
    return sig.base64EncodedString()
  }

  private func loadPrivateKey(context: LAContext?) -> SecKey? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    if let context = context {
      query[kSecUseAuthenticationContext as String] = context
    }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let item = item else { return nil }
    // Safe: kSecClassKey + kSecReturnRef yields a SecKey.
    return (item as! SecKey)
  }

  private func deleteKey() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// Wraps the raw ANSI X9.63 EC point (`0x04 || X || Y`, 65 bytes) from
  /// SecKeyCopyExternalRepresentation in the fixed P-256 SPKI header — matching
  /// the Android keystore output and the backend's X509EncodedKeySpec.
  private func spkiBase64(_ pub: SecKey) throws -> String {
    var error: Unmanaged<CFError>?
    guard let raw = SecKeyCopyExternalRepresentation(pub, &error) as Data? else {
      throw KeystoreError("key_error", "Không xuất được public key: \(describe(error))")
    }
    let header: [UInt8] = [
      0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
      0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]
    var spki = Data(header)
    spki.append(raw)
    return spki.base64EncodedString()
  }

  private func mapSignError(_ error: Unmanaged<CFError>?) -> KeystoreError {
    guard let cf = error?.takeRetainedValue() else {
      return KeystoreError("auth_failed", "Ký thất bại.")
    }
    let code = CFErrorGetCode(cf)
    // LAError.userCancel == -2, .userFallback == -3, .systemCancel == -4;
    // OSStatus errSecUserCanceled == -128.
    switch code {
    case -2, -3, -4, -128:
      return KeystoreError("user_canceled", "Đã huỷ xác thực sinh trắc học.")
    case Int(LAError.biometryLockout.rawValue):
      return KeystoreError("lockout", "Sinh trắc học tạm khoá. Thử lại sau.")
    default:
      return KeystoreError("auth_failed", "Xác thực sinh trắc học thất bại.")
    }
  }

  private func describe(_ error: Unmanaged<CFError>?) -> String {
    guard let cf = error?.takeRetainedValue() else { return "unknown" }
    return CFErrorCopyDescription(cf) as String? ?? "unknown"
  }
}

private struct KeystoreError: Error {
  let code: String
  let message: String
  init(_ code: String, _ message: String) {
    self.code = code
    self.message = message
  }
  var asFlutterError: FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
