import 'dart:convert';
import 'dart:typed_data';

import 'package:ca_attendance/crypto/ec_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceIdentity', () {
    test('public key is a 91-byte P-256 X.509 SPKI', () {
      final id = DeviceIdentity.generate();
      final der = base64Decode(id.publicKeyBase64);
      expect(der.length, 91);
      // SEQUENCE, total content 0x59, then nested AlgorithmIdentifier SEQUENCE.
      expect(der[0], 0x30);
      expect(der[1], 0x59);
      expect(der[2], 0x30);
      // Uncompressed EC point marker right after the 26-byte header.
      expect(der[26], 0x04);
    });

    test('signature is DER and re-sign is deterministic (RFC 6979)', () {
      final id = DeviceIdentity.generate();
      final msg = Uint8List.fromList(utf8.encode('ABCDEFGH23'));
      final sig1 = id.signToBase64(msg);
      final sig2 = id.signToBase64(msg);
      expect(sig1, sig2, reason: 'deterministic k => identical signatures');

      final der = base64Decode(sig1);
      expect(der[0], 0x30, reason: 'DER SEQUENCE tag');
      expect(der[2], 0x02, reason: 'first element is an INTEGER (r)');
      // SEQUENCE length byte matches the remaining bytes.
      expect(der[1], der.length - 2);
    });

    test('private-key round-trip preserves the public key', () {
      final id = DeviceIdentity.generate();
      final reborn = DeviceIdentity.fromPrivateHex(id.privateHex);
      expect(reborn.publicKeyBase64, id.publicKeyBase64);

      // ...and signs identically for the same message.
      final msg = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      expect(reborn.signToBase64(msg), id.signToBase64(msg));
    });

    test('different messages produce different signatures', () {
      final id = DeviceIdentity.generate();
      final a = id.signToBase64(Uint8List.fromList(utf8.encode('CHECK_IN')));
      final b = id.signToBase64(Uint8List.fromList(utf8.encode('CHECK_OUT')));
      expect(a, isNot(b));
    });
  });
}
