/// A javelin's aerodynamics as measured in a wind tunnel, for the flight
/// model.
///
/// Seo K, Okuizumi H, Konishi Y, Kobayashi T, Hasegawa H, Obayashi S (2023).
/// Measurement of aerodynamic force and moment acting on a javelin using a
/// magnetic suspension and balance system. Sci Rep 13:391 (CC BY 4.0).
/// A women's 600 g javelin (Nishi Hybrid Genome X, 2.21 m, 24.7 mm at its
/// thickest) held in the air by magnets at 25 m/s, so nothing touched it —
/// the one open measurement of a modern javelin with no support rod
/// disturbing the flow. Digitized by hand from Fig. 10, the vibrating case,
/// which the paper finds almost the same as the still one; C_m at 0° read as
/// −0.01 and set to 0, since the paper says it is almost nothing there.
///
/// The coefficients are referenced as the paper does: the cross-section at
/// the thickest point, and the length for the moment, taken about the center
/// of mass. No men's javelin has been measured this way, so every weight
/// flies on these coefficients with its own length and diameter, and the
/// screen says so.
///
/// What the table is for is the shape of C_m: nose-up below about 11° and
/// nose-down above, so a released javelin settles at that attack and rides
/// it down the field — the lift a tuned point mass had to be given by hand.
library;

import 'dart:math' as math;

double _rad(double deg) => deg * math.pi / 180;

/// Fig. 10 a row an angle: attack in degrees, then C_D, C_L and C_m.
const _table = [
  (0.0, 1.30, 0.00, 0.00),
  (2.0, 1.50, 0.10, 0.01),
  (4.0, 1.65, 0.45, 0.02),
  (5.0, 1.75, 0.65, 0.02),
  (6.0, 1.80, 0.80, 0.03),
  (8.0, 2.00, 1.40, 0.04),
  (10.0, 2.10, 2.35, 0.01),
  (12.0, 2.45, 3.55, -0.03),
  (14.0, 2.85, 4.95, -0.13),
  (15.0, 3.15, 5.70, -0.21),
  (16.0, 3.50, 6.35, -0.33),
  (18.0, 4.45, 8.35, -0.66),
];

/// The last measured attack; past it the table is carried on along its last
/// segment.
const javelinMeasuredToDeg = 18.0;

/// How far the last segment is carried on. Past this nothing was measured
/// and nothing about the trend is safe to extend: drag and moment hold, and
/// the lift runs down to nothing by 90°, side-on to the air.
const _extendToDeg = 30.0;

double _lookup(
    double Function((double, double, double, double)) column, double deg) {
  final a = math.min(deg, _extendToDeg);
  var i = _table.length - 2;
  for (var j = 0; j < _table.length - 1; j++) {
    if (a <= _table[j + 1].$1) {
      i = j;
      break;
    }
  }
  final (lo, hi) = (_table[i], _table[i + 1]);
  final t = (a - lo.$1) / (hi.$1 - lo.$1);
  return column(lo) + t * (column(hi) - column(lo));
}

double _deg(double alpha) => alpha.abs() * 180 / math.pi;

/// Drag coefficient, the same either side of the path.
double javelinDrag(double alpha) => _lookup((r) => r.$2, _deg(alpha));

/// Lift coefficient, signed with the attack.
double javelinLift(double alpha) {
  final deg = _deg(alpha);
  final fade = deg <= _extendToDeg
      ? 1.0
      : math.max(0.0, (90 - deg) / (90 - _extendToDeg));
  return alpha.sign * _lookup((r) => r.$3, deg) * fade;
}

/// Pitching moment coefficient about the center of mass, nose up positive,
/// signed with the attack.
double javelinMoment(double alpha) =>
    alpha.sign * _lookup((r) => r.$4, _deg(alpha));

/// The thickest diameter of a javelin of [weightKg], meters: the tested
/// women's 600 g, the men's 800 g (Nordic Master 60, Chowdhury et al. 2013),
/// and on a line through the two for the weights between and beyond.
double javelinDiameter(double weightKg) =>
    0.0247 + (0.0295 - 0.0247) / 0.2 * (weightKg - 0.6);

/// C_mq for the damping moment, referenced like the table. A shaft turning
/// at ω meets the air at ωx/u more attack x along it, and summing that
/// normal force's moment down a uniform shaft gives C_Nα / 12. The table's
/// normal force is not a straight line in the attack, so its slope is read
/// as the secant out to 8°, where the javelin spends its flight's first
/// half: lift over the angle, plus the drag the normal force carries.
final javelinPitchDamping =
    (javelinLift(_rad(8)) / _rad(8) + javelinDrag(0)) / 12;
