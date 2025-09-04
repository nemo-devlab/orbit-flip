// lib/engine/obstacle.dart
// Core obstacle data models + angle helpers for Orbit Flip.
// UI-agnostic (no Flutter imports).

import 'dart:math' as math;

/// Spawn lanes (semantic only; most logic uses explicit angles).
/// Canvas angles: 0=RIGHT, π/2=BOTTOM, π=LEFT, 3π/2=TOP.
enum Lane { top, right, bottom, left }

/// Obstacle type: [red] is collectible (+1), [black] ends the run.
enum ObType { red, black }

/// Size applies only to black hazards (affects speed/visual radius).
enum ObSize { small, medium, large }

extension LaneAngle on Lane {
  /// Angle in radians for this lane in **canvas coordinates**.
  double get angle {
    switch (this) {
      case Lane.right:
        return 0.0;
      case Lane.bottom:
        return math.pi / 2;
      case Lane.left:
        return math.pi;
      case Lane.top:
        return 3 * math.pi / 2;
    }
  }

  String get label {
    switch (this) {
      case Lane.top:
        return 'top';
      case Lane.right:
        return 'right';
      case Lane.bottom:
        return 'bottom';
      case Lane.left:
        return 'left';
    }
  }
}

/// Wraps an angle to [0, 2π).
double wrapAngle(double a) {
  final twoPi = 2 * math.pi;
  a = a % twoPi;
  if (a < 0) a += twoPi;
  return a;
}

/// Smallest unsigned angular distance between two angles (radians).
double angularDistance(double a, double b) {
  final twoPi = 2 * math.pi;
  final diff = (a - b).abs();
  return diff <= math.pi ? diff : twoPi - diff;
}

/// An obstacle scheduled to reach the orbit radius at [tContactMs] (TOP arc).
/// Optionally it also reaches the BOTTOM arc at [tContactMs2].
/// During each contact window (centered at those times with width
/// [contactWindowMs]), collisions/collections are resolved.
///
/// New (diagonal support):
/// - [angleBottomRad] can override the default symmetric bottom angle.
/// - [dxPerDy] is a constant x-slope (px per px of y) used by the UI painter
///   to render a straight diagonal path: x(y) = xTop + dxPerDy * (y - yTop).
class Obstacle {
  Obstacle({
    required this.lane,
    required this.type,
    required this.tContactMs,      // top contact time (ms since run start)
    this.contactWindowMs = 120,    // active window width (ms)
    this.consumed = false,
    this.angleRad,                 // explicit TOP angle override (radians)
    this.angleBottomRad,           // explicit BOTTOM angle override (radians)
    this.tContactMs2,              // bottom contact time (ms), optional
    this.size,                     // black only
    this.travelMs,                 // top→bottom travel time (ms), optional
    this.dxPerDy,                  // straight diagonal slope for UI rendering
    int? id,
  }) : id = id ?? _nextId++ {
    assert(contactWindowMs > 0, 'contactWindowMs must be > 0');
    _precompute(); // fill derived/cached fields once at construction
  }

  // ---- Identity / basic fields ----
  final int id; // unique for debugging/culling
  final Lane lane;
  final ObType type;

  /// Primary (top) contact time and window width.
  final double tContactMs;
  final double contactWindowMs;

  /// If true, the obstacle was collected (red) — black removes/ends run.
  bool consumed;

  /// Optional explicit angles (radians).
  final double? angleRad;        // TOP angle override
  final double? angleBottomRad;  // BOTTOM angle override (for diagonals)

  /// Optional bottom-arc contact time; enables a second contact window.
  final double? tContactMs2;

  /// Optional visual/logic metadata
  final ObSize? size;      // only used for black rendering/speed in UI
  final double? travelMs;  // per-obstacle fall duration (ms), used by UI

  /// Straight-line diagonal slope for UI (pixels of x per pixel of y).
  /// If null, UI may default to 0 (vertical fall).
  final double? dxPerDy;

  // ---- Derived, precomputed & cached (set in _precompute) ----

  /// Cached angles for TOP and BOTTOM crossings (wrapped to [0, 2π)).
  late final double angleTop;     // = wrapAngle(angleRad ?? lane.angle)
  late final double angleBottom;  // = wrapAngle(angleBottomRad ?? (2π - angleTop))

  /// Cached window edges for top contact.
  late final double win1StartMs;  // = tContactMs - halfWinMs
  late final double win1EndMs;    // = tContactMs + halfWinMs

  /// Cached window edges for bottom contact (null if no tContactMs2).
  late final double? win2StartMs; // = tContactMs2 - halfWinMs
  late final double? win2EndMs;   // = tContactMs2 + halfWinMs

  /// Cached half window width (ms).
  late final double halfWinMs;    // = contactWindowMs * 0.5

  /// Angle (radians) where this obstacle can contact the player on TOP arc.
  /// For engine code that expects a single `angle` (TOP), keep this getter.
  double get angle => angleTop;

  /// Convenience: whether a bottom window exists.
  bool get hasBottom => tContactMs2 != null;

  /// Returns true if [tNowMs] is inside the obstacle's **top** contact window.
  bool isActiveAt(double tNowMs) => (tNowMs >= win1StartMs) && (tNowMs <= win1EndMs);

  /// Compute the derived fields once (or after edits) to avoid per-frame math.
  void _precompute() {
    final aTop = wrapAngle(angleRad ?? lane.angle);
    angleTop = aTop;

    // If a custom bottom angle is provided (diagonals), use it; else default.
    final ab = angleBottomRad != null ? wrapAngle(angleBottomRad!) : wrapAngle(2 * math.pi - aTop);
    angleBottom = ab;

    halfWinMs = contactWindowMs * 0.5;
    win1StartMs = tContactMs - halfWinMs;
    win1EndMs   = tContactMs + halfWinMs;

    if (tContactMs2 != null) {
      final t2 = tContactMs2!;
      win2StartMs = t2 - halfWinMs;
      win2EndMs   = t2 + halfWinMs;
    } else {
      win2StartMs = null;
      win2EndMs   = null;
    }
  }

  /// Returns a copy with selective overrides. Recomputes caches automatically.
  Obstacle copyWith({
    Lane? lane,
    ObType? type,
    double? tContactMs,
    double? contactWindowMs,
    bool? consumed,
    double? angleRad,
    double? angleBottomRad,
    double? tContactMs2,
    ObSize? size,
    double? travelMs,
    double? dxPerDy,
    int? id,
  }) {
    final out = Obstacle(
      lane: lane ?? this.lane,
      type: type ?? this.type,
      tContactMs: tContactMs ?? this.tContactMs,
      contactWindowMs: contactWindowMs ?? this.contactWindowMs,
      consumed: consumed ?? this.consumed,
      angleRad: angleRad ?? this.angleRad,
      angleBottomRad: angleBottomRad ?? this.angleBottomRad,
      tContactMs2: tContactMs2 ?? this.tContactMs2,
      size: size ?? this.size,
      travelMs: travelMs ?? this.travelMs,
      dxPerDy: dxPerDy ?? this.dxPerDy,
      id: id ?? this.id,
    );
    return out; // ctor already calls _precompute()
  }

  @override
  String toString() =>
      'Obstacle#$id(type:$type lane:${lane.label} aTop:${angleTop.toStringAsFixed(2)} '
      'aBot:${angleBottom.toStringAsFixed(2)} '
      't:${tContactMs.toStringAsFixed(1)}ms '
      '${hasBottom ? "t2:${tContactMs2!.toStringAsFixed(1)}ms " : ""}'
      'win:${contactWindowMs.toStringAsFixed(0)}ms '
      '${dxPerDy != null ? "dxPerDy:${dxPerDy!.toStringAsFixed(3)} " : ""}'
      'consumed:$consumed)';
}

int _nextId = 1;

/// Helper used by the engine to test if the player at angle [theta]
/// makes contact with this obstacle at time [tNowMs], using an angular
/// tolerance [deltaRad]. The caller decides how to respond to the result.
/// Returns true if the angular alignment is within tolerance **and** the
/// obstacle is inside its (top) contact window and not yet consumed.
bool isContactAligned(Obstacle o, double theta, double tNowMs, double deltaRad) {
  if (o.consumed) return false;
  if (!o.isActiveAt(tNowMs)) return false;
  return angularDistance(theta, o.angleTop) <= deltaRad;
}
