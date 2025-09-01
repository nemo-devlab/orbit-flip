// engine/obstacle.dart
// Pure game-logic for obstacles.
// Core obstacle data models and angle helpers for Orbit Flip.
// This file is UI-agnostic and contains no Flutter imports.

import 'dart:math' as math;

/// Four spawn lanes aligned to screen edges.
/// \- We use **canvas angles** (0 rad points RIGHT, y increases DOWN):
///   RIGHT = 0, BOTTOM = π/2, LEFT = π, TOP = 3π/2.
/// Keep this consistent with rendering and collision checks.
enum Lane { top, right, bottom, left }

/// Obstacle type: [red] is a reward (collect = +1), [black] ends the run.
enum ObType { red, black }

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

  /// Human-friendly label for debugging.
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

/// An obstacle scheduled to reach the orbit radius at [tContactMs].
/// \- During the contact window (centered at [tContactMs] with width
///   [contactWindowMs]) collisions/collections are resolved.
/// \- Rendering may animate the obstacle traveling in/out, but the logic only
///   cares about the contact window.
class Obstacle {
  Obstacle({
    required this.lane,
    required this.type,
    required this.tContactMs,
    this.contactWindowMs = 120,
    this.consumed = false,
    this.angleRad,           // (already added earlier)
    this.tContactMs2,        // ← add this
    this.size,         // ← add
    this.travelMs,     // ← add (top→bottom travel time for THIS obstacle)
    int? id,
  }) : id = id ?? _nextId++ {
    assert(contactWindowMs > 0, 'contactWindowMs must be > 0');
  }

  /// Unique identifier. We treat equality by [id] for simple list/set usage.
  final int id;
  final Lane lane;
  final ObType type;
  final double tContactMs;        // existing (top crossing)
  final double? tContactMs2;      // ← add: optional bottom crossing time (ms)
  final double contactWindowMs; // width of the active window (ms)
  final double? angleRad;
  final ObSize? size;      // only used for black visuals/speed
  final double? travelMs;  // overrides default travel duration (ms) for this obstacle

  bool consumed; // set true when collected (red). Black ends run immediately.

  /// Angle (radians) where this obstacle can contact the player.
  double get angle => angleRad ?? lane.angle;

  /// Returns true if [tNowMs] is inside the obstacle's contact window.
  bool isActiveAt(double tNowMs) {
      final half = contactWindowMs * 0.5;
      final in1 = (tNowMs >= tContactMs - half) && (tNowMs <= tContactMs + half);
      if (in1) return true;
      final t2 = tContactMs2;
      if (t2 != null) {
        return (tNowMs >= t2 - half) && (tNowMs <= t2 + half);
      }
      return false;
    }

  /// Returns a copy with selective overrides.
    Obstacle copyWith({
    Lane? lane,
    ObType? type,
    double? tContactMs,
    double? contactWindowMs,
    bool? consumed,
    double? angleRad,
    double? tContactMs2,
    ObSize? size,       // ← add
    double? travelMs,   // ← add
    int? id,
  }) => Obstacle(
        lane: lane ?? this.lane,
        type: type ?? this.type,
        tContactMs: tContactMs ?? this.tContactMs,
        contactWindowMs: contactWindowMs ?? this.contactWindowMs,
        consumed: consumed ?? this.consumed,
        angleRad: angleRad ?? this.angleRad,
        tContactMs2: tContactMs2 ?? this.tContactMs2,
        size: size ?? this.size,           // ← add
        travelMs: travelMs ?? this.travelMs, // ← add
        id: id ?? this.id,
      );


  /// Stable, concise debug text.
  @override
  String toString() =>
      'Obstacle#$id(type: $type, lane: ${lane.label}, t: ${tContactMs.toStringAsFixed(1)}ms)';

  /// Equality by [id] so collections can de-dup consistently after (de)serialization.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Obstacle && other.id == id);

  @override
  int get hashCode => id.hashCode;

  // --- JSON ---
  Map<String, dynamic> toJson() => {
        'id': id,
        'lane': lane.name,
        'type': type.name,
        'tContactMs': tContactMs,
        'contactWindowMs': contactWindowMs,
        'consumed': consumed,
        'angleRad': angleRad, // ← add
        'tContactMs2': tContactMs2,   // ← add
        'size': size?.name,     // ← add
        'travelMs': travelMs,   // ← add
      };

    factory Obstacle.fromJson(Map<String, dynamic> j) => Obstacle(
      lane: Lane.values.firstWhere((e) => e.name == j['lane']),
      type: ObType.values.firstWhere((e) => e.name == j['type']),
      tContactMs: (j['tContactMs'] as num).toDouble(),
      tContactMs2: (j['tContactMs2'] as num?)?.toDouble(), // ← add
      contactWindowMs: (j['contactWindowMs'] as num?)?.toDouble() ?? 120,
      consumed: j['consumed'] as bool? ?? false,
      angleRad: (j['angleRad'] as num?)?.toDouble(), // ← add
      size: (j['size'] is String) ? ObSize.values.firstWhere(
        (e) => e.name == j['size'],
        orElse: () => ObSize.medium,
        ) : null,
      travelMs: (j['travelMs'] as num?)?.toDouble(),
      id: j['id'] as int?,
    );

}

int _nextId = 1;

/// Helper used by the engine to test if the player at angle [theta]
/// makes contact with this obstacle at time [tNowMs], using an angular
/// tolerance [deltaRad]. The caller decides how to respond to the result.
/// Returns true if the angular alignment is within tolerance **and** the
/// obstacle is inside its contact window and not yet consumed.
bool isContactAligned(Obstacle o, double theta, double tNowMs, double deltaRad) {
  if (o.consumed) return false;
  if (!o.isActiveAt(tNowMs)) return false;
  return angularDistance(theta, o.angle) <= deltaRad;
}

// -----------------------
// Contact resolution API
// -----------------------

/// Result of resolving contacts for the current frame.
class ContactOutcome {
  final List<Obstacle> collected; // newly-collected REDs (to remove & +score)
  final List<Obstacle> blacks;    // BLACKs that aligned this frame (to remove)
  const ContactOutcome({required this.collected, required this.blacks});

  bool get hitBlack => blacks.isNotEmpty;

  @override
  String toString() =>
      'ContactOutcome(collected: ${collected.length}, blacks: ${blacks.length})';
}


/// Checks all [obstacles] against the player angle [theta] at time [tNowMs].
ContactOutcome resolveContacts(
  Iterable<Obstacle> obstacles,
  double theta,
  double tNowMs,
  double deltaRad,
) {
  final collected = <Obstacle>[];
  final blacks = <Obstacle>[];

  for (final o in obstacles) {
    if (!isContactAligned(o, theta, tNowMs, deltaRad)) continue;
    if (o.type == ObType.red) {
      o.consumed = true;
      collected.add(o);
    } else {
      blacks.add(o);
    }
  }

  return ContactOutcome(collected: collected, blacks: blacks);
}

/// True when an obstacle's active window has fully passed relative to [tNowMs].
bool isExpired(Obstacle o, double tNowMs) => tNowMs > (o.tContactMs + o.contactWindowMs * 0.5);

/// Remove expired obstacles from [list]. Optionally keep consumed reds around
/// for UI animations by setting [removeConsumed] = false.
int cullExpired(List<Obstacle> list, double tNowMs, {bool removeConsumed = true}) {
  final before = list.length;
  list.removeWhere((o) => isExpired(o, tNowMs) && (removeConsumed || !o.consumed));
  return before - list.length; // number removed
}
