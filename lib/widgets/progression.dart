import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One measured throw on the season's line.
class ProgressionPoint {
  const ProgressionPoint({
    required this.on,
    required this.meters,
    this.atMeet = false,
  });

  final DateTime on;

  /// Always meters — the line is a shape, and drawing it in the unit each
  /// mark happened to be entered in would kink it wherever a meet measured
  /// in feet.
  final double meters;

  /// Whether the throw was taken at a meet. Drawn solid where it was and
  /// hollow where it wasn't: an athlete whose training marks run past their
  /// competition marks is the thing a season chart is for.
  final bool atMeet;
}

/// An athlete's season at one event and implement, as a line.
///
/// Plotted against the calendar rather than against throw number, so a
/// month with nothing in it reads as a month with nothing in it. Small on
/// purpose: this sits inside a card on a profile and answers one question —
/// is it going the right way — rather than standing in for a results table.
class ProgressionChart extends StatelessWidget {
  const ProgressionChart({
    super.key,
    required this.points,
    required this.color,
    this.height = 92,
  });

  /// Oldest first. Fewer than two and there is no line to draw, only a mark
  /// to place.
  final List<ProgressionPoint> points;

  /// The event's color, so the line belongs to the same event as everything
  /// else on the card.
  final Color color;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ProgressionPainter(
          points: points,
          color: color,
          axis: scheme.outlineVariant,
          label: scheme.onSurfaceVariant,
          surface: scheme.surface,
          // Taken off the theme rather than built here: the app names its
          // type once, and a bare TextStyle would paint the two value
          // labels in whatever the platform's default happens to be.
          text: theme.textTheme.labelSmall ?? const TextStyle(),
        ),
      ),
    );
  }
}

class _ProgressionPainter extends CustomPainter {
  const _ProgressionPainter({
    required this.points,
    required this.color,
    required this.axis,
    required this.label,
    required this.surface,
    required this.text,
  });

  final List<ProgressionPoint> points;
  final Color color;
  final Color axis;
  final Color label;

  /// What a hollow dot is filled with, so the line does not show through a
  /// throw that wasn't at a meet.
  final Color surface;

  /// The style the two value labels are set in.
  final TextStyle text;

  /// Room at the right for the two value labels.
  static const _gutter = 46.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final plot = Rect.fromLTWH(
        4, 10, math.max(size.width - _gutter - 4, 8), size.height - 24);

    var lowest = points.first.meters;
    var highest = points.first.meters;
    for (final point in points) {
      lowest = math.min(lowest, point.meters);
      highest = math.max(highest, point.meters);
    }
    // A season inside a handful of centimeters would otherwise be drawn as
    // a mountain range. Hold the scale open to at least a meter so the line
    // says how much it moved, not just which way.
    final span = math.max(highest - lowest, 1.0);
    final middle = (highest + lowest) / 2;
    final top = middle + span / 2;
    final bottom = middle - span / 2;

    final first = points.first.on.millisecondsSinceEpoch.toDouble();
    final last = points.last.on.millisecondsSinceEpoch.toDouble();
    final days = last - first;

    Offset at(int index) {
      final point = points[index];
      // Everything on one day — or a single throw — is spread evenly
      // instead, since the calendar has nothing to say about the order.
      final x = days <= 0
          ? (points.length == 1
              ? plot.center.dx
              : plot.left + plot.width * index / (points.length - 1))
          : plot.left +
              plot.width * (point.on.millisecondsSinceEpoch - first) / days;
      final y = plot.bottom -
          plot.height * ((point.meters - bottom) / (top - bottom));
      return Offset(x, y);
    }

    // The floor of the season, so the line has something to sit on.
    canvas.drawLine(
      Offset(plot.left, plot.bottom + 6),
      Offset(plot.right, plot.bottom + 6),
      Paint()
        ..color = axis.withOpacity(0.5)
        ..strokeWidth = 1,
    );

    final spots = [for (var i = 0; i < points.length; i++) at(i)];

    if (spots.length > 1) {
      final line = Path()..moveTo(spots.first.dx, spots.first.dy);
      for (final spot in spots.skip(1)) {
        line.lineTo(spot.dx, spot.dy);
      }
      // A wash under the line: it gives the shape a body at this size,
      // where a hairline on its own reads as a scratch.
      final under = Path.from(line)
        ..lineTo(spots.last.dx, plot.bottom + 6)
        ..lineTo(spots.first.dx, plot.bottom + 6)
        ..close();
      canvas.drawPath(
        under,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, plot.top),
            Offset(0, plot.bottom + 6),
            [color.withOpacity(0.22), color.withOpacity(0.02)],
          ),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < spots.length; i++) {
      final furthest = points[i].meters >= highest;
      canvas.drawCircle(spots[i], furthest ? 4.5 : 3.2,
          Paint()..color = points[i].atMeet ? color : surface);
      if (!points[i].atMeet || furthest) {
        canvas.drawCircle(
          spots[i],
          furthest ? 4.5 : 3.2,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = furthest ? 2 : 1.4,
        );
      }
    }

    _text('${highest.toStringAsFixed(2)} m', Offset(plot.right + 6, plot.top),
        canvas, color);
    if (highest != lowest) {
      _text('${lowest.toStringAsFixed(2)} m',
          Offset(plot.right + 6, plot.bottom - 4), canvas, label);
    }
  }

  void _text(String text, Offset at, Canvas canvas, Color color) {
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: this.text.copyWith(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_ProgressionPainter old) =>
      old.points != points || old.color != color || old.text != text;
}
