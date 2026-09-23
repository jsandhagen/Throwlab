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

/// The hammer: the ball, the wire, and the handle the thrower holds it by.
///
/// The handle is what makes it a hammer rather than a ball on a stick — a
/// closed loop, a rounded triangle both hands go through with the wire
/// fixed at its point, not a bar across the end. It is about as wide as the
/// ball, as on a real one. The wire is steel and a hairline, as it is; the
/// handle is steel with its grip bound in cord across the far side, where
/// the hands are. The wire is a fraction of a real one's length, since a
/// real one is ten balls long and would leave the ball a dot.
List<GlyphPart> hammerParts() {
  const ball = Offset(0.28, 0.72);
  const radius = 0.16;
  const gap = 0.02; // between the steel and the ball
  const u = Offset(math.sqrt1_2, -math.sqrt1_2); // ball -> handle
  const p = Offset(math.sqrt1_2, math.sqrt1_2); // across the wire
  const reach = 0.54; // ball center to the handle's point
  const length = 0.21, width = 0.29; // the handle, along and across
  const frame = 0.032; // the handle's thickness
  const corner = 0.036; // the rounding at each corner, outside
  const wire = 0.013; // half the wire's thickness
  const steps = 64;

  final point = ball + u * reach;
  final handle = [
    point,
    point + u * length + p * (width / 2),
    point + u * length - p * (width / 2),
  ];

  // A convex polygon with its corners rounded to [r], struck around the
  // same centers whatever [r] is, so the inside of the loop is exactly the
  // outside moved in by the frame's thickness.
  List<Offset> rounded(List<Offset> corners, double r) {
    final n = corners.length;
    final centroid = corners.reduce((a, b) => a + b) / n.toDouble();
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final at = corners[i];
      final prev = corners[(i + n - 1) % n], next = corners[(i + 1) % n];
      final a = (prev - at) / (prev - at).distance;
      final b = (next - at) / (next - at).distance;
      final bisector = (a + b) / (a + b).distance;
      final half = math.acos((a.dx * b.dx + a.dy * b.dy).clamp(-1.0, 1.0)) / 2;
      final center = at + bisector * (corner / math.sin(half));
      // Outward normals of the edge coming in and the edge going out.
      Offset outward(Offset from, Offset to) {
        final d = (to - from) / (to - from).distance;
        final n1 = Offset(-d.dy, d.dx);
        final mid = (from + to) / 2;
        return ((mid + n1) - centroid).distance > (mid - centroid).distance
            ? n1
            : -n1;
      }

      final start = outward(prev, at).direction;
      var sweep = outward(at, next).direction - start;
      while (sweep <= -math.pi) {
        sweep += 2 * math.pi;
      }
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      const arc = steps ~/ 8;
      for (var k = 0; k <= arc; k++) {
        final angle = start + sweep * k / arc;
        out.add(center + Offset(math.cos(angle), math.sin(angle)) * r);
      }
    }
    return out;
  }

  List<Offset> circle(Offset center, double r) => [
        for (var i = 0; i < steps; i++)
          center +
              Offset(math.cos(2 * math.pi * i / steps),
                      math.sin(2 * math.pi * i / steps)) *
                  r,
      ];

  List<Offset> bar(Offset from, Offset to, double half) {
    final d = (to - from) / (to - from).distance;
    final n = Offset(-d.dy, d.dx) * half;
    return [from + n, to + n, to - n, from - n];
  }

  // The grip: over the far bar, between the corners' rounding, and a
  // little proud of the frame it is bound on.
  final gripAt = point + u * (length - frame / 2);
  const gripHalf = width / 2 - corner * 2.2;

  return [
    GlyphPart([circle(ball, radius)]),
    GlyphPart([
      bar(ball + u * (radius + gap), point + u * (frame * 0.5), wire),
    ], material: GlyphMaterial.steel),
    GlyphPart([rounded(handle, corner), rounded(handle, corner - frame)],
        material: GlyphMaterial.steel),
    GlyphPart([
      bar(gripAt - p * gripHalf, gripAt + p * gripHalf, frame * 0.72),
    ], material: GlyphMaterial.cord),
  ];
}

/// Hand-drawn implement glyphs so each event reads as its real implement —
/// a solid shot, a discus with its rim, a pointed javelin, a hammer on its wire and handle —
/// instead of a stand-in Material icon. It takes the ambient [IconTheme]
/// color unless [color] is given, and its highlights are punched out
/// (even-odd) so they reveal whatever sits behind the glyph — a faint sheen
/// on any background. The discus, the hammer and the javelin are the
/// exception, drawn
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

  void _hammer(Canvas canvas, double s) => _parts(canvas, s, hammerParts());

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
