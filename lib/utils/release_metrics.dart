import 'dart:math' as math;
import 'dart:ui';

/// Result of a two-frame release measurement.
class ReleaseMetrics {
  const ReleaseMetrics({
    required this.speed,
    required this.releaseAngleDeg,
    this.attackAngleDeg,
  });

  /// Release speed in m/s.
  final double speed;

  /// Flight-path angle above horizontal, in degrees.
  final double releaseAngleDeg;

  /// Implement attitude minus flight-path angle (javelin); positive means
  /// nose above the flight path. Null when not measured.
  final double? attackAngleDeg;
}

/// Computes release metrics from four taps on the video.
///
/// [refA]/[refB] mark the implement's reference dimension on the release
/// frame (javelin tip then tail, or opposite edges of the ball), in widget
/// pixels; the known [referenceMeters] between them calibrates the scale.
/// [pointA] marks the implement on the release frame and [pointB] the same
/// spot [dtSeconds] later. Angles are mirrored so throws to the left read
/// the same as throws to the right.
ReleaseMetrics computeReleaseMetrics({
  required Offset refA,
  required Offset refB,
  required Offset pointA,
  required Offset pointB,
  required double referenceMeters,
  required double dtSeconds,
  bool withAttackAngle = false,
}) {
  final refPx = (refA - refB).distance;
  if (refPx == 0 || dtSeconds <= 0) {
    return const ReleaseMetrics(speed: 0, releaseAngleDeg: 0);
  }
  final metersPerPixel = referenceMeters / refPx;
  final d = pointB - pointA;
  final speed = d.distance * metersPerPixel / dtSeconds;

  // Screen y grows downward, so negate it; mirror leftward throws.
  final mirror = d.dx < 0 ? -1.0 : 1.0;
  final releaseAngle =
      math.atan2(-d.dy, d.dx * mirror) * 180 / math.pi;

  double? attack;
  if (withAttackAngle) {
    final axis = refA - refB; // tail → tip
    final attitude =
        math.atan2(-axis.dy, axis.dx * mirror) * 180 / math.pi;
    var diff = attitude - releaseAngle;
    // The tip/tail tap order is ambiguous; fold into [-90, 90].
    while (diff > 90) {
      diff -= 180;
    }
    while (diff < -90) {
      diff += 180;
    }
    attack = diff;
  }

  return ReleaseMetrics(
    speed: speed,
    releaseAngleDeg: releaseAngle,
    attackAngleDeg: attack,
  );
}
