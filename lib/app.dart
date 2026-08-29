import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/ui_Dashboard.dart';

class EpmsApp extends StatelessWidget {
  const EpmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EPMS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const DashboardScreen(),
    );
  }
}
