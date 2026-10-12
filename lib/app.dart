import 'package:flutter/material.dart';

import 'controllers/auth_controller.dart';
import 'controllers/farm_controller.dart';
import 'core/theme/app_theme.dart';
import 'views/app_shell.dart';
import 'views/login_view.dart';
import 'views/splash_view.dart';

class TechnovateFarmApp extends StatefulWidget {
  const TechnovateFarmApp({super.key});

  @override
  State<TechnovateFarmApp> createState() => _TechnovateFarmAppState();
}

class _TechnovateFarmAppState extends State<TechnovateFarmApp> {
  final farm = FarmController.instance;
  final auth = AuthController.instance;

  @override
  void initState() {
    super.initState();
    // Every record and account change is logged with the signed-in user's name.
    farm.actor = () => auth.currentUser?.name;
    // Every write is checked against the signed-in user's rights.
    farm.access = () => auth.access;
    auth.onAudit = farm.log;
    _start();
  }

  Future<void> _start() async {
    await farm.init();
    await auth.init();
    // Notes from data migration (e.g. retired roles) go to the activity log.
    for (final notice in auth.pendingNotices) {
      await farm.log(notice);
    }
    auth.pendingNotices.clear();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'DeshIT-BD',
        theme: AppTheme.light,
        home: ListenableBuilder(
          listenable: Listenable.merge([farm, auth]),
          builder: (context, _) {
            if (!farm.ready || !auth.ready) return const SplashScreen();
            final user = auth.currentUser;
            if (user == null) return const LoginPage();
            // Keyed by user so navigation resets when someone else signs in.
            return AppShell(key: ValueKey(user.username), user: user);
          },
        ),
      );
}
