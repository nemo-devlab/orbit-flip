// lib/engine/wave_generator.dart
// Wave pattern helpers for Orbit Flip.
// Generates time-scheduled obstacles (no UI). Use these to prebuild waves
// and then feed them to your engine via scheduleMany(...).

// It can:
// - make a quick tutorial wave,
// - build alternating two-lane runs (optionally “every Nth is black”),
// - cycle through lists of lanes/types,
// - create a randomStream with pBlack and optional time jitter,
// - drop crossPairs (two-at-once beats),
// - and concat/shift waves to stitch sets together.

import 'dart:math' as math;
import 'obstacle.dart';

/// Utility to generate obstacle sequences using beats/intervals.
class WaveGenerator {
  WaveGenerator({int? seed, this.windowMs = 120}) : rng = math.Random(seed);

  /// Random source (seed for deterministic runs in tests).
  final math.Random rng;

  /// Default contact window applied to generated obstacles (ms).
  final double windowMs;

  /// Convert BPM to milliseconds per beat.
  static double beatMs(double bpm) => 60000.0 / bpm;

  /// Simple tutorial: three reds (Top, Bottom, Left) then one black (Right).
  /// Starts after one beat to give the player a moment.
  List<Obstacle> tutorial({required double startMs, double bpm = 120}) {
    final b = beatMs(bpm);
    return [
      Obstacle(lane: Lane.top,    type: ObType.red,   tContactMs: startMs + 1 * b, contactWindowMs: windowMs),
      Obstacle(lane: Lane.bottom, type: ObType.red,   tContactMs: startMs + 2 * b, contactWindowMs: windowMs),
      Obstacle(lane: Lane.left,   type: ObType.red,   tContactMs: startMs + 3 * b, contactWindowMs: windowMs),
      Obstacle(lane: Lane.right,  type: ObType.black, tContactMs: startMs + 4 * b, contactWindowMs: windowMs),
    ]..sort((a, b) => a.tContactMs.compareTo(b.tContactMs));
  }

  /// Alternates between two lanes every [gapMs]. Optionally make every Nth
  /// obstacle black (hazard) using [everyNBlack].
  List<Obstacle> alternating({
    required double startMs,
    required int count,
    required double gapMs,
    Lane a = Lane.left,
    Lane b = Lane.right,
    ObType baseType = ObType.red,
    int everyNBlack = 0,
  }) {
    final list = <Obstacle>[];
    var t = startMs;
    for (int i = 0; i < count; i++) {
      final lane = (i % 2 == 0) ? a : b;
      final type = (everyNBlack > 0 && (i + 1) % everyNBlack == 0) ? ObType.black : baseType;
      list.add(Obstacle(lane: lane, type: type, tContactMs: t, contactWindowMs: windowMs));
      t += gapMs;
    }
    return _sorted(list);
  }

  /// Cycles through [lanes] and [types] lists together across [count] notes.
  /// For example, lanes = [top, right, bottom, left], types = [red, red, red, black].
  List<Obstacle> cycle({
    required double startMs,
    required int count,
    required double gapMs,
    required List<Lane> lanes,
    required List<ObType> types,
  }) {
    assert(lanes.isNotEmpty && types.isNotEmpty, 'lanes/types cannot be empty');
    final list = <Obstacle>[];
    var t = startMs;
    for (int i = 0; i < count; i++) {
      final lane = lanes[i % lanes.length];
      final type = types[i % types.length];
      list.add(Obstacle(lane: lane, type: type, tContactMs: t, contactWindowMs: windowMs));
      t += gapMs;
    }
    return _sorted(list);
  }

  /// Random lane + type stream with optional time/lane jitter.
  /// [pBlack] is probability of a black obstacle (0..1).
  /// [jitterMs] randomly offsets tContact by [-jitterMs, +jitterMs].
  List<Obstacle> randomStream({
    required double startMs,
    required int count,
    required double gapMs,
    double pBlack = 0.2,
    List<Lane>? lanePool,
    double jitterMs = 0.0,
  }) {
    final lanes = lanePool ?? Lane.values;
    final list = <Obstacle>[];
    var t = startMs;
    for (int i = 0; i < count; i++) {
      final lane = lanes[rng.nextInt(lanes.length)];
      final type = (rng.nextDouble() < pBlack) ? ObType.black : ObType.red;
      final j = (jitterMs <= 0) ? 0.0 : rng.nextDouble() * (2 * jitterMs) - jitterMs;
      list.add(Obstacle(lane: lane, type: type, tContactMs: t + j, contactWindowMs: windowMs));
      t += gapMs;
    }
    return _sorted(list);
  }

  /// Two-at-once cross pattern on each beat (e.g., top+bottom, then left+right).
  /// Useful for teaching flips.
  List<Obstacle> crossPairs({
    required double startMs,
    required int pairs,
    required double gapMs,
    ObType type = ObType.red,
    bool alternateAxes = true,
  }) {
    final list = <Obstacle>[];
    var t = startMs;
    for (int i = 0; i < pairs; i++) {
      final vertical = (i % 2 == 0) || !alternateAxes;
      if (vertical) {
        list.add(Obstacle(lane: Lane.top, type: type, tContactMs: t, contactWindowMs: windowMs));
        list.add(Obstacle(lane: Lane.bottom, type: type, tContactMs: t, contactWindowMs: windowMs));
      } else {
        list.add(Obstacle(lane: Lane.left, type: type, tContactMs: t, contactWindowMs: windowMs));
        list.add(Obstacle(lane: Lane.right, type: type, tContactMs: t, contactWindowMs: windowMs));
      }
      t += gapMs;
    }
    return _sorted(list);
  }

  // ---- helpers ----

  List<Obstacle> shift(List<Obstacle> src, double offsetMs) =>
      src.map((o) => o.copyWith(tContactMs: o.tContactMs + offsetMs)).toList()..sort((a, b) => a.tContactMs.compareTo(b.tContactMs));

  List<Obstacle> concat(Iterable<List<Obstacle>> waves) {
    final out = <Obstacle>[];
    for (final w in waves) {
      out.addAll(w);
    }
    return _sorted(out);
  }

  List<Obstacle> _sorted(List<Obstacle> list) {
    list.sort((a, b) => a.tContactMs.compareTo(b.tContactMs));
    return list;
  }
}
