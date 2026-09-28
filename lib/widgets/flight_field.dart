import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/flight_model.dart';
import 'distance_field.dart';
import 'throw_card.dart';

/// One flight on the field, in the ink it is drawn in.
class FieldFlight {
  const FieldFlight(this.flight, this.color);
  final Flight flight;
  final Color color;
}

/// A throw seen side-on across the field it lands in: the circle and its
/// stop board (or the runway and its foul line) at the left, the grass
/// running out from it with a marker every round number of meters — or
/// feet, whichever the coach measures in — and the flight arcing over it
/// to a divot.
///
/// Drawn to one scale in both directions, because a flat throw that looks
/// steep is a picture of a different throw. With two flights the second is
/// drawn over the first and the ground between their landings is lit, so
/// the difference is the thing the eye goes to.
class FlightField extends StatelessWidget {
  const FlightField({
    super.key,
    required this.event,
    required this.flights,
    this.ghost,
  });

  final ThrowEvent event;

  /// One or two. The last is drawn on top.
  final List<FieldFlight> flights;

  /// Faint and dashed behind the rest — the same release at its best angle.
  final Flight? ghost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = DistanceField.preferred;
    return LayoutBuilder(builder: (context, box) {
      final all = [...flights.map((f) => f.flight), if (ghost != null) ghost!];
      final layout = _FieldLayout.of(all, box.maxWidth, unit, event);
      return SizedBox(
        height: layout.height,
        child: CustomPaint(
          size: Size(box.maxWidth, layout.height),
          painter: _FieldPainter(
            layout: layout,
            event: event,
            flights: flights,
            ghost: ghost,
            unit: unit,
            grass: theme.colorScheme.primary,
            line: theme.colorScheme.outlineVariant,
            faint: theme.colorScheme.onSurfaceVariant,
            ink: theme.colorScheme.onSurface,
            // What the card the field sits on is painted in, so a label can
            // be lifted off the lines behind it without a box of another
            // color around it.
            backdrop:
                theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
            text: theme.textTheme.labelSmall ?? const TextStyle(),
          ),
        ),
      );
    });
  }
}

const _groundBand = 22.0;
const _sky = 30.0;

/// Where everything goes, worked out once from the flights and the width.
class _FieldLayout {
  _FieldLayout({
    required this.origin,
    required this.scale,
    required this.height,
    required this.step,
  });

  /// The front of the circle, or the foul line, in pixels from the left.
  final double origin;

  /// Pixels per meter, both ways.
  final double scale;
  final double height;

  /// Meters between markers.
  final double step;

  double get ground => height - _groundBand;

  Offset at(Offset meters) =>
      Offset(origin + meters.dx * scale, ground - meters.dy * scale);

  static _FieldLayout of(
      List<Flight> flights, double width, DistanceUnit unit, ThrowEvent event) {
    final far = flights.fold(1.0, (m, f) => math.max(m, f.distance));
    final high = flights.fold(0.5, (m, f) => math.max(m, f.apex));
    // Room at the left for the circle, or a stretch of runway, drawn to the
    // same scale as the rest; room at the right so the far divot and its
    // label are not on the edge.
    final behind = event == ThrowEvent.javelin ? 4.0 : _circleDiameter(event);
    final span = far * 1.08 + behind;
    final scale0 = width / span;
    final scale = math.min(scale0, 150 / high);
    final height =
        (high * scale + _sky + _groundBand).clamp(110.0, 200.0).toDouble();
    return _FieldLayout(
      origin: behind * scale,
      scale: scale,
      height: height,
      step: _markerStep(far, unit),
    );
  }
}

double _circleDiameter(ThrowEvent event) =>
    event == ThrowEvent.discus ? 2.5 : 2.135;

/// The shortest round interval that puts no more than seven markers out to
/// [far], in the unit the coach reads — a marker every 10 ft is not a
/// marker every 3.048 m with a decimal on it.
double _markerStep(double far, DistanceUnit unit) {
  final perUnit = unit == DistanceUnit.feet ? metersPerFoot : 1.0;
  const steps = [1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0];
  for (final s in steps) {
    if (far / (s * perUnit) <= 7) return s * perUnit;
  }
  return steps.last * perUnit;
}

class _FieldPainter extends CustomPainter {
  _FieldPainter({
    required this.layout,
    required this.event,
    required this.flights,
    required this.ghost,
    required this.unit,
    required this.grass,
    required this.line,
    required this.faint,
    required this.ink,
    required this.backdrop,
    required this.text,
  });

  final _FieldLayout layout;
  final ThrowEvent event;
  final List<FieldFlight> flights;
  final Flight? ghost;
  final DistanceUnit unit;
  final Color grass;
  final Color line;
  final Color faint;
  final Color ink;
  final Color backdrop;
  final TextStyle text;

  TextPainter _label(String s, Color color, {FontWeight? weight}) =>
      TextPainter(
        text: TextSpan(
            text: s, style: text.copyWith(color: color, fontWeight: weight)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final ground = layout.ground;
    final width = size.width;

    // The grass, from the front of the circle out. Behind it is the
    // circle's concrete or the runway, which are not grass.
    canvas.drawRect(
      Rect.fromLTRB(layout.origin, ground, width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            grass.withValues(alpha: 0.16),
            grass.withValues(alpha: 0.04)
          ],
        ).createShader(Rect.fromLTRB(0, ground, width, size.height)),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, ground, layout.origin, ground + 3),
      Paint()..color = line,
    );
    canvas.drawLine(
        Offset(layout.origin, ground),
        Offset(width, ground),
        Paint()
          ..color = line
          ..strokeWidth = 1);

    _markers(canvas, size);
    _thrower(canvas);

    if (ghost != null) {
      _dashed(canvas, _path(ghost!), faint.withValues(alpha: 0.5));
    }
    if (flights.length == 2) _gap(canvas, size);
    for (final f in flights) {
      canvas.drawPath(
          _path(f.flight),
          Paint()
            ..color = f.color
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 2.5);
      canvas.drawCircle(
          layout.at(f.flight.path.first), 3, Paint()..color = f.color);
      _divot(canvas, layout.at(Offset(f.flight.distance, 0)), f.color);
    }
    _landingLabels(canvas, size);
  }

  /// A marker on the grass every round number of meters (or feet), and a
  /// faint line up from it so a landing can be read off against it.
  void _markers(Canvas canvas, Size size) {
    final perUnit = unit == DistanceUnit.feet ? metersPerFoot : 1.0;
    final tick = Paint()
      ..color = faint.withValues(alpha: 0.8)
      ..strokeWidth = 1.2;
    final guide = Paint()
      ..color = faint.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final ground = layout.ground;
    final marks = <double>[];
    for (var m = layout.step;; m += layout.step) {
      final x = layout.at(Offset(m, 0)).dx;
      if (x > size.width - 6) break;
      marks.add(m);
    }
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      final x = layout.at(Offset(m, 0)).dx;
      canvas.drawLine(Offset(x, 6), Offset(x, ground), guide);
      canvas.drawLine(Offset(x, ground - 3), Offset(x, ground + 4), tick);
      final value = (m / perUnit).round();
      final last = i == marks.length - 1;
      final label = _label(
          last ? '$value${unit == DistanceUnit.feet ? ' ft' : ' m'}' : '$value',
          faint);
      var left = x - label.width / 2;
      if (left + label.width > size.width) left = size.width - label.width;
      label.paint(canvas, Offset(left, ground + 6));
    }
  }

  /// The stop board on the front of the circle, or the foul line at the
  /// end of the runway.
  void _thrower(Canvas canvas) {
    final ground = layout.ground;
    final x = layout.origin;
    if (event == ThrowEvent.javelin) {
      canvas.drawRect(Rect.fromLTWH(x - 1.5, ground - 1, 3, 5),
          Paint()..color = ink.withValues(alpha: 0.85));
      return;
    }
    final board = math.max(3.0, 0.114 * layout.scale);
    canvas.drawRect(
      Rect.fromLTWH(x - board, ground - math.max(4.0, 0.1 * layout.scale),
          board, math.max(4.0, 0.1 * layout.scale)),
      Paint()..color = ink.withValues(alpha: 0.85),
    );
  }

  Path _path(Flight f) {
    final first = layout.at(f.path.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in f.path.skip(1)) {
      final o = layout.at(p);
      path.lineTo(o.dx, o.dy);
    }
    return path;
  }

  void _dashed(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  void _divot(Canvas canvas, Offset at, Color color) {
    canvas
      ..drawCircle(
          at,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color.withValues(alpha: 0.55))
      ..drawCircle(at, 3.2, Paint()..color = color);
  }

  /// The ground between the two landings, lit in the second throw's ink —
  /// what the change is worth, laid out on the field it was worth it on.
  void _gap(Canvas canvas, Size size) {
    final a = flights[0].flight.distance;
    final b = flights[1].flight.distance;
    final xa = layout.at(Offset(a, 0)).dx;
    final xb = layout.at(Offset(b, 0)).dx;
    if ((xa - xb).abs() < 1) return;
    final ground = layout.ground;
    canvas.drawRect(
      Rect.fromLTRB(
          math.min(xa, xb), ground - 2.5, math.max(xa, xb), ground + 2.5),
      Paint()..color = flights[1].color.withValues(alpha: 0.45),
    );
  }

  /// How far each went, beside its divot. To the right of it, because the
  /// flight comes down into the divot from the left and a label centered
  /// over it sat on its own arc; pushed back left only where the field runs
  /// out, and on a patch of the card's own color either way. When the two
  /// would touch, the second goes above the first rather than on it.
  void _landingLabels(Canvas canvas, Size size) {
    final ground = layout.ground;
    Rect? previous;
    for (final f in flights) {
      final label = _label(formatDistance(f.flight.distance, unit), f.color,
          weight: FontWeight.w700);
      final x = layout.at(Offset(f.flight.distance, 0)).dx;
      final left = (x + 5)
          .clamp(0.0, math.max(0.0, size.width - label.width - 2))
          .toDouble();
      var rect = Rect.fromLTWH(
          left, ground - 10 - label.height, label.width, label.height);
      if (previous != null && rect.inflate(3).overlaps(previous)) {
        rect = rect.shift(Offset(0, previous.top - 3 - rect.bottom));
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(3)),
          Paint()..color = backdrop.withValues(alpha: 0.85));
      label.paint(canvas, rect.topLeft);
      previous = rect;
    }
  }

  // Everything it draws is worked out from values rebuilt on every slider
  // move; comparing them all costs about what painting them does.
  @override
  bool shouldRepaint(_FieldPainter old) => true;
}
