import 'package:flutter/material.dart';

import '../models/elite_releases.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/flight_model.dart';
import '../widgets/distance_field.dart';
import '../widgets/event_glyph.dart';
import '../widgets/flight_field.dart';
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

bool _hasAttack(ThrowEvent event) =>
    event == ThrowEvent.discus || event == ThrowEvent.javelin;

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
  String speedDelta(double d) =>
      imperial ? '${_signed(d / _mph, 1)} mph' : '${_signed(d, 1)} m/s';

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
/// when it is somebody's. A throw that is moved on a slider is nobody's any
/// more — Walsh's release with another meter a second on it is not Walsh's.
class _Throw {
  const _Throw(this.spec, this.release, [this.label]);
  final ImplementSpec spec;
  final Release release;
  final String? label;
}

String _eliteLabel(EliteRange r, ImplementSpec spec) =>
    '${r.field.label} · ${spec.weightLabel}';

class _ReleaseCalculatorScreenState extends State<ReleaseCalculatorScreen> {
  static const _measuredLabel = 'Your measured throw';

  late ThrowEvent _event = widget.event;
  late _Throw _one = widget.measured == null
      ? _elite(widget.event, EliteField.men)
      : _fit(
          _Throw(
            widget.implementKg == null
                ? widget.event.defaultImplement
                : widget.event.specFor(widget.implementKg!),
            widget.measured!,
            _measuredLabel,
          ),
          widget.event);
  _Throw? _two;

  /// Which throw the sliders move: 0, the baseline, or 1, the what-if.
  int _editing = 0;

  /// Opens in whatever the coach last typed a distance in, and can be
  /// flipped here without changing that — reading one what-if in the other
  /// unit is not a change of mind about the next mark.
  late DistanceUnit _unit = DistanceField.preferred;

  bool get _comparing => _two != null;
  _Throw get _current => _editing == 1 ? _two! : _one;
  _Throw? get _other => !_comparing ? null : (_editing == 1 ? _one : _two);

  _Throw _elite(ThrowEvent event, EliteField field) {
    final range = eliteRanges[event]![field]!;
    final spec = event.specFor(range.weightKg);
    return _Throw(
      spec,
      Release(
        speed: range.typicalSpeed,
        angleDeg: range.typicalAngle,
        height: range.typicalHeight,
        attackDeg: range.attackDeg,
      ),
      _eliteLabel(range, spec),
    );
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

  void _setSpec(ImplementSpec spec) =>
      setState(() => _put(_Throw(spec, _current.release)));

  void _pickEvent(ThrowEvent event) {
    if (event == _event) return;
    setState(() {
      _event = event;
      _one = _elite(event, EliteField.men);
      _two = null;
      _editing = 0;
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

  void _backToMeasured() => setState(() {
        _one = _fit(
            _Throw(
                widget.implementKg == null
                    ? widget.event.defaultImplement
                    : widget.event.specFor(widget.implementKg!),
                widget.measured!,
                _measuredLabel),
            _event);
      });

  /// Two roles rather than two numbers. The baseline is whatever the
  /// comparison is measured from — a measured throw, an elite final, or
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
    final oneFlight = flyThrow(_event, _one.spec, _one.release);
    final twoFlight =
        _two == null ? null : flyThrow(_event, _two!.spec, _two!.release);
    final current = _current;
    final best = bestAngle(_event, current.spec, current.release);
    final units = _Units(_unit);
    final worth = sensitivity(_event, current.spec, current.release,
        speedStep: units.speedLever, heightStep: units.heightLever);
    final unit = _unit;
    // The first throw steps back to a neutral ink once there is a second to
    // stand in front of it.
    final oneColor = _comparing ? scheme.onSurfaceVariant : scheme.primary;
    final twoColor = scheme.primary;
    final showBack = widget.measured != null &&
        _event == widget.event &&
        _one.label != _measuredLabel;
    final other = _other?.release;

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
                ButtonSegment(value: DistanceUnit.meters, label: Text('m')),
                ButtonSegment(value: DistanceUnit.feet, label: Text('ft')),
              ],
              selected: {_unit},
              onSelectionChanged: (u) => setState(() => _unit = u.first),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _EventPicker(event: _event, onEvent: _pickEvent),
            ),
            const _Disclaimer(),
            _ResultCard(
              event: _event,
              units: units,
              one: (name: _source(0), flight: oneFlight, color: oneColor),
              two: twoFlight == null
                  ? null
                  : (name: _source(1), flight: twoFlight, color: twoColor),
              ghost: _comparing || (best.distance - oneFlight.distance) < 0.02
                  ? null
                  : flyThrow(_event, _one.spec,
                      _one.release.copyWith(angleDeg: best.angleDeg)),
            ),
            if (showBack)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton.icon(
                    onPressed: _backToMeasured,
                    icon: const Icon(Icons.undo),
                    label: const Text('Back to the measured throw'),
                  ),
                ),
              ),
            _Heading('Release',
                action: _comparing
                    ? IconButton(
                        tooltip: 'Remove the what-if',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close),
                        onPressed: _removeSecond,
                      )
                    : TextButton.icon(
                        onPressed: _addSecond,
                        icon: const Icon(Icons.add),
                        label: const Text('Try a change'),
                      )),
            if (_comparing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final i in [0, 1])
                      ButtonSegment(
                        value: i,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == 0 ? oneColor : twoColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_role(i)),
                          ],
                        ),
                      ),
                  ],
                  selected: {_editing},
                  onSelectionChanged: (s) => setState(() => _editing = s.first),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _source(_editing),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  DropdownButton<ImplementSpec>(
                    value: current.spec,
                    underline: const SizedBox(),
                    items: [
                      for (final s in _event.implements)
                        DropdownMenuItem(value: s, child: Text(s.weightLabel)),
                    ],
                    onChanged: (s) {
                      if (s != null) _setSpec(s);
                    },
                  ),
                ],
              ),
            ),
            _Dial(
              label: 'Speed',
              value: current.release.speed,
              other: other?.speed,
              span: _spans[_event]!.speed,
              step: units.speedStep,
              format: units.speed,
              delta: units.speedDelta,
              onChanged: (v) => _setRelease(current.release.copyWith(speed: v)),
            ),
            _Dial(
              label: 'Angle',
              value: current.release.angleDeg,
              other: other?.angleDeg,
              span: _angleSpan,
              step: 0.5,
              format: (v) => '${v.toStringAsFixed(1)}°',
              delta: (d) => '${_signed(d, 1)}°',
              onChanged: (v) =>
                  _setRelease(current.release.copyWith(angleDeg: v)),
            ),
            _Dial(
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
            if (_hasAttack(_event))
              _Dial(
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
            if (_hasWind(_event))
              _Dial(
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
            _BestAngle(
              best: best,
              gain: best.distance -
                  flyThrow(_event, current.spec, current.release).distance,
              angleDeg: current.release.angleDeg,
              flies: _hasAttack(_event),
              unit: unit,
            ),
            _Heading('What each is worth',
                trailing: _comparing
                    ? 'to the ${_role(_editing).toLowerCase()}'
                    : null),
            _Worth(worth: worth, units: units),
            const _Heading('Compare with an elite final'),
            _EliteCards(
              event: _event,
              units: units,
              selected: _two?.label,
              throwFor: (field) => _elite(_event, field),
              onTap: _compareWith,
            ),
            _Heading('Measured at finals', trailing: _event.label),
            _References(
              event: _event,
              selected: _two?.label,
              units: units,
              onTry: (r) {
                final spec = _event.specFor(r.weightKg);
                // Only what was published: a row with a speed alone takes
                // the angle and height from the throw it is laid over.
                _compareWith(_Throw(
                  spec,
                  _one.release.copyWith(
                    speed: r.speed,
                    angleDeg: r.angleDeg,
                    height: r.height,
                  ),
                  r.athlete,
                ));
              },
            ),
            const _Heading('About the model'),
            const _Caveat(),
            const _Heading('Sources'),
            const _Sources(),
          ],
        ),
      ),
    );
  }
}

/// '+0.8', '−2.0', '0.0' — a plain zero rather than a signed one, since
/// '+0.0' reads as a change that isn't there.
String _signed(double v, int digits) {
  final s = v.abs().toStringAsFixed(digits);
  if (double.parse(s) == 0) return s;
  return '${v > 0 ? '+' : '−'}$s';
}

class _EventPicker extends StatelessWidget {
  const _EventPicker({required this.event, required this.onEvent});

  final ThrowEvent event;
  final ValueChanged<ThrowEvent> onEvent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ThrowEvent>(
          showSelectedIcon: false,
          segments: [
            for (final e in ThrowEvent.values)
              ButtonSegment(
                value: e,
                tooltip: e.label,
                icon: EventGlyph(e, size: 22),
              ),
          ],
          selected: {event},
          onSelectionChanged: (s) => onEvent(s.first),
        ),
        const SizedBox(height: 8),
        Text(event.label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

typedef _Shown = ({String name, Flight flight, Color color});

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.event,
    required this.units,
    required this.one,
    required this.two,
    required this.ghost,
  });

  final ThrowEvent event;
  final _Units units;
  final _Shown one;
  final _Shown? two;
  final Flight? ghost;

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
      final gap = two!.flight.distance - one.flight.distance;
      // Said the way a coach would say it: how much further or shorter the
      // change throws than what it was measured from.
      final same = formatDistance(gap.abs(), unit) == formatDistance(0, unit);
      final gapText = same
          ? formatDistance(0, unit)
          : '${gap > 0 ? '+' : '−'}${formatDistance(gap.abs(), unit)}';
      final verdict = same
          ? 'the same as the baseline'
          : gap > 0
              ? 'further than the baseline'
              : 'shorter than the baseline';
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

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headline(),
            const SizedBox(height: 12),
            FlightField(
              event: event,
              flights: [
                FieldFlight(one.flight, one.color),
                if (two != null) FieldFlight(two!.flight, two!.color),
              ],
              unit: unit,
              ghost: ghost,
            ),
          ],
        ),
      ),
    );
  }
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

/// The two senior finals, one tap each, with what the model makes of a
/// typical release in them.
class _EliteCards extends StatelessWidget {
  const _EliteCards({
    required this.event,
    required this.units,
    required this.selected,
    required this.throwFor,
    required this.onTap,
  });

  final ThrowEvent event;
  final _Units units;
  final String? selected;
  final _Throw Function(EliteField) throwFor;
  final ValueChanged<_Throw> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final field in EliteField.values)
                Expanded(
                  child: Builder(builder: (context) {
                    final t = throwFor(field);
                    final on = selected == t.label;
                    final d = flyThrow(event, t.spec, t.release).distance;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: on ? scheme.primary : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: InkWell(
                        key: ValueKey('elite-${field.name}'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => onTap(t),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(field.label,
                                        style: theme.textTheme.titleSmall),
                                  ),
                                  Icon(on ? Icons.check : Icons.add,
                                      size: 18,
                                      color: on
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant),
                                ],
                              ),
                              Text(t.spec.weightLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 6),
                              Text('≈ ${units.mark(d)}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text(
                                units.release(t.release),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'A typical release in a senior final — approximate, drawn from '
            'the biomechanics literature rather than one report. Tap one to '
            'compare it with the baseline.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _BestAngle extends StatelessWidget {
  const _BestAngle({
    required this.best,
    required this.gain,
    required this.angleDeg,
    required this.flies,
    required this.unit,
  });

  final ({double angleDeg, double distance}) best;
  final double gain;
  final double angleDeg;
  final bool flies;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Within a quarter degree, or a couple of centimeters, of the best angle
    // is at it — saying 'best at 37.1°' under a slider sat on 37.0° is
    // noise.
    final atBest = (best.angleDeg - angleDeg).abs() < 0.25 || gain < 0.02;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            atBest
                ? 'At the best angle for this speed and height.'
                : 'Best angle with everything else held: '
                    '${best.angleDeg.toStringAsFixed(1)}°, '
                    // Kept on one line with its unit.
                    '+${formatDistance(gain, unit).replaceAll(' ', ' ')}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            flies
                ? 'The attack angle is held with it. In a real throw the '
                    'two are found together, so treat this as a direction '
                    'rather than a target.'
                : 'A real athlete releases slower as the angle rises, so '
                    'their own best angle sits a few degrees under that one.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
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
/// this one is from it beside the value.
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
    this.hint,
  });

  final String label;
  final String? hint;
  final double value;

  /// The same setting on the other throw, when there is one.
  final double? other;
  final (double, double) span;
  final double step;
  final String Function(double) format;
  final String Function(double) delta;
  final ValueChanged<double> onChanged;

  static const _inset = 18.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = other == null ? 0.0 : value - other!;
    final differs = other != null && diff.abs() >= step / 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              if (differs)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(delta(diff),
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w600)),
                ),
              Text(format(value),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (hint != null)
            Text(hint!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          LayoutBuilder(builder: (context, box) {
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
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: _inset),
                  ),
                  child: Slider(
                    value: value,
                    min: span.$1,
                    max: span.$2,
                    semanticFormatterCallback: format,
                    onChanged: (v) {
                      onChanged((v / step).round() * step);
                    },
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Worth extends StatelessWidget {
  const _Worth({required this.worth, required this.units});

  final ({double perSpeed, double perDegree, double perHeight}) worth;
  final _Units units;

  @override
  Widget build(BuildContext context) {
    String signed(double m) => '${m >= 0 ? '+' : '−'}${units.mark(m.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _WorthTile(
              lever: units.speedLeverLabel, gain: signed(worth.perSpeed)),
          _WorthTile(lever: '+1°', gain: signed(worth.perDegree)),
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

class _References extends StatelessWidget {
  const _References({
    required this.event,
    required this.selected,
    required this.units,
    required this.onTry,
  });

  final ThrowEvent event;
  final String? selected;
  final _Units units;
  final ValueChanged<EliteRelease> onTry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rows = [
      for (final r in eliteReleases)
        if (r.event == event) r
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in rows)
              ListTile(
                title: Text(r.athlete),
                subtitle: Text(
                  '${units.mark(r.mark)} · '
                  '${event.specFor(r.weightKg).weightLabel} · ${r.meet}\n'
                  '${units.speed(r.speed)}'
                  '${r.angleDeg == null ? '' : ' · ${r.angleDeg!.toStringAsFixed(1)}°'}'
                  '${r.height == null ? '' : ' · ${units.height(r.height!)}'}'
                  '${r.complete ? '' : ' · speed only published'}',
                ),
                isThreeLine: true,
                trailing: selected == r.athlete
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : TextButton(
                        onPressed: () => onTry(r),
                        child: const Text('Try'),
                      ),
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                    'No individual releases for this event in the app yet — '
                    'the typical finals above are the reference for now.',
                    style: muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  const _Caveat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'The implement is flown as a point through still, sea-level air. '
        'Drag acts on every implement and lift on the discus and the '
        'javelin, with coefficients shaped like the wind-tunnel curves in '
        'the papers below and then tuned so typical elite releases land '
        'near where finals are won — not values measured for this app. The '
        'discus comes out several meters short at elite speeds, and the '
        "hammer's wire is not counted. Distance runs from the hand, so the "
        'few tenths a thrower reaches past the stop board are not in it. A '
        'measured release is only as good as the video: side-on, square to '
        'the throw. The typical elite finals are approximate ranges drawn '
        "from the literature, the women's from the thinner half of it.",
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Numbers are based on ideal, simplified flight mechanics and '
              'should be used as a guide, not a reference.',
              style: theme.textTheme.bodyMedium
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
          usedFor: 'Release speeds under Measured at finals, and the angle '
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
