// lib/engine/engine.dart
// Immediate flip + generous contact (bigger tolerance + proximity fallback).
// Keeps arc-based analytic detection, and then applies a forgiving fallback.

import 'dart:math' as math;
import 'obstacle.dart';

class OrbitEngine {
  OrbitEngine({
    this.toleranceRad = 0.2,   // ~26° (more generous)
    double angularSpeed = 1.4,  // abs rad/s; spacey default
  }) : _angularSpeed = angularSpeed.abs();

  // --- Motion & tolerance ---
  double toleranceRad;
  double _angularSpeed; // >= 0
  int _dirSign = 1;     // +1 = CW, -1 = CCW

  // Run physics in fixed sub-steps (ms) inside each frame.
  // 8ms ≈ 125 Hz; you can try 4ms (250 Hz) if needed.
  static const double kMaxStepMs = 8.0;

  double get angularVel => _dirSign * _angularSpeed;
  void setAngularSpeed(double speed) => _angularSpeed = speed.abs();

  // ---- Flip handling ----
  final List<double> _pendingFlipsMs = <double>[];
  double _lastFlipMs = -1e9;
  double _graceUntilMs = 0.0; // brief post-flip tolerance grace

  /// Immediate flip for responsive feel + queue flip time for arc splitting.
  void flipDirection() {
    final t = tMs;
    _dirSign = -_dirSign;    // instant visual/motion response
    _pendingFlipsMs.add(t);  // record exact timestamp for tick segmentation
    _lastFlipMs = t;         // (kept for debugging; no debounce)
  }

  // Only consider obstacles whose top contact is near the current frame.
  // Look a little into the past, and far enough ahead to include the bottom window.
  static const double _kHorizonBeforeMs = 12000.0;  // past
  static const double _kHorizonAfterMs  = 600.0; // future (covers bottom contact span)

  int _lowerBoundByT(double time) {
    // binary search on sorted obstacles by tContactMs
    int lo = 0, hi = obstacles.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (obstacles[mid].tContactMs < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }


  // --- Timebase ---
  final Stopwatch _clock = Stopwatch();
  double get tMs => _clock.elapsedMilliseconds.toDouble();
  double _lastMs = 0.0;
  int _dirAtLastTickSign = 1; // direction at the start of previous tick

  // --- State ---
  final List<Obstacle> obstacles = [];
  double playerTheta = 3 * math.pi / 2; // start at TOP
  int score = 0;
  bool gameOver = false;
  bool running = false;

  // ---- Lifecycle ----
  void start() {
    reset();
    running = true;
    _clock.start();
    _lastMs = tMs;
  }

  void pause() {
    running = false;
    _clock.stop();
  }

  void resume() {
    if (!gameOver && !running) {
      running = true;
      _clock.start();
      _lastMs = tMs;
    }
  }

  void reset() {
    running = false;
    gameOver = false;
    score = 0;
    playerTheta = 3 * math.pi / 2;
    obstacles.clear();
    _clock..reset()..stop();
    _lastMs = 0.0;
    _pendingFlipsMs.clear();
    _dirSign = 1;
    _dirAtLastTickSign = 1;
    _lastFlipMs = -1e9;
    _graceUntilMs = 0.0;
  }

  // ---- Scheduling ----
  Obstacle schedule(Lane lane, ObType type, double atMs, {double windowMs = 120}) {
    final o = Obstacle(
      lane: lane,
      type: type,
      tContactMs: atMs,
      contactWindowMs: windowMs,
    );
    obstacles.add(o);
    return o;
  }

  void scheduleMany(Iterable<Obstacle> os) {
    obstacles.addAll(os);
    obstacles.sort((a, b) => a.tContactMs.compareTo(b.tContactMs));
  }

  // ---- Core tick: flip-aware + analytic crossing + proximity fallback ----
  void tick() {
    if (!running || gameOver) return;

    final now = tMs;

    // Split only at real flips since last frame.
    final flips = _pendingFlipsMs.where((f) => f > _lastMs && f <= now).toList()..sort();
    final segmentEnds = [...flips, now];

    var segStart   = _lastMs;
    var thetaStart = playerTheta;
    var dirSign    = _dirAtLastTickSign; // direction that was active at start of last frame

    for (final segEnd in segmentEnds) {
      if (gameOver) break;

      final dtMs = segEnd - segStart;
      if (dtMs > 0) {
        final omega    = dirSign * _angularSpeed; // rad/s
        final thetaEnd = wrapAngle(thetaStart + omega * (dtMs / 1000.0));

        // Strict detection (no grace/magnet), but check both windows.
        final ended = _resolveSegmentArc(
          t0: segStart,
          t1: segEnd,
          theta0: thetaStart,
          theta1: thetaEnd,
          dirSign: dirSign,
          tol: toleranceRad,
        );
        if (ended) {
          playerTheta = thetaEnd;
          _dirAtLastTickSign = _dirSign;
          _lastMs = now;
          _pendingFlipsMs.removeWhere((f) => f <= now);
          return;
        }

        // Advance
        thetaStart = thetaEnd;
      }

      // Toggle for next segment if this boundary is a flip
      if (segEnd != now) dirSign = -dirSign;
      segStart = segEnd;
    }

    // Commit frame
    playerTheta = thetaStart;
    _dirAtLastTickSign = _dirSign;
    _lastMs = now;
    _pendingFlipsMs.removeWhere((f) => f <= now);

    // Light safety cull; UI handles visual lifetime
    obstacles.removeWhere((o) => now > o.tContactMs + 8000);
  }



  /// Analytic contact for one segment [t0..t1] with arc theta0→theta1 (dirSign).
  bool _resolveSegmentArc({
    required double t0,
    required double t1,
    required double theta0,
    required double theta1,
    required int dirSign,
    required double tol,
  }) {
    if (t1 <= t0) return false;

    final startTime = t0 - _kHorizonBeforeMs;
    final endTime   = t1 + _kHorizonAfterMs;

    // scan only a slice [startIdx .. endIdx)
    final startIdx = _lowerBoundByT(startTime);
    int i = startIdx;

    final toRemove = <Obstacle>[];
    var hitBlack = false;

    while (i < obstacles.length) {
      final o = obstacles[i];
      if (o.tContactMs > endTime) break; // everything beyond this is too far

      if (!o.consumed) {
        final half = o.contactWindowMs * 0.5;

        // Top window
        final w1a = o.tContactMs - half;
        final w1b = o.tContactMs + half;

        // Bottom window (optional)
        final hasW2 = o.tContactMs2 != null;
        final w2a = hasW2 ? o.tContactMs2! - half : 0.0;
        final w2b = hasW2 ? o.tContactMs2! + half : 0.0;

        // Time overlap with this segment?
        final overlaps1 = !(t1 < w1a || t0 > w1b);
        final overlaps2 = hasW2 && !(t1 < w2a || t0 > w2b);

        if (overlaps1 || overlaps2) {
          final angleTop    = o.angle;
          final angleBottom = hasW2 ? wrapAngle(2 * math.pi - angleTop) : angleTop;

          bool hit = false;
          if (overlaps1) {
            hit = _arcHitsAngle(a0: theta0, a1: theta1, dirSign: dirSign, target: angleTop, tol: tol);
          }
          if (!hit && overlaps2) {
            hit = _arcHitsAngle(a0: theta0, a1: theta1, dirSign: dirSign, target: angleBottom, tol: tol);
          }

          if (hit) {
            if (o.type == ObType.red) {
              o.consumed = true;
              toRemove.add(o);
              score += 1;
            } else {
              toRemove.add(o);
              hitBlack = true;
            }
          }
        }
      }

      i++;
    }

    if (toRemove.isNotEmpty) {
      obstacles.removeWhere(toRemove.contains);
    }
    if (hitBlack) {
      gameOver = true;
      pause();
    }
    return hitBlack;
  }


  bool _arcHitsAngle({
    required double a0,
    required double a1,
    required int dirSign,
    required double target,
    required double tol,
  }) {
    final twoPi = 2 * math.pi;
    a0 = wrapAngle(a0);
    a1 = wrapAngle(a1);
    target = wrapAngle(target);

    // Expand target band
    var tMin = target - tol;
    var tMax = target + tol;

    // Normalize to an increasing sweep [s0..s1]
    double s0, s1;
    if (dirSign >= 0) {
      s0 = a0;
      s1 = a1 < a0 ? a1 + twoPi : a1;
      while (tMin < s0 - twoPi) { tMin += twoPi; tMax += twoPi; }
      while (tMin > s0 + twoPi) { tMin -= twoPi; tMax -= twoPi; }
    } else {
      // Map decreasing a0→a1 to increasing a1→a0
      s0 = a1;
      s1 = a0 < a1 ? a0 + twoPi : a0;
      while (tMin < s0 - twoPi) { tMin += twoPi; tMax += twoPi; }
      while (tMin > s0 + twoPi) { tMin -= twoPi; tMax -= twoPi; }
    }

    // Overlap means the swept arc touched the target band
    return !(s1 < tMin || s0 > tMax);
  }


  //   const double epsMs = 50; // light time grace for window edges
  //   final os = List<Obstacle>.from(obstacles);
  //   final toRemove = <Obstacle>[];
  //   var hitBlack = false;

  //   for (final o in os) {
  //     if (o.consumed) continue;

  //     final half = o.contactWindowMs * 0.5;

  //     // Window #1 (top)
  //     final w1a = o.tContactMs - half - epsMs;
  //     final w1b = o.tContactMs + half + epsMs;

  //     // Window #2 (bottom) — may be null
  //     final hasW2 = o.tContactMs2 != null;
  //     final w2a = hasW2 ? o.tContactMs2! - half - epsMs : 0.0;
  //     final w2b = hasW2 ? o.tContactMs2! + half + epsMs : 0.0;

  //     // Early reject if segment overlaps neither window
  //     final overlaps1 = !(t1 < w1a || t0 > w1b);
  //     final overlaps2 = hasW2 && !(t1 < w2a || t0 > w2b);
  //     if (!overlaps1 && !overlaps2) continue;

  //     // Compute exact crossing time for this sub-segment
  //     final tCross = _analyticHitTime(
  //       t0: t0,
  //       t1: t1,
  //       a0: theta0,
  //       a1: theta1,
  //       dirSign: dirSign,
  //       target: o.angle,
  //       tol: tol,
  //     );

  //     // TEMP DEBUG
  //     // ignore: dead_code
  //     if (tCross != null) {
  //       final win = (tCross >= w1a && tCross <= w1b) ? "W1"
  //                 : (hasW2 && tCross >= w2a && tCross <= w2b) ? "W2"
  //                 : "NONE";
  //       // Print only when close to the bottom window to keep noise low
  //       if (hasW2 && (tCross - o.tContactMs2!).abs() < 180) {
  //         // ignore: avoid_print
  //         print("HIT? id=${o.id} tCross=${tCross.toStringAsFixed(1)} in=$win "
  //               "theta0=${theta0.toStringAsFixed(2)} theta1=${theta1.toStringAsFixed(2)} "
  //               "target=${o.angle.toStringAsFixed(2)} tol=$tol dir=$dirSign");
  //       }
  //     }

  //     if (tCross == null) continue;

  //     // Accept if crossing time lands inside either window
  //     final inW1 = (tCross >= w1a && tCross <= w1b);
  //     final inW2 = hasW2 && (tCross >= w2a && tCross <= w2b);
  //     if (!inW1 && !inW2) continue;

  //     // Apply result
  //     if (o.type == ObType.red) {
  //       o.consumed = true;
  //       toRemove.add(o);
  //       score += 1;
  //     } else {
  //       toRemove.add(o);
  //       hitBlack = true;
  //     }
  //   }

  //   if (toRemove.isNotEmpty) {
  //     obstacles.removeWhere((x) => toRemove.contains(x));
  //   }
  //   if (hitBlack) {
  //     gameOver = true;
  //     pause();
  //   }
  //   return hitBlack;
  // }


  /// Fallback: near contact time, accept slightly larger angular error.
  // void _proximityFallback(double nowMs) {
  //   const double timeSlackMs = 140.0;
  //   const double tolMul = 1.10; // +10% angular slack
  //   final tol = toleranceRad * tolMul;

  //   final snapshot = List<Obstacle>.from(obstacles);
  //   for (final o in snapshot) {
  //     if (o.consumed) continue;

  //     final dt1 = (nowMs - o.tContactMs).abs();
  //     final dt2 = o.tContactMs2 != null ? (nowMs - o.tContactMs2!).abs() : double.infinity;
  //     final dtMin = dt1 < dt2 ? dt1 : dt2;

  //     if (dtMin > timeSlackMs) continue;
  //     if (angularDistance(playerTheta, o.angle) <= tol) {
  //       if (o.type == ObType.red) {
  //         o.consumed = true;
  //         obstacles.remove(o);
  //         score += 1;
  //       } else {
  //         obstacles.remove(o);
  //         gameOver = true;
  //         pause();
  //       }
  //       if (gameOver) return; // stop after black
  //     }
  //   }
  // }


  /// Returns exact time (ms) when the directed arc a0→a1 (following dirSign)
  /// first enters the target band [target - tol, target + tol], or null if never.
  double? _analyticHitTime({
    required double t0,
    required double t1,
    required double a0,
    required double a1,
    required int dirSign,
    required double target,
    required double tol,
  }) {
    final twoPi = 2 * math.pi;
    a0 = wrapAngle(a0);
    a1 = wrapAngle(a1);
    target = wrapAngle(target);

    // Map to an increasing sweep domain [s0..s1]
    double s0, s1;
    if (dirSign >= 0) {
      s0 = a0;
      s1 = a1 < a0 ? a1 + twoPi : a1; // unwrap
    } else {
      // decreasing a0→a1 becomes increasing a1→a0
      s0 = a1;
      s1 = a0 < a1 ? a0 + twoPi : a0;
    }
    final sweep = s1 - s0;
    if (sweep <= 0) return null;

    // Target band [tMin..tMax], shifted near the sweep domain
    var tMin = target - tol;
    var tMax = target + tol;
    while (tMax < s0 - twoPi) { tMin += twoPi; tMax += twoPi; }
    while (tMin > s1 + twoPi) { tMin -= twoPi; tMax -= twoPi; }

    // Intersection of [s0..s1] and [tMin..tMax]
    final interStart = math.max(s0, tMin);
    final interEnd   = math.min(s1, tMax);
    if (interStart > interEnd) return null; // no overlap

    // Earliest angle of intersection → exact crossing time
    final u = (interStart - s0) / sweep; // 0..1
    return t0 + u * (t1 - t0);
  }

  // Deterministic single-instant step (no segmentation)
  ContactOutcome stepAt(double tOverrideMs) {
    final out = resolveContacts(obstacles, playerTheta, tOverrideMs, toleranceRad);
    if (out.collected.isNotEmpty) {
      score += out.collected.length;
      obstacles.removeWhere((o) => out.collected.contains(o));
    }
    if (out.hitBlack) {
      obstacles.removeWhere((o) => out.blacks.contains(o));
      gameOver = true;
    }
    return out;
  }

  String debugSummary() =>
      't=${tMs.toStringAsFixed(1)}ms score=$score gameOver=$gameOver obstacles=${obstacles.length}';
}
