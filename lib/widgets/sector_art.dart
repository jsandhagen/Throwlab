/// The competition sector, drawn as ornament.
///
/// Both painters work over a normalized box, so the same geometry serves a
/// centered illustration and a full-screen backdrop.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Half the legal landing sector, in degrees. The sector is 34.92° wide —
/// the angle a circle of radius 20 m cuts a 12 m chord on.
const double sectorHalfAngleDeg = 34.92 / 2;

/// The sector's lean expressed the way a canvas wants it: horizontal shift
/// per unit of height.
final double sectorLean = math.tan(sectorHalfAngleDeg * math.pi / 180);

/// The landing sector: the circle at the apex and the two lines that open
/// from it at 34.92°. Drawn from the top-center of the box, downward.
class SectorPainter extends CustomPainter {
  const SectorPainter({required this.color, this.opacity = 1});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final apex = Offset(size.width / 2, size.height * 0.08);
    final reach = size.height - apex.dy;
    final spread = reach * sectorLean;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.5 * opacity),
          color.withOpacity(0.02 * opacity),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawLine(apex, apex + Offset(-spread, reach), line);
    canvas.drawLine(apex, apex + Offset(spread, reach), line);

    // The throwing circle sits at the apex, half of it behind the lines.
    final radius = size.width * 0.055;
    canvas.drawCircle(
      apex,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withOpacity(0.45 * opacity),
    );

    // Distance arcs, the way a sector is marked out every 10 m.
    for (final fraction in const [0.42, 0.68, 0.94]) {
      final r = reach * fraction;
      canvas.drawArc(
        Rect.fromCircle(center: apex, radius: r),
        math.pi / 2 - sectorHalfAngleDeg * math.pi / 180,
        2 * sectorHalfAngleDeg * math.pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withOpacity((0.3 - fraction * 0.22) * opacity),
      );
    }
  }

  @override
  bool shouldRepaint(SectorPainter old) =>
      old.color != color || old.opacity != opacity;
}

/// The sector as background art: the throwing circle sits just off the
/// bottom-left corner, its distance arcs sweep diagonally across the screen,
/// and the two sector lines cut through them. Faint by design — it should
/// register as texture, not as a diagram.
class SectorBackdropPainter extends CustomPainter {
  const SectorBackdropPainter({required this.color, this.opacity = 1});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    // Close enough to the corner that the arcs actually curve.
    final apex = Offset(-size.width * 0.1, size.height * 1.08);
    final corner = Offset(size.width * 1.04, -size.height * 0.04);
    final bearing = math.atan2(corner.dy - apex.dy, corner.dx - apex.dx);
    const half = sectorHalfAngleDeg * math.pi / 180;
    final reach = (corner - apex).distance;

    // A wash at the circle end, so the corner has depth behind the lines.
    canvas.drawCircle(
      apex,
      size.height * 0.85,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withOpacity(0.07 * opacity),
            color.withOpacity(0),
          ],
        ).createShader(
            Rect.fromCircle(center: apex, radius: size.height * 0.85)),
    );

    Paint stroke(double width, double alpha) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          color.withOpacity(alpha * opacity),
          color.withOpacity(alpha * 0.3 * opacity),
        ],
      ).createShader(Offset.zero & size);

    // Distance arcs, sweeping wider than the sector so they cross the whole
    // screen; the sector is the part the lines pick out.
    const sweep = 1.15; // radians, centered on the diagonal
    for (var i = 1; i <= 7; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: apex, radius: reach * (0.16 + i * 0.135)),
        bearing - sweep / 2,
        sweep,
        false,
        stroke(1, 0.22),
      );
    }
    for (final sign in [-1, 1]) {
      final angle = bearing + sign * half;
      canvas.drawLine(
        apex,
        apex + Offset(math.cos(angle), math.sin(angle)) * reach * 1.2,
        stroke(1.2, 0.3),
      );
    }
    // The circle itself, mostly off-screen at the corner.
    canvas.drawCircle(
      apex,
      size.width * 0.16,
      stroke(1.4, 0.34),
    );
  }

  @override
  bool shouldRepaint(SectorBackdropPainter old) =>
      old.color != color || old.opacity != opacity;
}
