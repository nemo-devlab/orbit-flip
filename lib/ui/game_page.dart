import 'dart:async';
import 'dart:math' as Math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'widgets/score_text.dart';
import 'widgets/pause_overlay.dart';

/// ---- Bindings you will connect to your existing engine/painter ----
/// Provide a factory that returns your CustomPainter with `repaint` listenable.
/// Keep your engine ticking in [tick], flip on tap via [flip], expose
/// [score] and [isGameOver]. This keeps GamePage UI-agnostic & perf-safe.
typedef PainterFactory = CustomPainter Function(Listenable repaint);

class GameBindings {
  final void Function(int dtMs) tick;
  final void Function() flip;
  final int Function() score;
  final bool Function() isGameOver;
  final PainterFactory painterFactory;

  GameBindings({
    required this.tick,
    required this.flip,
    required this.score,
    required this.isGameOver,
    required this.painterFactory,
  });
}

/// Optional null bindings so the page compiles before you wire the engine.
/// It draws a faint ring & dot but does not simulate gameplay.
class _NullBindings extends GameBindings {
  _NullBindings()
      : super(
          tick: (_) {},
          flip: () {},
          score: () => 0,
          isGameOver: () => false,
          painterFactory: (repaint) => _PlaceholderPainter(repaint),
        );
}

/// -------------------------------------------------------------------

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  /// Pass real bindings via route arguments if you want:
  /// Navigator.pushNamed(context, '/game', arguments: yourBindings);
  static GameBindings _bindingsFrom(Object? args) =>
      (args is GameBindings) ? args : _NullBindings();

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  static const int _kHudThrottleMs = 150; // tune 150–300
  late final AnimationController _controller;
  late GameBindings _bindings;

  // HUD state (throttled)
  int _score = 0;
  Timer? _hudTimer;

  bool _paused = false;
  bool _handledGameOver = false;
  late int _lastMs;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(_onFrame)
      ..repeat(min: 0.0, max: 1.0, period: const Duration(milliseconds: 16)); // ~60Hz

    _hudTimer = Timer.periodic(
      const Duration(milliseconds: _kHudThrottleMs),
      (_) => setState(() => _score = _bindings.score()),
    );
    _lastMs = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindings =
        GamePage._bindingsFrom(ModalRoute.of(context)?.settings.arguments);
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onFrame() {
    // No per-frame setState. Only tick engine and check game-over.
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = now - _lastMs;
    _lastMs = now;
    _bindings.tick(dt);

    if (!_handledGameOver && _bindings.isGameOver()) {
      _handledGameOver = true;
      _controller.stop();
      final finalScore = _bindings.score();
      // Defer a frame to avoid Navigator during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/over', arguments: finalScore);
      });
    }
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _controller.stop();
      } else {
        _handledGameOver = false; // resume if not over
        _controller.repeat(
            min: 0.0, max: 1.0, period: const Duration(milliseconds: 16));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Gameplay canvas
            RepaintBoundary(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _bindings.flip,
                child: CustomPaint(
                  painter: _bindings.painterFactory(_controller),
                  size: Size.infinite,
                ),
              ),
            ),

            // HUD
            Positioned(
              left: 16,
              right: 16,
              top: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ScoreText(label: 'Current Score', value: _score),
                  IconButton(
                    onPressed: _togglePause,
                    icon: const Icon(Icons.pause_rounded, color: Colors.white),
                    tooltip: 'Pause',
                  ),
                ],
              ),
            ),

            if (_paused)
              PauseOverlay(
                onResume: _togglePause,
                onQuit: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// Simple placeholder painter so the page compiles even before wiring.
class _PlaceholderPainter extends CustomPainter {
  final Listenable repaint;
  _PlaceholderPainter(this.repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.shortestSide * 0.28);
    final bg = Paint()
      ..color = const Color(0xFF0B0E13)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bg);

    final orbit = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(c, r, orbit);

    final dotPaint = Paint()..color = Colors.white.withOpacity(0.9);
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final angle = (t % 6.28318);
    final pos = Offset(c.dx + r * MathCos(angle), c.dy + r * MathSin(angle));
    canvas.drawCircle(pos, 8, dotPaint);
  }

  double MathCos(double x) => Math.sin(x + 1.57079632679); // cheap cos via sin
  double MathSin(double x) => Math.sin(x);

  @override
  bool shouldRepaint(covariant _PlaceholderPainter oldDelegate) => true;
}
