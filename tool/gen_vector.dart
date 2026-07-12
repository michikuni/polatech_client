// Generates an interop test vector with the SAME crypto the app uses, so it can
// be checked against the backend's real JDK verifier (SHA256withECDSA + X.509).
//
//   dart run tool/gen_vector.dart <output-file>
//
// Output file format (one token per line):
//   line 1: public key  (X.509 SPKI, Base64)
//   line 2: message #1   (Base64 of signed bytes)   -- enroll case
//   line 3: signature #1 (DER ECDSA, Base64)
//   line 4: message #2   (Base64 of signed bytes)   -- attendance case
//   line 5: signature #2 (DER ECDSA, Base64)
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ca_attendance/crypto/ec_signer.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'vector.txt';

  final id = DeviceIdentity.generate();

  // Round-trip the private key through persistence and make sure the rebuilt
  // identity has the same public key (otherwise stored keys would break).
  final reborn = DeviceIdentity.fromPrivateHex(id.privateHex);
  if (reborn.publicKeyBase64 != id.publicKeyBase64) {
    stderr.writeln('FATAL: private-key round-trip changed the public key');
    exit(2);
  }

  // Case 1 — enrollment proof: sign UTF-8(pairingCode).
  final pairingCode = 'ABCDEFGH23';
  final enrollMsg = Uint8List.fromList(utf8.encode(pairingCode));
  final enrollSig = id.signToBase64(enrollMsg);

  // Case 2 — attendance: sign (32-byte nonce bytes || UTF-8("CHECK_IN")).
  final rnd = Random.secure();
  final nonce = Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
  final attMsg = Uint8List.fromList(<int>[...nonce, ...utf8.encode('CHECK_IN')]);
  final attSig = id.signToBase64(attMsg);

  File(outPath).writeAsStringSync(
    <String>[
      id.publicKeyBase64,
      base64Encode(enrollMsg),
      enrollSig,
      base64Encode(attMsg),
      attSig,
    ].join('\n'),
  );
  stdout.writeln('wrote vector to $outPath');
}
