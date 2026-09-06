/// The metal a personal best is marked in: the sheen the card's edge is
/// stroked with, and the first-place medal pinned to it.
///
/// Both are drawn rather than tinted. A flat swatch of yellow reads as a
/// highlight colour; what says "medal" is the banding — light and dark
/// rolling across a curved surface — so the ramp below is shared by the
/// edge and the disc, and the two catch the light the same way.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The flat gold, for text and small icons where a gradient would only
/// muddy a few pixels.
const personalBestGold = Color(0xFFFFC94D);

/// A polished-metal ramp: shadowed edge, broad sheen, a specular band, then
/// back down. Read along the light's direction, these are the reflections a
/// curved gold surface makes.
const _metal = <Color>[
  Color(0xFF8C5C18),
  Color(0xFFC98F28),
  Color(0xFFF8DE8E),
  Color(0xFFFFF6D2),
  Color(0xFFE3B449),
  Color(0xFF9C6516),
  Color(0xFFD9A63C),
  Color(0xFF8A5A18),
];
const _metalStops = <double>[0, 0.14, 0.3, 0.42, 0.58, 0.74, 0.88, 1];

/// The ramp as a gradient, lit from [begin] towards [end].
LinearGradient goldGradient({
  AlignmentGeometry begin = Alignment.topLeft,
  AlignmentGeometry end = Alignment.bottomRight,
}) =>
    LinearGradient(
      begin: begin,
      end: end,
      colors: _metal,
      stops: _metalStops,
    );

/// The ramp swept around a centre, so each side of a frame catches the
/// light differently — which is what a polished edge does, and what a
/// single corner-to-corner ramp can't fake.
SweepGradient goldSweep(Offset centre) => SweepGradient(
      center: Alignment.center,
      startAngle: -math.pi / 4,
      endAngle: math.pi * 7 / 4,
      colors: const [
        ..._metal,
        ..._metal,
        Color(0xFF8C5C18),
      ],
      stops: [
        for (final stop in _metalStops) stop / 2,
        for (final stop in _metalStops) 0.5 + stop / 2,
        1,
      ],
      transform: GradientRotation(0),
    );

/// Strokes a rounded rectangle in polished gold, inside the bounds it is
/// given.
///
/// A foreground painter rather than a border on the card's shape: the card
/// is already clipped to its radius, so the stroke has to sit inside that
/// clip, and painting it here keeps a best exactly the same size as every
/// other card instead of two pixels fatter.
class GoldEdgePainter extends CustomPainter {
  const GoldEdgePainter({this.radius = 16, this.width = 2});

  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    // Half the stroke falls either side of the path, so inset by that much
    // to keep all of it inside the clip.
    final rect = Offset.zero & size;
    final inset = rect.deflate(width / 2);
    final rrect = RRect.fromRectAndRadius(
        inset, Radius.circular(radius - width / 2));
    // Lit from the corner the medal hangs in, so the edge brightens towards
    // it rather than fighting it.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = goldSweep(rect.center).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GoldEdgePainter old) =>
      old.radius != radius || old.width != width;
}

/// A first-place medal: ribbon, milled gold disc, and the numeral struck
/// into it.
///
/// Drawn like the event glyphs and the sector are, so it scales to whatever
/// corner it is pinned in and needs no icon font — and so the disc can
/// actually catch light across its face, which an icon can't.
class FirstPlaceMedal extends StatelessWidget {
  const FirstPlaceMedal({super.key, this.size = 30});

  /// Width. The medal is a little taller than it is wide, for the ribbon.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Personal best',
      child: SizedBox(
        width: size,
        height: size * _MedalPainter.aspect,
        child: const CustomPaint(painter: _MedalPainter()),
      ),
    );
  }
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter();

  /// Height as a multiple of width — the disc plus the ribbon above it.
  static const aspect = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centre = Offset(w * 0.5, h * 0.64);
    final radius = w * 0.38;

    _ribbon(canvas, w, h, centre, radius);
    _disc(canvas, centre, radius);
    _numeral(canvas, centre, radius);
  }

  /// Two folded bands running up off the top of the medal. The near fold is
  /// lighter than the far one, which is what makes a flat pair of triangles
  /// read as a ribbon rather than a bow tie.
  void _ribbon(
      Canvas canvas, double w, double h, Offset centre, double radius) {
    const far = Color(0xFF7E2621);
    const near = Color(0xFFB3352E);
    final top = centre.dy - radius * 0.55;

    final left = Path()
      ..moveTo(w * 0.16, 0)
      ..lineTo(w * 0.44, 0)
      ..lineTo(centre.dx + w * 0.03, top)
      ..lineTo(centre.dx - w * 0.16, top)
      ..close();
    final right = Path()
      ..moveTo(w * 0.56, 0)
      ..lineTo(w * 0.84, 0)
      ..lineTo(centre.dx + w * 0.16, top)
      ..lineTo(centre.dx - w * 0.03, top)
      ..close();
    canvas
      ..drawPath(right, Paint()..color = far)
      ..drawPath(left, Paint()..color = near);
  }

  void _disc(Canvas canvas, Offset centre, double radius) {
    final bounds = Rect.fromCircle(center: centre, radius: radius);
    // The rim, lit from the top-left; the face, lit from the opposite
    // corner, so the two never wash into one flat coin.
    canvas
      ..drawCircle(
        centre,
        radius,
        Paint()
          ..shader = goldGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              .createShader(bounds),
      )
      ..drawCircle(
        centre,
        radius * 0.82,
        Paint()
          ..shader = goldGradient(
                  begin: Alignment.bottomRight, end: Alignment.topLeft)
              .createShader(bounds),
      )
      // Milling: the knurled edge a struck medal has, drawn as short ticks
      // rather than a texture so it survives being 24 pixels across.
      ..save();
    final tick = Paint()
      ..color = const Color(0x5C3D2606)
      ..strokeWidth = radius * 0.09
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < 16; i++) {
      final angle = i * math.pi / 8;
      final unit = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
          centre + unit * (radius * 0.86), centre + unit * radius, tick);
    }
    canvas.restore();

    // A specular sweep across the upper left, clipped to the face.
    canvas
      ..save()
      ..clipPath(Path()
        ..addOval(Rect.fromCircle(center: centre, radius: radius * 0.82)))
      ..drawPath(
        Path()
          ..moveTo(centre.dx - radius, centre.dy - radius * 0.15)
          ..quadraticBezierTo(centre.dx - radius * 0.2,
              centre.dy - radius * 0.85, centre.dx + radius, centre.dy - radius)
          ..lineTo(centre.dx - radius, centre.dy - radius),
        Paint()..color = const Color(0x59FFFFFF),
      )
      ..restore();
  }

  /// The 1, struck into the face: a stem with a flag and a foot, drawn as a
  /// path so it is the same shape at any size and owes nothing to a font.
  void _numeral(Canvas canvas, Offset centre, double radius) {
    final height = radius * 1.05;
    final top = centre.dy - height / 2;
    final bottom = centre.dy + height / 2;
    final stem = radius * 0.2;
    final x = centre.dx + radius * 0.04;

    final one = Path()
      // The flag, then down the left of the stem to the foot.
      ..moveTo(x - radius * 0.34, top + height * 0.26)
      ..lineTo(x - stem / 2, top)
      ..lineTo(x + stem / 2, top)
      ..lineTo(x + stem / 2, bottom - stem * 0.9)
      ..lineTo(x + radius * 0.34, bottom - stem * 0.9)
      ..lineTo(x + radius * 0.34, bottom)
      ..lineTo(x - radius * 0.34, bottom)
      ..lineTo(x - radius * 0.34, bottom - stem * 0.9)
      ..lineTo(x - stem / 2, bottom - stem * 0.9)
      ..lineTo(x - stem / 2, top + height * 0.2)
      ..lineTo(x - radius * 0.2, top + height * 0.38)
      ..close();

    canvas
      // A struck numeral is a shadow and a highlight either side of an
      // edge; one offset copy of each is enough to sell the relief.
      ..drawPath(
          one.shift(Offset(0, radius * 0.06)),
          Paint()..color = const Color(0x66FFF2C8))
      ..drawPath(one, Paint()..color = const Color(0xE04A2F08));
  }

  @override
  bool shouldRepaint(_MedalPainter old) => false;
}
