// lib/engine/engine.dart
// Flip-aware orbit engine with precomputed obstacle caches.
// - Splits integration only at flip instants (no fixed substeps)
// - Uses precomputed angles/windows on Obstacle (top/bottom)
// - Scans only nearby obstacles by time (binary search on sorted list)
// - Marks consumed immediately; actual removal can be throttled by UI

import 'dart:math' as math;
import 'obstacle.dart';

class OrbitEngine {
  OrbitEngine({
    this.toleranceRad = 0.2,   // strict-ish (you tuned this)
    double angularSpeed = 1.4,  // abs rad/s
  }) : _angularSpeed = angularSpeed.abs();

  // --- Motion & tolerance ---
  double toleranceRad;
  double _angularSpeed; // >= 0
  int _dirSign = 1;     // +1 = CW, -1 = CCW

  double get angularVel => _dirSign * _angularSpeed;
  void setAngularSpeed(double speed) => _angularSpeed = speed.abs();

  // ---- Flip handling ----
  final List<double> _pendingFlipsMs = <double>[];
  double _lastFlipMs = -1e9;

  /// Immediate flip for responsive feel + queue flip time for arc splitting.
  void flipDirection() {
    final t = tMs;
    _dirSign = -_dirSign;    // instant visual/motion response
    _pendingFlipsMs.add(t);  // record exact timestamp for tick segmentation
    _lastFlipMs = t;         // (kept for debugging; no debounce)
  }

  // ---- Time slicing (by top contact time) -------------------------------
  // We keep a *large* look-back to include obstacles whose TOP time is long
  // past but whose BOTTOM window is active now. Small look-ahead is enough.
  static const double _kLookBackMs  = 7000.0; // cover slow large hazards
  static const double _kLookAheadMs = 450.0;

  int _lowerBoundByT(double time) {
    // binary search on sorted obstacles by tContactMs (TOP)
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

  // ---- Core tick: flip-aware + cached-window arc tests -------------------
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

        // Strict detection (no grace/magnet), check both windows using caches.
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

    // No per-frame cull here; UI can throttle removals safely.
  }

  /// Fast contact resolution for one segment [t0..t1] with arc theta0→theta1.
  bool _resolveSegmentArc({
    required double t0,
    required double t1,
    required double theta0,
    required double theta1,
    required int dirSign,
    required double tol,
  }) {
    if (t1 <= t0) return false;

    final startTime = t0 - _kLookBackMs;
    final endTime   = t1 + _kLookAheadMs;

    // Scan only [startIdx .. endIdx)
    final startIdx = _lowerBoundByT(startTime);
    final endIdx   = _lowerBoundByT(endTime);

    var hitBlack = false;

    for (int i = startIdx; i < endIdx; i++) {
      final o = obstacles[i];
      if (o.consumed) continue;

      // Time overlap with this segment?
      final overlaps1 = !(t1 < o.win1StartMs || t0 > o.win1EndMs);
      final hasW2 = o.win2StartMs != null;
      final overlaps2 = hasW2 && !(t1 < o.win2StartMs! || t0 > o.win2EndMs!);

      if (!overlaps1 && !overlaps2) continue;

      // Angle band test on the swept arc (cheap boolean)
      bool hit = false;
      if (overlaps1) {
        hit = _arcHitsAngle(
          a0: theta0, a1: theta1, dirSign: dirSign, target: o.angleTop, tol: tol,
        );
      }
      if (!hit && overlaps2) {
        hit = _arcHitsAngle(
          a0: theta0, a1: theta1, dirSign: dirSign, target: o.angleBottom, tol: tol,
        );
      }
      if (!hit) continue;

      // Apply once
      if (o.type == ObType.red) {
        o.consumed = true; // prevent double-score; UI cull will remove soon
        score += 1;
      } else {
        o.consumed = true;
        hitBlack = true;
      }
    }

    if (hitBlack) {
      gameOver = true;
      pause();
    }
    return hitBlack;
  }

  /// Returns true if the directed arc a0→a1 (following dirSign) touches
  /// the target band [target - tol, target + tol].
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

  String debugSummary() =>
      't=${tMs.toStringAsFixed(1)}ms score=$score gameOver=$gameOver obstacles=${obstacles.length}';
}
