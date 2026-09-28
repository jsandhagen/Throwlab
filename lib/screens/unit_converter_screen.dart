import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../widgets/angular.dart';
import '../widgets/distance_field.dart';
import '../widgets/event_glyph.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_picker.dart' show eventColor;
import '../widgets/throw_card.dart';

/// The three conversions a throws coach does in their head at a meet and
/// gets wrong: a mark between meters and feet, an implement between
/// kilograms and pounds, and a speed between m/s and what a radar gun reads.
///
/// A mark is typed in the app's own [DistanceField] — the same boxes a mark
/// is entered in everywhere else, feet and inches as two — so a conversion
/// here reads exactly as the mark would on a card, including the rule it is
/// recorded under: down to the quarter inch.
class UnitConverterScreen extends StatefulWidget {
  const UnitConverterScreen({super.key});

  @override
  State<UnitConverterScreen> createState() => _UnitConverterScreenState();
}

enum _Tab { distance, weight, speed }

const _lb = 0.45359237;
const _mph = 0.44704;
const _kmh = 1 / 3.6;

class _UnitConverterScreenState extends State<UnitConverterScreen> {
  var _tab = _Tab.distance;

  // Each tab keeps what was typed in it, so flipping across to check a
  // weight and back does not lose the mark.
  double? _meters;
  DistanceUnit _distanceUnit = DistanceField.preferred;
  final _weight = _Quantity(
    units: const [
      _Unit('kg', 'kg', 1, digits: 2),
      _Unit('lb', 'lb', _lb, digits: 2),
    ],
    label: 'Weight',
  );
  final _speed = _Quantity(
    units: const [
      _Unit('m/s', 'm/s', 1, digits: 2),
      _Unit('mph', 'mph', _mph, digits: 1),
      _Unit('km/h', 'km/h', _kmh, digits: 1),
    ],
    label: 'Speed',
  );

  @override
  void dispose() {
    _weight.dispose();
    _speed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Unit converter')),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter:
                    SectorBackdropPainter(color: theme.colorScheme.primary),
              ),
            ),
          ),
          Column(
            children: [
              HeaderBand(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: AngularSegmentedBar<_Tab>(
                    value: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                    segments: const [
                      AngularSegment(
                          value: _Tab.distance,
                          icon: Icons.straighten,
                          label: 'Distance'),
                      AngularSegment(
                          value: _Tab.weight,
                          icon: Icons.scale_outlined,
                          label: 'Weight'),
                      AngularSegment(
                          value: _Tab.speed, icon: Icons.speed, label: 'Speed'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: switch (_tab) {
                    _Tab.distance => _distance(context),
                    _Tab.weight => _weightTab(context),
                    _Tab.speed => _speedTab(context),
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _distance(BuildContext context) {
    final meters = _meters;
    return ListView(
      key: const PageStorageKey('distance'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _Heading('A mark'),
        _Panel(
          child: DistanceField(
            meters: meters,
            unit: _distanceUnit,
            remember: false,
            onChanged: (m, unit) => setState(() {
              _meters = m;
              _distanceUnit = unit;
            }),
          ),
        ),
        const _Heading('Written out'),
        _Panel(
          child: Column(
            children: [
              _Row('Meters', meters == null ? '—' : formatDistance(meters)),
              _Row(
                  'Feet and inches',
                  meters == null
                      ? '—'
                      : formatDistance(meters, DistanceUnit.feet)),
              _Row(
                  'Inches',
                  meters == null
                      ? '—'
                      : '${(meters / 0.0254).toStringAsFixed(2)} in'),
              _Row(
                  'Centimeters',
                  meters == null
                      ? '—'
                      : '${(meters * 100).toStringAsFixed(1)} cm'),
            ],
          ),
        ),
        const _Note(
            'Feet and inches are rounded down to the quarter inch, the way '
            'a mark is recorded, so a conversion and back can come out a '
            'centimeter short. Meters are to the centimeter.'),
      ],
    );
  }

  Widget _weightTab(BuildContext context) {
    final kg = _weight.base;
    // An implement the weight typed is, within a few grams — '16' in pounds
    // is the men's shot, and saying so answers the question the weight was
    // typed to ask.
    final matches = [
      if (kg != null)
        for (final event in ThrowEvent.values)
          for (final spec in event.implements)
            if ((spec.weightKg - kg).abs() < 0.02) (event, spec),
    ];
    return ListView(
      key: const PageStorageKey('weight'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _Heading('An implement'),
        _Panel(child: _QuantityField(quantity: _weight, onChanged: _changed)),
        if (matches.isNotEmpty) ...[
          const _Heading('That is'),
          _Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (event, spec) in matches)
                  _ImplementTile(event: event, spec: spec),
              ],
            ),
          ),
        ],
        const _Heading('Every implement'),
        _Panel(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              for (final event in ThrowEvent.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Row(
                    children: [
                      EventGlyph(event, size: 16, color: eventColor(event)),
                      const SizedBox(width: 8),
                      Text(event.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                for (final spec in event.implements)
                  _Row(spec.weightLabel, _bothWeights(spec.weightKg),
                      aside: spec.usedBy),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _speedTab(BuildContext context) {
    return ListView(
      key: const PageStorageKey('speed'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _Heading('A release speed'),
        _Panel(child: _QuantityField(quantity: _speed, onChanged: _changed)),
        const _Note('A radar gun reads miles an hour; the biomechanics '
            'reports and the what-if calculator give meters a second.'),
      ],
    );
  }

  void _changed() => setState(() {});
}

/// '7.26 kg · 16.01 lb' — both, since the table is read by people who
/// think in either.
String _bothWeights(double kg) {
  final grams = kg < 1;
  final metric =
      grams ? '${(kg * 1000).round()} g' : '${_trim(kg.toStringAsFixed(2))} kg';
  return '$metric · ${(kg / _lb).toStringAsFixed(2)} lb';
}

String _trim(String s) => s.contains('.')
    ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
    : s;

class _Unit {
  const _Unit(this.name, this.suffix, this.toBase, {required this.digits});
  final String name;
  final String suffix;

  /// How many of the base unit one of this is.
  final double toBase;
  final int digits;
}

/// A number typed in one of several units, and the base-unit value it is.
class _Quantity {
  _Quantity({required this.units, required this.label});

  final List<_Unit> units;
  final String label;
  final controller = TextEditingController();
  late _Unit unit = units.first;

  double? get base {
    final v = parseDistanceValue(controller.text);
    return v == null ? null : v * unit.toBase;
  }

  /// Switching unit converts what is typed rather than reinterpreting it:
  /// 7.26 typed in kilograms becomes 16.01 in pounds, not 7.26 lb.
  void switchTo(_Unit next) {
    final value = base;
    unit = next;
    if (value != null) {
      controller.text =
          _trim((value / next.toBase).toStringAsFixed(next.digits));
    }
  }

  void dispose() => controller.dispose();
}

/// The same shape as [DistanceField]: the box, the other units underneath
/// at the size of the number typed, and the switch beside them.
class _QuantityField extends StatelessWidget {
  const _QuantityField({required this.quantity, required this.onChanged});

  final _Quantity quantity;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = quantity.base;
    final others = [
      for (final u in quantity.units)
        if (u != quantity.unit) u
    ];
    final readouts = [
      for (final u in others)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('In ${u.name}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              // One line whatever the width: a number that wraps its unit
              // onto the next line reads as two numbers.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  base == null
                      ? '—'
                      : '${(base / u.toBase).toStringAsFixed(u.digits)} '
                          '${u.suffix}',
                  key: ValueKey('${quantity.label}-${u.name}'),
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: base == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
    ];
    final picker = SegmentedButton<_Unit>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final u in quantity.units)
          ButtonSegment(value: u, label: Text(u.name)),
      ],
      selected: {quantity.unit},
      onSelectionChanged: (s) {
        quantity.switchTo(s.single);
        onChanged();
      },
    );
    // Two units lay out as a mark does, the switch beside the readout. A
    // third would squeeze both readouts into wrapping, so the switch goes
    // on a line of its own under the box it governs.
    final inline = quantity.units.length <= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: ValueKey('${quantity.label}-input'),
          controller: quantity.controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: quantity.label,
            suffixText: quantity.unit.suffix,
          ),
        ),
        const SizedBox(height: 12),
        if (!inline) ...[
          Align(alignment: Alignment.centerRight, child: picker),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [...readouts, if (inline) picker],
        ),
      ],
    );
  }
}

class _ImplementTile extends StatelessWidget {
  const _ImplementTile({required this.event, required this.spec});

  final ThrowEvent event;
  final ImplementSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: EventGlyph(event, size: 26, color: eventColor(event)),
      title: Text('${event.label} · ${spec.weightLabel}',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${spec.usedBy}\n${spec.referenceLabel} '
          '${_size(spec.minSize)}–${_size(spec.maxSize)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      isThreeLine: true,
    );
  }

  /// A diameter in millimeters, a javelin's length in meters.
  static String _size(double m) =>
      m < 1 ? '${(m * 1000).round()} mm' : '${m.toStringAsFixed(1)} m';
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
        color: cardOverSector(Theme.of(context).colorScheme),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(padding: padding, child: child),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.aside});

  final String label;
  final String value;
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // Both halves loose, so each gets what it needs and neither more than
      // half: the value sits hard against the right edge, and a long label
      // wraps rather than pushing it off the card.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                if (aside != null) Text(aside!, style: muted),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// The athlete profile's section heading, so the two screens are headed
/// alike.
class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
