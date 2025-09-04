// lib/ui/game_bindings.dart
//
// Production-safe bindings between your UI and the engine/painter.
// - No per-frame setState in UI; the painter is driven by a Listenable (AnimationController).
// - You keep your existing engine API exactly as-is.
//
// HOW TO USE (example):
// final engine = Engine(); // your type
// final bindings = ProductionBindings.fromEngine<Engine>(
//   engine: engine,
//   tick: (e, dtMs) => e.tick(dtMs),            // <- your engine's tick
//   flip: (e) => e.flipDirection(),             // <- your instant flip
//   score: (e) => e.score,                      // <- wherever your score lives
//   isGameOver: (e) => e.isGameOver,            // <- same signal as debug page
//   painter: (e, repaint) => DebugOrbitPainter( // <- your debug painter, unchanged
//     e,
//     repaint: repaint,
//   ),
// );
// Navigator.pushNamed(context, '/game', arguments: bindings);

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Factory that must return your CustomPainter wired to the given [repaint]
/// (typically an AnimationController). This lets the painter repaint without
/// any widget setState.
typedef PainterFactory = CustomPainter Function(Listenable repaint);

/// Minimal contract the gameplay UI needs. You provide these via
/// [ProductionBindings.fromEngine] so the UI never reaches into engine types.
class GameBindings {
  /// Advance the simulation by [dtMs] milliseconds (called every frame).
  final void Function(int dtMs) tick;

  /// Flip the orbit immediately (called on tap).
  final void Function() flip;

  /// Current score (the same number you show on your debug HUD).
  final int Function() score;

  /// True when the engine reports a terminal state.
  final bool Function() isGameOver;

  /// Builds the painter used by the playfield. The UI passes its repaint
  /// listenable so your painter can stay in sync without per-frame setState.
  final PainterFactory painterFactory;

  const GameBindings({
    required this.tick,
    required this.flip,
    required this.score,
    required this.isGameOver,
    required this.painterFactory,
  });
}

/// Convenience helpers to build [GameBindings] from any engine type without
/// importing that engine here. Keeps this file drop-in and compile-safe.
class ProductionBindings {
  /// Bind any engine type [E] to the UI by describing how to call it.
  ///
  /// - [tick] should call your engine's tick with `dtMs`.
  /// - [flip] should call your engine's immediate flip method.
  /// - [score] returns the current score as an `int`.
  /// - [isGameOver] mirrors the same signal used in your debug page.
  /// - [painter] must return your CustomPainter that draws the playfield.
  static GameBindings fromEngine<E>({
    required E engine,
    required void Function(E engine, int dtMs) tick,
    required void Function(E engine) flip,
    required int Function(E engine) score,
    required bool Function(E engine) isGameOver,
    required CustomPainter Function(E engine, Listenable repaint) painter,
  }) {
    return GameBindings(
      tick: (dt) => tick(engine, dt),
      flip: () => flip(engine),
      score: () => score(engine),
      isGameOver: () => isGameOver(engine),
      painterFactory: (repaint) => painter(engine, repaint),
    );
  }
}
