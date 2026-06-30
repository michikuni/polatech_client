import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Elliptic-curve identity of the device.
///
/// Holds an EC **P-256 (secp256r1)** key pair and produces signatures that the
/// backend verifies with the Java `SHA256withECDSA` scheme. Only the public key
/// ever leaves the device; the private scalar `d` is what we persist locally.
///
/// Wire formats are chosen to match the backend exactly:
///  * public key  -> X.509 `SubjectPublicKeyInfo`, DER, standard Base64
///  * signature   -> DER `SEQUENCE { INTEGER r, INTEGER s }`, standard Base64
class DeviceIdentity {
  DeviceIdentity._(this._privateKey, this._publicKey);

  final ECPrivateKey _privateKey;
  final ECPublicKey _publicKey;

  static const String _curveName = 'secp256r1';

  /// Fixed DER prefix of an X.509 SubjectPublicKeyInfo for a P-256 public key.
  /// Everything after these 26 bytes is the 65-byte uncompressed EC point
  /// (`0x04 || X(32) || Y(32)`).
  static const List<int> _spkiP256Header = <int>[
    0x30, 0x59, // SEQUENCE (89 bytes)
    0x30, 0x13, //   SEQUENCE (19 bytes) AlgorithmIdentifier
    0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, // OID ecPublicKey
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, // OID prime256v1
    0x03, 0x42, 0x00, //   BIT STRING (66 bytes; 0 unused bits)
  ];

  /// Generates a brand-new device key pair.
  factory DeviceIdentity.generate() {
    final domain = ECDomainParameters(_curveName);
    final keyGen = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(domain),
          _secureRandom(),
        ),
      );
    final pair = keyGen.generateKeyPair();
    return DeviceIdentity._(
      pair.privateKey as ECPrivateKey,
      pair.publicKey as ECPublicKey,
    );
  }

  /// Re-creates an identity from a previously persisted private scalar (hex).
  factory DeviceIdentity.fromPrivateHex(String hex) {
    final domain = ECDomainParameters(_curveName);
    final d = BigInt.parse(hex, radix: 16);
    final q = domain.G * d;
    return DeviceIdentity._(
      ECPrivateKey(d, domain),
      ECPublicKey(q, domain),
    );
  }

  /// The private scalar as hex — the only secret we persist on the device.
  String get privateHex => _privateKey.d!.toRadixString(16);

  /// X.509 SubjectPublicKeyInfo (DER) for this key, Base64-encoded.
  /// This is exactly what the backend feeds to `X509EncodedKeySpec`.
  String get publicKeyBase64 {
    final point = _publicKey.Q!.getEncoded(false); // 0x04 || X || Y (65 bytes)
    if (point.length != 65) {
      throw StateError('Unexpected EC point length: ${point.length}');
    }
    final spki = Uint8List(_spkiP256Header.length + point.length)
      ..setRange(0, _spkiP256Header.length, _spkiP256Header)
      ..setRange(_spkiP256Header.length, _spkiP256Header.length + point.length,
          point);
    return base64Encode(spki);
  }

  /// Signs [message] with SHA256withECDSA and returns the DER signature, Base64.
  String signToBase64(Uint8List message) {
    // Deterministic (RFC 6979) k => no RNG needed and reproducible; the inner
    // SHA256Digest makes generateSignature hash the message itself, matching
    // Java's "SHA256withECDSA". Wrapped to always emit a normalized low-S sig.
    final signer = NormalizedECDSASigner(
      ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64)),
    )..init(true, PrivateKeyParameter<ECPrivateKey>(_privateKey));
    final sig = signer.generateSignature(message) as ECSignature;
    return base64Encode(_encodeDerSignature(sig.r, sig.s));
  }

  /// DER-encodes an ECDSA signature as `SEQUENCE { INTEGER r, INTEGER s }`.
  static Uint8List _encodeDerSignature(BigInt r, BigInt s) {
    final rEnc = _derInteger(r);
    final sEnc = _derInteger(s);
    final body = Uint8List(rEnc.length + sEnc.length)
      ..setRange(0, rEnc.length, rEnc)
      ..setRange(rEnc.length, rEnc.length + sEnc.length, sEnc);
    return _tlv(0x30, body); // SEQUENCE
  }

  /// Encodes a non-negative [value] as a DER INTEGER (minimal, with a leading
  /// 0x00 when the high bit is set so it is read as positive).
  static Uint8List _derInteger(BigInt value) {
    var bytes = _unsignedBytes(value);
    if (bytes.isEmpty) bytes = Uint8List(1); // value 0 -> single 0x00
    if (bytes[0] & 0x80 != 0) {
      final padded = Uint8List(bytes.length + 1)..setRange(1, bytes.length + 1, bytes);
      bytes = padded;
    }
    return _tlv(0x02, bytes); // INTEGER
  }

  /// Big-endian byte representation of a non-negative BigInt, no leading zeros.
  static Uint8List _unsignedBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List(0);
    final out = <int>[];
    var v = value;
    final mask = BigInt.from(0xff);
    while (v > BigInt.zero) {
      out.add((v & mask).toInt());
      v = v >> 8;
    }
    return Uint8List.fromList(out.reversed.toList());
  }

  /// Tag-length-value with DER definite length encoding.
  static Uint8List _tlv(int tag, Uint8List content) {
    final len = content.length;
    final List<int> header;
    if (len < 0x80) {
      header = <int>[tag, len];
    } else {
      final lenBytes = _unsignedBytes(BigInt.from(len));
      header = <int>[tag, 0x80 | lenBytes.length, ...lenBytes];
    }
    return Uint8List.fromList(<int>[...header, ...content]);
  }

  static SecureRandom _secureRandom() {
    final fortuna = FortunaRandom();
    final rnd = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => rnd.nextInt(256)),
    );
    fortuna.seed(KeyParameter(seed));
    return fortuna;
  }
}
