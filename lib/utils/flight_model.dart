/// An implement's flight through air, for the what-if calculator.
///
/// `projectile.dart` answers in a vacuum, which is fair for a shot and
/// wrong for anything that flies: a discus and a javelin are carried by
/// lift, and a hammer loses a couple of meters to drag at the speeds that
/// win championships. This steps the flight in small slices of time with
/// both forces on it, so every event gets a distance and the same model
/// answers every what-if.
///
/// A point mass with an attitude, in the plane of the throw. The javelin's
/// attitude is a rigid body's — it pitches under the moment of its center
/// of pressure sitting behind its center of mass — and the discus's is held,
/// the way a spinning disc holds it. The aerodynamic coefficients are the
/// shapes the wind-tunnel literature reports (lift climbing with angle of
/// attack until the flow separates, drag growing with its square), scaled
/// against releases measured at championship finals — see [Aero] for how
/// close each event gets. That makes the answer a good estimate of *how
/// much* a change is worth and an approximate one of the mark itself, and
/// the screen says so.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/throw_event.dart';
import 'projectile.dart' show gravity;

/// Air at a warm afternoon at sea level, kg/m³.
const double airDensity = 1.2;

double _rad(double deg) => deg * math.pi / 180;

// The four numbers below are tuned rather than looked up: nothing in the
// open literature gives them, and each was set so the flights it governs
// behave the way the rest of this file says they should.

/// What a javelin's moment of inertia is of a uniform rod's.
const _javelinTaper = 0.8;

/// C_mq, set so a javelin's pitch oscillation has died away within a
/// second or two rather than rocking it all the way down the field.
const _javelinPitchDamping = 0.15;

/// The attack at which a javelin's center of pressure reaches its center
/// of mass — halfway there at half of it.
const _javelinCpZeroDeg = 60.0;

/// The share of a discus's peak lift left once the flow has let go.
const _discusStalledLift = 0.6;

/// What the athlete controls at the moment the implement leaves the hand.
class Release {
  const Release({
    required this.speed,
    required this.angleDeg,
    required this.height,
    this.attackDeg = 0,
    this.wind = 0,
    this.pitchRate = 0,
  });

  /// m/s, along the flight path.
  final double speed;

  /// Flight-path angle above horizontal.
  final double angleDeg;

  /// Meters above the ground it lands on.
  final double height;

  /// Implement attitude minus flight-path angle — nose (or leading edge)
  /// above the path is positive. Only a discus and a javelin have one.
  final double attackDeg;

  /// m/s along the throw: positive at the athlete's back, negative in
  /// their face.
  final double wind;

  /// °/s the implement is already turning at as it leaves the hand, nose
  /// up positive. Only a javelin pitches: it is the one that is a rigid
  /// body here rather than a gyroscope.
  final double pitchRate;

  Release copyWith({
    double? speed,
    double? angleDeg,
    double? height,
    double? attackDeg,
    double? wind,
    double? pitchRate,
  }) =>
      Release(
        speed: speed ?? this.speed,
        angleDeg: angleDeg ?? this.angleDeg,
        height: height ?? this.height,
        attackDeg: attackDeg ?? this.attackDeg,
        wind: wind ?? this.wind,
        pitchRate: pitchRate ?? this.pitchRate,
      );
}

/// How an implement meets the air.
///
/// Every coefficient is referenced to [area], and the attitude either holds
/// ([pitchInertia] zero — a spinning discus is a gyroscope, and keeps the
/// tilt it was released at all the way down; Hubbard and Cheng's discus
/// turns mainly in roll, which a flight in one plane has no axis for) or
/// pitches as a rigid body under the moment of its center of pressure,
/// which is what a javelin's tail does to its nose.
class Aero {
  const Aero({
    required this.area,
    required this.dragBase,
    this.dragPerAttack = 0,
    this.liftSlope = 0,
    this.stallDeg = 90,
    double? recoverDeg,
    this.stalledLift = 1,
    this.liftZeroDeg = 90,
    this.length = 0,
    this.cpBehind = 0,
    this.cpZeroDeg = 90,
    this.pitchInertia = 0,
    this.pitchDamping = 0,
  }) : recoverDeg = recoverDeg ?? stallDeg;

  /// Reference area, m².
  final double area;

  /// Drag coefficient with the implement edge-on to the air.
  final double dragBase;

  /// Drag added per sin²α — the implement turned into the flow.
  final double dragPerAttack;

  /// Lift per radian of attack, before the flow separates.
  final double liftSlope;

  /// Past this the flow comes off the upper surface and lift falls away.
  final double stallDeg;

  /// Once stalled, the flow only comes back on below this — a separated
  /// flow does not reattach at the angle it let go at. Equal to [stallDeg]
  /// where the implement has no hysteresis worth modeling.
  final double recoverDeg;

  /// The share of the lift at the stall that is left the moment the flow
  /// separates.
  final double stalledLift;

  /// Where the lift left after the stall has run down to nothing.
  final double liftZeroDeg;

  /// Meters from tip to tail, for the pitch damping's lever.
  final double length;

  /// Meters the center of pressure sits behind the center of mass at a
  /// small angle of attack.
  final double cpBehind;

  /// The attack at which the center of pressure has closed all the way up
  /// to the center of mass; it closes on it linearly from [cpBehind].
  final double cpZeroDeg;

  /// kg·m² about the center of mass, across the shaft. Zero holds the
  /// attitude fixed.
  final double pitchInertia;

  /// C_mq: the pitch damping coefficient, referenced to [area] and
  /// [length]².
  final double pitchDamping;

  bool get hasAttitude => liftSlope > 0;

  bool get pitches => hasAttitude && pitchInertia > 0;

  bool stallsAt(double alpha) => alpha.abs() > _rad(stallDeg);

  bool recoversAt(double alpha) => alpha.abs() < _rad(recoverDeg);

  double drag(double alpha) {
    final s = math.sin(alpha);
    return dragBase + dragPerAttack * s * s;
  }

  /// Linear up to the stall, then a drop to [stalledLift] of it and a
  /// straight run down to nothing at [liftZeroDeg]. [stalled] keeps the
  /// implement on that second branch down to [recoverDeg] even though the
  /// angle is back under the stall.
  double lift(double alpha, {bool stalled = false}) {
    final a = alpha.abs();
    final stall = _rad(stallDeg);
    final double magnitude;
    if (!stalled && a <= stall) {
      magnitude = liftSlope * a;
    } else {
      final zero = _rad(liftZeroDeg);
      magnitude = liftSlope *
          stall *
          stalledLift *
          math.max(0, (zero - a) / (zero - stall));
    }
    return alpha.sign * magnitude;
  }

  /// m: how far behind the center of mass the center of pressure is at
  /// [alpha]. Forward as the implement turns into the flow.
  double cpOffset(double alpha) =>
      cpBehind * math.max(0, 1 - alpha.abs() / _rad(cpZeroDeg));

  /// The air an implement of [spec] flies through as.
  ///
  /// A shot and a hammer's head are spheres, at a sphere's drag. The
  /// hammer's wire and handle drag too and are not in here, which is the
  /// model erring long.
  ///
  /// The javelin was set so an 800 g release at 29 m/s and 35° lands in
  /// the high eighties, where finals are won, with the best angle in the
  /// mid-thirties and a nose held well above the path costing distance —
  /// the three things the javelin literature agrees on.
  ///
  /// The discus is the weak one, and errs short on purpose. A point mass
  /// held at a fixed tilt cannot both throw as far as a championship
  /// final does and keep its best angle in the thirties: every bit of lift
  /// added to reach the mark drags the best angle down into the twenties,
  /// which is a flat throw nobody coaches. The best angle was kept; an
  /// elite release comes out several meters short of what it was measured
  /// to throw, and the screen says that.
  factory Aero.of(ThrowEvent event, ImplementSpec spec) {
    switch (event) {
      case ThrowEvent.shotPut:
      case ThrowEvent.hammer:
        final r = spec.nominalSize / 2;
        return Aero(area: math.pi * r * r, dragBase: 0.5);
      case ThrowEvent.discus:
        final r = spec.nominalSize / 2;
        // The tunnel's stall is at 28–30° and the flow does not come back on
        // until about 25°; what is left after it runs down to nothing only
        // at 90°, face on to the air.
        return Aero(
          area: math.pi * r * r,
          dragBase: 0.07,
          dragPerAttack: 2.5,
          liftSlope: 2.8,
          stallDeg: 29,
          recoverDeg: 25,
          stalledLift: _discusStalledLift,
          liftZeroDeg: 90,
        );
      case ThrowEvent.javelin:
        // Side-on area of the shaft: its length by its thickest diameter,
        // which grows with the weight the way the rules have it.
        final length = spec.nominalSize;
        final diameter = 0.020 + 0.010 * spec.weightKg;
        return Aero(
          area: length * diameter,
          dragBase: 0.015,
          dragPerAttack: 1.1,
          liftSlope: 0.45,
          stallDeg: 25,
          liftZeroDeg: 40,
          length: length,
          // Schneeberger (2009): 14.3 cm behind for the men's 2.6–2.7 m
          // javelin and 12.6 cm for the women's 2.2–2.3 m, and on a line
          // through the two for the lengths between and beyond.
          cpBehind: 0.126 + (0.143 - 0.126) / (2.65 - 2.25) * (length - 2.25),
          cpZeroDeg: _javelinCpZeroDeg,
          // A uniform rod is mL²/12; a javelin tapers to both ends, so it is
          // less than that by a share nobody has published.
          pitchInertia: _javelinTaper * spec.weightKg * length * length / 12,
          pitchDamping: _javelinPitchDamping,
        );
    }
  }
}

/// Where a release goes.
class Flight {
  const Flight({
    required this.distance,
    required this.time,
    required this.apex,
    required this.path,
  });

  /// Measured along the ground from the release point, meters. The tape is
  /// run from the inside of the stop board, and the hand is usually a few
  /// tenths out past it at release, so a mark reads a little further than
  /// this.
  final double distance;

  /// Seconds in the air.
  final double time;

  /// Highest point above the ground, meters.
  final double apex;

  /// The flight as (along, up) in meters, from release to landing, sampled
  /// often enough to draw.
  final List<Offset> path;
}

/// Flies [release] with [aero] and a [mass] in kilograms.
///
/// Fourth-order Runge–Kutta at 2 ms, and the landing found by
/// interpolating the last step across the ground, so the answer moves
/// smoothly under a slider rather than in steps of the time slice.
Flight fly(Release release, Aero aero, double mass) {
  if (release.speed <= 0) {
    return Flight(
        distance: 0,
        time: 0,
        apex: release.height,
        path: [Offset(0, release.height)]);
  }
  const dt = 0.002;
  final k = airDensity * aero.area / (2 * mass);
  final gamma0 = _rad(release.angleDeg);

  // State: x, y, vx, vy, attitude, pitch rate.
  var s = [
    0.0,
    release.height,
    release.speed * math.cos(gamma0),
    release.speed * math.sin(gamma0),
    gamma0 + (aero.hasAttitude ? _rad(release.attackDeg) : 0),
    aero.pitches ? _rad(release.pitchRate) : 0.0,
  ];

  double alphaOf(List<double> s) =>
      aero.hasAttitude ? s[4] - math.atan2(s[3], s[2] - release.wind) : 0.0;

  // Whether the flow is off the upper surface. It is a memory rather than
  // a function of the angle — that is the hysteresis — so it is held for a
  // whole step and moved only between them.
  var stalled = aero.stallsAt(alphaOf(s));

  List<double> derivative(List<double> s) {
    final ux = s[2] - release.wind;
    final uy = s[3];
    final u = math.sqrt(ux * ux + uy * uy);
    var ax = 0.0;
    var ay = -gravity;
    var dRate = 0.0;
    if (u > 1e-9) {
      final alpha = alphaOf(s);
      final cd = aero.drag(alpha);
      final cl = aero.lift(alpha, stalled: stalled);
      final d = k * cd * u;
      final l = k * cl * u;
      // Drag straight back along the air's velocity, lift square to it.
      ax += -d * ux - l * uy;
      ay += -d * uy + l * ux;
      if (aero.pitches) {
        // The force across the shaft, acting at the center of pressure: a
        // nose above the path is pushed back down onto it.
        final q = 0.5 * airDensity * aero.area * u * u;
        final normal = q * (cl * math.cos(alpha) + cd * math.sin(alpha));
        final moment = -aero.cpOffset(alpha) * normal;
        final damping = -0.5 *
            airDensity *
            u *
            aero.area *
            aero.length *
            aero.length *
            aero.pitchDamping *
            s[5];
        dRate = (moment + damping) / aero.pitchInertia;
      }
    }
    return [s[2], s[3], ax, ay, s[5], dRate];
  }

  List<double> step(List<double> s, List<double> d, double h) =>
      [for (var i = 0; i < s.length; i++) s[i] + d[i] * h];

  final path = <Offset>[Offset(0, release.height)];
  var t = 0.0;
  var apex = release.height;
  var steps = 0;
  // A minute of flight is a release nothing in athletics produces; the cap
  // is only there so a nonsense input can't spin the loop forever.
  while (t < 60) {
    final k1 = derivative(s);
    final k2 = derivative(step(s, k1, dt / 2));
    final k3 = derivative(step(s, k2, dt / 2));
    final k4 = derivative(step(s, k3, dt));
    final next = [
      for (var i = 0; i < s.length; i++)
        s[i] + dt / 6 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
    ];
    if (next[1] <= 0) {
      final f = s[1] / (s[1] - next[1]);
      final x = s[0] + (next[0] - s[0]) * f;
      path.add(Offset(x, 0));
      return Flight(distance: x, time: t + dt * f, apex: apex, path: path);
    }
    s = next;
    t += dt;
    final alpha = alphaOf(s);
    if (!stalled && aero.stallsAt(alpha)) stalled = true;
    if (stalled && aero.recoversAt(alpha)) stalled = false;
    apex = math.max(apex, s[1]);
    if (++steps % 10 == 0) path.add(Offset(s[0], s[1]));
  }
  return Flight(distance: s[0], time: t, apex: apex, path: path);
}

/// [release] thrown with [spec] at [event].
Flight flyThrow(ThrowEvent event, ImplementSpec spec, Release release) =>
    fly(release, Aero.of(event, spec), spec.weightKg);

/// The release angle that throws furthest with everything else held, found
/// by golden-section search between 5° and 60° — every event's best is in
/// there, and one peak is all the curve has.
///
/// Everything else held is the catch, and the screen says it: a real
/// athlete releasing higher releases slower (Linthorne 2001), so the angle
/// that is best for a person sits a few degrees under this one.
({double angleDeg, double distance}) bestAngle(
    ThrowEvent event, ImplementSpec spec, Release release) {
  final aero = Aero.of(event, spec);
  double at(double deg) =>
      fly(release.copyWith(angleDeg: deg), aero, spec.weightKg).distance;
  const phi = 0.6180339887498949;
  var lo = 5.0;
  var hi = 60.0;
  var a = hi - phi * (hi - lo);
  var b = lo + phi * (hi - lo);
  var fa = at(a);
  var fb = at(b);
  while (hi - lo > 0.05) {
    if (fa < fb) {
      lo = a;
      a = b;
      fa = fb;
      b = lo + phi * (hi - lo);
      fb = at(b);
    } else {
      hi = b;
      b = a;
      fb = fa;
      a = hi - phi * (hi - lo);
      fa = at(a);
    }
  }
  final angle = (lo + hi) / 2;
  return (angleDeg: angle, distance: at(angle));
}

/// What each lever is worth from here: meters gained for [speedStep] more
/// m/s, one more degree, and [heightStep] more meters of height — one m/s
/// and ten centimeters by default, a mile an hour and four inches for a
/// coach reading in feet. The comparison the research keeps coming back
/// to — speed is worth far more than angle — and the one a coach can do
/// something with.
({double perSpeed, double perDegree, double perHeight}) sensitivity(
    ThrowEvent event, ImplementSpec spec, Release release,
    {double speedStep = 1, double heightStep = 0.1}) {
  final aero = Aero.of(event, spec);
  double at(Release r) => fly(r, aero, spec.weightKg).distance;
  final base = at(release);
  return (
    perSpeed: at(release.copyWith(speed: release.speed + speedStep)) - base,
    perDegree: at(release.copyWith(angleDeg: release.angleDeg + 1)) - base,
    perHeight: at(release.copyWith(height: release.height + heightStep)) - base,
  );
}
