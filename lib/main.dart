import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/monitor.dart';
import 'data/notifier.dart';
import 'data/session.dart';
import 'theme.dart';
import 'ui/login_page.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.bar,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final session = SessionController()..restore();
  SystemNotifier.instance.init();
  BackgroundMonitor.init();
  runApp(RigDeckApp(session: session));
}

class RigDeckApp extends StatelessWidget {
  const RigDeckApp({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RigDeck',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.restoring) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final backend = session.backend;
          if (backend == null) return LoginPage(session: session);
          // A new backend (another login or demo) gets fresh stores and pages.
          return Shell(key: ObjectKey(backend), session: session, backend: backend);
        },
      ),
    );
  }
}
