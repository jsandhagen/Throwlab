import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/elite_releases.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/flight_model.dart';
import '../widgets/distance_field.dart';
import '../widgets/event_glyph.dart';
import '../widgets/throw_card.dart';

/// The what-if calculator: a release, the distance it throws, and what
/// moving any one part of it is worth.
///
/// It answers a question a coach asks out loud — 'if he found another meter
/// a second, what's that worth?' — with the flight model in
/// `flight_model.dart`, and holds the answer against releases measured at
/// championship finals. The numbers are estimates and the screen says so
/// where they are read, not in a footnote: a what-if is worth having for
/// the size of a change, and the model is much surer of that than of the
/// mark itself.
class ReleaseCalculatorScreen extends StatefulWidget {
  const ReleaseCalculatorScreen({
    super.key,
    this.event = ThrowEvent.shotPut,
    this.implementKg,
    this.measured,
  });

  final ThrowEvent event;
  final double? implementKg;

  /// A release measured off a clip, which the calculator opens on and can
  /// always go back to.
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

double _clamp(double v, (double, double) span) =>
    v.clamp(span.$1, span.$2).toDouble();

Release _typical(ThrowEvent event) {
  final range = eliteRanges[event]!;
  return Release(
    speed: range.typicalSpeed,
    angleDeg: range.typicalAngle,
    height: range.typicalHeight,
    // A discus flies best leading edge a little down on the path; a javelin
    // with its nose on it.
    attackDeg: event == ThrowEvent.discus ? -8 : 0,
  );
}

class _ReleaseCalculatorScreenState extends State<ReleaseCalculatorScreen> {
  late ThrowEvent _event = widget.event;
  late ImplementSpec _spec = widget.implementKg == null
      ? widget.event.defaultImplement
      : widget.event.specFor(widget.implementKg!);
  late Release _release = _fit(widget.measured ?? _typical(widget.event));

  /// Whose release is on the sliders, when it is somebody's.
  late String? _loaded = widget.measured == null ? null : 'measured';

  Release _fit(Release r) {
    final span = _spans[_event]!;
    return Release(
      speed: _clamp(r.speed, span.speed),
      angleDeg: _clamp(r.angleDeg, _angleSpan),
      height: _clamp(r.height, span.height),
      attackDeg: _hasAttack(_event) ? _clamp(r.attackDeg, _attackSpan) : 0,
      wind: _event == ThrowEvent.shotPut ? 0 : _clamp(r.wind, _windSpan),
    );
  }

  void _set(Release r) => setState(() {
        _release = _fit(r);
        _loaded = null;
      });

  void _pickEvent(ThrowEvent event) {
    if (event == _event) return;
    setState(() {
      _event = event;
      _spec = event.defaultImplement;
      _release = _fit(_typical(event).copyWith(wind: _release.wind));
      _loaded = null;
    });
  }

  void _load(EliteRelease r) => setState(() {
        _release = _fit(_release.copyWith(
          speed: r.speed,
          angleDeg: r.angleDeg,
          height: r.height,
        ));
        _loaded = r.athlete;
      });

  void _backToMeasured() => setState(() {
        _release = _fit(widget.measured!);
        _loaded = 'measured';
      });

  @override
  Widget build(BuildContext context) {
    final flight = flyThrow(_event, _spec, _release);
    final best = bestAngle(_event, _spec, _release);
    final worth = sensitivity(_event, _spec, _release);
    final bestFlight =
        flyThrow(_event, _spec, _release.copyWith(angleDeg: best.angleDeg));
    final unit = DistanceField.preferred;
    final measuredOn = widget.measured != null && _event == widget.event;

    return Scaffold(
      appBar: AppBar(title: const Text('What if')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _EventPicker(
                event: _event,
                spec: _spec,
                onEvent: _pickEvent,
                onSpec: (spec) => setState(() => _spec = spec),
              ),
            ),
            _ResultCard(
              flight: flight,
              best: best,
              bestFlight: bestFlight,
              angleDeg: _release.angleDeg,
              unit: unit,
              flies: _hasAttack(_event),
              caption: _loaded == 'measured'
                  ? 'Your measured throw'
                  : _loaded != null
                      ? "$_loaded's release"
                      : null,
            ),
            if (measuredOn && _loaded != 'measured')
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
            const _Heading('Release'),
            _Dial(
              label: 'Speed',
              value: _release.speed,
              span: _spans[_event]!.speed,
              step: 0.1,
              format: (v) => '${v.toStringAsFixed(1)} m/s',
              onChanged: (v) => _set(_release.copyWith(speed: v)),
            ),
            _Dial(
              label: 'Angle',
              value: _release.angleDeg,
              span: _angleSpan,
              step: 0.5,
              format: (v) => '${v.toStringAsFixed(1)}°',
              onChanged: (v) => _set(_release.copyWith(angleDeg: v)),
            ),
            _Dial(
              label: 'Height',
              value: _release.height,
              span: _spans[_event]!.height,
              step: 0.01,
              format: (v) => '${v.toStringAsFixed(2)} m',
              onChanged: (v) => _set(_release.copyWith(height: v)),
            ),
            if (_hasAttack(_event))
              _Dial(
                label: 'Attack',
                hint: _event == ThrowEvent.discus
                    ? 'Leading edge above (+) or below (−) the path'
                    : 'Nose above (+) or below (−) the path',
                value: _release.attackDeg,
                span: _attackSpan,
                step: 0.5,
                signed: true,
                format: (v) => '${v >= 0 ? '+' : '−'}'
                    '${v.abs().toStringAsFixed(1)}°',
                onChanged: (v) => _set(_release.copyWith(attackDeg: v)),
              ),
            // A shot is in the air two seconds at a third of a discus's
            // speed; wind moves it centimeters, and a dial that does nothing
            // reads as a broken one.
            if (_event != ThrowEvent.shotPut)
              _Dial(
                label: 'Wind',
                hint: 'Behind the thrower (+) or in their face (−)',
                value: _release.wind,
                span: _windSpan,
                step: 0.5,
                signed: true,
                format: (v) => v == 0
                    ? 'Still'
                    : '${v.abs().toStringAsFixed(1)} m/s '
                        '${v > 0 ? 'tail' : 'head'}',
                onChanged: (v) => _set(_release.copyWith(wind: v)),
              ),
            const _Heading('What each is worth'),
            _Worth(worth: worth, unit: unit),
            _Heading('Measured at finals',
                trailing: '${_event.label} · ${_spec.weightLabel}'),
            _References(
              event: _event,
              spec: _spec,
              loaded: _loaded,
              unit: unit,
              onLoad: _load,
            ),
            const _Caveat(),
          ],
        ),
      ),
    );
  }
}

class _EventPicker extends StatelessWidget {
  const _EventPicker({
    required this.event,
    required this.spec,
    required this.onEvent,
    required this.onSpec,
  });

  final ThrowEvent event;
  final ImplementSpec spec;
  final ValueChanged<ThrowEvent> onEvent;
  final ValueChanged<ImplementSpec> onSpec;

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
        Row(
          children: [
            Expanded(
              child: Text(event.label,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            DropdownButton<ImplementSpec>(
              value: spec,
              underline: const SizedBox(),
              items: [
                for (final s in event.implements)
                  DropdownMenuItem(value: s, child: Text(s.weightLabel)),
              ],
              onChanged: (s) {
                if (s != null) onSpec(s);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.flight,
    required this.best,
    required this.bestFlight,
    required this.angleDeg,
    required this.unit,
    required this.flies,
    this.caption,
  });

  /// A discus or a javelin, whose best angle comes with an attack angle
  /// held rather than with the speed Linthorne measured falling away.
  final bool flies;
  final Flight flight;
  final ({double angleDeg, double distance}) best;
  final Flight bestFlight;
  final double angleDeg;
  final DistanceUnit unit;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gain = best.distance - flight.distance;
    // Within a quarter degree, or a couple of centimeters, of the best angle
    // is at it — saying 'best at 37.1°' under a slider sat on 37.0° is
    // noise.
    final atBest = (best.angleDeg - angleDeg).abs() < 0.25 || gain < 0.02;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (caption != null)
              Text(caption!.toUpperCase(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(letterSpacing: 1.1, color: scheme.primary)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('≈ ',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatDistance(flight.distance, unit),
                      key: const ValueKey('whatIfDistance'),
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '${flight.time.toStringAsFixed(2)} s in the air · '
              'peaks ${flight.apex.toStringAsFixed(1)} m up',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: CustomPaint(
                size: Size.infinite,
                painter: _FlightPainter(
                  flight: flight,
                  ghost: atBest ? null : bestFlight,
                  ink: scheme.primary,
                  ghostInk: scheme.onSurfaceVariant,
                  ground: scheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              atBest
                  ? 'At the best angle for this speed and height.'
                  : 'Best angle with everything else held: '
                      '${best.angleDeg.toStringAsFixed(1)}°, '
                      // Kept on one line with its unit.
                      '+${formatDistance(gain, unit).replaceAll(' ', '\u00A0')}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              flies
                  ? 'The attack angle is held with it. In a real throw the '
                      'two are found together, so treat this as a direction '
                      'rather than a target.'
                  : 'A real athlete releases slower as the angle rises, so '
                      'their own best angle sits a few degrees under that '
                      'one.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The flight side-on, to scale in both directions, with the best angle's
/// flight faint behind it when the two differ.
class _FlightPainter extends CustomPainter {
  _FlightPainter({
    required this.flight,
    required this.ghost,
    required this.ink,
    required this.ghostInk,
    required this.ground,
  });

  final Flight flight;
  final Flight? ghost;
  final Color ink;
  final Color ghostInk;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final far = math.max(flight.distance, ghost?.distance ?? 0);
    final high = math.max(flight.apex, ghost?.apex ?? 0);
    if (far <= 0 || high <= 0) return;
    // One scale for both axes, so a flat throw looks flat.
    final scale = math.min(size.width / far, (size.height - 4) / high);
    Offset at(Offset p) => Offset(p.dx * scale, size.height - p.dy * scale);

    canvas.drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        Paint()
          ..color = ground
          ..strokeWidth = 1);

    Path pathOf(Flight f) {
      final path = Path()..moveTo(at(f.path.first).dx, at(f.path.first).dy);
      for (final p in f.path.skip(1)) {
        final o = at(p);
        path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    if (ghost != null) {
      canvas.drawPath(
          pathOf(ghost!),
          Paint()
            ..color = ghostInk.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    canvas.drawPath(
        pathOf(flight),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.5);
    canvas.drawCircle(at(flight.path.last), 3.5, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_FlightPainter old) =>
      old.flight != flight ||
      old.ghost != ghost ||
      old.ink != ink ||
      old.ground != ground;
}

class _Heading extends StatelessWidget {
  const _Heading(this.label, {this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: style)),
          if (trailing != null)
            Text(trailing!,
                style: style?.copyWith(
                    letterSpacing: 0, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

/// A labelled slider that snaps to [step], so what it reads is what was
/// set.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.span,
    required this.step,
    required this.format,
    required this.onChanged,
    this.hint,
    this.signed = false,
  });

  final String label;
  final String? hint;
  final double value;
  final (double, double) span;
  final double step;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  /// A zero in the middle worth marking: attack and wind.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(format(value),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (hint != null)
            Text(hint!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: value,
              min: span.$1,
              max: span.$2,
              semanticFormatterCallback: format,
              onChanged: (v) {
                var snapped = (v / step).round() * step;
                // A signed dial catches at zero, the one value on it
                // somebody sets on purpose.
                if (signed && snapped.abs() < step * 1.5) snapped = 0;
                onChanged(snapped);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Worth extends StatelessWidget {
  const _Worth({required this.worth, required this.unit});

  final ({double perSpeed, double perDegree, double perHeight}) worth;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    String signed(double m) =>
        '${m >= 0 ? '+' : '−'}${formatDistance(m.abs(), unit)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _WorthTile(lever: '+1 m/s', gain: signed(worth.perSpeed)),
          _WorthTile(lever: '+1°', gain: signed(worth.perDegree)),
          _WorthTile(lever: '+10 cm higher', gain: signed(worth.perHeight)),
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
    required this.spec,
    required this.loaded,
    required this.unit,
    required this.onLoad,
  });

  final ThrowEvent event;
  final ImplementSpec spec;
  final String? loaded;
  final DistanceUnit unit;
  final ValueChanged<EliteRelease> onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rows = eliteReleasesFor(event, spec.weightKg);
    final range = eliteRanges[event]!;
    String span((double, double) r, int digits, String suffix) =>
        '${r.$1.toStringAsFixed(digits)}–${r.$2.toStringAsFixed(digits)}$suffix';

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
                  '${formatDistance(r.mark, unit)} · ${r.meet}\n'
                  '${r.speed.toStringAsFixed(2)} m/s'
                  '${r.angleDeg == null ? '' : ' · ${r.angleDeg!.toStringAsFixed(1)}°'}'
                  '${r.height == null ? '' : ' · ${r.height!.toStringAsFixed(2)} m'}'
                  '${r.complete ? '' : ' · speed only published'}',
                ),
                isThreeLine: true,
                trailing: loaded == r.athlete
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : TextButton(
                        onPressed: () => onLoad(r),
                        child: const Text('Try'),
                      ),
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  spec == event.defaultImplement
                      ? 'No individual releases for this event in the app '
                          'yet — the typical range is below.'
                      : 'The measured releases are all senior implements. '
                          'Switch to the ${event.defaultImplement.weightLabel} '
                          'to see them.',
                  style: muted,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Typical of a senior men\'s final',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${span(range.speed, 1, ' m/s')} · '
                    '${span(range.angleDeg, 0, '°')} · '
                    '${span(range.height, 1, ' m')}, '
                    'throwing ${span(range.marks, 0, ' m')}. Approximate — '
                    'drawn from the biomechanics literature, not one report.',
                    style: muted,
                  ),
                ],
              ),
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
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These are estimates, not predictions of a mark. The model '
              'flies the implement through still, sea-level air with lift '
              'and drag taken from wind-tunnel studies, and treats a discus '
              'and a javelin more simply than they really fly — the discus '
              'comes out several meters short of what elite releases were '
              'measured to throw. Trust how much a change is worth more than '
              'the distance itself. A measured release is only as good as '
              'the video: side-on, square to the throw.',
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}
