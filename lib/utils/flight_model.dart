/// An implement's flight through air, for the what-if calculator.
///
/// `projectile.dart` answers in a vacuum, which is fair for a shot and
/// wrong for anything that flies: a discus and a javelin are carried by
/// lift, and a hammer loses a couple of meters to drag at the speeds that
/// win championships. This steps the flight in small slices of time with
/// both forces on it, so every event gets a distance and the same model
/// answers every what-if.
///
/// A point mass with an attitude. The javelin's attitude is a rigid
/// body's, pitching in the plane of the throw under the moment the wind
/// tunnel measured on it (`javelin_aero.dart`). The discus's is a
/// gyroscope's: its spin turns the same nose-up moment into roll rather
/// than pitch, so it is flown in three dimensions, banked at release and
/// rolling over as it goes (Hubbard and Cheng). The discus's coefficients
/// are the shapes the wind-tunnel literature reports (lift climbing with
/// angle of attack until the flow separates, drag growing with its square,
/// the pitching moment's slope as Hubbard and Cheng estimated it); the
/// javelin's are measured and not tuned at all — see [Aero] for how close
/// each event gets. That makes the answer a good estimate of *how
/// much* a change is worth and an approximate one of the mark itself, and
/// the screen says so.
library;

import 'dart:math' as math;
import 'dart:typed_data';
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

/// The share of a discus's peak lift left once the flow has let go — and of
/// its pitching moment, which the tunnel sees fall away at the same stall.
const _discusStalledLift = 0.6;

/// How far a discus is banked about its line of flight as it leaves the
/// hand, degrees, and which way: against the roll its own moment will put
/// on it, so it rolls back through level in the air. Nothing publishes
/// what throwers do; this is near the 54° Hubbard and Cheng found best,
/// and where a flight with everything else at a final's typical release
/// goes furthest here.
const _discusBankDeg = -50.0;

/// A discus's spin as it leaves the hand, rad/s — Hubbard and Cheng's
/// nominal release, about seven turns a second.
const _discusSpin = 42.0;

/// What a discus's moment of inertia about its axis is of a flat plate's.
/// The rim carries most of the weight, so it is more than a plate's half
/// of mr², by a share the rules do not fix.
const _discusRim = 1.1;

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
/// (a shot and a hammer have none worth the name), pitches as a rigid body
/// under its measured pitching moment, which is what a javelin's tail does
/// to its nose, or — [spinMomentum] set — precesses: a spinning discus is
/// a gyroscope, and the same nose-up moment that would pitch it instead
/// rolls it over, which is the discus Hubbard and Cheng fly.
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
    this.momentSlope = 0,
    this.spinMomentum = 0,
    this.bankDeg = 0,
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

  /// Pitching moment per radian of attack before the stall, nose up,
  /// referenced to [area] and [length], for the implements not flown on a
  /// measured table.
  final double momentSlope;

  /// kg·m²/s of spin about the implement's own axis. Non-zero flies it as
  /// a gyroscope, in three dimensions.
  final double spinMomentum;

  /// Degrees the implement is banked about its line of flight at release.
  final double bankDeg;

  bool get hasAttitude => measured || liftSlope > 0;

  bool get pitches => hasAttitude && pitchInertia > 0;

  bool get precesses => hasAttitude && spinMomentum > 0;

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
  /// positive, referenced to [area] and [length]. Off a table it climbs with
  /// the lift and falls away with it at the stall.
  double moment(double alpha, {bool stalled = false}) {
    if (measured) return javelinMoment(alpha);
    if (momentSlope == 0) return 0;
    final a = alpha.abs();
    final stall = _rad(stallDeg);
    final double magnitude;
    if (!stalled && a <= stall) {
      magnitude = momentSlope * a;
    } else {
      final zero = _rad(liftZeroDeg);
      magnitude = momentSlope *
          stall *
          stalledLift *
          math.max(0, (zero - a) / (zero - stall));
    }
    return alpha.sign * magnitude;
  }

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
  /// The discus rolls. Held at a fixed tilt in the plane of the throw it
  /// could not both throw as far as a final does and keep its best angle in
  /// the thirties — every bit of lift that reached the mark dragged the
  /// best angle into the twenties, because a discus held level stalls the
  /// moment a high throw starts down. A real one is rolling over by then,
  /// and a rolled disc meets the descending air at a shallower angle, so
  /// it keeps gliding. Flown that way, on the same lift and drag, with
  /// nothing tuned to a distance, the best release comes out at 38° and
  /// 70 m for 25 m/s — Hubbard and Cheng's 38.4° and 69.4 m — and a
  /// final's typical release lands inside what finals throw.
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
        // The moment is Hubbard and Cheng's 0.007 per degree, on the
        // diameter.
        return Aero(
          area: math.pi * r * r,
          dragBase: 0.07,
          dragPerAttack: 2.5,
          liftSlope: 2.8,
          stallDeg: 29,
          recoverDeg: 25,
          stalledLift: _discusStalledLift,
          liftZeroDeg: 90,
          length: spec.nominalSize,
          momentSlope: 0.007 * 180 / math.pi,
          spinMomentum: _discusRim * 0.5 * spec.weightKg * r * r * _discusSpin,
          bankDeg: _discusBankDeg,
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
  if (aero.precesses) return _flySpinning(release, aero, mass);
  const dt = 0.002;
  final k = airDensity * aero.area / (2 * mass);
  final gamma0 = _rad(release.angleDeg);

  // State: x, y, vx, vy, attitude, pitch rate. Held in fixed buffers and
  // written in place: a flight is a couple of thousand RK4 steps, the
  // calculator flies dozens of them for every move of a slider, and a
  // fresh list per stage was most of what a flight cost.
  var s = Float64List.fromList([
    0.0,
    release.height,
    release.speed * math.cos(gamma0),
    release.speed * math.sin(gamma0),
    gamma0 + (aero.hasAttitude ? _rad(release.attackDeg) : 0),
    aero.pitches ? _rad(release.pitchRate) : 0.0,
  ]);
  var next = Float64List(6);
  final k1 = Float64List(6);
  final k2 = Float64List(6);
  final k3 = Float64List(6);
  final k4 = Float64List(6);
  final mid = Float64List(6);

  // Wrapped, so a javelin sent tumbling by a slider at its end reads the
  // angle it is actually meeting the air at rather than a turn and a half.
  double alphaOf(Float64List s) {
    if (!aero.hasAttitude) return 0;
    final a = s[4] - math.atan2(s[3], s[2] - release.wind);
    return math.atan2(math.sin(a), math.cos(a));
  }

  // Whether the flow is off the upper surface. It is a memory rather than
  // a function of the angle — that is the hysteresis — so it is held for a
  // whole step and moved only between them.
  var stalled = aero.stallsAt(alphaOf(s));

  void derivative(Float64List s, Float64List out) {
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
    out[0] = s[2];
    out[1] = s[3];
    out[2] = ax;
    out[3] = ay;
    out[4] = s[5];
    out[5] = dRate;
  }

  void step(Float64List s, Float64List d, double h, Float64List out) {
    for (var i = 0; i < 6; i++) {
      out[i] = s[i] + d[i] * h;
    }
  }

  final path = <Offset>[Offset(0, release.height)];
  var t = 0.0;
  var apex = release.height;
  var steps = 0;
  // A minute of flight is a release nothing in athletics produces; the cap
  // is only there so a nonsense input can't spin the loop forever.
  while (t < 60) {
    derivative(s, k1);
    step(s, k1, dt / 2, mid);
    derivative(mid, k2);
    step(s, k2, dt / 2, mid);
    derivative(mid, k3);
    step(s, k3, dt, mid);
    derivative(mid, k4);
    for (var i = 0; i < 6; i++) {
      next[i] = s[i] + dt / 6 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i]);
    }
    if (next[1] <= 0) {
      final f = s[1] / (s[1] - next[1]);
      final x = s[0] + (next[0] - s[0]) * f;
      path.add(Offset(x, 0));
      return Flight(distance: x, time: t + dt * f, apex: apex, path: path);
    }
    final was = s;
    s = next;
    next = was;
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
/// read from a secondary summary.
///
/// The hammer's is backed out the javelin's way: flown with speed held it
/// is best at 44°, where elite throwers release at 37–42° — a gap Castaldi
/// et al. (2022) put down to the speed a steeper orbit costs — and 0.8 m/s
/// per 10° is what lands both the men's and the women's typical release in
/// the middle of that. Nobody has published the number itself.
///
/// The discus's is backed out the same way. Flown rolling, it is best at
/// 38–39° with speed held, a little over the 36–37° a final's typical
/// release sits at, and 0.5 m/s per 10° brings the men's and the women's
/// there. Leigh et al. (2010) measured the fall on elite discus throwers,
/// and it was steep for some and shallow for others, so it is the dial most
/// worth setting to the athlete's own.
double typicalSpeedLossPerDeg(ThrowEvent event) => switch (event) {
      ThrowEvent.javelin => 0.1,
      ThrowEvent.shotPut => 1.7 * math.pi / 180,
      ThrowEvent.hammer => 0.08,
      ThrowEvent.discus => 0.05,
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
///
/// With [speedLossPerDeg] the angle carries the speed it costs: raising it
/// takes that much speed off with it, the way the calculator's own angle
/// does, and the speed lever is only whatever speed changed on top of that.
/// Split the other way, an angle raised on its own showed as a gain for the
/// angle and a loss for a speed nobody had touched — a row going red while
/// the throw went further.
Map<Lever, double> gapShares(
  ThrowEvent event,
  ImplementSpec spec,
  Release from,
  Release to, {
  double speedLossPerDeg = 0,
}) {
  final a = from;
  final b = to;
  final carried = -speedLossPerDeg * (b.angleDeg - a.angleDeg);
  final ownSpeed = b.speed - a.speed - carried;
  // Within a hair is the same: an elite thrower's height is the middle of a
  // range, and (1.8 + 2.1) / 2 is not quite the 1.95 a coach typed.
  bool differs(double x, double y) => (x - y).abs() > 1e-9;
  final moved = [
    if (ownSpeed.abs() > 1e-9) Lever.speed,
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
          speed: a.speed +
              (takes(Lever.angle) ? carried : 0) +
              (takes(Lever.speed) ? ownSpeed : 0),
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

/// [fly] for a spinning implement: a point mass in three dimensions with
/// its axis precessing under the pitching moment. The attack angle it is
/// released at is the true one — between the flight path and the disc —
/// and the bank is about the flight path, so the one the coach sets is the
/// one it leaves the hand at. A discus drifts a few meters sideways as it
/// rolls; the tape runs from the circle, so the distance is the radial one
/// and the path is drawn along it.
Flight _flySpinning(Release release, Aero aero, double mass) {
  const dt = 0.002;
  final k = airDensity * aero.area / (2 * mass);
  final precession =
      airDensity * aero.area * aero.length / (2 * aero.spinMomentum);
  final gamma = _rad(release.angleDeg);
  final attack = _rad(release.attackDeg);
  final bank = _rad(aero.bankDeg);
  final ca = math.cos(attack);
  final sa = math.sin(attack);
  final cg = math.cos(gamma);
  final sg = math.sin(gamma);

  // x along the throw, y up, z across; then the velocity; then the disc's
  // axis. The axis leans back off the path by the attack, square to the
  // path, and is then banked about it.
  var s = Float64List.fromList([
    0.0,
    release.height,
    0.0,
    release.speed * cg,
    release.speed * sg,
    0.0,
    -sa * cg + ca * math.cos(bank) * -sg,
    -sa * sg + ca * math.cos(bank) * cg,
    ca * math.sin(bank),
  ]);
  var next = Float64List(9);
  final k1 = Float64List(9);
  final k2 = Float64List(9);
  final k3 = Float64List(9);
  final k4 = Float64List(9);
  final mid = Float64List(9);

  // The angle the air meets the disc at: positive onto its underside.
  double alphaOf(Float64List s) {
    final ux = s[3] - release.wind;
    final u = math.sqrt(ux * ux + s[4] * s[4] + s[5] * s[5]);
    final n = math.sqrt(s[6] * s[6] + s[7] * s[7] + s[8] * s[8]);
    if (u < 1e-9 || n < 1e-9) return 0;
    final d = -(ux * s[6] + s[4] * s[7] + s[5] * s[8]) / (u * n);
    return math.asin(d.clamp(-1.0, 1.0));
  }

  var stalled = aero.stallsAt(alphaOf(s));

  void derivative(Float64List s, Float64List out) {
    final ux = s[3] - release.wind;
    final uy = s[4];
    final uz = s[5];
    final u = math.sqrt(ux * ux + uy * uy + uz * uz);
    var ax = 0.0;
    var ay = -gravity;
    var az = 0.0;
    var nx = 0.0;
    var ny = 0.0;
    var nz = 0.0;
    if (u > 1e-9) {
      final hx = ux / u;
      final hy = uy / u;
      final hz = uz / u;
      final nl = math.sqrt(s[6] * s[6] + s[7] * s[7] + s[8] * s[8]);
      final ex = s[6] / nl;
      final ey = s[7] / nl;
      final ez = s[8] / nl;
      final along = ex * hx + ey * hy + ez * hz;
      final alpha = math.asin((-along).clamp(-1.0, 1.0));
      // Lift square to the air, on the side the axis leans to.
      var lx = ex - along * hx;
      var ly = ey - along * hy;
      var lz = ez - along * hz;
      final ll = math.sqrt(lx * lx + ly * ly + lz * lz);
      if (ll > 1e-12) {
        lx /= ll;
        ly /= ll;
        lz /= ll;
      }
      final q = k * u * u;
      final d = q * aero.drag(alpha);
      final l = q * aero.lift(alpha, stalled: stalled);
      ax += -d * hx + l * lx;
      ay += -d * hy + l * ly;
      az += -d * hz + l * lz;
      // The moment is about the axis square to the air and the disc; a
      // gyroscope's axis moves along it rather than turning about it.
      var px = hy * ez - hz * ey;
      var py = hz * ex - hx * ez;
      var pz = hx * ey - hy * ex;
      final pl = math.sqrt(px * px + py * py + pz * pz);
      if (pl > 1e-12) {
        final w =
            precession * u * u * aero.moment(alpha, stalled: stalled) / pl;
        nx = w * px;
        ny = w * py;
        nz = w * pz;
      }
    }
    out[0] = s[3];
    out[1] = s[4];
    out[2] = s[5];
    out[3] = ax;
    out[4] = ay;
    out[5] = az;
    out[6] = nx;
    out[7] = ny;
    out[8] = nz;
  }

  void step(Float64List s, Float64List d, double h, Float64List out) {
    for (var i = 0; i < 9; i++) {
      out[i] = s[i] + d[i] * h;
    }
  }

  double radial(double x, double z) => math.sqrt(x * x + z * z);

  final path = <Offset>[Offset(0, release.height)];
  var t = 0.0;
  var apex = release.height;
  var steps = 0;
  while (t < 60) {
    derivative(s, k1);
    step(s, k1, dt / 2, mid);
    derivative(mid, k2);
    step(s, k2, dt / 2, mid);
    derivative(mid, k3);
    step(s, k3, dt, mid);
    derivative(mid, k4);
    for (var i = 0; i < 9; i++) {
      next[i] = s[i] + dt / 6 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i]);
    }
    final nl =
        math.sqrt(next[6] * next[6] + next[7] * next[7] + next[8] * next[8]);
    next[6] /= nl;
    next[7] /= nl;
    next[8] /= nl;
    if (next[1] <= 0) {
      final f = s[1] / (s[1] - next[1]);
      final x = s[0] + (next[0] - s[0]) * f;
      final z = s[2] + (next[2] - s[2]) * f;
      final distance = radial(x, z);
      path.add(Offset(distance, 0));
      return Flight(
          distance: distance, time: t + dt * f, apex: apex, path: path);
    }
    final was = s;
    s = next;
    next = was;
    t += dt;
    final alpha = alphaOf(s);
    if (!stalled && aero.stallsAt(alpha)) stalled = true;
    if (stalled && aero.recoversAt(alpha)) stalled = false;
    apex = math.max(apex, s[1]);
    if (++steps % 10 == 0) path.add(Offset(radial(s[0], s[2]), s[1]));
  }
  return Flight(distance: radial(s[0], s[2]), time: t, apex: apex, path: path);
}
