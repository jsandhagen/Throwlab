import 'package:flutter/material.dart';

import '../models/throw_event.dart';

/// The javelin in the unit square, tail bottom-left and point top-right, as
/// two closed outlines: the shaft with its cord grip, and the metal head.
///
/// Drawn to a real one's proportions rather than as a needle with a bump:
/// a shaft of nearly one width, a grip barely proud of it — cord bound on,
/// not a handle — sitting just behind the middle over the balance point, a
/// tail drawn out to a fine point, and a long metal head, a fifth of the
/// whole, tapering gently and then sharply at the very end. The hairline
/// left between head and shaft is the seam where the metal is fitted, which
/// a monochrome glyph can only say as a gap. Everything is thicker than a
/// real one's by a long way, since a real one at 16 px is no pixels wide,
/// but the widths keep their ratios to each other.
///
/// The page a competition is shared on draws the same outlines, handed to
/// it as SVG by `spectatorPage`, so the two cannot be two javelins.
List<List<Offset>> javelinOutline() {
  const tail = Offset(0.08, 0.92);
  const tip = Offset(0.92, 0.08);
  final length = (tip - tail).distance;
  final u = (tip - tail) / length; // tail -> tip
  final p = Offset(-u.dy, u.dx); // perpendicular
  const w = 0.019; // half-width of the shaft at its widest

  // (fraction of the length from the tail, half-width as a share of [w]).
  const shaft = [
    (0.0, 0.0),
    (0.06, 0.25),
    (0.15, 0.50),
    (0.28, 0.76),
    (0.40, 0.97),
    // The grip, with the rounded ends of bound cord.
    (0.405, 1.0), (0.409, 1.24), (0.415, 1.32),
    (0.472, 1.32), (0.478, 1.24), (0.482, 1.0),
    (0.55, 1.0),
    (0.79, 0.95),
  ];
  const head = [
    (0.797, 0.95),
    (0.975, 0.45),
    (1.0, 0.0),
  ];

  List<Offset> outline(List<(double, double)> profile) {
    Offset at(double t, double half) =>
        tail + u * (length * t) + p * (w * half);
    return [
      for (final (t, half) in profile) at(t, half),
      for (final (t, half) in profile.reversed) at(t, -half),
    ];
  }

  return [
    outline(shaft),
    outline(head),
  ];
}

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

  /// Disc seen face-on: a solid ring with an open center, the record-like
  /// look of the original discus icon.
  void _discus(Canvas canvas, double s) {
    final center = Offset(s * 0.5, s * 0.5);
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addOval(Rect.fromCircle(center: center, radius: s * 0.33));
    path.addOval(Rect.fromCircle(center: center, radius: s * 0.075));
    canvas.drawPath(path, _fill);
  }

  /// The javelin's outline, laid down the diagonal — see [javelinOutline].
  void _javelin(Canvas canvas, double s) {
    final path = Path();
    for (final part in javelinOutline()) {
      path.addPolygon([for (final o in part) o * s], true);
    }
    canvas.drawPath(path, _fill);
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

/// The mark for the events as a set: an implement climbing away from the
/// circle. No single implement can stand for all four, and the nearest
/// Material icon is a chequered flag — a finish line, which belongs to a
/// race and not to a throw.
class ThrowsGlyph extends StatelessWidget {
  const ThrowsGlyph({super.key, this.size = 24, this.color});

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
      child: CustomPaint(painter: _ThrowsGlyphPainter(resolved)),
    );
  }
}

class _ThrowsGlyphPainter extends CustomPainter {
  _ThrowsGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final implement = Offset(s * 0.73, s * 0.26);
    final radius = s * 0.21;
    final trail = s * 0.105;

    // The line the implement is travelling along as it leaves the trail,
    // 30° above horizontal. Both the end of the curve and its control point
    // sit on this line through the center of the ball, so the curve's last
    // tangent aims at that center instead of passing under it — eyeballed
    // endpoints read as a flight the implement isn't on.
    const approach = Offset(0.866, -0.5);

    // Clear of the ball by the trail's own rounded cap plus a hairline, so
    // the two read as one flight rather than merging at icon sizes.
    final end = implement - approach * (radius + trail / 2 + s * 0.05);
    final control = end - approach * (s * 0.30);

    canvas.drawPath(
      Path()
        ..moveTo(s * 0.08, s * 0.90)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = trail
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      implement,
      radius,
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ThrowsGlyphPainter old) => old.color != color;
}
