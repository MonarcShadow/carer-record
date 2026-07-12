import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'presentation/auth/login_screen.dart';

void main() {
  runApp(const CarerRecordApp());
}

class CarerRecordApp extends StatelessWidget {
  const CarerRecordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carer Record',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const LoginScreen(),
    );
  }
}