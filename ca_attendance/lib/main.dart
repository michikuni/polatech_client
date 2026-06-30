import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/enroll_page.dart';
import 'ui/server_setup_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.create();
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const AttendanceApp(),
    ),
  );
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chấm công',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootPage(),
    );
  }
}

/// Routes between the top-level screens purely from [AppState.screen].
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final screen = context.watch<AppState>().screen;
    switch (screen) {
      case AppScreen.serverSetup:
        return const ServerSetupPage();
      case AppScreen.enroll:
        return const EnrollPage();
      case AppScreen.attendance:
        return const HomeShell();
    }
  }
}
