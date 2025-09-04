// lib/ui/production_bindings.dart
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../engine/engine.dart';
import '../engine/obstacle.dart';
import 'game_page.dart';                 // for GameBindings typedefs
import 'debug_orbit_page.dart' show createProductionPainter; 
// we'll add this function in step C

class ProductionBindings {
  static GameBindings create(BuildContext context) {
    final eng = OrbitEngine(toleranceRad: 0.2, angularSpeed: 1.6);

    // ---- spawner state (ported from debug page) ----
    const kCols = 10;
    const kMaxOnscreen = 5;
    const kTravelMs = 4500.0;
    const kSpawnCheckMin = 240.0, kSpawnCheckMax = 360.0;
    const kUsableOrbitX = 0.88;
    const kSlopeMin = 0.12, kSlopeMax = 0.20;
    const topY = -24.0;

    final rng = math.Random();
    double nextSpawnCheckMs = 0.0;
    List<double> colAngles = const [];
    Size? lastSize;

    List<double> _computeColumnAngles(Size size) {
      final cx = size.width * 0.5, cy = size.height * 0.5;
      final r = (size.width < size.height ? size.width : size.height) * 0.20; // match debug
      final usableR = r * kUsableOrbitX;
      final minX = cx - usableR, maxX = cx + usableR;
      final step = (maxX - minX) / kCols;
      final angles = <double>[];
      for (int i = 0; i < kCols; i++) {
        final x = minX + (i + 0.5) * step;
        final dx = x - cx;
        final inside = (r * r - dx * dx).clamp(0.0, double.infinity);
        final ry = math.sqrt(inside);
        final yTop = cy - ry;
        final thetaTop = math.atan2(yTop - cy, dx);
        angles.add(thetaTop); // wrap not necessary here
      }
      return angles;
    }

    ({double yBottom, double angleBottom}) _solveBottomFor(Size size, double angleTop, double m) {
      final cx = size.width * 0.5, cy = size.height * 0.5;
      final r = (size.width < size.height ? size.width : size.height) * 0.20;
      final xTop = cx + r * math.cos(angleTop);
      final yTop = cy + r * math.sin(angleTop);
      final p = (xTop - cx) - m * yTop;
      final A = m * m + 1.0;
      final B = 2.0 * (p * m - cy);
      final C = p * p + cy * cy - r * r;
      final disc = (B * B - 4.0 * A * C);
      final sqrtD = math.sqrt(disc < 0 ? 0 : disc);
      final y1 = (-B - sqrtD) / (2.0 * A);
      final y2 = (-B + sqrtD) / (2.0 * A);
      final eps = 1e-6;
      double yBottom;
      if ((y1 - yTop).abs() < eps) {
        yBottom = y2;
      } else if ((y2 - yTop).abs() < eps) {
        yBottom = y1;
      } else {
        yBottom = (y1 > cy) ? y1 : (y2 > cy ? y2 : ((y1 - yTop).abs() > (y2 - yTop).abs() ? y1 : y2));
      }
      final xBottom = xTop + m * (yBottom - yTop);
      final angleBottom = math.atan2(yBottom - cy, xBottom - cx);
      return (yBottom: yBottom, angleBottom: angleBottom);
    }

    int _visibleCount(double nowMs, Size size) {
      final bottomY = size.height + 24.0;
      int count = 0;
      for (final o in eng.obstacles) {
        if (o.consumed) continue;
        final r = (size.width < size.height ? size.width : size.height) * 0.20;
        final cx = size.width * 0.5, cy = size.height * 0.5;
        final xTop = cx + r * math.cos(o.angleTop);
        final yTop = cy + r * math.sin(o.angleTop);
        final travel = o.travelMs ?? kTravelMs;
        final uTop = ((yTop - topY) / (bottomY - topY)).clamp(0.0, 1.0);
        final tSpawn = o.tContactMs - uTop * travel;
        final tExit = tSpawn + travel;
        if (nowMs >= tSpawn && nowMs <= tExit) count++;
      }
      return count;
    }

    void _spawnOne(double nowMs, Size size) {
      final angleTop = colAngles[rng.nextInt(colAngles.length)];
      final mAbs = kSlopeMin + rng.nextDouble() * (kSlopeMax - kSlopeMin);
      final m = (rng.nextBool() ? 1.0 : -1.0) * mAbs;

      final cx = size.width * 0.5, cy = size.height * 0.5;
      final r = (size.width < size.height ? size.width : size.height) * 0.20;
      final bottomY = size.height + 24.0;
      final xTop = cx + r * math.cos(angleTop);
      final yTop = cy + r * math.sin(angleTop);
      final bot = _solveBottomFor(size, angleTop, m);
      final yBottom = bot.yBottom;
      final angleBottom = bot.angleBottom;

      final fracTop = ((yTop - topY) / (bottomY - topY)).clamp(0.0, 1.0);
      final fracBottom = ((yBottom - topY) / (bottomY - topY)).clamp(0.0, 1.0);

      final isBlack = rng.nextDouble() < 0.65;
      final type = isBlack ? ObType.black : ObType.red;

      ObSize? sizeTag;
      double travel = kTravelMs;
      if (isBlack) {
        final rPick = rng.nextDouble();
        if (rPick < 1 / 3) { sizeTag = ObSize.small; travel *= 0.8; }
        else if (rPick < 2 / 3) { sizeTag = ObSize.medium; /*1.0*/ }
        else { sizeTag = ObSize.large; travel *= 1.25; }
      }

      final spawnDelay = rng.nextDouble() * 60.0;
      final tSpawn = nowMs + spawnDelay;
      final tTop = tSpawn + fracTop * travel;
      final tBottom = tSpawn + fracBottom * travel;

      final o = Obstacle(
        lane: Lane.top,
        type: type,
        tContactMs: tTop,
        tContactMs2: tBottom,
        contactWindowMs: 220,
        angleRad: angleTop,
        angleBottomRad: angleBottom,
        size: sizeTag,
        travelMs: travel,
        dxPerDy: m,
      );
      eng.scheduleMany([o]);
    }

    return GameBindings(
      tick: (_) {
        // mirror your debug loop
        eng.tick();

        final size = MediaQuery.of(context).size;
        if (lastSize != size || colAngles.isEmpty) {
          lastSize = size;
          colAngles = _computeColumnAngles(size);
        }

        final now = eng.tMs;
        if (eng.running && !eng.gameOver && now >= nextSpawnCheckMs) {
          final onscreen = _visibleCount(now, size);
          if (onscreen < kMaxOnscreen) {
            final toMake = math.min(1 + rng.nextInt(2), kMaxOnscreen - onscreen);
            for (int i = 0; i < toMake; i++) { _spawnOne(now, size); }
          }
          final jitter = kSpawnCheckMin + rng.nextDouble() * (kSpawnCheckMax - kSpawnCheckMin);
          nextSpawnCheckMs = now + jitter;
        }

        // soft cull (3–4x/sec) — optional: let engine drop them on its own if you prefer
        // (not included here for brevity)
      },
      flip: () => eng.flipDirection(),
      score: () => eng.score,
      isGameOver: () => eng.gameOver,
      painterFactory: (repaint) => createProductionPainter(eng, repaint: repaint),
    );
  }
}
