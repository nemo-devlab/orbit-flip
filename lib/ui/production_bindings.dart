// lib/ui/production_bindings.dart
//
// Binds the production UI to your gameplay engine and painter.
// - Uses the same painter you use on the debug page.
// - Calls your engine.tick(...) every frame (handles both tick() and tick(int)).
// - Flips instantly via engine.flipDirection().
// - Exposes score and isGameOver for the HUD and navigation.
//
// REQUIREMENTS (one-time):
// 1) In lib/ui/debug_orbit_page.dart, expose a factory:
//      CustomPainter createProductionPainter(Engine eng, {required Listenable repaint}) { ... }
//    (It may wrap a private _OrbitPainter; that’s fine.)
// 2) Your engine class exposes:
//      void tick([int dtMs]);  // OR void tick();
//      void flipDirection();
//      int  get score;
//      bool get isGameOver;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../engine/engine.dart' as eng;
import 'game_bindings.dart';
import 'debug_orbit_page.dart' show createProductionPainter;

class ProductionBindings {
  /// Create bindings with a **new** engine instance.
  /// If your engine class is not `Engine`, change the ctor below to e.g. `eng.OrbitEngine()`.
  static GameBindings create() {
    final engine = eng.OrbitEngine(); // <-- adjust type name if needed
    return fromEngine(engine);
  }

  /// Create bindings around an **existing** engine you constructed elsewhere.
  static GameBindings fromEngine(dynamic engine) {
    return GameBindings(
      tick: (dtMs) => _safeTick(engine, dtMs),
      flip: () => _safeFlip(engine),
      score: () => _safeScore(engine),
      isGameOver: () => _safeOver(engine),
      painterFactory: (repaint) => createProductionPainter(engine, repaint: repaint),
    );
  }

  // ---- Safe adapters (work with either tick() or tick(int)) ----

  static void _safeTick(dynamic e, int dtMs) {
    try {
      // Try tick(int)
      Function.apply((e as dynamic).tick as Function, [dtMs]);
    } catch (_) {
      try {
        // Fallback: tick()
        Function.apply((e as dynamic).tick as Function, const []);
      } catch (__){ /* no-op if not available */ }
    }
  }

  static void _safeFlip(dynamic e) {
    try {
      Function.apply((e as dynamic).flipDirection as Function, const []);
    } catch (_) {
      // Fallback to a generic 'flip' if you named it differently
      try { Function.apply((e as dynamic).flip as Function, const []); } catch(__) {}
    }
  }

  static int _safeScore(dynamic e) {
    try {
      final s = (e as dynamic).score;
      if (s is int) return s;
      if (s is num) return s.toInt();
    } catch (_) {}
    return 0;
  }

  static bool _safeOver(dynamic e) {
    try {
      final v = (e as dynamic).isGameOver;
      return v == true;
    } catch (_) {}
    return false;
  }
}
