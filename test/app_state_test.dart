import 'package:ca_attendance/data/pairing_qr.dart';
import 'package:ca_attendance/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The keys [LocalStore] writes; an enrolled device is simulated by seeding them.
Map<String, Object> _enrolledPrefs(String baseUrl) => {
      'base_url': baseUrl,
      'device_public_key': 'ignored-in-these-tests',
      'device_id': 7,
      'employee_id': 3,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connect-only QR re-points an enrolled device without losing pairing', () async {
    SharedPreferences.setMockInitialValues(_enrolledPrefs('http://192.168.1.10:8080'));
    final state = await AppState.create();
    expect(state.screen, AppScreen.attendance);

    // The server came back on a new IP; the admin shows the portal's server QR.
    final error = await state.applyPairingQr(
      PairingQr.parse('{"url":"http://192.168.1.55:8080"}')!,
    );

    expect(error, isNull);
    expect(state.baseUrl, 'http://192.168.1.55:8080');
    expect(state.deviceId, 7, reason: 'the hardware key and pairing must survive');
    expect(state.screen, AppScreen.attendance);
    expect(state.takePendingPairingCode(), isNull);
  });

  test('pairing QR configures the address and hands the code to the enroll screen',
      () async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.create();
    expect(state.screen, AppScreen.serverSetup);

    final error = await state.applyPairingQr(
      PairingQr.parse('{"url":"http://192.168.1.10:8080","code":"ABCDEFGH23"}')!,
    );

    expect(error, isNull);
    expect(state.baseUrl, 'http://192.168.1.10:8080');
    expect(state.screen, AppScreen.enroll);
    expect(state.takePendingPairingCode(), 'ABCDEFGH23');
    expect(state.takePendingPairingCode(), isNull, reason: 'handed over exactly once');
  });

  test('connect-only QR on an unpaired device saves the address but asks for a code',
      () async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.create();

    final error = await state.applyPairingQr(
      PairingQr.parse('{"url":"http://192.168.1.10:8080"}')!,
    );

    expect(error, contains('chưa ghép cặp'));
    expect(state.baseUrl, 'http://192.168.1.10:8080');
    expect(state.screen, AppScreen.enroll);
  });
}
