// lib/ui/home_page.dart
//
// Home screen for Orbit Flip.
// - Dark minimal layout with soft glow and rounded cards.
// - Shows Best Score (from SharedPreferences via Prefs service).
// - Big Play button → Navigator.pushNamed('/game').
// - Settings sheet with stub toggles (sound / haptics).
//
// If you’re using GameBindings, you can pass them when navigating:
//    Navigator.pushNamed(context, '/game', arguments: YourBindings.create());
//
// Requires: lib/services/prefs.dart

import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../services/prefs.dart';
import 'production_bindings.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _bg = Color(0xFF0B0E13);
  static const Color _card = Color(0xFF141821);
  static const Color _accent = Color(0xFF4DFFDB);

  int _best = 0;
  Timer? _initialPoll;

  @override
  void initState() {
    super.initState();
    _loadBest();
    // tiny delayed re-check so hot-reload shows fresh value
    _initialPoll = Timer(const Duration(milliseconds: 12), _loadBest);
  }

  @override
  void dispose() {
    _initialPoll?.cancel();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final b = await Prefs.getBestScore();
    if (mounted) setState(() => _best = b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _Starfield(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top bar — Settings (stub)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings_rounded,
                            color: Colors.white70),
                        onPressed: _openSettings,
                        tooltip: 'Settings',
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Title + tagline
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'ORBIT\nFLIP',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                height: 0.95,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'LUMINOUS SPACE ADVENTURE',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.white70,
                                letterSpacing: 2,
                              ),
                        ),
                        const SizedBox(height: 36),
                        // Play button
                        _GlowCircleButton(
                          size: 112,
                          onPressed: () {
                            // If you have GameBindings, pass them as arguments here.
                            final bindings = ProductionBindings.create(context);
                            Navigator.pushNamed(context, '/game', arguments: bindings);
                          },
                          child: const Icon(Icons.play_arrow,
                              size: 42, color: Colors.black87),
                        ),
                        const SizedBox(height: 34),
                        // Best score card
                        _BestScoreCard(value: _best),
                        const SizedBox(height: 10),
                        // tiny accent ping (subtle glow dot)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _accent.withOpacity(0.95),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withOpacity(0.45),
                                blurRadius: 18,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SettingsSheet(),
    );
  }
}

/// Rounded card that mirrors the reference look.
class _BestScoreCard extends StatelessWidget {
  final int value;
  const _BestScoreCard({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'BEST SCORE',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(width: 12),
          Text(
            _fmt(value),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - 1 - i;
      buf.write(s[idx]);
      if ((i + 1) % 3 == 0 && idx != 0) buf.write(',');
    }
    return buf.toString().split('').reversed.join();
  }
}

/// Big circular glowing CTA used for Play.
class _GlowCircleButton extends StatelessWidget {
  final double size;
  final Widget child;
  final VoidCallback onPressed;

  const _GlowCircleButton({
    required this.size,
    required this.child,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFCDCDCD)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33FFFFFF),
                blurRadius: 36,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Settings bottom sheet (stub toggles).
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  bool sound = true;
  bool haptics = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.only(top: 12, left: 16, right: 16, bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            _settingRow('Sound', sound, (v) => setState(() => sound = v)),
            _settingRow('Haptics', haptics, (v) => setState(() => haptics = v)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// Subtle starfield background (no allocations in paint).
class _Starfield extends StatelessWidget {
  const _Starfield();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _StarPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x14FFFFFF);
    // Deterministic pseudo-random spread; tiny dots for texture.
    for (int i = 0; i < 120; i++) {
      final x = ((i * 73 + 97) % size.width).toDouble();
      final y = ((i * 111 + 53) % size.height).toDouble();
      canvas.drawCircle(Offset(x, y), 0.8 + (i % 3) * 0.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
