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
Shader goldShader(Rect bounds) => _ramp(_metal, bounds);

/// The other two of a podium, struck the same way.
///
/// Same five stops, same narrow spread, same light from the same corner —
/// so three lines drawn across a sector read as three medals rather than as
/// three arbitrary colors. Silver is the cool one and bronze the warm one;
/// neither is allowed to go dark, for the reason the gold isn't.
const _silverMetal = <Color>[
  Color(0xFFA9B4BE),
  Color(0xFFE4EAEF),
  Color(0xFFC6CED6),
  Color(0xFFF2F6F9),
  Color(0xFFADB8C2),
];
const _bronzeMetal = <Color>[
  Color(0xFFB0724A),
  Color(0xFFE2A379),
  Color(0xFFCB8A5B),
  Color(0xFFF0BE96),
  Color(0xFFB4764D),
];

/// The flat mid tone of each, for text beside the line it belongs to —
/// the same reason [personalBestGold] exists.
const secondPlaceSilver = Color(0xFFC6CED6);
const thirdPlaceBronze = Color(0xFFCB8A5B);

Shader silverShader(Rect bounds) => _ramp(_silverMetal, bounds);
Shader bronzeShader(Rect bounds) => _ramp(_bronzeMetal, bounds);

Shader _ramp(List<Color> metal, Rect bounds) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: metal,
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

/// A first-place medal: a struck disc with a star cut clean out of it,
/// hanging from two straps of ribbon.
///
/// Drawn like the event glyphs and the sector are, so it scales to whatever
/// corner it is pinned in, needs no icon font, and takes the same gold as
/// the frame around the card it sits on. The star is a real hole rather
/// than a lighter shape, which is what keeps it reading as a medal at 13
/// pixels instead of as a yellow blob with a smudge in it.
///
/// The disc is the subject. The ribbon was as wide as it and half again as
/// tall once, and at the size a personal best is actually marked at —
/// beside a mark, or a placing — that read as a gold V with something under
/// it. It is shorter now, and it hangs clear of the disc rather than
/// running under it: ribbon and disc are the same metal, so with nothing
/// between them the straps melted into the top of the coin.
///
/// The ribbon is not two mirrored straps. It is one band, tapering as it
/// comes down, with a slot cut across it at 45° — so the right-hand piece
/// runs out to a point while the left carries on to a square end. That
/// asymmetry is the whole read: a ribbon has a front and a back and is
/// folded through itself, and two straps leaning symmetrically into each
/// other are a V, which is a letter.
class FirstPlaceMedal extends StatelessWidget {
  const FirstPlaceMedal({super.key, this.size = 20});

  /// Width — which is the disc's diameter. The ribbon puts a little more
  /// height on top, so a badge is sized by how big its disc should be and
  /// the straps follow.
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

  /// The ribbon, as fractions of the disc's diameter: how tall it stands,
  /// how much air is under it, how wide it is across the top, and how far
  /// each edge draws in per unit of height as it comes down.
  static const _ribbon = 0.585;
  static const _gap = 0.079;
  static const _left = 0.030;
  static const _right = 0.954;
  static const _taper = 0.37;

  /// The slot through it: where its left edge crosses the top, how wide it
  /// is measured across, and how far it leans per unit of height. It leans
  /// harder than the band's edges draw in, which is what runs the
  /// right-hand piece out to a point while the left one carries on.
  static const _slot = 0.396;
  static const _slotWidth = 0.169;
  static const _slotLean = 0.55;

  /// Height as a multiple of width: the disc, plus the ribbon and the gap
  /// above it.
  static const aspect = 1 + _ribbon + _gap;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2;
    final center = Offset(w / 2, h - radius);
    final bounds = Offset.zero & size;

    // One layer for the medal, so the star is punched out of the disc.
    canvas.saveLayer(bounds, Paint());

    // One band rather than two straps: it tapers as it comes down, and a
    // leaning slot splits it into a long piece cut off square and a short
    // one running out to a point. See the class comment for why it is
    // lopsided; the numbers are measured, not invented.
    final ribbon = Paint()..shader = goldShader(bounds);
    final foot = w * _ribbon;
    final band = Path()
      ..addPolygon([
        Offset(w * _left, 0),
        Offset(w * _right, 0),
        Offset(w * (_right - _taper * _ribbon), foot),
        Offset(w * (_left + _taper * _ribbon), foot),
      ], true);

    /// Everything to the right of the slot's edge through [x] — a
    /// half-plane, as a box big enough to reach past the badge.
    Path beyond(double x) => Path()
      ..addPolygon([
        Offset(w * (x - _slotLean), -w),
        Offset(w * (x + 2 * _slotLean), 2 * w),
        Offset(w * (x + 2 * _slotLean + 4), 2 * w),
        Offset(w * (x - _slotLean + 4), -w),
      ], true);

    canvas
      ..drawPath(
        Path.combine(PathOperation.difference, band, beyond(_slot)),
        ribbon,
      )
      ..drawPath(
        Path.combine(
            PathOperation.intersect, band, beyond(_slot + _slotWidth)),
        ribbon,
      )
      // The disc takes the ramp across its own square rather than across the
      // whole badge: a coin is lit corner to corner, and over the taller
      // bounds it only ever caught the pale end of the sheen.
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader =
              goldShader(Rect.fromCircle(center: center, radius: radius)),
      )
      ..drawPath(
        _star(center, radius * 0.58),
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();
  }

  /// A five-pointed star, one point straight up. Chunky rather than
  /// spindly: the points have to survive being a couple of pixels long.
  Path _star(Offset center, double outer) {
    final inner = outer * 0.5;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_MedalPainter old) => false;
}
