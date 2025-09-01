// lib/main.dart
import 'package:flutter/material.dart';
import 'ui/debug_orbit_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbit Debug',
      theme: ThemeData(useMaterial3: true),
      home: const DebugOrbitPage(),
    );
  }
}