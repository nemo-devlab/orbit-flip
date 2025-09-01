import 'dart:math' as math;
import 'package:orbit_flip/engine/obstacle.dart';
import 'package:orbit_flip/engine/wave_generator.dart';

void main() {
  final gen = WaveGenerator(seed: 42);

  // A tiny “level 0” tutorial starting at 1000ms
  final wave0 = gen.tutorial(startMs: 1000, bpm: 120);

  // A simple alternating red run with a black every 4th, 250ms apart
  final wave1 = gen.alternating(
    startMs: 3000,
    count: 8,
    gapMs: 250,
    a: Lane.left,
    b: Lane.right,
    baseType: ObType.red,
    everyNBlack: 4,
  );

  // Combine and sort
  final wave = gen.concat([wave0, wave1]);

  // Simulate a couple moments in time
  _tick(wave, tMs: 1000, theta: 3*math.pi/2); // collect top red
  _tick(wave, tMs: 3750, theta: 0.0);         // maybe hit a right-lane black
}

void _tick(List<Obstacle> obstacles,
    {required int tMs, required double theta}) {
  final out = resolveContacts(obstacles, theta, tMs.toDouble(), 0.18);
  print('t=$tMs -> $out');
  cullExpired(obstacles, tMs.toDouble());
}
