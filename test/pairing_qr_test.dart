import 'package:ca_attendance/data/pairing_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingQr.parse', () {
    test('reads the server address and code from a portal QR', () {
      final qr = PairingQr.parse(
        '{"url":"http://192.168.1.10:8080","code":"ABCDEFGH23"}',
      );
      expect(qr!.baseUrl, 'http://192.168.1.10:8080');
      expect(qr.code, 'ABCDEFGH23');
    });

    test('strips a trailing slash off the address', () {
      final qr = PairingQr.parse('{"url":"http://10.0.0.5:8080/","code":"AB2"}');
      expect(qr!.baseUrl, 'http://10.0.0.5:8080');
    });

    test('upper-cases the code, matching the server alphabet', () {
      expect(PairingQr.parse('{"url":"http://h:8080","code":"ab2"}')!.code, 'AB2');
    });

    test('accepts a bare code (legacy QR) with no address', () {
      final qr = PairingQr.parse(' abcdefgh23 ');
      expect(qr!.code, 'ABCDEFGH23');
      expect(qr.baseUrl, isNull);
    });

    test('accepts a connect-only QR: address, no pairing code', () {
      final qr = PairingQr.parse('{"url":"http://192.168.1.20:8080"}');
      expect(qr!.baseUrl, 'http://192.168.1.20:8080');
      expect(qr.code, isNull);
    });

    test('ignores a non-http address rather than trusting it', () {
      final qr = PairingQr.parse('{"url":"ftp://evil/","code":"AB2"}');
      expect(qr!.code, 'AB2');
      expect(qr.baseUrl, isNull);
    });

    test('rejects QRs carrying neither a code nor a usable address', () {
      expect(PairingQr.parse(''), isNull);
      expect(PairingQr.parse('   '), isNull);
      expect(PairingQr.parse('{}'), isNull);
      expect(PairingQr.parse('{"url":"ftp://evil/"}'), isNull);
      expect(PairingQr.parse('{not json'), isNull);
    });
  });
}
