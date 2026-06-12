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
/// Ball events: [refA]/[refB] mark opposite edges of the ball on the
/// release frame, in widget pixels; the known [referenceMeters] between
/// them calibrates the scale. [pointA] marks the ball's center on the
/// release frame and [pointB] the same spot [dtSeconds] later.
///
/// Javelin ([javelin] true): [refA]/[refB] are tip and tail on the release
/// frame, [pointA]/[pointB] tip and tail again [dtSeconds] later. Speed
/// tracks the shaft midpoint, the scale averages both tapped lengths, and
/// the attack angle compares the averaged shaft attitude with the flight
/// path.
///
/// Angles are mirrored so throws to the left read the same as throws to
/// the right.
ReleaseMetrics computeReleaseMetrics({
  required Offset refA,
  required Offset refB,
  required Offset pointA,
  required Offset pointB,
  required double referenceMeters,
  required double dtSeconds,
  bool javelin = false,
}) {
  if (javelin) {
    return _javelinMetrics(
        refA, refB, pointA, pointB, referenceMeters, dtSeconds);
  }
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

  return ReleaseMetrics(speed: speed, releaseAngleDeg: releaseAngle);
}

ReleaseMetrics _javelinMetrics(
  Offset tipA,
  Offset tailA,
  Offset tipB,
  Offset tailB,
  double referenceMeters,
  double dtSeconds,
) {
  final axisA = tipA - tailA; // tail → tip
  var axisB = tipB - tailB;
  if (axisA.distance == 0 || axisB.distance == 0 || dtSeconds <= 0) {
    return const ReleaseMetrics(speed: 0, releaseAngleDeg: 0);
  }
  // Tolerate the tip/tail order being swapped on one frame.
  if (axisA.dx * axisB.dx + axisA.dy * axisB.dy < 0) {
    axisB = -axisB;
  }
  final metersPerPixel =
      referenceMeters / ((axisA.distance + axisB.distance) / 2);
  final d = (tipB + tailB) / 2 - (tipA + tailA) / 2;
  final speed = d.distance * metersPerPixel / dtSeconds;

  final mirror = d.dx < 0 ? -1.0 : 1.0;
  final releaseAngle =
      math.atan2(-d.dy, d.dx * mirror) * 180 / math.pi;
  final attitudeA =
      math.atan2(-axisA.dy, axisA.dx * mirror) * 180 / math.pi;
  final attitudeB =
      math.atan2(-axisB.dy, axisB.dx * mirror) * 180 / math.pi;
  var diff = (attitudeA + attitudeB) / 2 - releaseAngle;
  // A consistently reversed tip/tail order flips the attitude by 180°;
  // fold into [-90, 90].
  while (diff > 90) {
    diff -= 180;
  }
  while (diff < -90) {
    diff += 180;
  }

  return ReleaseMetrics(
    speed: speed,
    releaseAngleDeg: releaseAngle,
    attackAngleDeg: diff,
  );
}
