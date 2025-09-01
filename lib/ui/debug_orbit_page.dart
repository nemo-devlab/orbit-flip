// lib/ui/debug_orbit_page.dart
// Optimized debug UI:
// - Static background painter (orbit ring).
// - Dynamic painter repaints via AnimationController (no setState each frame).
// - HUD throttled; obstacle culling throttled (3–4x/sec).
// - Sprites for obstacles (fast blits), lane caching, constant-speed fall.
// - 10 orbit-safe columns; black sizes (small/medium/large) change fall speed.
// - Two contact moments per obstacle (top & bottom).

import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui show Image, PictureRecorder; // for sprite creation
import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../engine/obstacle.dart';

class DebugOrbitPage extends StatefulWidget {
  const DebugOrbitPage({super.key});
  @override
  State<DebugOrbitPage> createState() => _DebugOrbitPageState();
}

class _DebugOrbitPageState extends State<DebugOrbitPage>
    with SingleTickerProviderStateMixin {
  late final OrbitEngine eng;
  late final AnimationController _loop;
  final GlobalKey _canvasKey = GlobalKey();

  // Base travel time (top → bottom). Increase to slow the fall.
  static const double kTravelMs = 6200;

  // Black size → speed multipliers (relative to kTravelMs)
  static const double _speedSmall = 0.75;  // faster (shorter travel time)
  static const double _speedMedium = 1.2;  // default-ish
  static const double _speedLarge = 1.6;   // slower (longer travel time)

  // Per-burst timing spread so waves aren’t straight lines
  static const double _kPerObstacleJitterMs = 600.0; // ±600 ms random
  static const double _kLaneStaggerMs = 120.0;       // 0,120,240,... ms

  // Draw radii
  static const double _rRed = 9;
  static const double _rBlackSmall = 7;
  static const double _rBlackMedium = 12;
  static const double _rBlackLarge = 17;

  // Mix of hazards (black %)
  static const double _pBlack = 0.3;

  // HUD + cull throttling
  double _lastHudMs = 0;
  double _lastCullMs = 0;
  int _lastScore = 0;
  bool _lastGameOver = false;

  // Sprites (cached tiny images) for fast drawing
  ui.Image? _spriteRed, _spriteBlkS, _spriteBlkM, _spriteBlkL;
  bool _spritesReady = false;

  @override
  void initState() {
    super.initState();
    // Strict-ish tolerance as per your last settings
    eng = OrbitEngine(toleranceRad: 0.2, angularSpeed: 1.4);

    _loop = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(() {
        eng.tick();

        final now = eng.tMs;

        // Throttled cull (3–4x/second) rather than every frame
        if (now - _lastCullMs > 300) {
          _lastCullMs = now;
          eng.obstacles.removeWhere(
            (o) => now > o.tContactMs + (o.travelMs ?? kTravelMs) + 800,
          );
        }

        // Throttle HUD updates (~8 fps) or when score/gameOver changes
        final hudDue = (now - _lastHudMs) > 125.0;
        if (hudDue || eng.score != _lastScore || eng.gameOver != _lastGameOver) {
          _lastHudMs = now;
          _lastScore = eng.score;
          _lastGameOver = eng.gameOver;
          if (mounted) setState(() {});
        }
        // No setState otherwise; canvas repaints via `repaint: _loop`.
      });

    // Build obstacle sprites once after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _spriteRed  = await _makeCircleSprite(_rRed,        Colors.red);
      _spriteBlkS = await _makeCircleSprite(_rBlackSmall, Colors.black);
      _spriteBlkM = await _makeCircleSprite(_rBlackMedium,Colors.black);
      _spriteBlkL = await _makeCircleSprite(_rBlackLarge, Colors.black);
      _spritesReady = true;
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  // Draw a circle with white stroke once; cache into an image sprite
  Future<ui.Image> _makeCircleSprite(double radius, Color fill) async {
    final w = (radius * 2 + 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), w.toDouble()));

    final center = Offset(w / 2, w / 2);
    final pFill = Paint()..color = fill..isAntiAlias = true;
    final pStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withOpacity(0.9)
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius, pFill);
    canvas.drawCircle(center, radius, pStroke);

    final pic = recorder.endRecording();
    return pic.toImage(w, w);
  }

  void _play() {
    if (eng.running) return;
    eng.start();
    _loop.repeat();
  }

  void _pause() {
    eng.pause();
    _loop.stop();
  }

  void _resume() {
    eng.resume();
    _loop.repeat();
  }

  void _reset() {
    eng.reset();
    _loop.stop();
    setState(() {}); // HUD reset
  }

  void _flipImmediate(TapDownDetails _) {
    eng.flipDirection(); // instant toggle
    // painter will repaint on next vsync; no setState
  }

  Size? _canvasSize() {
    final ctx = _canvasKey.currentContext;
    final rb = ctx?.findRenderObject() as RenderBox?;
    return rb?.size;
  }

  /// 10 orbit-safe columns:
  /// x spans [cx - 0.88R, cx + 0.88R], angle is the **top arc** intersection.
  List<double> _computeColumnAngles(Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r = math.min(size.width, size.height) * 0.32;

    final usableR = r * 0.88; // 12% margin from each side
    final minX = cx - usableR;
    final maxX = cx + usableR;
    final step = (maxX - minX) / 10.0;

    final angles = <double>[];
    for (int i = 0; i < 10; i++) {
      final x = minX + (i + 0.5) * step;
      final dx = x - cx;
      final inside = (r * r - dx * dx).clamp(0.0, double.infinity);
      final ry = math.sqrt(inside);
      final yTop = cy - ry;
      final thetaTop = math.atan2(yTop - cy, dx); // canvas coords
      angles.add(wrapAngle(thetaTop));
    }
    return angles;
  }

  // Spawns bursts; each obstacle gets top & bottom contact times and per-obstacle travelMs (black only).
  void _loadRain() {
    final size = _canvasSize() ?? MediaQuery.of(context).size;
    final angles = _computeColumnAngles(size);
    final rand = math.Random(101);

    final start = eng.tMs + kTravelMs + 600; // ensure spawn begins off-screen
    const bursts = 30; // total waves

    // Orbit geometry reused for timing
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r = math.min(size.width, size.height) * 0.32;

    const topY = -24.0;
    final bottomY = size.height + 24.0;

    final wave = <Obstacle>[];
    double t = start;

    for (int b = 0; b < bursts; b++) {
      final n = 4 + rand.nextInt(5); // 4..8 simultaneous
      final chosen = <int>{};
      double slowestTravelInBurst = kTravelMs;
      double latestTTopInBurst = t; // track latest top-contact in this burst

      for (int i = 0; i < n; i++) {
        int idx; int guard = 0;
        do { idx = rand.nextInt(angles.length); } while (chosen.contains(idx) && ++guard < 20);
        chosen.add(idx);

        final angleTop = angles[idx];

        // Exact orbit geometry → Y at top/bottom intersections for this lane
        final xTop = cx + r * math.cos(angleTop);
        final dx = xTop - cx;
        final inside = (r * r - dx * dx).clamp(0.0, double.infinity);
        final ry = math.sqrt(inside);
        final yTopContact = cy - ry;
        final yBottomContact = cy + ry;

        final fracTop    = ((yTopContact    - topY) / (bottomY - topY)).clamp(0.0, 1.0);
        final fracBottom = ((yBottomContact - topY) / (bottomY - topY)).clamp(0.0, 1.0);

        // Type/size/speed
        final isBlack = rand.nextDouble() < _pBlack;
        final type = isBlack ? ObType.black : ObType.red;

        ObSize? sizeTag;
        double travel = kTravelMs;
        if (isBlack) {
          final rPick = rand.nextDouble();
          if (rPick < 1 / 3) { sizeTag = ObSize.small;  travel = kTravelMs * _speedSmall;  }
          else if (rPick < 2 / 3) { sizeTag = ObSize.medium; travel = kTravelMs * _speedMedium; }
          else { sizeTag = ObSize.large;  travel = kTravelMs * _speedLarge;  }
        }

        // Per-obstacle timing spread inside burst
        final jitter  = (_kPerObstacleJitterMs * (rand.nextDouble() * 2 - 1)); // [-j, +j]
        final stagger = i * _kLaneStaggerMs;                                   // 0,120,240...
        final tTop    = t + jitter + stagger;                                  // de-synced
        final tBottom = tTop + (fracBottom - fracTop) * travel;

        wave.add(Obstacle(
          lane: Lane.top,
          type: type,
          tContactMs: tTop,           // top crossing
          tContactMs2: tBottom,       // bottom crossing
          contactWindowMs: 220,       // strict-ish
          angleRad: angleTop,         // lane angle = top arc
          size: sizeTag,              // (black only)
          travelMs: travel,           // per-obstacle travel duration
        ));

        if (travel > slowestTravelInBurst) slowestTravelInBurst = travel;
        if (tTop > latestTTopInBurst) latestTTopInBurst = tTop;
      }

      // Start next burst after the slowest in this burst has exited
      t = latestTTopInBurst + slowestTravelInBurst + 200;
    }

    eng.scheduleMany(wave);
    // No setState; canvas repaints on next tick via _loop
  }

  @override
  Widget build(BuildContext context) {
    final t = eng.tMs;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orbit Debug'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                't=${t.toStringAsFixed(0)}  score=${eng.score}  ${eng.gameOver ? "GAME OVER" : ""}',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // catch taps anywhere
              onTapDown: _flipImmediate,        // fire on finger-down (snappier)
              child: RepaintBoundary(
                key: _canvasKey,
                child: Stack(
                  children: [
                    // Static background ring (never repaints)
                    const CustomPaint(
                      painter: _OrbitBgPainter(),
                      child: SizedBox.expand(),
                    ),
                    // Dynamic layer (repaints via _loop)
                    CustomPaint(
                      painter: _OrbitPainter(
                        eng: eng,
                        repaint: _loop,
                        sprites: _spritesReady
                            ? _Sprites(
                                _spriteRed!, _spriteBlkS!,
                                _spriteBlkM!, _spriteBlkL!,
                              )
                            : null,
                      ),
                      isComplex: true,
                      willChange: true,
                      child: const SizedBox.expand(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(onPressed: _play, child: const Text('Play')),
              ElevatedButton(onPressed: _pause, child: const Text('Pause')),
              ElevatedButton(onPressed: _resume, child: const Text('Resume')),
              ElevatedButton(onPressed: _reset, child: const Text('Reset')),
              ElevatedButton(onPressed: _loadRain, child: const Text('Load Rain')),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Sprites {
  _Sprites(this.red, this.blkS, this.blkM, this.blkL);
  final ui.Image red, blkS, blkM, blkL;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.eng,
    this.sprites,
    Listenable? repaint,
  }) : super(repaint: repaint);

  final OrbitEngine eng;
  final _Sprites? sprites;

  // draw constants (reuse across paints)
  static const double kTravelMs = _DebugOrbitPageState.kTravelMs;
  static const double rRed = _DebugOrbitPageState._rRed;
  static const double rBlackSmall = _DebugOrbitPageState._rBlackSmall;
  static const double rBlackMedium = _DebugOrbitPageState._rBlackMedium;
  static const double rBlackLarge = _DebugOrbitPageState._rBlackLarge;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final orbitR = math.min(size.width, size.height) * 0.32;

    // Helper to place points on orbit
    Offset pointOnCircle(double theta) =>
        Offset(cx + orbitR * math.cos(theta), cy + orbitR * math.sin(theta));

    // Player (planet)
    final player = pointOnCircle(eng.playerTheta);
    final pFill = Paint()..color = Colors.blueAccent;
    canvas.drawCircle(player, 10, pFill);

    // Off-screen spawn/exit
    const topY = -24.0;
    final bottomY = size.height + 24.0;

    // Cache lane positions per unique angle
    final Map<double, Offset> laneCache = {};
    Offset laneFor(double angle) =>
        laneCache.putIfAbsent(angle, () => pointOnCircle(angle));

    // Inline y-mapper (uses per-obstacle travel when present)
    double? yAtTime(Obstacle o, double nowMs, double yTopContact) {
      final travel = o.travelMs ?? kTravelMs;
      final uTop = ((yTopContact - topY) / (bottomY - topY)).clamp(0.0, 1.0);
      final tSpawn = o.tContactMs - uTop * travel;
      final tExit = tSpawn + travel;
      if (nowMs < tSpawn || nowMs > tExit) return null;
      final u = ((nowMs - tSpawn) / travel).clamp(0.0, 1.0);
      return topY + (bottomY - topY) * u; // manual lerp
    }

    final now = eng.tMs;
    final obstacles = eng.obstacles; // no List.of() allocation
    final s = sprites;

    // Fallback paints for first frames (sprites not yet ready)
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withOpacity(0.9);
    final fillPaint = Paint();

    for (int i = 0; i < obstacles.length; i++) {
      final o = obstacles[i];
      final lane = laneFor(o.angle); // top-arc angle for lane
      final laneX = lane.dx;
      final yTopContact = lane.dy;

      final y = yAtTime(o, now, yTopContact);
      if (y == null) continue;

      final c = Offset(laneX, y);

      if (s == null) {
        // vector fallback (first frames only)
        double radius;
        if (o.type == ObType.red) {
          fillPaint.color = Colors.red;
          radius = rRed;
        } else {
          fillPaint.color = Colors.black;
          switch (o.size) {
            case ObSize.small:
              radius = rBlackSmall; break;
            case ObSize.large:
              radius = rBlackLarge; break;
            case ObSize.medium:
            default:
              radius = rBlackMedium; break;
          }
        }
        canvas.drawCircle(c, radius, fillPaint);
        canvas.drawCircle(c, radius, strokePaint);
      } else {
        // sprite blit (fast path)
        ui.Image img;
        if (o.type == ObType.red) {
          img = s.red;
        } else {
          switch (o.size) {
            case ObSize.small:  img = s.blkS; break;
            case ObSize.large:  img = s.blkL; break;
            case ObSize.medium:
            default:            img = s.blkM; break;
          }
        }
        final w = img.width.toDouble();
        final h = img.height.toDouble();
        final dst = Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h);
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, w, h), dst, Paint());
      }
    }
  }

  // With `repaint: listenable`, only repaint if the engine instance changes.
  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => oldDelegate.eng != eng;
}

// Static background painter: draws the orbit ring once.
class _OrbitBgPainter extends CustomPainter {
  const _OrbitBgPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5, cy = size.height * 0.5;
    final r  = math.min(size.width, size.height) * 0.32;
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
  @override
  bool shouldRepaint(covariant _OrbitBgPainter old) => false;
}
