import 'package:flutter/material.dart';
import 'ui/home_page.dart';
import 'ui/game_page.dart';
import 'ui/game_over_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrbitFlipApp());
}

class OrbitFlipApp extends StatelessWidget {
  const OrbitFlipApp({super.key});

  static const kBgColor = Color(0xFF0B0E13);
  static const kAccent = Color(0xFF4DFFDB);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kAccent,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Orbit Flip',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: kBgColor,
        fontFamily: 'SF Pro', // system default; swap if you prefer
      ),
      routes: {
        '/': (_) => const HomePage(),
        '/game': (_) => const GamePage(),
        '/over': (_) => const GameOverPage(),
        // Add your debug page route here if you want:
        // '/debug': (_) => const DebugOrbitPage(),
      },
    );
  }
}
