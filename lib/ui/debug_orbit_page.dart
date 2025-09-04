// lib/ui/debug_orbit_page.dart
// Simpler & smoother (straight diagonals):
// - Max 5 obstacles on-screen (reactive spawner).
// - Faster fall, bigger obstacles.
// - TRUE straight-line diagonal fall (no wiggle).
// - Slightly smaller orbit (0.28 * minSide).
// - Static background + sprite blits + throttled HUD/cull.

import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui show Image, PictureRecorder;
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
  // ---------- Tunables ----------
  static const int _kCols = 10;                 // lanes across the orbit top arc
  static const int _kMaxOnscreen = 5;           // hard cap
  static const double _kOrbitFactor = 0.20;     // orbit radius = factor * minSide
  static const double _kTravelMs = 4500;        // base top→bottom time (faster)
  static const double _kSpawnCheckMin = 240;    // ms between spawn attempts (min)
  static const double _kSpawnCheckMax = 360;    // ms between spawn attempts (max)
  static const double _kUsableOrbitX = 0.88;    // keep lanes inside ±12% margin
  static const double _kHudThrottleMs = 200.0;  // HUD refresh interval (ms)

  // Straight-line slope range (dx per 1px of vertical)
  static const double _kSlopeMin = 0.12;
  static const double _kSlopeMax = 0.20;

  // Radii (bigger)
  static const double _rRed = 10;
  static const double _rBlackSmall = 8;
  static const double _rBlackMedium = 12;
  static const double _rBlackLarge = 16;

  // Black speed multipliers (still relative to base travel)
  static const double _speedSmall = 0.8;   // faster
  static const double _speedMedium = 1;  // default
  static const double _speedLarge = 1.25;   // slower (but still faster overall)

  // Black share (keep some variety)
  static const double _pBlack = 0.65;

  // ---------- Engine & loop ----------
  late final OrbitEngine eng;
  late final AnimationController _loop;
  final GlobalKey _canvasKey = GlobalKey();
  final math.Random _rng = math.Random();

  // HUD & cull throttling
  double _lastHudMs = 0;
  double _lastCullMs = 0;
  int _lastScore = 0;
  bool _lastGameOver = false;

  // Spawner throttling
  double _nextSpawnCheckMs = 0;

  // Sprites
  ui.Image? _spriteRed, _spriteBlkS, _spriteBlkM, _spriteBlkL;
  bool _spritesReady = false;

  // Cached column angles (recomputed when size changes)
  Size? _lastSize;
  List<double> _colAngles = const [];

  @override
  void initState() {
    super.initState();
    eng = OrbitEngine(toleranceRad: 0.2, angularSpeed: 1.6);

    _loop = AnimationController(vsync: this, duration: const Duration(days: 1))
      ..addListener(() {
        eng.tick();

        final now = eng.tMs;

        // ---- spawn reactively under cap ----
        if (eng.running && !eng.gameOver && now >= _nextSpawnCheckMs) {
          final size = _canvasSize() ?? MediaQuery.of(context).size;
          _ensureColumns(size);
          final onscreen = _visibleCount(now, size);
          if (onscreen < _kMaxOnscreen) {
            final toMake = math.min(1 + _rng.nextInt(2), _kMaxOnscreen - onscreen); // 1..2
            for (int i = 0; i < toMake; i++) {
              _spawnOne(now, size);
            }
          }
          // schedule next check with small jitter
          final jitter = _kSpawnCheckMin + _rng.nextDouble() * (_kSpawnCheckMax - _kSpawnCheckMin);
          _nextSpawnCheckMs = now + jitter;
        }

        // ---- throttled cull (3–4x/sec) ----
        if (now - _lastCullMs > 300) {
          _lastCullMs = now;
          // Cull objects a bit after their exit. Base on their own travel time.
          final size = _canvasSize() ?? MediaQuery.of(context).size;
          _ensureColumns(size);
          eng.obstacles.removeWhere((o) {
            final fracTop = _fracTopFor(size, o.angleTop);
            final travel = o.travelMs ?? _kTravelMs;
            final tSpawn = o.tContactMs - fracTop * travel;
            final tExit = tSpawn + travel;
            return now > tExit + 500; // grace
          });
        }

        // ---- HUD throttle ----
        final hudDue = (now - _lastHudMs) > _kHudThrottleMs;
        if (hudDue || eng.score != _lastScore || eng.gameOver != _lastGameOver) {
          _lastHudMs = now;
          _lastScore = eng.score;
          _lastGameOver = eng.gameOver;
          if (mounted) setState(() {});
        }
      });

    // Build sprites once after first frame
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

  // ---------- Helpers ----------

  Size? _canvasSize() {
    final ctx = _canvasKey.currentContext;
    final rb = ctx?.findRenderObject() as RenderBox?;
    return rb?.size;
  }

  void _ensureColumns(Size size) {
    if (_lastSize == size && _colAngles.isNotEmpty) return;
    _lastSize = size;
    _colAngles = _computeColumnAngles(size);
  }

  // Lanes across the top arc, kept inside ±12% margin to avoid tangent glitches
  List<double> _computeColumnAngles(Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r = math.min(size.width, size.height) * _kOrbitFactor;

    final usableR = r * _kUsableOrbitX; // 12% margin
    final minX = cx - usableR;
    final maxX = cx + usableR;
    final step = (maxX - minX) / _kCols;

    final angles = <double>[];
    for (int i = 0; i < _kCols; i++) {
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

  // fraction along topY→bottomY for the lane's top-contact Y
  double _fracTopFor(Size size, double angleTop) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r = math.min(size.width, size.height) * _kOrbitFactor;
    const topY = -24.0;
    final bottomY = size.height + 24.0;

    final xTop = cx + r * math.cos(angleTop);
    final yTop = cy + r * math.sin(angleTop);
    return ((yTop - topY) / (bottomY - topY)).clamp(0.0, 1.0);
  }

  // How many obstacles are currently visible on screen (ignoring consumed)
  int _visibleCount(double nowMs, Size size) {
    const topY = -24.0;
    final bottomY = size.height + 24.0;

    int count = 0;
    for (final o in eng.obstacles) {
      if (o.consumed) continue;
      final fracTop = _fracTopFor(size, o.angleTop);
      final travel = o.travelMs ?? _kTravelMs;
      final tSpawn = o.tContactMs - fracTop * travel;
      final tExit = tSpawn + travel;
      if (nowMs >= tSpawn && nowMs <= tExit) count++;
    }
    return count;
  }

  // Solve the second (bottom) intersection of a line with slope m and the orbit circle.
  // Line: x = xTop + m * (y - yTop), anchored at (xTop, yTop).
  // Returns (yBottom, angleBottom).
  ({double yBottom, double angleBottom}) _solveBottomFor(
      Size size, double angleTop, double m) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r  = math.min(size.width, size.height) * _kOrbitFactor;

    final xTop = cx + r * math.cos(angleTop);
    final yTop = cy + r * math.sin(angleTop);

    // Quadratic: A*y^2 + B*y + C = 0
    final p = (xTop - cx) - m * yTop;
    final A = m * m + 1.0;
    final B = 2.0 * (p * m - cy);
    final C = p * p + cy * cy - r * r;

    final disc = (B * B - 4.0 * A * C);
    final sqrtD = math.sqrt(disc < 0 ? 0 : disc);
    final y1 = (-B - sqrtD) / (2.0 * A);
    final y2 = (-B + sqrtD) / (2.0 * A);

    // One root is yTop. Pick the *other*, preferring the one below center.
    double yBottom;
    const eps = 1e-6;
    if ((y1 - yTop).abs() < eps) {
      yBottom = y2;
    } else if ((y2 - yTop).abs() < eps) {
      yBottom = y1;
    } else {
      // Fallback: choose the one greater than cy (below center), else the farthest from yTop.
      yBottom = (y1 > cy) ? y1 : (y2 > cy ? y2 : ((y1 - yTop).abs() > (y2 - yTop).abs() ? y1 : y2));
    }

    final xBottom = xTop + m * (yBottom - yTop);
    final angleBottom = wrapAngle(math.atan2(yBottom - cy, xBottom - cx));
    return (yBottom: yBottom, angleBottom: angleBottom);
  }

  void _spawnOne(double nowMs, Size size) {
    // pick a random lane
    final angleTop = _colAngles[_rng.nextInt(_colAngles.length)];

    // slope (dx per dy), small constant, random sign
    final mAbs = _kSlopeMin + _rng.nextDouble() * (_kSlopeMax - _kSlopeMin);
    final m = (_rng.nextBool() ? 1.0 : -1.0) * mAbs;

    // geometry for timing
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final r  = math.min(size.width, size.height) * _kOrbitFactor;
    const topY = -24.0;
    final bottomY = size.height + 24.0;

    final xTop = cx + r * math.cos(angleTop);
    final yTop = cy + r * math.sin(angleTop);

    final bot = _solveBottomFor(size, angleTop, m);
    final yBottom = bot.yBottom;
    final angleBottom = bot.angleBottom;

    // fractions along fall window
    final fracTop    = ((yTop    - topY) / (bottomY - topY)).clamp(0.0, 1.0);
    final fracBottom = ((yBottom - topY) / (bottomY - topY)).clamp(0.0, 1.0);

    // type: mostly red, some black
    final isBlack = _rng.nextDouble() < _pBlack;
    final type = isBlack ? ObType.black : ObType.red;

    // per-obstacle speed & size (black only)
    ObSize? sizeTag;
    double travel = _kTravelMs;
    if (isBlack) {
      final rPick = _rng.nextDouble();
      if (rPick < 1 / 3) { sizeTag = ObSize.small;  travel *= _speedSmall; }
      else if (rPick < 2 / 3) { sizeTag = ObSize.medium; travel *= _speedMedium; }
      else { sizeTag = ObSize.large;  travel *= _speedLarge; }
    }

    // tiny spawn jitter so starts aren't robotic
    final spawnDelay = _rng.nextDouble() * 60.0; // 0..60 ms
    final tSpawn = nowMs + spawnDelay;

    final tTop    = tSpawn + fracTop    * travel;
    final tBottom = tSpawn + fracBottom * travel;

    final o = Obstacle(
      lane: Lane.top,
      type: type,
      tContactMs: tTop,
      tContactMs2: tBottom,
      contactWindowMs: 220,
      angleRad: angleTop,
      angleBottomRad: angleBottom, // real diagonal bottom angle
      size: sizeTag,
      travelMs: travel,
      dxPerDy: m,                  // straight diagonal slope for painter
    );
    eng.scheduleMany([o]);
  }

  // ---------- Sprites ----------
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

  // ---------- Controls ----------
  void _play() {
    if (eng.running) return;
    eng.start();
    _loop.repeat();
    _nextSpawnCheckMs = eng.tMs; // allow immediate spawn check
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
    eng.flipDirection();
    // repaint will happen on next vsync via _loop
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
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _flipImmediate, // snappy flips
              child: RepaintBoundary(
                key: _canvasKey,
                child: Stack(
                  children: [
                    const CustomPaint( // static background ring
                      painter: _OrbitBgPainter(),
                      child: SizedBox.expand(),
                    ),
                    CustomPaint( // dynamic layer
                      painter: _OrbitPainter(
                        eng: eng,
                        sprites: _spritesReady
                            ? _Sprites(_spriteRed!, _spriteBlkS!, _spriteBlkM!, _spriteBlkL!)
                            : null,
                        repaint: _loop,
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
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// --------- Painter sprites holder ---------
class _Sprites {
  _Sprites(this.red, this.blkS, this.blkM, this.blkL);
  final ui.Image red, blkS, blkM, blkL;
}

// --------- Dynamic painter (straight diagonal) ---------
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.eng, this.sprites, Listenable? repaint})
      : super(repaint: repaint);

  final OrbitEngine eng;
  final _Sprites? sprites;

  static const double kTravelMs = _DebugOrbitPageState._kTravelMs;
  static const double kOrbitFactor = _DebugOrbitPageState._kOrbitFactor;

  static const double rRed = _DebugOrbitPageState._rRed;
  static const double rBlackSmall = _DebugOrbitPageState._rBlackSmall;
  static const double rBlackMedium = _DebugOrbitPageState._rBlackMedium;
  static const double rBlackLarge = _DebugOrbitPageState._rBlackLarge;

  @override
  void paint(Canvas canvas, Size size) {
    // Per-frame constants
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final orbitR = math.min(size.width, size.height) * kOrbitFactor;
    const topY = -24.0;
    final bottomY = size.height + 24.0;

    // Helpers
    Offset onOrbit(double theta) =>
        Offset(cx + orbitR * math.cos(theta), cy + orbitR * math.sin(theta));

    // Planet
    final planet = onOrbit(eng.playerTheta);
    canvas.drawCircle(planet, 10, Paint()..color = Colors.blueAccent);

    // Lane cache: angle→top-contact Offset on orbit
    final Map<double, Offset> laneCache = {};
    Offset laneTopOf(double angle) => laneCache.putIfAbsent(angle, () => onOrbit(angle));

    // Inline mappers
    double? yAtTime(Obstacle o, double nowMs, double yTop) {
      final travel = o.travelMs ?? kTravelMs;
      final uTop = ((yTop - topY) / (bottomY - topY)).clamp(0.0, 1.0);
      final tSpawn = o.tContactMs - uTop * travel;
      final tExit = tSpawn + travel;
      if (nowMs < tSpawn || nowMs > tExit) return null;
      final u = ((nowMs - tSpawn) / travel).clamp(0.0, 1.0);
      return topY + (bottomY - topY) * u;
    }

    final now = eng.tMs;
    final obstacles = eng.obstacles;
    final s = sprites;

    // Fallback paints (first frames before sprites ready)
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withOpacity(0.9);
    final fillPaint = Paint();

    for (int i = 0; i < obstacles.length; i++) {
      final o = obstacles[i];
      if (o.consumed) continue;

      final laneTop = laneTopOf(o.angleTop);
      final xTop = laneTop.dx;
      final yTop = laneTop.dy;

      final y = yAtTime(o, now, yTop);
      if (y == null) continue;

      // Straight-line x from constant slope (dx per dy)
      final m = o.dxPerDy ?? 0.0;
      final x = xTop + m * (y - yTop);
      final c = Offset(x, y);

      if (s == null) {
        // Vector fallback (rare; first frame)
        double radius;
        if (o.type == ObType.red) {
          fillPaint.color = Colors.red; radius = rRed;
        } else {
          fillPaint.color = Colors.black;
          switch (o.size) {
            case ObSize.small:  radius = rBlackSmall; break;
            case ObSize.large:  radius = rBlackLarge; break;
            case ObSize.medium:
            default:            radius = rBlackMedium; break;
          }
        }
        canvas.drawCircle(c, radius, fillPaint);
        canvas.drawCircle(c, radius, strokePaint);
      } else {
        // Sprite blit (fast path)
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
        final w = img.width.toDouble(), h = img.height.toDouble();
        final dst = Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h);
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, w, h), dst, Paint());
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.eng != eng;
}

// --------- Static background ring ---------
class _OrbitBgPainter extends CustomPainter {
  const _OrbitBgPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5, cy = size.height * 0.5;
    final r  = math.min(size.width, size.height) * _DebugOrbitPageState._kOrbitFactor;
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
