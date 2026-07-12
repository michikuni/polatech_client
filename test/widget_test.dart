import 'package:ca_attendance/main.dart';
import 'package:ca_attendance/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('fresh install lands on the server setup screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.create();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const AttendanceApp(),
      ),
    );
    await tester.pumpAndSettle();

    // No base URL yet => the first screen asks how to reach the server. The scan
    // leads (the QR carries the address); the IP form stays hidden until asked
    // for.
    expect(find.text('Kết nối máy chủ'), findsOneWidget);
    expect(find.text('Quét mã QR'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.text('Không quét được? Nhập địa chỉ thủ công'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsOneWidget);
  });
}
