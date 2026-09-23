import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/throw_event.dart';

/// What a part of a drawn implement is made of, which is what it is
/// colored by: the glyph's own color for the painted body, and the real
/// thing's own color for its steel and its cord.
enum GlyphMaterial { paint, steel, cord }

/// One piece of a drawn implement: outlines in the unit square, filled
/// even-odd so a ring is an outline with its hole as a second one.
///
/// Steel is kept off the painted parts by a hairline of nothing rather than
/// laid against them, because the glyph is also drawn all in white (a throw
/// card's placeholder), and there the gap is the only thing that says where
/// the head ends or the rim begins. Cord needs no gap: it is dark whatever
/// the glyph is drawn in.
class GlyphPart {
  const GlyphPart(this.outlines, {this.material = GlyphMaterial.paint});

  final List<List<Offset>> outlines;
  final GlyphMaterial material;
}

/// The color [material] is drawn in on a glyph drawn in [tint]. Steel is
/// white and cord is a near-black gray — light enough to stand off the dark
/// theme it is drawn on, since black cord on a black page is a gap in the
/// shaft — and both are as opaque as the tint, so a glyph dimmed for a
/// disabled row dims all of it.
Color glyphColor(GlyphMaterial material, Color tint) => switch (material) {
      GlyphMaterial.paint => tint,
      GlyphMaterial.steel => Colors.white.withValues(alpha: tint.a),
      GlyphMaterial.cord => glyphCord.withValues(alpha: tint.a),
    };

/// The cord a javelin's grip is bound in.
const glyphCord = Color(0xFF4A4E55);

/// The javelin, tail bottom-left and point top-right: the shaft, the cord
/// grip bound over it, and the metal head.
///
/// Drawn to a real one's proportions rather than as a needle with a bump:
/// a shaft of nearly one width, a grip barely proud of it — cord bound on,
/// not a handle — sitting just behind the middle over the balance point, a
/// tail drawn out to a fine point, and a long metal head, a fifth of the
/// whole, tapering gently and then sharply at the very end. Everything is
/// thicker than a real one's by a long way, since a real one at 16 px is no
/// pixels wide, but the widths keep their ratios to each other.
///
/// The page a competition is shared on draws the same parts, handed to it
/// as SVG by `spectatorPage`, so the two cannot be two javelins.
List<GlyphPart> javelinParts() {
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
    (0.55, 1.0),
    (0.79, 0.95),
  ];
  // Bound over the shaft, with the rounded ends of wrapped cord.
  const grip = [
    (0.405, 1.0),
    (0.409, 1.24),
    (0.415, 1.32),
    (0.472, 1.32),
    (0.478, 1.24),
    (0.482, 1.0),
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
    GlyphPart([outline(shaft)]),
    GlyphPart([outline(grip)], material: GlyphMaterial.cord),
    GlyphPart([outline(head)], material: GlyphMaterial.steel),
  ];
}

/// The discus face on, as it lies in the hand: a steel rim, the body
/// inside it, and the steel plate at the middle.
///
/// To a real one's proportions where they survive the size: the plate a
/// quarter of the width across, and the rim's face about a tenth of the
/// radius. Face on rather than tilted in flight, because a tilted disc is
/// a squashed oval beside a round shot and a round hammer — flat, it is
/// the same size as its neighbors and the only one with a rim.
List<GlyphPart> discusParts() {
  const center = Offset(0.5, 0.5);
  const radius = 0.36;
  const gap = 0.02; // between the steel and the body
  const steps = 64;

  List<Offset> circle(double r) => [
        for (var i = 0; i < steps; i++)
          center +
              Offset(math.cos(2 * math.pi * i / steps),
                      math.sin(2 * math.pi * i / steps)) *
                  r,
      ];

  const rimInner = radius * 0.89;
  const plate = radius * 0.25;
  return [
    GlyphPart([circle(radius), circle(rimInner)],
        material: GlyphMaterial.steel),
    GlyphPart([circle(rimInner - gap), circle(plate + gap)]),
    GlyphPart([circle(plate)], material: GlyphMaterial.steel),
  ];
}

/// Hand-drawn implement glyphs so each event reads as its real implement —
/// a solid shot, a discus with its rim, a pointed javelin, a hammer on its wire —
/// instead of a stand-in Material icon. It takes the ambient [IconTheme]
/// color unless [color] is given, and its highlights are punched out
/// (even-odd) so they reveal whatever sits behind the glyph — a faint sheen
/// on any background. The discus and the javelin are the exception, drawn
/// in what a real one is made of where that is not paint ([GlyphMaterial]).
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

  void _discus(Canvas canvas, double s) => _parts(canvas, s, discusParts());

  void _javelin(Canvas canvas, double s) => _parts(canvas, s, javelinParts());

  void _parts(Canvas canvas, double s, List<GlyphPart> parts) {
    for (final part in parts) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final outline in part.outlines) {
        path.addPolygon([for (final o in outline) o * s], true);
      }
      canvas.drawPath(path, _fill..color = glyphColor(part.material, color));
    }
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
