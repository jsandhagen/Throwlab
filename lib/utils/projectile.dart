/// Vacuum-ballistics helpers for the release-metrics features.
///
/// Good first approximations for shot put and hammer; discus and javelin
/// will need aerodynamic corrections (lift/drag) before predictions are
/// trustworthy — see ROADMAP.md.
library;

import 'dart:math' as math;

const double gravity = 9.80665;

double _radians(double degrees) => degrees * math.pi / 180;

/// Horizontal distance for a release at [speed] (m/s), [angleDeg] above
/// horizontal, from [releaseHeight] meters above the landing plane.
double predictedDistance(double speed, double angleDeg,
    {double releaseHeight = 0}) {
  if (speed <= 0) return 0;
  final theta = _radians(angleDeg);
  final vx = speed * math.cos(theta);
  final vy = speed * math.sin(theta);
  return vx * (vy + math.sqrt(vy * vy + 2 * gravity * releaseHeight)) /
      gravity;
}

/// Time from release to landing, in seconds.
double flightTime(double speed, double angleDeg, {double releaseHeight = 0}) {
  final vy = speed * math.sin(_radians(angleDeg));
  return (vy + math.sqrt(vy * vy + 2 * gravity * releaseHeight)) / gravity;
}

/// Distance-maximizing release angle (degrees) for a given speed and
/// release height. With a raised release point the optimum drops below 45°.
double optimalAngleDeg(double speed, {double releaseHeight = 0}) {
  if (speed <= 0) return 45;
  final sinTheta =
      1 / math.sqrt(2 + 2 * gravity * releaseHeight / (speed * speed));
  return math.asin(sinTheta) * 180 / math.pi;
}

/// Meters left on the table by releasing at [actualAngleDeg] instead of the
/// optimal angle: "your speed was X, optimal angle was Y, cost Z meters".
double distanceLostToAngle(double speed, double actualAngleDeg,
    {double releaseHeight = 0}) {
  final best = predictedDistance(
      speed, optimalAngleDeg(speed, releaseHeight: releaseHeight),
      releaseHeight: releaseHeight);
  final actual =
      predictedDistance(speed, actualAngleDeg, releaseHeight: releaseHeight);
  return best - actual;
}
