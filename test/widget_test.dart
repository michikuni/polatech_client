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

    // No base URL yet => the first screen asks for the server address.
    expect(find.text('Kết nối máy chủ'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });
}
