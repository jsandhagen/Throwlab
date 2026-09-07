/// The gold a personal best is marked in: the medal, and the frame around
/// the throw that won it.
///
/// One ramp serves both, and it is a narrow one — a light sheen either side
/// of the same mid gold, never dropping to brown. A wide ramp makes a
/// convincing coin on its own and a blotchy frame around a photo, and what
/// matters more is that the two read as the same piece of metal.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The flat gold, for text and small marks where a gradient would only
/// muddy a few pixels. The medal's mid tone, so they match.
const personalBestGold = Color(0xFFF7B733);

/// Sheen, mid, sheen — enough to look like metal, even enough to run all
/// the way round a frame without a dark side.
const _metal = <Color>[
  Color(0xFFE9A62B),
  Color(0xFFFFD978),
  Color(0xFFF7B733),
  Color(0xFFFFE9A8),
  Color(0xFFECAA2E),
];
const _metalStops = <double>[0, 0.26, 0.52, 0.78, 1];

/// The ramp across [bounds], lit from the top left.
Shader goldShader(Rect bounds) => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: _metal,
      stops: _metalStops,
    ).createShader(bounds);

/// Strokes a rounded rectangle in gold, inside the bounds it is given.
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(inset, Radius.circular(radius - width / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = goldShader(rect),
    );
  }

  @override
  bool shouldRepaint(GoldEdgePainter old) =>
      old.radius != radius || old.width != width;
}

/// A first-place medal: two straps of ribbon meeting at a disc, with a star
/// cut clean out of it.
///
/// Drawn like the event glyphs and the sector are, so it scales to whatever
/// corner it is pinned in, needs no icon font, and takes the same gold as
/// the frame around the card it sits on. The star is a real hole rather
/// than a lighter shape, which is what keeps it reading as a medal at 20
/// pixels instead of as a yellow blob with a smudge in it.
class FirstPlaceMedal extends StatelessWidget {
  const FirstPlaceMedal({super.key, this.size = 20});

  /// Width — which is the disc's diameter. The ribbon makes the medal a
  /// good deal taller than it is wide, so a badge is sized by how big its
  /// disc should be and the straps follow.
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

  /// Height as a multiple of width. The disc is the full width and the
  /// ribbon stands about two thirds of that again above it — long straps
  /// and a big disc, the proportions a medal hanging on a wall has.
  static const aspect = 1.62;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2;
    final centre = Offset(w / 2, h - radius);
    final bounds = Offset.zero & size;

    final metal = Paint()..shader = goldShader(bounds);

    // One layer for the whole medal, so the star can be punched through
    // the ribbon and the disc alike rather than out of one of them.
    canvas.saveLayer(bounds, Paint());

    // Two broad straps, each running from its own top corner down across
    // the middle, ending under the disc. Wide, long, and crossing is what
    // makes them read as ribbon; the narrowing gap between them is the
    // fold. Drawn first so the disc covers where they cross.
    final ribbonBottom = centre.dy;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(w * 0.38, 0)
          ..lineTo(w * 0.66, ribbonBottom)
          ..lineTo(w * 0.28, ribbonBottom)
          ..close(),
        metal,
      )
      ..drawPath(
        Path()
          ..moveTo(w * 0.62, 0)
          ..lineTo(w, 0)
          ..lineTo(w * 0.72, ribbonBottom)
          ..lineTo(w * 0.34, ribbonBottom)
          ..close(),
        metal,
      )
      ..drawCircle(centre, radius, metal)
      ..drawPath(
        _star(centre, radius * 0.62),
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();
  }

  /// A five-pointed star, one point straight up.
  Path _star(Offset centre, double outer) {
    final inner = outer * 0.46;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = centre +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_MedalPainter old) => false;
}
