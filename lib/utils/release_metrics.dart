import 'dart:math' as math;
import 'dart:ui';

import '../models/throw_event.dart';
import 'flight_model.dart';

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

  /// Implement attitude minus flight-path angle, as the camera sees it side
  /// on (javelin and discus); positive means the nose, or the leading edge,
  /// above the flight path. Null when not measured.
  final double? attackAngleDeg;
}

/// Computes release metrics from four taps on the video.
///
/// Ball events: [refA]/[refB] mark opposite edges of the ball on the
/// release frame, in widget pixels; the known [referenceMeters] between
/// them calibrates the scale. [pointA] marks the ball's center on the
/// release frame and [pointB] the same spot [dtSeconds] later.
///
/// Discus ([discus] true): the same taps, with [refA]/[refB] on its front
/// and back rims — the two ends of its long side in the picture. A circle
/// seen at any tilt is an ellipse whose long axis is still the whole
/// diameter, so the scale holds; and that axis is the disc's attitude as
/// the camera sees it, so the attack angle comes out of the same two taps.
///
/// Javelin ([javelin] true): [refA]/[refB] are tip and tail on the release
/// frame, [pointA]/[pointB] tip and tail again [dtSeconds] later. Speed
/// tracks the shaft midpoint, the scale averages both tapped lengths, and
/// the attack angle compares the averaged shaft attitude with the flight
/// path.
///
/// Angles are mirrored so throws to the left read the same as throws to
/// the right.
///
/// The chord between the two frames equals the instantaneous velocity at
/// the interval's midpoint, by which time gravity has already removed
/// g·dt/2 of vertical speed; that is added back so the result is the true
/// release velocity. Pass [gravity] 0 to disable (e.g. geometry tests).
ReleaseMetrics computeReleaseMetrics({
  required Offset refA,
  required Offset refB,
  required Offset pointA,
  required Offset pointB,
  required double referenceMeters,
  required double dtSeconds,
  bool javelin = false,
  bool discus = false,
  double gravity = 9.80665,
}) {
  if (javelin) {
    return _javelinMetrics(
        refA, refB, pointA, pointB, referenceMeters, dtSeconds, gravity);
  }
  final refPx = (refA - refB).distance;
  if (refPx == 0 || dtSeconds <= 0) {
    return const ReleaseMetrics(speed: 0, releaseAngleDeg: 0);
  }
  final metersPerPixel = referenceMeters / refPx;
  final d = pointB - pointA;
  // Screen y grows downward: gravity is +y, so the midpoint correction
  // subtracts from the screen-space vertical velocity.
  final vx = d.dx * metersPerPixel / dtSeconds;
  final vy = d.dy * metersPerPixel / dtSeconds - gravity * dtSeconds / 2;
  final speed = math.sqrt(vx * vx + vy * vy);

  // Negate y so up is positive; mirror leftward throws.
  final mirror = vx < 0 ? -1.0 : 1.0;
  final releaseAngle = math.atan2(-vy, vx * mirror) * 180 / math.pi;
  if (!discus) {
    return ReleaseMetrics(speed: speed, releaseAngleDeg: releaseAngle);
  }
  // Which rim was tapped first says nothing, so the line is folded to
  // whichever way points downrange.
  final rim = refB - refA;
  final attitude = math.atan2(-rim.dy, rim.dx * mirror) * 180 / math.pi;
  return ReleaseMetrics(
    speed: speed,
    releaseAngleDeg: releaseAngle,
    attackAngleDeg: _fold(attitude - releaseAngle),
  );
}

/// An angle between a line and the path, into [-90, 90]: a line has no
/// direction, so one read end for end is the same line.
double _fold(double deg) {
  while (deg > 90) {
    deg -= 180;
  }
  while (deg < -90) {
    deg += 180;
  }
  return deg;
}

ReleaseMetrics _javelinMetrics(
  Offset tipA,
  Offset tailA,
  Offset tipB,
  Offset tailB,
  double referenceMeters,
  double dtSeconds,
  double gravity,
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
  // Midpoint gravity correction, as in computeReleaseMetrics.
  final vx = d.dx * metersPerPixel / dtSeconds;
  final vy = d.dy * metersPerPixel / dtSeconds - gravity * dtSeconds / 2;
  final speed = math.sqrt(vx * vx + vy * vy);

  final mirror = vx < 0 ? -1.0 : 1.0;
  final releaseAngle = math.atan2(-vy, vx * mirror) * 180 / math.pi;
  final attitudeA = math.atan2(-axisA.dy, axisA.dx * mirror) * 180 / math.pi;
  final attitudeB = math.atan2(-axisB.dy, axisB.dx * mirror) * 180 / math.pi;
  // A consistently reversed tip/tail order flips the attitude by 180°.
  return ReleaseMetrics(
    speed: speed,
    releaseAngleDeg: releaseAngle,
    attackAngleDeg: _fold((attitudeA + attitudeB) / 2 - releaseAngle),
  );
}

/// What a measured release comes to, flown exactly as the what-if
/// calculator flies it — the same model, the same speed lost going higher —
/// so the sheet under a clip and the screen its 'What if…' opens can't
/// disagree. Still air, since a clip does not say what the wind was, from
/// [height], since four taps don't measure one. [release] is what the
/// calculator is handed.
({Release release, double distance, double bestAngleDeg, double lostToAngle})
    flyMeasured(ThrowEvent event, ImplementSpec spec, ReleaseMetrics metrics,
        {required double height}) {
  final release = Release(
    speed: metrics.speed,
    angleDeg: metrics.releaseAngleDeg,
    height: height,
    attackDeg: metrics.attackAngleDeg ?? 0,
  );
  final distance = flyThrow(event, spec, release).distance;
  final best = bestAngle(event, spec, release,
      speedLossPerDeg: typicalSpeedLossPerDeg(event));
  return (
    release: release,
    distance: distance,
    bestAngleDeg: best.angleDeg,
    lostToAngle: math.max(0.0, best.distance - distance),
  );
}
