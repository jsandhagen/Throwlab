import 'dart:async';

import 'package:flutter/material.dart';

import '../models/elite_releases.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/flight_model.dart';
import '../widgets/angular.dart';
import '../widgets/distance_field.dart';
import '../widgets/event_glyph.dart';
import '../widgets/flight_field.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_card.dart';

/// The what-if calculator: a release, the distance it throws, and what
/// moving any one part of it is worth — and a second throw laid over the
/// first, so the question is asked the way a coach asks it: this one,
/// against that one.
///
/// It answers with the flight model in `flight_model.dart` and holds the
/// answer against releases measured at championship finals. The numbers are
/// estimates and the screen says so where they are read, not in a footnote:
/// a what-if is worth having for the size of a change, and the model is
/// much surer of that than of the mark itself.
class ReleaseCalculatorScreen extends StatefulWidget {
  const ReleaseCalculatorScreen({
    super.key,
    this.event = ThrowEvent.shotPut,
    this.implementKg,
    this.measured,
  });

  final ThrowEvent event;
  final double? implementKg;

  /// A release measured off a clip, which the calculator opens on as the
  /// first throw and can always go back to.
  final Release? measured;

  @override
  State<ReleaseCalculatorScreen> createState() =>
      _ReleaseCalculatorScreenState();
}

/// How far each slider runs. Wide enough for a first-year thrower and a
/// world record alike, and no wider — a slider that spends half its length
/// on speeds nobody reaches is one that can't be set to a tenth.
class _Span {
  const _Span(this.speed, this.height);
  final (double, double) speed;
  final (double, double) height;
}

const _spans = {
  ThrowEvent.shotPut: _Span((5, 16), (1.0, 2.6)),
  ThrowEvent.discus: _Span((10, 28), (0.8, 2.2)),
  ThrowEvent.hammer: _Span((10, 31), (0.5, 2.2)),
  ThrowEvent.javelin: _Span((10, 33), (1.0, 2.4)),
};

const _angleSpan = (0.0, 60.0);
const _attackSpan = (-20.0, 20.0);
const _windSpan = (-8.0, 8.0);
const _pitchSpan = (-30.0, 30.0);

/// m/s per 10°: from holding speed to losing a tenth of a javelin's.
const _speedLossSpan = (0.0, 3.0);

bool _hasAttack(ThrowEvent event) =>
    event == ThrowEvent.discus || event == ThrowEvent.javelin;

/// Only the javelin is flown as a body that turns in pitch; a discus holds
/// its tilt, and a rate given to it would be a dial that does nothing.
bool _hasPitchRate(ThrowEvent event) => event == ThrowEvent.javelin;

/// A shot is in the air two seconds at a third of a discus's speed; wind
/// moves it centimeters, and a dial that does nothing reads as a broken one.
bool _hasWind(ThrowEvent event) => event != ThrowEvent.shotPut;

double _clamp(double v, (double, double) span) =>
    v.clamp(span.$1, span.$2).toDouble();

const _mph = 0.44704;
const _inch = 0.0254;

/// The release read in the coach's own units. A coach who measures in feet
/// thinks of speed in miles an hour — what a radar gun reads — and of a
/// release height in feet and inches, and a screen that spoke to them in
/// m/s would be a conversion on every slider. Everything is still stored
/// and flown in meters; this is only how it is read and how far each step
/// goes, so a slider in feet moves a tenth of a mile an hour, not a tenth
/// of a meter a second spelled in the wrong unit.
class _Units {
  const _Units(this.distance);
  final DistanceUnit distance;

  bool get imperial => distance == DistanceUnit.feet;

  double get speedStep => imperial ? 0.1 * _mph : 0.1;
  double get heightStep => imperial ? 0.25 * _inch : 0.01;
  double get windStep => imperial ? _mph : 0.5;

  /// The lever the worth tiles are priced in: one of the unit a speed is
  /// read in, and a round handful of height.
  double get speedLever => imperial ? _mph : 1;
  double get heightLever => imperial ? 4 * _inch : 0.1;
  String get speedLeverLabel => imperial ? '+1 mph' : '+1 m/s';
  String get heightLeverLabel => imperial ? '+4 in higher' : '+10 cm higher';

  String mark(double m) => formatDistance(m, distance);

  String speed(double mps) => imperial
      ? '${(mps / _mph).toStringAsFixed(1)} mph'
      : '${mps.toStringAsFixed(1)} m/s';

  /// [fine] for a change under a tenth, which a tenth would print as
  /// nothing — a shot putter's 0.03 m/s a degree read as '0.0 m/s'.
  String speedDelta(double d, {bool fine = false}) {
    final v = imperial ? d / _mph : d;
    final digits = fine && v.abs() < 0.1 ? 2 : 1;
    return '${_signed(v, digits)} ${imperial ? 'mph' : 'm/s'}';
  }

  // A release height is a mark like any other on this screen: 6-11 in feet,
  // the way the throw it comes from is written.
  String height(double m) =>
      imperial ? formatDistance(m, distance) : '${m.toStringAsFixed(2)} m';
  String heightDelta(double d) =>
      imperial ? '${_signed(d / _inch, 1)} in' : '${_signed(d, 2)} m';

  String wind(double v) {
    if (v == 0) return 'Still';
    final size = imperial
        ? '${(v.abs() / _mph).toStringAsFixed(0)} mph'
        : '${v.abs().toStringAsFixed(1)} m/s';
    return '$size ${v > 0 ? 'tail' : 'head'}';
  }

  String windDelta(double d) =>
      imperial ? '${_signed(d / _mph, 0)} mph' : '${_signed(d, 1)} m/s';

  /// A height in the air, to the nearest whole unit — 'peaks 19 ft up'.
  String rise(double m) => imperial
      ? '${(m / metersPerFoot).toStringAsFixed(0)} ft'
      : '${m.toStringAsFixed(1)} m';

  String release(Release r) =>
      '${speed(r.speed)} · ${r.angleDeg.toStringAsFixed(1)}° · '
      '${height(r.height)}';
}

/// One throw on the screen: the implement, the release, and whose it is
/// when it is somebody's. The implement is the screen's, never the
/// throw's: both are flown with the one being studied, because a change of
/// implement is not something a release can be asked about — the model
/// has no athlete in it to throw a heavier ball slower. A throw that is moved on a slider is nobody's any
/// more — Walsh's release with another meter a second on it is not Walsh's.
class _Throw {
  const _Throw(this.spec, this.release, [this.label]);
  final ImplementSpec spec;
  final Release release;
  final String? label;
}

/// What the typical elite release is called wherever it is named: after
/// the throwers, not after a competition, since it is drawn from many.
const _eliteLabel = 'Typical elite thrower';

class _ReleaseCalculatorScreenState extends State<ReleaseCalculatorScreen> {
  static const _measuredLabel = 'Your measured throw';

  late ThrowEvent _event = widget.event;

  /// What both throws are flown with: the measured throw's implement, or
  /// the event's own. The same for both — a reference brings its release
  /// and nothing else, so what the gap measures is the release — and
  /// changing it starts the screen over (`_pickImplement`), since nothing
  /// on it was thrown with the new one.
  late ImplementSpec _spec = _specFor(widget.event);

  /// The implement the measured throw was thrown with, when there is one.
  ImplementSpec? get _measuredSpec => widget.measured == null
      ? null
      : widget.implementKg == null
          ? widget.event.defaultImplement
          : widget.event.specFor(widget.implementKg!);

  ImplementSpec _specFor(ThrowEvent event) =>
      event == widget.event && widget.implementKg != null
          ? event.specFor(widget.implementKg!)
          : event.defaultImplement;

  /// m/s of release speed the athlete gives up per degree steeper, for the
  /// best-angle search only. Opens on the event's estimate and is the
  /// coach's to set; an event nobody has measured it for has none.
  late double _speedLoss = typicalSpeedLossPerDeg(widget.event);
  late _Throw _one = _baseline();
  _Throw? _two;

  /// Which throw the sliders move: 0, the baseline, or 1, the what-if.
  int _editing = 0;

  /// Opens in whatever the coach last typed a distance in, and can be
  /// flipped here without changing that — reading one what-if in the other
  /// unit is not a change of mind about the next mark.
  late DistanceUnit _unit = DistanceField.preferred;

  final _scroll = ScrollController();

  /// The picture in the result card: once it is out of sight the result
  /// floats, whatever of the card's text is still showing under it.
  final _fieldKey = GlobalKey();
  final _stackKey = GlobalKey();

  /// Whether the result card has scrolled out of sight, and its small copy
  /// is hanging at the top instead.
  bool _floating = false;

  @override
  void dispose() {
    _followTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Floats the result once the flight in the card has gone up under the
  /// top of the page. Not the whole card: the gap's breakdown hangs under
  /// the flight, and waiting for that to go too left the dials a screen
  /// long with nothing to watch but a footnote. Not sooner either, since
  /// while the flight is in sight a second copy of it is the same picture
  /// twice.
  void _checkFloating() {
    bool off() {
      if (!_scroll.hasClients || _scroll.offset <= 0) return false;
      final field = _fieldKey.currentContext?.findRenderObject();
      final stack = _stackKey.currentContext?.findRenderObject();
      // Scrolled far enough that the list has let the card go.
      if (field is! RenderBox || !field.attached) return true;
      if (stack is! RenderBox) return false;
      final foot = field.localToGlobal(Offset(0, field.size.height)).dy;
      return foot < stack.localToGlobal(Offset.zero).dy + 8;
    }

    final next = off();
    if (next != _floating) setState(() => _floating = next);
  }

  /// A slider in the hand, and which. While one is, only the two flights
  /// on the field are flown for each move: the best angle, what a nudge is
  /// worth and where the gap comes from are a hundred flights between them
  /// on a javelin, and flown on every move they held each frame to a tenth
  /// of a second — which a coach felt as a slider that dragged, and saw as
  /// the speed jumping after the angle rather than riding with it. They
  /// are worked out once the finger lifts.
  String? _sliding;

  /// The speed has just moved because the angle did, so its dial can say
  /// so for a moment after a tap as well as for the length of a drag.
  bool _speedFollowed = false;
  Timer? _followTimer;

  ({String key, _Derived value})? _derived;

  /// Everything [_derived] depends on, spelled out: the same release to the
  /// last bit is the same answer.
  String _derivedKey(_Units units) {
    String r(Release x) => '${x.speed},${x.angleDeg},${x.height},'
        '${x.attackDeg},${x.wind},${x.pitchRate}';
    return '${_event.name}|${_spec.weightKg}|${r(_one.release)}|'
        '${_two == null ? '-' : r(_two!.release)}|$_editing|$_loss|'
        '${units.speedLever}|${units.heightLever}';
  }

  /// The slow half of the screen, from the cache while a slider is in the
  /// hand and worked out again otherwise when anything it reads has moved.
  ({String key, _Derived value}) _derivedFor(_Units units) {
    final key = _derivedKey(units);
    final cached = _derived;
    if (cached != null && (cached.key == key || _sliding != null)) {
      return cached;
    }
    final current = _current;
    // The athlete's best angle, with speed falling as it rises, and the
    // flight's own with speed held — the two answers the literature gives,
    // said side by side so neither is mistaken for the other.
    final best = bestAngle(_event, current.spec, current.release,
        speedLossPerDeg: _loss);
    final held =
        _loss > 0 ? bestAngle(_event, current.spec, current.release) : null;
    final worth = sensitivity(_event, current.spec, current.release,
        speedStep: units.speedLever,
        heightStep: units.heightLever,
        speedLossPerDeg: _loss);
    final shares = !_comparing
        ? null
        : gapShares(_event, _spec, _one.release, _two!.release,
            speedLossPerDeg: _loss);
    final from = flyThrow(_event, current.spec, current.release).distance;
    Flight? ghost;
    if (!_comparing) {
      final at = flyThrow(_event, _one.spec,
          _one.release.copyWith(angleDeg: best.angleDeg, speed: best.speed));
      if (at.distance - from >= 0.02) ghost = at;
    }
    return _derived = (
      key: key,
      value: (
        best: best,
        held: held,
        worth: worth,
        shares: shares,
        ghost: ghost,
        gain: best.distance - from,
        angleDeg: current.release.angleDeg,
      ),
    );
  }

  void _slideStart(String label) => setState(() => _sliding = label);
  void _slideEnd() => setState(() => _sliding = null);

  bool get _comparing => _two != null;
  _Throw get _current => _editing == 1 ? _two! : _one;
  _Throw? get _other => !_comparing ? null : (_editing == 1 ? _one : _two);

  /// The typical elite release with this implement, or null where elite
  /// throwers don't throw it.
  _Throw? _elite() {
    final range = eliteRangeFor(_event, _spec.weightKg);
    return range == null ? null : _Throw(_spec, _typical(range), _eliteLabel);
  }

  static Release _typical(EliteRange range) => Release(
        speed: range.typicalSpeed,
        angleDeg: range.typicalAngle,
        height: range.typicalHeight,
        attackDeg: range.attackDeg,
      );

  /// What the screen opens on for the event and implement it is on: the
  /// measured throw where it was thrown with this implement, else the
  /// typical elite thrower with it, else — for an implement no elite
  /// thrower throws — the nearest one's release as numbers to start from,
  /// under nobody's name.
  _Throw _baseline() {
    if (widget.measured != null &&
        _event == widget.event &&
        _spec == _measuredSpec) {
      return _fit(_Throw(_spec, widget.measured!, _measuredLabel), _event);
    }
    return _elite() ??
        _fit(_Throw(_spec, _typical(nearestEliteRange(_event, _spec.weightKg))),
            _event);
  }

  /// Whose elite throwers the list holds: the implement's own, or the
  /// men's where a boys' implement borrows them.
  String _eliteTrailing() {
    final elite = eliteWeightFor(_event, _spec.weightKg);
    if (elite == null || elite == _spec.weightKg) return _spec.weightLabel;
    return "Men's ${_event.specFor(elite).weightLabel}";
  }

  /// Everything back to what the event and implement open on.
  void _startOver() {
    _speedLoss = typicalSpeedLossPerDeg(_event);
    _one = _baseline();
    _two = null;
    _editing = 0;
    if (_scroll.hasClients && _scroll.offset > 0) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    }
  }

  /// A new implement starts over: every number on the screen was flown with
  /// the old one, and carrying a release across to a heavier ball at the
  /// same speed is the what-if the model can't answer.
  void _pickImplement(ImplementSpec spec) {
    if (spec == _spec) return;
    setState(() {
      _spec = spec;
      _startOver();
    });
  }

  _Throw _fit(_Throw t, ThrowEvent event) {
    final span = _spans[event]!;
    final r = t.release;
    return _Throw(
      t.spec,
      Release(
        speed: _clamp(r.speed, span.speed),
        angleDeg: _clamp(r.angleDeg, _angleSpan),
        height: _clamp(r.height, span.height),
        attackDeg: _hasAttack(event) ? _clamp(r.attackDeg, _attackSpan) : 0,
        wind: _hasWind(event) ? _clamp(r.wind, _windSpan) : 0,
        pitchRate: _hasPitchRate(event) ? _clamp(r.pitchRate, _pitchSpan) : 0,
      ),
      t.label,
    );
  }

  void _put(_Throw t) {
    final fitted = _fit(t, _event);
    if (_editing == 1) {
      _two = fitted;
    } else {
      _one = fitted;
    }
  }

  void _setRelease(Release r) => setState(() => _put(_Throw(_current.spec, r)));

  /// The speed lost per degree steeper as the flight is flown: the coach's
  /// setting where the event trades speed for angle, nothing where it
  /// doesn't.
  double get _loss => typicalSpeedLossPerDeg(_event) > 0 ? _speedLoss : 0;

  /// An angle, and the speed that goes with it: [_loss] per degree off the
  /// speed for every degree steeper, and back on for every degree flatter.
  void _setAngle(double angle) {
    final r = _current.release;
    if (_loss > 0) {
      _speedFollowed = true;
      _followTimer?.cancel();
      _followTimer = Timer(_followShown, () {
        if (mounted) setState(() => _speedFollowed = false);
      });
    }
    _setRelease(r.copyWith(
      angleDeg: angle,
      speed: r.speed - _loss * (angle - r.angleDeg),
    ));
  }

  static const _followShown = Duration(milliseconds: 900);

  /// Whether the speed's dial is lit as following the angle: while the
  /// angle is in the hand, and for a moment after it was stepped.
  bool get _speedFollowing =>
      _loss > 0 && (_sliding == 'Angle' || _speedFollowed);

  void _pickEvent(ThrowEvent event) {
    if (event == _event) return;
    // A new event is a new throw: its result is what to look at first.
    setState(() {
      _event = event;
      _spec = _specFor(event);
      _startOver();
    });
  }

  /// A reference goes in as the what-if, over whatever the baseline is —
  /// the comparison it is there to make. Tapping the one already there puts
  /// it away again.
  void _compareWith(_Throw t) => setState(() {
        if (_two?.label == t.label) {
          _two = null;
          _editing = 0;
          return;
        }
        _two = _fit(t, _event);
        _editing = 1;
      });

  void _addSecond() => setState(() {
        _two = _Throw(_one.spec, _one.release);
        _editing = 1;
      });

  void _removeSecond() => setState(() {
        _two = null;
        _editing = 0;
      });

  /// Whether the what-if has been moved off the baseline at all — the reset
  /// is only offered when there is something to reset.
  bool get _differs {
    final a = _one.release, b = _two!.release;
    return _one.spec != _two!.spec ||
        a.speed != b.speed ||
        a.angleDeg != b.angleDeg ||
        a.height != b.height ||
        a.attackDeg != b.attackDeg ||
        a.wind != b.wind ||
        a.pitchRate != b.pitchRate;
  }

  void _resetToBaseline() => setState(() {
        _two = _Throw(_one.spec, _one.release);
      });

  /// The best angle, tried. With nothing to compare against it goes in as a
  /// what-if over the throw it was worked out for, so the gain is read off
  /// the headline rather than the baseline being lost to it; while
  /// comparing it moves whichever throw the sliders are on. The speed goes
  /// with it, since the thrower's best angle is flown at the speed the
  /// thrower would have there.
  void _tryAngle(({double angleDeg, double distance, double speed}) best) =>
      setState(() {
        // Rounded to the tenth the dial reads, and the speed taken off the
        // rounded angle by the dial's own rule: the search's speed belongs
        // to the unrounded one, and the difference showed as a speed row
        // of 0.00 in the breakdown.
        final angle = (best.angleDeg * 10).round() / 10;
        Release at(Release r) => r.copyWith(
            angleDeg: angle, speed: r.speed - _loss * (angle - r.angleDeg));
        if (!_comparing) {
          _two = _fit(
              _Throw(_one.spec, at(_one.release), 'At the best angle'), _event);
          _editing = 1;
          return;
        }
        _put(_Throw(_current.spec, at(_current.release)));
      });

  void _backToMeasured() => setState(() {
        _one = _fit(_Throw(_spec, widget.measured!, _measuredLabel), _event);
      });

  /// Two roles rather than two numbers. The baseline is whatever the
  /// comparison is measured from — a measured throw, a typical elite thrower, or
  /// numbers typed in — and the what-if is the change being asked about;
  /// 'throw 1' and 'throw 2' said neither, and a baseline that was never
  /// thrown is no less a baseline.
  static String _role(int i) => i == 0 ? 'Baseline' : 'What if';

  /// Where a throw came from, when that is anything but the sliders.
  String _source(int i) {
    final t = i == 0 ? _one : _two!;
    return t.label ?? (i == 0 ? 'Custom release' : 'Your changes');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('What if'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<DistanceUnit>(
              key: const ValueKey('whatIfUnits'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                    value: DistanceUnit.meters,
                    label: Text('m'),
                    tooltip: 'Meters'),
                ButtonSegment(
                    value: DistanceUnit.feet,
                    label: Text('ft'),
                    tooltip: 'Feet, inches and mph'),
              ],
              selected: {_unit},
              onSelectionChanged: (u) => setState(() => _unit = u.first),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // The sector every other screen in the app stands on, so this
          // reads as a room in it rather than a form from somewhere else.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: SectorBackdropPainter(color: scheme.primary),
              ),
            ),
          ),
          Column(
            children: [
              HeaderBand(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AngularSegmentedBar<ThrowEvent>(
                        value: _event,
                        onChanged: _pickEvent,
                        segments: [
                          for (final e in ThrowEvent.values)
                            AngularSegment(
                              value: e,
                              glyph: (color) =>
                                  EventGlyph(e, size: 16, color: color),
                              label: e == ThrowEvent.shotPut ? 'Shot' : e.label,
                            ),
                        ],
                      ),
                      _ImplementPicker(
                        event: _event,
                        value: _spec,
                        onChanged: _pickImplement,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _body(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final oneFlight = flyThrow(_event, _one.spec, _one.release);
    final twoFlight =
        _two == null ? null : flyThrow(_event, _two!.spec, _two!.release);
    final current = _current;
    final units = _Units(_unit);
    final tradesSpeed = typicalSpeedLossPerDeg(_event) > 0;
    final speedLoss = _loss;
    final loss = _loss;
    final derived = _derivedFor(units);
    // Held over from before the slider was picked up, and said so by
    // dimming, rather than a number that disagrees with the flight above
    // it read as if it were current.
    final stale = derived.key != _derivedKey(units);
    final (:best, :held, :worth, :shares, :ghost, gain: _, angleDeg: _) =
        derived.value;

    // The baseline steps back to a neutral ink once there is a what-if to
    // stand in front of it.
    final oneColor = _comparing ? scheme.onSurfaceVariant : scheme.primary;
    final twoColor = scheme.primary;
    final showBack = widget.measured != null &&
        _event == widget.event &&
        _spec == _measuredSpec &&
        _one.label != _measuredLabel;
    final other = _other?.release;
    final otherRole = _comparing ? _role(1 - _editing).toLowerCase() : null;
    final gap =
        twoFlight == null ? 0.0 : twoFlight.distance - oneFlight.distance;
    final shown = (
      one: (name: _source(0), flight: oneFlight, color: oneColor),
      two: twoFlight == null
          ? null
          : (name: _source(1), flight: twoFlight, color: twoColor),
    );
    Widget dial({
      required String label,
      required double value,
      required (double, double) span,
      required double step,
      required String Function(double) format,
      required String Function(double) delta,
      required ValueChanged<double> onChanged,
      double? other,
      String? hint,
      String? follows,
      bool following = false,
    }) =>
        _Dial(
          onSlideStart: () => _slideStart(label),
          onSlideEnd: _slideEnd,
          follows: follows,
          following: following,
          label: label,
          value: value,
          span: span,
          step: step,
          format: format,
          delta: delta,
          onChanged: onChanged,
          other: other,
          otherRole: otherRole,
          hint: hint,
        );

    final list = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _checkFloating();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _checkFloating();
          return false;
        },
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _Disclaimer(),
            _ResultCard(
              fieldKey: _fieldKey,
              event: _event,
              units: units,
              one: shown.one,
              two: shown.two,
              // What changed, under the picture of what it did.
              breakdown: shares == null
                  ? null
                  : _Settling(
                      stale: stale,
                      child: _GapShares(
                        speedLossPerDeg: loss,
                        shares: shares,
                        gap: stale ? _sum(shares) : gap,
                        one: _one,
                        two: _two!,
                        units: units,
                      ),
                    ),
              ghost: ghost,
              // The two ways off the number: ask what a change would do, or
              // go back to the throw that was measured.
              actions: [
                if (!_comparing)
                  FilledButton.tonalIcon(
                    key: const ValueKey('whatIfTry'),
                    onPressed: _addSecond,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Try a change'),
                  ),
                if (showBack)
                  TextButton.icon(
                    onPressed: _backToMeasured,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Back to the measured throw'),
                  ),
              ],
            ),
            _Heading('Release',
                action: _comparing
                    ? IconButton(
                        tooltip: 'Remove the what-if',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                        onPressed: _removeSecond,
                      )
                    : null),
            if (_comparing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: AngularSegmentedBar<int>(
                  value: _editing,
                  onChanged: (i) => setState(() => _editing = i),
                  segments: [
                    for (final i in [0, 1])
                      AngularSegment(
                        value: i,
                        // The throw's own ink, so the switch is also the key
                        // to the two lines on the field above it.
                        glyph: (_) => Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == 0 ? oneColor : twoColor,
                          ),
                        ),
                        label: _role(i),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        if (_comparing)
                          TextSpan(
                              text:
                                  'Moving the ${_role(_editing).toLowerCase()} · ',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        TextSpan(text: _source(_editing)),
                      ]),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  // Always there while the what-if is on the sliders, and only
                  // lit once it has moved: appearing on the first nudge pushed
                  // every dial under it down a row, out from under the thumb.
                  if (_comparing && _editing == 1)
                    IconButton(
                      key: const ValueKey('whatIfReset'),
                      tooltip: 'Start again from the baseline',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.restart_alt),
                      onPressed: _differs ? _resetToBaseline : null,
                    ),
                ],
              ),
            ),
            dial(
              label: 'Speed',
              follows: loss > 0 ? 'Angle' : null,
              following: _speedFollowing,
              value: current.release.speed,
              other: other?.speed,
              span: _spans[_event]!.speed,
              step: units.speedStep,
              format: units.speed,
              delta: units.speedDelta,
              onChanged: (v) => _setRelease(current.release.copyWith(speed: v)),
            ),
            dial(
              label: 'Angle',
              // Going higher costs release speed (Red and Zogaib 1977,
              // Linthorne 2001), so where the loss is modeled the speed moves
              // with the angle, by the amount on the best-angle card: a
              // steeper release at the same speed is a throw nobody makes,
              // and the flight flattered it. Where it isn't — the hammer, the
              // discus, a loss set to nothing — the speed is held, and that
              // is said where the angle is raised against the other throw.
              hint: loss > 0
                  ? 'Speed moves with it: '
                      '${units.speedDelta(-loss * 10)} per 10° steeper'
                  : other != null && current.release.angleDeg > other.angleDeg
                      ? 'Steeper than the ${_role(1 - _editing).toLowerCase()}. '
                          'Speed is held here, but a real athlete usually '
                          'releases slower when they release higher.'
                      : null,
              value: current.release.angleDeg,
              other: other?.angleDeg,
              span: _angleSpan,
              step: 0.5,
              format: (v) => '${v.toStringAsFixed(1)}°',
              delta: (d) => '${_signed(d, 1)}°',
              onChanged: _setAngle,
            ),
            dial(
              label: 'Height',
              value: current.release.height,
              other: other?.height,
              span: _spans[_event]!.height,
              step: units.heightStep,
              format: units.height,
              delta: units.heightDelta,
              onChanged: (v) =>
                  _setRelease(current.release.copyWith(height: v)),
            ),
            // What the implement does once it has left the hand, apart from
            // the three numbers every release has: a coach reading a shot put
            // never sees this heading, and one reading a javelin sees where
            // the release stops and the flight starts.
            if (_hasAttack(_event) || _hasWind(_event))
              const _Heading('In the air'),
            if (_hasAttack(_event))
              dial(
                label: 'Attack',
                hint: _event == ThrowEvent.discus
                    ? 'Leading edge above (+) or below (−) the path'
                    : 'Nose above (+) or below (−) the path',
                value: current.release.attackDeg,
                other: other?.attackDeg,
                span: _attackSpan,
                step: 0.5,
                format: (v) => '${_signed(v, 1)}°',
                delta: (d) => '${_signed(d, 1)}°',
                onChanged: (v) =>
                    _setRelease(current.release.copyWith(attackDeg: v)),
              ),
            if (_hasPitchRate(_event))
              dial(
                label: 'Pitch rate',
                hint: 'Nose turning up (+) or down (−) as it leaves the hand',
                value: current.release.pitchRate,
                other: other?.pitchRate,
                span: _pitchSpan,
                step: 1,
                format: (v) => '${_signed(v, 0)}°/s',
                delta: (d) => '${_signed(d, 0)}°/s',
                onChanged: (v) =>
                    _setRelease(current.release.copyWith(pitchRate: v)),
              ),
            if (_hasWind(_event))
              dial(
                label: 'Wind',
                hint: 'Behind the thrower (+) or in their face (−)',
                value: current.release.wind,
                other: other?.wind,
                span: _windSpan,
                step: units.windStep,
                format: units.wind,
                delta: units.windDelta,
                onChanged: (v) =>
                    _setRelease(current.release.copyWith(wind: v)),
              ),
            _Heading('Best angle',
                trailing: _comparing
                    ? 'for the ${_role(_editing).toLowerCase()}'
                    : null),
            _Settling(
              stale: stale,
              child: _BestAngle(
                event: _event,
                best: best,
                held: held,
                gain: derived.value.gain,
                angleDeg: derived.value.angleDeg,
                speedLoss: tradesSpeed ? _speedLoss : null,
                units: units,
                onTry: () => _tryAngle(best),
                lossDial: !tradesSpeed
                    ? null
                    : _Dial(
                        onSlideStart: () => _slideStart('loss'),
                        onSlideEnd: _slideEnd,
                        label: 'Speed lost per 10° steeper',
                        hint: _speedLossBasis(_event),
                        value: _speedLoss * 10,
                        span: _speedLossSpan,
                        step: units.speedStep,
                        format: units.speed,
                        delta: units.speedDelta,
                        onChanged: (v) => setState(() => _speedLoss = v / 10),
                      ),
                onResetLoss:
                    (_speedLoss - typicalSpeedLossPerDeg(_event)).abs() < 1e-9
                        ? null
                        : () => setState(
                            () => _speedLoss = typicalSpeedLossPerDeg(_event)),
              ),
            ),
            // One nudge each from where the sliders are, not a split of the
            // gap — that is what the list under the result is for, and a
            // heading that let these read as one had coaches adding them up.
            _Heading('What a nudge is worth',
                trailing: _comparing
                    ? 'from the ${_role(_editing).toLowerCase()}'
                    : 'from here'),
            _Settling(
              stale: stale,
              child: _Worth(
                  worth: worth, units: units, speedLossPerDeg: speedLoss),
            ),
            _Heading('Compare with elite throwers', trailing: _eliteTrailing()),
            _EliteThrowers(
              event: _event,
              spec: _spec,
              units: units,
              selected: _two?.label,
              typical: _elite(),
              // Only what was published: a row with a speed alone takes the
              // angle and height from the throw it is laid over.
              measured: (r) => _Throw(
                _spec,
                _one.release.copyWith(
                  speed: r.speed,
                  angleDeg: r.angleDeg,
                  height: r.height,
                ),
                r.athlete,
              ),
              onTap: _compareWith,
            ),
            const _Heading('About the model'),
            const _Caveat(),
            const _Heading('Sources'),
            const _Sources(),
          ],
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Stack(
        key: _stackKey,
        children: [
          list,
          // The result, kept in sight while the dials that move it are
          // being turned: once the card has scrolled off, a small copy of
          // it — the number and the flight — hangs at the top of the page,
          // so a slider halfway down it is never turned blind.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, -0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: !_floating
                  ? const SizedBox.shrink()
                  : _FloatingResult(
                      key: const ValueKey('whatIfFloating'),
                      event: _event,
                      units: units,
                      one: shown.one,
                      two: shown.two,
                      shares: stale ? null : shares,
                      gap: gap,
                      onTap: () => _scroll.animateTo(0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The implement both throws are flown with, set with the event rather
/// than with either throw: it belongs to the whole screen, and changing it
/// starts the screen over, which it says.
class _ImplementPicker extends StatelessWidget {
  const _ImplementPicker({
    required this.event,
    required this.value,
    required this.onChanged,
  });

  final ThrowEvent event;
  final ImplementSpec value;
  final ValueChanged<ImplementSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Row(
      children: [
        Text('Implement', style: theme.textTheme.bodyMedium),
        const SizedBox(width: 12),
        DropdownButton<ImplementSpec>(
          key: const ValueKey('whatIfImplement'),
          value: value,
          underline: const SizedBox(),
          borderRadius: BorderRadius.circular(12),
          style: theme.textTheme.titleSmall,
          items: [
            for (final s in event.implements)
              DropdownMenuItem(value: s, child: Text(s.weightLabel)),
          ],
          onChanged: (s) {
            if (s != null) onChanged(s);
          },
        ),
        const Spacer(),
        Flexible(
          child: Text('Changing it resets',
              overflow: TextOverflow.ellipsis, style: muted),
        ),
      ],
    );
  }
}

/// Where the speed-loss estimate an event opens on comes from, said under
/// its dial: a number a coach is asked to trust or replace has to say what
/// it rests on.
String _speedLossBasis(ThrowEvent event) => switch (event) {
      ThrowEvent.javelin =>
        'Estimated from academic research: Red & Zogaib (1977) measured '
            'javelin throwers releasing slower as they released higher. '
            "Set it to your athlete's own if you have it.",
      _ => 'Estimated from academic research: Linthorne (2001) measured '
          'shot putters releasing slower as they released higher. '
          "Set it to your athlete's own if you have it.",
    };

double _sum(Map<Lever, double> m) => m.values.fold(0.0, (a, b) => a + b);

/// What is held over from before a slider was picked up, set back while it
/// is: a best angle and a breakdown for the throw as it was, read at full
/// weight beside a flight that has moved on, would say two things at once.
class _Settling extends StatelessWidget {
  const _Settling({required this.stale, required this.child});

  final bool stale;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: stale ? 0.4 : 1,
        duration: const Duration(milliseconds: 120),
        child: child,
      );
}

/// '+0.8', '−2.0', '0.0' — a plain zero rather than a signed one, since
/// '+0.0' reads as a change that isn't there.
String _signed(double v, int digits) {
  final s = v.abs().toStringAsFixed(digits);
  if (double.parse(s) == 0) return s;
  return '${v > 0 ? '+' : '−'}$s';
}

typedef _Shown = ({String name, Flight flight, Color color});

typedef _Derived = ({
  ({double angleDeg, double distance, double speed}) best,
  ({double angleDeg, double distance, double speed})? held,
  ({double perSpeed, double perDegree, double perHeight}) worth,
  Map<Lever, double>? shares,
  Flight? ghost,

  /// What the best angle gains on the throw it was worked out for, and the
  /// angle that throw was at — kept with the answer so that, held over
  /// while a slider moves, the two still describe one throw.
  double gain,
  double angleDeg,
});

/// The gap said the way a coach would say it: how much further or shorter
/// the change throws than what it was measured from.
({String gapText, String verdict, bool same}) _gapWords(
    double gap, DistanceUnit unit) {
  final same = formatDistance(gap.abs(), unit) == formatDistance(0, unit);
  return (
    gapText: same
        ? formatDistance(0, unit)
        : '${gap > 0 ? '+' : '−'}${formatDistance(gap.abs(), unit)}',
    verdict: same
        ? 'the same as the baseline'
        : gap > 0
            ? 'further than the baseline'
            : 'shorter than the baseline',
    same: same,
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.event,
    required this.units,
    required this.one,
    required this.two,
    required this.ghost,
    this.actions = const [],
    this.breakdown,
    this.fieldKey,
  });

  /// On the flight, so the screen can tell when it has scrolled away.
  final Key? fieldKey;

  final ThrowEvent event;
  final _Units units;
  final _Shown one;
  final _Shown? two;
  final Flight? ghost;
  final List<Widget> actions;

  /// Where the gap comes from, when there are two throws.
  final Widget? breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final big =
        theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final unit = units.distance;

    Widget headline() {
      if (two == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(one.name.toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1.1, color: scheme.primary)),
            _Approx(
              text: formatDistance(one.flight.distance, unit),
              style: big,
              valueKey: const ValueKey('whatIfDistance'),
            ),
            Text(
              '${one.flight.time.toStringAsFixed(2)} s in the air · '
              'peaks ${units.rise(one.flight.apex)} up',
              style: muted,
            ),
          ],
        );
      }
      final (:gapText, :verdict, :same) =
          _gapWords(two!.flight.distance - one.flight.distance, unit);
      final gap = two!.flight.distance - one.flight.distance;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHAT IF',
              style: theme.textTheme.labelSmall
                  ?.copyWith(letterSpacing: 1.1, color: scheme.primary)),
          _Approx(
            text: gapText,
            style: big?.copyWith(
                color: same
                    ? null
                    : gap > 0
                        ? scheme.primary
                        : scheme.error),
            valueKey: const ValueKey('whatIfGap'),
          ),
          Text(verdict,
              key: const ValueKey('whatIfVerdict'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final (i, t) in [(0, one), (1, two!)])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: t.color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: _ReleaseCalculatorScreenState._role(i),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(
                            text: ' · ${t.name}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ]),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text('≈ ${formatDistance(t.flight.distance, unit)}',
                      key: ValueKey('whatIfDistance${i + 1}'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      );
    }

    // Solid, like the live board's card: a field drawn over the sector
    // backdrop is two fields at different angles.
    final surface = solidCardOverSector(scheme);
    return Card(
      color: surface,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headline(),
            const SizedBox(height: 12),
            FlightField(
              key: fieldKey,
              event: event,
              flights: [
                FieldFlight(one.flight, one.color),
                if (two != null) FieldFlight(two!.flight, two!.color),
              ],
              unit: unit,
              backdrop: surface,
              ghost: ghost,
            ),
            if (ghost != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: CustomPaint(
                        size: const Size(18, 2),
                        painter: _DashPainter(scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('The same throw at its best angle',
                          style: muted),
                    ),
                  ],
                ),
              ),
            if (breakdown != null) breakdown!,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The dashed key to the ghost flight on the field.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(x + 3, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A distance with the '≈' every estimate on this screen wears.
class _Approx extends StatelessWidget {
  const _Approx({required this.text, this.style, this.valueKey});

  final String text;
  final TextStyle? style;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('≈ ',
            style: theme.textTheme.headlineMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text, key: valueKey, style: style),
          ),
        ),
      ],
    );
  }
}

/// How far a typical elite release goes with an implement. It is the same
/// for as long as the event and implement are, and flying it again on every
/// move of a slider was a javelin flight a frame spent on nothing.
final _typicalDistances = <String, double>{};

double _typicalDistance(ThrowEvent event, ImplementSpec spec, Release r) =>
    _typicalDistances.putIfAbsent(
        '${event.name}|${spec.weightKg}|${r.speed}|${r.angleDeg}|'
        '${r.height}|${r.attackDeg}',
        () => flyThrow(event, spec, r).distance);

/// The elite throwers who throw this implement, one tap each: the typical
/// release first, approximate and drawn from the literature, then the
/// throwers measured by name. Only this implement's — an elite thrower's
/// release flown with somebody else's implement is a throw nobody made —
/// so a lighter implement than the senior ones has nobody, and says so.
class _EliteThrowers extends StatelessWidget {
  const _EliteThrowers({
    required this.event,
    required this.spec,
    required this.units,
    required this.selected,
    required this.typical,
    required this.measured,
    required this.onTap,
  });

  final ThrowEvent event;
  final ImplementSpec spec;
  final _Units units;
  final String? selected;
  final _Throw? typical;
  final _Throw Function(EliteRelease) measured;
  final ValueChanged<_Throw> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final named = eliteReferencesFor(event, spec.weightKg);
    // A boys' implement borrows the men's elite throwers: their release,
    // flown with this implement.
    final eliteKg = eliteWeightFor(event, spec.weightKg);
    final borrowed = eliteKg != null && eliteKg != spec.weightKg;
    final eliteLabel =
        eliteKg == null ? null : event.specFor(eliteKg).weightLabel;

    Widget row({
      required Key key,
      required _Throw t,
      required String title,
      required String subtitle,
      bool threeLine = false,
    }) {
      final on = selected == t.label;
      return ListTile(
        key: key,
        onTap: () => onTap(t),
        title: Text(title),
        subtitle: Text(subtitle),
        isThreeLine: threeLine,
        trailing: Icon(on ? Icons.check_circle : Icons.add_circle_outline,
            color: on ? scheme.primary : scheme.onSurfaceVariant),
      );
    }

    final senior = [
      for (final r in eliteRanges[event]!.values)
        event.specFor(r.weightKg).weightLabel
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: cardOverSector(scheme),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (typical != null)
                  row(
                    key: const ValueKey('elite-typical'),
                    t: typical!,
                    title: _eliteLabel,
                    subtitle:
                        '≈ ${units.mark(_typicalDistance(event, spec, typical!.release))}'
                        ' · ${units.release(typical!.release)}',
                  ),
                for (final r in named)
                  row(
                    key: ValueKey('elite-${r.athlete}'),
                    t: measured(r),
                    title: r.athlete,
                    subtitle: '${units.mark(r.mark)}'
                        '${borrowed ? ' with the $eliteLabel' : ''}'
                        ' · ${r.meet}\n'
                        '${units.speed(r.speed)}'
                        '${r.angleDeg == null ? '' : ' · ${r.angleDeg!.toStringAsFixed(1)}°'}'
                        '${r.height == null ? '' : ' · ${units.height(r.height!)}'}'
                        '${r.complete ? '' : ' · speed only published'}',
                    threeLine: true,
                  ),
                if (typical == null && named.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Text(
                      key: const ValueKey('eliteNone'),
                      'Elite throwers throw the ${senior.join(' and the ')}, '
                      "and the men's stand in for the boys' implements "
                      'between them, so there is no one to compare the '
                      '${spec.weightLabel} with.',
                      style: muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (typical != null || named.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${borrowed ? "Elite men's releases, flown with the ${spec.weightLabel}: it is the speed and angle that carry across, not the implement. " : ''}'
              '${typical == null ? '' : 'The typical release is approximate, drawn from the biomechanics literature rather than one report. '}'
              '${named.isEmpty ? '' : 'Named throwers were measured at the championship given. '}'
              'Tap one to compare it with the baseline.',
              style: muted,
            ),
          ),
      ],
    );
  }
}

class _BestAngle extends StatelessWidget {
  const _BestAngle({
    required this.event,
    required this.best,
    required this.held,
    required this.gain,
    required this.angleDeg,
    required this.speedLoss,
    required this.units,
    required this.onTry,
    this.lossDial,
    this.onResetLoss,
  });

  final ThrowEvent event;
  final ({double angleDeg, double distance, double speed}) best;

  /// The flight's own best, with speed held, when that differs from [best].
  final ({double angleDeg, double distance, double speed})? held;
  final double gain;
  final double angleDeg;

  /// m/s per degree, or null for an event flown at a held speed.
  final double? speedLoss;
  final _Units units;

  /// Puts the best angle on the sliders.
  final VoidCallback onTry;

  /// The speed lost per degree, set here rather than among the release's
  /// own dials: it is not part of any throw, only of how the best angle is
  /// searched for, and among speed, angle and height it read as a fourth
  /// thing about the release.
  final Widget? lossDial;

  /// Back to the estimate, when the coach has moved off it.
  final VoidCallback? onResetLoss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = units.distance;
    // Within a quarter degree, or a couple of centimeters, of the best angle
    // is at it — saying 'best at 37.1°' under a slider sat on 37.0° is
    // noise.
    final atBest = (best.angleDeg - angleDeg).abs() < 0.25 || gain < 0.02;
    final forThrower = speedLoss != null && speedLoss! > 0;
    final String line;
    if (forThrower) {
      line = atBest
          ? "At this thrower's best angle."
          : "Best angle for this thrower: ${best.angleDeg.toStringAsFixed(1)}°, "
              // Kept on one line with its unit.
              '+${formatDistance(gain, unit).replaceAll(' ', ' ')}.';
    } else {
      line = atBest
          ? 'At the best angle for this speed and height.'
          : 'Best angle with everything else held: '
              '${best.angleDeg.toStringAsFixed(1)}°, '
              '+${formatDistance(gain, unit).replaceAll(' ', ' ')}.';
    }
    final String note;
    if (forThrower) {
      note = 'Speed falls as the angle rises, which is most of why elite '
          'throwers release in the thirties. With speed held, the flight alone is best '
          'at ${held!.angleDeg.toStringAsFixed(1)}°.'
          '${_hasAttack(event) ? ' The attack angle is held with it.' : ''}';
    } else if (speedLoss != null) {
      // The coach has set the loss to nothing.
      note = 'Speed is held, so this is the flight\'s best angle, not an '
          "athlete's: a real one releases slower going higher.";
    } else {
      note = '${_hasAttack(event) ? 'The attack angle is held with it. ' : ''}'
          'Speed is held too — nobody has measured how much a '
          '${event == ThrowEvent.hammer ? 'hammer' : 'discus'} thrower loses '
          "going higher, so an athlete's own best angle sits somewhat under "
          'this one.';
    }
    final scheme = theme.colorScheme;
    return Card(
      color: cardOverSector(scheme),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(line,
                        key: const ValueKey('bestAngle'),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (!atBest) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      key: const ValueKey('tryBestAngle'),
                      onPressed: onTry,
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact),
                      child: const Text('Try it'),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                note,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (lossDial != null) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Divider(height: 1),
              ),
              lossDial!,
              if (onResetLoss != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton.icon(
                    key: const ValueKey('resetSpeedLoss'),
                    onPressed: onResetLoss,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Back to the research estimate'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label, {this.trailing, this.action});

  final String label;
  final String? trailing;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, action == null ? 16 : 8, 6),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: style)),
            if (trailing != null)
              Text(trailing!,
                  style: style?.copyWith(
                      letterSpacing: 0, fontWeight: FontWeight.w400)),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

/// A labelled slider that snaps to [step], so what it reads is what was
/// set — with the other throw's setting ticked on its track and how far
/// this one is from it beside the value. A thumb is a blunt tool for a
/// tenth of a meter a second, so a step either way sits at each end of the
/// track, and the difference is a button that puts this one back level
/// with the other throw: the two things a coach otherwise drags at and
/// misses.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.span,
    required this.step,
    required this.format,
    required this.delta,
    required this.onChanged,
    this.other,
    this.otherRole,
    this.hint,
    this.onSlideStart,
    this.onSlideEnd,
    this.follows,
    this.following = false,
  });

  final String label;
  final String? hint;
  final double value;

  /// A finger down on the track, and up again.
  final VoidCallback? onSlideStart;
  final VoidCallback? onSlideEnd;

  /// The dial this one moves with, when it moves with one — the speed with
  /// the angle — said by a link beside the label.
  final String? follows;

  /// Lit while it is being moved by the one it [follows]: the step it takes
  /// is a few percent of its track, and unlit it was easy to watch the
  /// angle and never see the speed go with it.
  final bool following;

  /// The same setting on the other throw, when there is one.
  final double? other;

  /// What the other throw is called, for the match button's tooltip.
  final String? otherRole;
  final (double, double) span;
  final double step;
  final String Function(double) format;
  final String Function(double) delta;
  final ValueChanged<double> onChanged;

  static const _inset = 18.0;

  double _snap(double v) => _clamp((v / step).round() * step, span);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = other == null ? 0.0 : value - other!;
    final differs = other != null && diff.abs() >= step / 2;
    Widget nudge(IconData icon, double by, String tip) {
      final next = _snap(value + by);
      return IconButton(
        key: ValueKey('$tip-$label'),
        tooltip: '$tip $label',
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: scheme.onSurfaceVariant,
        onPressed:
            (next - value).abs() < step / 2 ? null : () => onChanged(next),
        icon: Icon(icon),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      decoration: BoxDecoration(
        color: following
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.primary.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge),
                    ),
                    if (follows != null)
                      Tooltip(
                        message: 'Moves with the ${follows!.toLowerCase()}',
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(Icons.link,
                              key: ValueKey('follows-$label'),
                              size: 16,
                              color: following
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                        ),
                      ),
                    if (following)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text('with the ${follows!.toLowerCase()}',
                              key: ValueKey('following-$label'),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: scheme.primary)),
                        ),
                      ),
                  ],
                ),
              ),
              if (differs)
                Tooltip(
                  message: 'Match the ${otherRole ?? 'other throw'}',
                  child: InkWell(
                    key: ValueKey('match-$label'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => onChanged(_clamp(other!, span)),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.fromLTRB(6, 1, 4, 1),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(delta(diff),
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 2),
                          Icon(Icons.undo, size: 12, color: scheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              Text(format(value),
                  style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: following ? scheme.primary : null)),
            ],
          ),
          if (hint != null)
            Text(hint!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          Row(
            children: [
              nudge(Icons.remove, -step, 'Lower'),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final track = box.maxWidth - 2 * _inset;
                  double xOf(double v) =>
                      _inset + track * (v - span.$1) / (span.$2 - span.$1);
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (other != null)
                        Positioned(
                          left: xOf(_clamp(other!, span)) - 1.5,
                          top: 10,
                          bottom: 10,
                          child: Container(
                            key: ValueKey('other-$label'),
                            width: 3,
                            decoration: BoxDecoration(
                              color: scheme.onSurfaceVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: _inset),
                        ),
                        child: Slider(
                          value: value,
                          min: span.$1,
                          max: span.$2,
                          semanticFormatterCallback: format,
                          onChangeStart: (_) => onSlideStart?.call(),
                          onChangeEnd: (_) => onSlideEnd?.call(),
                          onChanged: (v) => onChanged(_snap(v)),
                        ),
                      ),
                    ],
                  );
                }),
              ),
              nudge(Icons.add, step, 'Raise'),
            ],
          ),
        ],
      ),
    );
  }
}

/// [shares] rounded to what the screen shows — hundredths of a meter, or
/// quarter inches floored the way a mark in feet is — so the rows add up
/// to the headline as printed and not just as computed. Each share is
/// rounded, and what that leaves over or short is moved one step at a time
/// onto the rows the rounding treated worst.
Map<Lever, int> _shownSteps(
    Map<Lever, double> shares, double gap, double step, bool floor) {
  final int target = floor
      ? gap.sign.toInt() * (gap.abs() / step + 1e-6).floor()
      : (gap / step).round();
  final raw = {for (final e in shares.entries) e.key: e.value / step};
  final shown = {for (final e in raw.entries) e.key: e.value.round()};
  var over = target - shown.values.fold<int>(0, (a, b) => a + b);
  while (over != 0 && shown.isNotEmpty) {
    final dir = over.sign;
    final worst = shown.keys.reduce((x, y) =>
        (raw[x]! - shown[x]!) * dir >= (raw[y]! - shown[y]!) * dir ? x : y);
    shown[worst] = shown[worst]! + dir;
    over -= dir;
  }
  return shown;
}

/// Where the gap between the baseline and the what-if comes from: one row
/// per lever that differs between them, largest first, adding up to the
/// headline.
class _GapShares extends StatelessWidget {
  const _GapShares({
    required this.shares,
    required this.gap,
    required this.one,
    required this.two,
    required this.units,
    this.speedLossPerDeg = 0,
  });

  final Map<Lever, double> shares;
  final double gap;
  final _Throw one;
  final _Throw two;
  final _Units units;

  /// The speed an angle carries with it, as the shares were split: the
  /// angle's row says the speed it cost, and the speed's row only what
  /// changed on top of that.
  final double speedLossPerDeg;

  String _change(Lever l) {
    final a = one.release;
    final b = two.release;
    final carried = -speedLossPerDeg * (b.angleDeg - a.angleDeg);
    return switch (l) {
      Lever.speed => units.speedDelta(b.speed - a.speed - carried),
      Lever.angle => '${_signed(b.angleDeg - a.angleDeg, 1)}°'
          '${carried.abs() < 0.005 ? '' : ' at ${units.speedDelta(carried, fine: true)}'}',
      Lever.height => units.heightDelta(b.height - a.height),
      Lever.attack => '${_signed(b.attackDeg - a.attackDeg, 1)}°',
      Lever.wind => units.windDelta(b.wind - a.wind),
      Lever.pitchRate => '${_signed(b.pitchRate - a.pitchRate, 0)}°/s',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final rows = _shareRows(shares, gap, units);
    // Inside the result card, under the flight: what changed sits with the
    // picture of what it did, rather than a heading further down the page.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Text('WHERE THE GAP COMES FROM',
            style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        // Said as a prompt, and at a row's height, rather than the rows
        // turning up on the first nudge and pushing every dial under the
        // card down out from under the thumb.
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.tune, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Move a dial below to change the what-if.',
                    key: const ValueKey('gapEmpty'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: _leverLabel(r.lever)),
                      TextSpan(text: '  ${_change(r.lever)}', style: muted),
                    ]),
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  r.text,
                  key: ValueKey('gapShare-${r.lever.name}'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _shareColor(r.sign, scheme),
                  ),
                ),
              ],
            ),
          ),
        if (rows.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'These add up to the gap. What two changes do together is '
              'shared between them, so a row is not what that change would '
              'be worth on its own.',
              style: muted,
            ),
          ),
      ],
    );
  }
}

String _leverLabel(Lever l) => switch (l) {
      Lever.speed => 'Speed',
      Lever.angle => 'Angle',
      Lever.height => 'Height',
      Lever.attack => 'Attack',
      Lever.wind => 'Wind',
      Lever.pitchRate => 'Pitch rate',
    };

Color? _shareColor(int sign, ColorScheme scheme) => sign == 0
    ? null
    : sign > 0
        ? scheme.primary
        : scheme.error;

/// The gap's shares as printed, largest first: each lever, its share
/// spelled in the reading unit, and which way it went.
List<({Lever lever, String text, int sign})> _shareRows(
    Map<Lever, double> shares, double gap, _Units units) {
  final feet = units.imperial;
  final step = feet ? metersPerFoot / 48 : 0.01;
  final shown = _shownSteps(shares, gap, step, feet);
  final order = shares.keys.toList()
    ..sort((x, y) => shares[y]!.abs().compareTo(shares[x]!.abs()));
  return [
    for (final l in order)
      (
        lever: l,
        text: () {
          final k = shown[l]!;
          final size = formatDistance(k.abs() * step, units.distance);
          return k == 0 ? size : '${k > 0 ? '+' : '−'}$size';
        }(),
        sign: shown[l]!.sign,
      ),
  ];
}

/// The result, small, for while the card itself is scrolled out of sight:
/// the number, the flight under it, and — comparing — what the gap is made
/// of in a line. A tap goes back up to the card.
class _FloatingResult extends StatelessWidget {
  const _FloatingResult({
    super.key,
    required this.event,
    required this.units,
    required this.one,
    required this.two,
    required this.shares,
    required this.gap,
    required this.onTap,
  });

  final ThrowEvent event;
  final _Units units;
  final _Shown one;
  final _Shown? two;
  final Map<Lever, double>? shares;
  final double gap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unit = units.distance;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final number = theme.textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700, height: 1.1);
    final surface = solidCardOverSector(scheme);

    final Widget headline;
    if (two == null) {
      headline = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('≈ ${formatDistance(one.flight.distance, unit)}', style: number),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(one.name, overflow: TextOverflow.ellipsis, style: muted),
          ),
        ],
      );
    } else {
      final words = _gapWords(gap, unit);
      headline = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('≈ ${words.gapText}',
              style: number?.copyWith(
                  color: words.same
                      ? null
                      : gap > 0
                          ? scheme.primary
                          : scheme.error)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${formatDistance(two!.flight.distance, unit)} against '
              '${formatDistance(one.flight.distance, unit)}',
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
        ],
      );
    }
    final rows = shares == null ? null : _shareRows(shares!, gap, units);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: DecoratedBox(
        // A soft shadow and a hairline: lifted off the page it floats over,
        // without a dark ring round it.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side:
                BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: headline),
                      Tooltip(
                        message: 'Back to the result',
                        child: Icon(Icons.keyboard_arrow_up,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FlightField(
                      event: event,
                      flights: [
                        FieldFlight(one.flight, one.color),
                        if (two != null) FieldFlight(two!.flight, two!.color),
                      ],
                      unit: unit,
                      backdrop: surface,
                      maxHeight: 116,
                    ),
                  ),
                  if (rows != null && rows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 6),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          for (final r in rows)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '${_leverLabel(r.lever)} '),
                                TextSpan(
                                  text: r.text,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _shareColor(r.sign, scheme)),
                                ),
                              ]),
                              style: muted,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Worth extends StatelessWidget {
  const _Worth(
      {required this.worth, required this.units, this.speedLossPerDeg = 0});

  final ({double perSpeed, double perDegree, double perHeight}) worth;
  final _Units units;

  /// What a degree steeper costs in speed, said on its tile when it costs
  /// any, since the tile is flown at it.
  final double speedLossPerDeg;

  @override
  Widget build(BuildContext context) {
    String signed(double m) => '${m >= 0 ? '+' : '−'}${units.mark(m.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _WorthTile(
              lever: units.speedLeverLabel, gain: signed(worth.perSpeed)),
          _WorthTile(
              lever: speedLossPerDeg > 0
                  ? '+1° at ${units.speedDelta(-speedLossPerDeg, fine: true)}'
                  : '+1°',
              gain: signed(worth.perDegree)),
          _WorthTile(
              lever: units.heightLeverLabel, gain: signed(worth.perHeight)),
        ],
      ),
    );
  }
}

class _WorthTile extends StatelessWidget {
  const _WorthTile({required this.lever, required this.gain});

  final String lever;
  final String gain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        color: cardOverSector(theme.colorScheme),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(gain,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(lever,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the model is built and where it falls short, a point to a
/// paragraph: one block of it was a page nobody read to the end, and the
/// end was where the javelin's and the discus's caveats were.
class _Caveat extends StatelessWidget {
  const _Caveat();

  static const _points = [
    (
      'The flight',
      'The implement is flown as a point through still, sea-level air. Drag '
          'acts on every implement, and lift on the discus and the javelin. '
          'Distance runs from the hand, so the few tenths a thrower reaches '
          'past the stop board are not in it.',
    ),
    (
      'Javelin',
      'Flies on drag, lift and pitching moment measured in a wind tunnel on '
          "a women's 600 g javelin (Seo et al. 2023), with nothing tuned; "
          'every other weight flies on the same ones with its own length and '
          "thickness, since no men's javelin has been measured that way. It "
          'pitches under the measured moment — nose-up under about 11° of '
          'attack, nose-down over it — so it settles there and rides it. How '
          'heavy it is to turn is an estimate.',
    ),
    (
      'Discus',
      'Its coefficients are shaped like the tunnel curves in the papers '
          'below and tuned so elite releases land where elite throwers do. '
          'It holds the tilt it was released at, stalls at 29° and only '
          'recovers under 25°. The real one turns in roll, which a flight in '
          'one plane cannot show, and it comes out several meters short at '
          'elite speeds.',
    ),
    (
      'Hammer',
      'The wire is not counted, and speed is held when the best angle is '
          'searched for, because nobody has measured how much a hammer '
          'thrower loses going higher.',
    ),
    (
      'Speed lost going higher',
      'Release speed falls as the release angle rises, so the best angle '
          'for the javelin and the shot is searched with speed falling by the '
          'amount set on that card. It opens on an estimate built from '
          'academic research — Red & Zogaib (1977) on javelin throwers, '
          'Linthorne (2001) on shot putters — scaled to each event rather '
          "than one published number, and is best replaced by an athlete's "
          'own.',
    ),
    (
      'References',
      'A measured release is only as good as the video: side-on, square to '
          'the throw. The typical elite throwers are approximate ranges drawn '
          "from the literature, the women's from the thinner half of it, and "
          "are offered with the implement they throw — and the men's with "
          "the boys' and junior men's implements between the men's and the "
          "women's, since it is the release that carries across.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (title, body) in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$title. ',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(text: body),
                ]),
                style: muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Said once, at the top, where nobody can scroll past it on the way to a
/// number.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('whatIfDisclaimer'),
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      // Small, because it is read once and then sits over every number
      // after that: the banner it replaced was a third of the result card.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline,
                size: 16, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Numbers are based on ideal, simplified flight mechanics and '
              'should be used as a guide, not a reference.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the model and the reference numbers are drawn from, and what each
/// was used for — so a coach can go and check any number on the page.
class _Sources extends StatelessWidget {
  const _Sources();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final sources = [
      ...whatIfSources,
      // Each measured release names the report it came out of.
      for (final report in {for (final r in eliteReleases) r.source})
        (
          citation: report,
          usedFor: 'Release speeds of the named elite throwers, and the angle '
              'and height where they were published.',
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, source) in sources.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 22, child: Text('${i + 1}.', style: muted)),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: source.citation,
                          style: theme.textTheme.bodySmall),
                      TextSpan(text: '\n${source.usedFor}', style: muted),
                    ])),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
