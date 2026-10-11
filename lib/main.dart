import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dashboard_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const VehicleScannerApp());
}

class VehicleScannerApp extends StatelessWidget {
  const VehicleScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vehicle Scanner',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const DashboardScreen(),
    );
  }
}
