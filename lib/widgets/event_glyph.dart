import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/throw_event.dart';

/// Hand-drawn implement glyphs so each event reads as its real implement —
/// a solid shot, a tilted discus, a pointed javelin, a hammer on its wire —
/// instead of a stand-in Material icon. Monochrome like an icon: it takes
/// the ambient [IconTheme] color unless [color] is given, and its
/// highlights are punched out (even-odd) so they reveal whatever sits
/// behind the glyph — a faint sheen on any background.
class EventGlyph extends StatelessWidget {
  const EventGlyph(this.event, {super.key, this.size = 24, this.color});

  final ThrowEvent event;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EventGlyphPainter(event, resolved)),
    );
  }
}

/// All geometry is expressed as fractions of the glyph's side length so the
/// drawings scale cleanly to any icon size.
class _EventGlyphPainter extends CustomPainter {
  _EventGlyphPainter(this.event, this.color);

  final ThrowEvent event;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    switch (event) {
      case ThrowEvent.shotPut:
        _shotPut(canvas, s);
      case ThrowEvent.discus:
        _discus(canvas, s);
      case ThrowEvent.hammer:
        _hammer(canvas, s);
      case ThrowEvent.javelin:
        _javelin(canvas, s);
    }
  }

  Paint get _fill => Paint()
    ..color = color
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  Paint _stroke(double width) => Paint()
    ..color = color
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Solid metal sphere with a punched specular highlight — a heavy ball,
  /// deliberately rounder and fuller than the flat discus.
  void _shotPut(Canvas canvas, double s) {
    final center = Offset(s * 0.5, s * 0.55);
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addOval(Rect.fromCircle(center: center, radius: s * 0.31));
    path.addOval(Rect.fromCircle(
        center: center + Offset(-s * 0.11, -s * 0.12), radius: s * 0.06));
    canvas.drawPath(path, _fill);
  }

  /// Disc seen face-on: a solid ring with an open centre, the record-like
  /// look of the original discus icon.
  void _discus(Canvas canvas, double s) {
    final center = Offset(s * 0.5, s * 0.5);
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addOval(Rect.fromCircle(center: center, radius: s * 0.33));
    path.addOval(Rect.fromCircle(center: center, radius: s * 0.075));
    canvas.drawPath(path, _fill);
  }

  /// The silhouette of a real javelin rather than a shaft with a triangle on
  /// the end: a hairline tail thickening over the back half, a constant
  /// widest section, the cord grip bulging at the balance point, then a long
  /// metal head drawn out to a needle point.
  void _javelin(Canvas canvas, double s) {
    final tail = Offset(s * 0.12, s * 0.88);
    final tip = Offset(s * 0.88, s * 0.12);
    final length = (tip - tail).distance;
    final u = (tip - tail) / length; // tail -> tip
    final p = Offset(-u.dy, u.dx); // perpendicular

    // Fractions of the length, measured from the tail.
    const shoulder = 0.55; // where the taper up from the tail tops out
    const grip = (0.58, 0.68); // the bound section, at the balance point
    const headJoin = 0.84; // where the metal head meets the shaft
    final wMax = s * 0.028; // half-width of the widest part of the shaft
    final cord = s * 0.020; // extra half-width from the wrapped cord

    double halfWidth(double t) {
      double w;
      if (t >= headJoin) {
        w = wMax * math.pow(1 - (t - headJoin) / (1 - headJoin), 0.8);
      } else if (t >= shoulder) {
        w = wMax;
      } else {
        w = wMax * math.pow(t / shoulder, 1.35);
      }
      if (t >= grip.$1 && t <= grip.$2) {
        // Rounded shoulders so the binding reads as a wrap, not a box.
        w += cord * math.min(1.0, math.min(t - grip.$1, grip.$2 - t) / 0.025);
      }
      return w;
    }

    const steps = 48;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final centre = tail + u * (length * t);
      final w = halfWidth(t);
      left.add(centre + p * w);
      right.add(centre - p * w);
    }
    canvas.drawPath(
        Path()..addPolygon([...left, ...right.reversed], true), _fill);
  }

  /// Ball on a wire ending in a grip handle — the hammer's three parts.
  void _hammer(Canvas canvas, double s) {
    final head = Offset(s * 0.30, s * 0.70);
    canvas.drawCircle(head, s * 0.17, _fill);
    final start = Offset(s * 0.41, s * 0.59);
    final handle = Offset(s * 0.74, s * 0.30);
    canvas.drawLine(start, handle, _stroke(s * 0.05));
    // Grip: a short bar across the wire's end.
    final u = (handle - start) / (handle - start).distance;
    final p = Offset(-u.dy, u.dx);
    canvas.drawLine(
        handle + p * (s * 0.10), handle - p * (s * 0.10), _stroke(s * 0.05));
  }

  @override
  bool shouldRepaint(_EventGlyphPainter old) =>
      old.event != event || old.color != color;
}
