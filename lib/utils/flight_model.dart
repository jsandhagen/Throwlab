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
/// attitude is a rigid body's, pitching under the moment the wind tunnel
/// measured on it (`javelin_aero.dart`), and the discus's is held, the way
/// a spinning disc holds it. The discus's coefficients are the shapes the
/// wind-tunnel literature reports (lift climbing with angle of attack until
/// the flow separates, drag growing with its square), scaled against
/// releases measured at championship finals; the javelin's are measured and
/// not tuned at all — see [Aero] for how close each event gets. That makes the answer a good estimate of *how
/// much* a change is worth and an approximate one of the mark itself, and
/// the screen says so.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/throw_event.dart';
import 'javelin_aero.dart';
import 'projectile.dart' show gravity;

/// Air at a warm afternoon at sea level, kg/m³.
const double airDensity = 1.2;

double _rad(double deg) => deg * math.pi / 180;

// The two numbers below are tuned rather than looked up: nothing in the
// open literature gives them, and each was set so the flights it governs
// behave the way the rest of this file says they should.

/// What a javelin's moment of inertia is of a uniform rod's.
const _javelinTaper = 0.8;

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
/// pitches as a rigid body under its measured pitching moment, which is
/// what a javelin's tail does to its nose.
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
    this.measured = false,
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

  /// Whether the coefficients come off the javelin's wind-tunnel table
  /// rather than the curve-shaped ones above, which then go unused.
  final bool measured;

  /// kg·m² about the center of mass, across the shaft. Zero holds the
  /// attitude fixed.
  final double pitchInertia;

  /// C_mq: the pitch damping coefficient, referenced to [area] and
  /// [length]².
  final double pitchDamping;

  bool get hasAttitude => measured || liftSlope > 0;

  bool get pitches => hasAttitude && pitchInertia > 0;

  bool stallsAt(double alpha) => alpha.abs() > _rad(stallDeg);

  bool recoversAt(double alpha) => alpha.abs() < _rad(recoverDeg);

  double drag(double alpha) {
    if (measured) return javelinDrag(alpha);
    final s = math.sin(alpha);
    return dragBase + dragPerAttack * s * s;
  }

  /// Linear up to the stall, then a drop to [stalledLift] of it and a
  /// straight run down to nothing at [liftZeroDeg]. [stalled] keeps the
  /// implement on that second branch down to [recoverDeg] even though the
  /// angle is back under the stall.
  double lift(double alpha, {bool stalled = false}) {
    if (measured) return javelinLift(alpha);
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

  /// Pitching moment coefficient about the center of mass, nose up
  /// positive, referenced to [area] and [length].
  double moment(double alpha) => measured ? javelinMoment(alpha) : 0;

  /// The air an implement of [spec] flies through as.
  ///
  /// A shot and a hammer's head are spheres, at a sphere's drag. The
  /// hammer's wire and handle drag too and are not in here, which is the
  /// model erring long.
  ///
  /// The javelin is measured rather than set: Seo et al.'s table, with
  /// nothing tuned to make it land anywhere, puts a typical men's final
  /// release in the mid-eighties and a women's in the low sixties, which is
  /// where finals are won.
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
        // The table is referenced to the cross-section at the thickest
        // point, and its moment to the whole length, about the center of
        // mass.
        final length = spec.nominalSize;
        final diameter = javelinDiameter(spec.weightKg);
        return Aero(
          area: math.pi * diameter * diameter / 4,
          dragBase: javelinDrag(0),
          measured: true,
          length: length,
          // A uniform rod is mL²/12; a javelin tapers to both ends, so it is
          // less than that by a share nobody has published.
          pitchInertia: _javelinTaper * spec.weightKg * length * length / 12,
          pitchDamping: javelinPitchDamping,
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

  // Wrapped, so a javelin sent tumbling by a slider at its end reads the
  // angle it is actually meeting the air at rather than a turn and a half.
  double alphaOf(List<double> s) {
    if (!aero.hasAttitude) return 0;
    final a = s[4] - math.atan2(s[3], s[2] - release.wind);
    return math.atan2(math.sin(a), math.cos(a));
  }

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
        // What the tunnel measured: nose-up under about 11° of attack and
        // nose-down over it, so the javelin settles there and rides it.
        final moment = 0.5 *
            airDensity *
            u *
            u *
            aero.area *
            aero.length *
            aero.moment(alpha);
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

/// The release angle that throws furthest, found by golden-section search
/// between 5° and 60° — every event's best is in there, and one peak is all
/// the curve has.
///
/// With [speedLossPerDeg] at zero, everything else is held, which answers
/// what the *flight* is best at: 44° for a shot from shoulder height in a
/// vacuum, about 40° for a javelin. No athlete throws like that. Release
/// speed falls as the release angle rises — Red and Zogaib (1977) measured
/// it falling linearly on javelin throwers, Linthorne (2001) on shot
/// putters — and that fall, not the flight, is most of why a finals release
/// sits in the thirties. So the search lets the speed fall by
/// [speedLossPerDeg] m/s for every degree steeper than the release it was
/// handed, anchored so that release keeps its own speed: nothing but the
/// search sees it, and the answer is the athlete's best angle rather than
/// the implement's.
({double angleDeg, double distance, double speed}) bestAngle(
    ThrowEvent event, ImplementSpec spec, Release release,
    {double speedLossPerDeg = 0}) {
  final aero = Aero.of(event, spec);
  double speedAt(double deg) =>
      math.max(0.0, release.speed - speedLossPerDeg * (deg - release.angleDeg));
  double at(double deg) => fly(
          release.copyWith(angleDeg: deg, speed: speedAt(deg)),
          aero,
          spec.weightKg)
      .distance;
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
  return (angleDeg: angle, distance: at(angle), speed: speedAt(angle));
}

/// How much release speed an athlete gives up per degree steeper, m/s, as
/// the calculator opens — an estimate for a coach to replace with their
/// athlete's own, and labeled one on the screen.
///
/// Red and Zogaib (1977) and Linthorne (2001) measured the fall and did not
/// publish one number for everybody, so these are set to scale. A javelin's
/// distance curve is flat enough near its peak — about 0.1 m lost per
/// degree² — and a meter a second worth enough, about 6 m, that 1 m/s per
/// 10° is what moves a flight-only 40° to the 35° finals release at. The
/// shot's is the 1.7 (m/s)/rad reported for Linthorne's college putters,
/// read from a secondary summary. Nobody has measured it for the hammer or
/// the discus, so they fly at a held speed and the screen says so.
double typicalSpeedLossPerDeg(ThrowEvent event) => switch (event) {
      ThrowEvent.javelin => 0.1,
      ThrowEvent.shotPut => 1.7 * math.pi / 180,
      ThrowEvent.discus || ThrowEvent.hammer => 0,
    };

/// What each lever is worth from here: meters gained for [speedStep] more
/// m/s, one more degree, and [heightStep] more meters of height — one m/s
/// and ten centimeters by default, a mile an hour and four inches for a
/// coach reading in feet. The comparison the research keeps coming back
/// to — speed is worth far more than angle — and the one a coach can do
/// something with.
({double perSpeed, double perDegree, double perHeight}) sensitivity(
    ThrowEvent event, ImplementSpec spec, Release release,
    {double speedStep = 1,
    double heightStep = 0.1,
    double speedLossPerDeg = 0}) {
  final aero = Aero.of(event, spec);
  double at(Release r) => fly(r, aero, spec.weightKg).distance;
  final base = at(release);
  return (
    perSpeed: at(release.copyWith(speed: release.speed + speedStep)) - base,
    // A degree steeper at the speed the best-angle search would give it, so
    // the tile and the best angle beside it tell one story.
    perDegree: at(release.copyWith(
            angleDeg: release.angleDeg + 1,
            speed: math.max(0.0, release.speed - speedLossPerDeg))) -
        base,
    perHeight: at(release.copyWith(height: release.height + heightStep)) - base,
  );
}

/// One of the things a what-if can change about a throw. The implement is
/// not one: both throws are the same implement, since the model has no
/// athlete in it to throw a heavier one slower.
enum Lever { speed, angle, height, attack, wind, pitchRate }

/// How far apart two releases of [spec] land, split between the levers
/// that differ between them, so the shares add up to the whole gap.
///
/// A share is not what that change is worth on its own. Two changes made
/// together throw further or shorter than the two made one at a time — a
/// faster release gains more from a steeper angle — so the gain they make
/// together has to be given to somebody, and handing it to whichever was
/// changed last would make the answer depend on an order nobody chose. So
/// each lever gets its gain averaged over every order the changes could be
/// made in (a Shapley split): what they do together is shared between
/// them, and the rows sum to [to] minus [from] exactly. It costs a flight
/// for every subset of the levers that moved — sixteen for four.
Map<Lever, double> gapShares(
  ThrowEvent event,
  ImplementSpec spec,
  Release from,
  Release to,
) {
  final a = from;
  final b = to;
  // Within a hair is the same: an elite thrower's height is the middle of a
  // range, and (1.8 + 2.1) / 2 is not quite the 1.95 a coach typed.
  bool differs(double x, double y) => (x - y).abs() > 1e-9;
  final moved = [
    if (differs(a.speed, b.speed)) Lever.speed,
    if (differs(a.angleDeg, b.angleDeg)) Lever.angle,
    if (differs(a.height, b.height)) Lever.height,
    if (differs(a.attackDeg, b.attackDeg)) Lever.attack,
    if (differs(a.wind, b.wind)) Lever.wind,
    if (differs(a.pitchRate, b.pitchRate)) Lever.pitchRate,
  ];
  final n = moved.length;
  final distance = <int, double>{};
  // The throw with the levers in [mask] taken from [to] and the rest from
  // [from].
  double at(int mask) => distance.putIfAbsent(mask, () {
        bool takes(Lever l) {
          final i = moved.indexOf(l);
          return i >= 0 && mask & (1 << i) != 0;
        }

        final release = Release(
          speed: takes(Lever.speed) ? b.speed : a.speed,
          angleDeg: takes(Lever.angle) ? b.angleDeg : a.angleDeg,
          height: takes(Lever.height) ? b.height : a.height,
          attackDeg: takes(Lever.attack) ? b.attackDeg : a.attackDeg,
          wind: takes(Lever.wind) ? b.wind : a.wind,
          pitchRate: takes(Lever.pitchRate) ? b.pitchRate : a.pitchRate,
        );
        return flyThrow(event, spec, release).distance;
      });

  double factorial(int k) => k <= 1 ? 1 : k * factorial(k - 1);
  final shares = <Lever, double>{};
  for (var i = 0; i < n; i++) {
    var share = 0.0;
    for (var mask = 0; mask < 1 << n; mask++) {
      if (mask & (1 << i) != 0) continue;
      var size = 0;
      for (var m = mask; m != 0; m &= m - 1) {
        size++;
      }
      final weight = factorial(size) * factorial(n - size - 1) / factorial(n);
      share += weight * (at(mask | (1 << i)) - at(mask));
    }
    shares[moved[i]] = share;
  }
  return shares;
}
