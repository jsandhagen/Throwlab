import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'scrub_frames.dart';

/// How the two clips are played through their releases.
enum CompareRoutine {
  /// Both run the same window at the same time, so the releases happen
  /// together. A difference between two throws shows up as a difference you
  /// can see at one instant.
  together,

  /// Both run together until a beat before the release and then hold; A
  /// finishes its throw alone, and B follows. Two releases half a second
  /// apart are two releases somebody can actually watch — side by side they
  /// are one instant and one pair of eyes.
  inTurn,
}

/// One stretch of the routine: where each clip sits at the start and the end
/// of it, and how long it lasts in *wall* seconds. A leg that plays footage
/// is as long as its footage divided by the speed; a leg where both clips
/// hold is the same beat however slowly the throws are being played.
class _Leg {
  const _Leg(this.seconds, this.fromA, this.toA, this.fromB, this.toB);

  final double seconds;
  final Duration fromA, toA, fromB, toB;
}

/// Plays two throws through their releases off their pre-extracted stills,
/// instead of running two video decoders side by side.
///
/// Two 1440p clips is the thing a phone can't reliably do at once: the
/// playback copies are cut with a keyframe every six frames so an exact seek
/// is cheap, which makes them expensive to decode, and concurrent decoders
/// share one throughput budget rather than getting one each. The stills have
/// none of that problem. They are already extracted, already the same
/// resolution as the video, and [ScrubFrames] already plays them at a flick
/// with a prefetch window — a scrub pushes far more frames a second through
/// it than a half-speed loop ever asks for.
///
/// What it buys beyond not stalling: the two clips are indexed by time
/// rather than started and hoped over, so they cannot drift apart, and a
/// routine that holds one clip while the other throws is arithmetic rather
/// than a second player told to wait.
class CompareLoop extends ChangeNotifier {
  CompareLoop({
    required this.framesA,
    required this.framesB,
    required TickerProvider vsync,
  }) {
    _ticker = vsync.createTicker(_onTick);
  }

  /// The stills for each clip. Owned by the screen, not by this: the scrub
  /// path shows the same frames.
  final ScrubFrames framesA;
  final ScrubFrames framesB;

  late final Ticker _ticker;

  /// The run-up and the flight the loop aims to include, before trimming to
  /// what the clips actually hold.
  static const lead = Duration(milliseconds: 2000);
  static const tail = Duration(milliseconds: 1500);

  /// Where the two clips stop together in the staggered routine. A second
  /// before the release is far enough back that both athletes are still in
  /// the throw rather than already out of it, so what follows reads as the
  /// same throw finishing rather than a clip starting.
  static const hold = Duration(milliseconds: 1000);

  /// The pause on either side of a throw taken alone. Wall time, so a beat
  /// stays a beat whatever speed the throws are played at.
  static const beat = Duration(milliseconds: 450);

  Duration _syncA = Duration.zero, _syncB = Duration.zero;
  Duration _durationA = Duration.zero, _durationB = Duration.zero;

  /// The release frames and clip lengths the routine is built around.
  /// Re-marking a release while the loop runs rebuilds it in place.
  void setClips({
    required Duration syncA,
    required Duration syncB,
    required Duration durationA,
    required Duration durationB,
  }) {
    if (syncA == _syncA &&
        syncB == _syncB &&
        durationA == _durationA &&
        durationB == _durationB) {
      return;
    }
    _syncA = syncA;
    _syncB = syncB;
    _durationA = durationA;
    _durationB = durationB;
    _rebuild();
  }

  double get speed => _speed;
  double _speed = 0.5;
  set speed(double value) {
    if (value == _speed || value <= 0) return;
    _speed = value;
    _rebuild();
  }

  CompareRoutine get routine => _routine;
  CompareRoutine _routine = CompareRoutine.together;
  set routine(CompareRoutine value) {
    if (value == _routine) return;
    _routine = value;
    // From the top: the legs of one routine have no counterpart in the
    // other, so carrying the position over would land mid-nothing.
    _legs = _buildLegs();
    _leg = 0;
    _legElapsed = 0;
    if (running) _show();
    notifyListeners();
  }

  List<_Leg> _legs = const [];
  int _leg = 0;
  double _legElapsed = 0;
  Duration _lastTick = Duration.zero;

  bool get running => _ticker.isActive;

  /// Whether there is a window worth playing: both releases marked, and
  /// enough footage around them to show.
  bool get hasWindow =>
      _syncA > Duration.zero &&
      _syncB > Duration.zero &&
      (leadIn + followThrough) > Duration.zero;

  static Duration _shortest(List<Duration> values) =>
      values.reduce((a, b) => a < b ? a : b);

  /// The lead-in both clips can afford: whichever has less footage before
  /// its release sets it, so the two show the same approach.
  Duration get leadIn {
    final value = _shortest([lead, _syncA, _syncB]);
    return value < Duration.zero ? Duration.zero : value;
  }

  /// Likewise for the follow-through after the release.
  Duration get followThrough {
    final value = _shortest([tail, _durationA - _syncA, _durationB - _syncB]);
    return value < Duration.zero ? Duration.zero : value;
  }

  /// Where both clips sit right now.
  ({Duration a, Duration b}) get poses {
    if (_legs.isEmpty) return (a: _syncA, b: _syncB);
    final leg = _legs[_leg];
    final t =
        leg.seconds <= 0 ? 1.0 : (_legElapsed / leg.seconds).clamp(0.0, 1.0);
    return (a: _lerp(leg.fromA, leg.toA, t), b: _lerp(leg.fromB, leg.toB, t));
  }

  static Duration _lerp(Duration from, Duration to, double t) => Duration(
      microseconds:
          from.inMicroseconds + ((to - from).inMicroseconds * t).round());

  /// Wall seconds a stretch of footage takes at the current speed.
  double _wall(Duration clip) =>
      clip.inMicroseconds / Duration.microsecondsPerSecond / _speed;

  static double get _beatSeconds =>
      beat.inMicroseconds / Duration.microsecondsPerSecond;

  List<_Leg> _buildLegs() {
    final runUp = leadIn;
    final flight = followThrough;
    final startA = _syncA - runUp, startB = _syncB - runUp;
    final endA = _syncA + flight, endB = _syncB + flight;
    if (_routine == CompareRoutine.together) {
      return [_Leg(_wall(runUp + flight), startA, endA, startB, endB)];
    }
    // The freeze lands [hold] before each release — or at the top of the
    // window when the clips don't hold that much run-up, in which case the
    // two simply start held rather than losing the stagger.
    final pause = hold < runUp ? hold : runUp;
    final markA = _syncA - pause, markB = _syncB - pause;
    return [
      // In together, to a beat before the release.
      _Leg(_wall(runUp - pause), startA, markA, startB, markB),
      // Both stop, which is what makes the two that follow read as one
      // replay rather than as two clips playing one after the other.
      _Leg(_beatSeconds, markA, markA, markB, markB),
      // A finishes the throw alone.
      _Leg(_wall(pause + flight), markA, endA, markB, markB),
      _Leg(_beatSeconds, endA, endA, markB, markB),
      // B follows, from the same frame of its own throw.
      _Leg(_wall(pause + flight), endA, endA, markB, endB),
      // A moment on the two finished throws before it comes round again.
      _Leg(_beatSeconds, endA, endA, endB, endB),
    ];
  }

  void _rebuild() {
    if (_legs.isEmpty) {
      _legs = _buildLegs();
      return;
    }
    // Hold the place: the legs keep their order and meaning, so the fraction
    // through the current one survives a speed change or a re-marked
    // release without the picture jumping.
    final was = _legs[_leg].seconds;
    final fraction = was <= 0 ? 0.0 : (_legElapsed / was).clamp(0.0, 1.0);
    _legs = _buildLegs();
    _leg = _leg.clamp(0, _legs.length - 1);
    _legElapsed = _legs[_leg].seconds * fraction;
  }

  /// Starts the routine from the top of the window.
  void start() {
    _legs = _buildLegs();
    _leg = 0;
    _legElapsed = 0;
    _lastTick = Duration.zero;
    // A fresh start: until the frame at the top of the window decodes the
    // panes show nothing rather than a still from wherever the last scrub
    // left off.
    framesA.reset();
    framesB.reset();
    _show();
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  void stop() {
    if (!_ticker.isActive) return;
    _ticker.stop();
    notifyListeners();
  }

  /// The still each pane is parked on, for handing the picture back to the
  /// video decoders when the loop stops.
  ({int a, int b}) get shownIndices {
    final pose = poses;
    return (
      a: framesA.indexForPosition(pose.a),
      b: framesB.indexForPosition(pose.b),
    );
  }

  void _show() {
    final pose = poses;
    framesA.showIndex(framesA.indexForPosition(pose.a));
    framesB.showIndex(framesB.indexForPosition(pose.b));
  }

  void _onTick(Duration elapsed) {
    if (_legs.isEmpty) {
      _ticker.stop();
      return;
    }
    final dt =
        ((elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, 0.25);
    _lastTick = elapsed;
    _legElapsed += dt;
    // A leg can be empty — no run-up to play before the freeze, no
    // follow-through to play after the release — so this walks on rather
    // than stalling in one. The guard is for the degenerate case where they
    // all are, which would otherwise spin here forever.
    var guard = _legs.length * 2;
    while (_legElapsed >= _legs[_leg].seconds) {
      _legElapsed -= _legs[_leg].seconds;
      _leg = (_leg + 1) % _legs.length;
      if (--guard <= 0) {
        _legElapsed = 0;
        break;
      }
    }
    _show();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }
}
