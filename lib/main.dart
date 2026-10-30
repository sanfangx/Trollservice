import 'package:flutter/cupertino.dart';

import 'screens/dashboard_screen.dart';
import 'services/daemon_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = DaemonController();
  await controller.initialize();
  runApp(TrollServiceApp(controller: controller));
}

class TrollServiceApp extends StatelessWidget {
  final DaemonController controller;

  const TrollServiceApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'TrollService',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
      ),
      home: DashboardScreen(controller: controller),
    );
  }
}
