/// Drawn ornaments from the events themselves: the implements, the legal
/// sector, a real flight path, and the surfaces a throw happens on.
///
/// Everything here is a [CustomPainter] over a normalized box, so the same
/// path serves a 20px tile glyph and a full-width backdrop.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../utils/projectile.dart';

/// Half the legal landing sector, in degrees. The sector is 34.92° wide —
/// the angle a circle of radius 20 m cuts a 12 m chord on.
const double sectorHalfAngleDeg = 34.92 / 2;

/// The sector's lean expressed the way a canvas wants it: horizontal shift
/// per unit of height.
final double sectorLean = math.tan(sectorHalfAngleDeg * math.pi / 180);

/// One implement, drawn rather than borrowed from an icon font.
class ImplementGlyph extends StatelessWidget {
  const ImplementGlyph({
    super.key,
    required this.event,
    required this.color,
    this.size = 24,
  });

  final ThrowEvent event;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: ImplementGlyphPainter(event: event, color: color),
        ),
      );
}

class ImplementGlyphPainter extends CustomPainter {
  const ImplementGlyphPainter({required this.event, required this.color});

  final ThrowEvent event;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    canvas.translate(
        (size.width - unit) / 2, (size.height - unit) / 2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color.withOpacity(0.22);

    switch (event) {
      case ThrowEvent.shotPut:
        // A sphere: circle, an inner arc for the highlight.
        final center = Offset(unit * 0.5, unit * 0.52);
        final radius = unit * 0.34;
        canvas.drawCircle(center, radius, fill);
        canvas.drawCircle(center, radius, stroke);
        canvas.drawArc(
          Rect.fromCircle(
              center: center + Offset(-radius * 0.18, -radius * 0.18),
              radius: radius * 0.52),
          math.pi * 1.05,
          math.pi * 0.62,
          false,
          stroke..strokeWidth = unit * 0.055,
        );
      case ThrowEvent.discus:
        // Seen in flight: a tilted disc, so it reads as a plate, not a ring.
        canvas.save();
        canvas.translate(unit * 0.5, unit * 0.5);
        canvas.rotate(-0.42);
        final face = Rect.fromCenter(
            center: Offset.zero, width: unit * 0.78, height: unit * 0.34);
        canvas.drawOval(face, fill);
        canvas.drawOval(face, stroke);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: unit * 0.34, height: unit * 0.14),
          stroke..strokeWidth = unit * 0.05,
        );
        canvas.restore();
      case ThrowEvent.hammer:
        // Ball, straight wire, and the spade grip square across its end.
        final ball = Offset(unit * 0.3, unit * 0.7);
        final radius = unit * 0.19;
        canvas.drawCircle(ball, radius, fill);
        canvas.drawCircle(ball, radius, stroke);
        final grip = Offset(unit * 0.74, unit * 0.26);
        final along = (grip - ball) / (grip - ball).distance;
        final across = Offset(-along.dy, along.dx);
        canvas.drawLine(ball + along * radius, grip,
            stroke..strokeWidth = unit * 0.055);
        final bar = across * (unit * 0.15);
        final handle = Path()
          ..moveTo((grip - bar).dx, (grip - bar).dy)
          ..lineTo((grip + bar).dx, (grip + bar).dy)
          ..lineTo((grip - along * (unit * 0.13)).dx,
              (grip - along * (unit * 0.13)).dy)
          ..close();
        canvas.drawPath(handle, fill);
        canvas.drawPath(handle, stroke..strokeWidth = unit * 0.06);
      case ThrowEvent.javelin:
        // Shaft at its attack angle, with the cord grip and a solid head.
        canvas.save();
        canvas.translate(unit * 0.5, unit * 0.5);
        canvas.rotate(-math.pi / 4);
        canvas.drawLine(Offset(-unit * 0.42, 0), Offset(unit * 0.42, 0),
            stroke..strokeWidth = unit * 0.07);
        final head = Path()
          ..moveTo(unit * 0.42, 0)
          ..lineTo(unit * 0.18, -unit * 0.075)
          ..lineTo(unit * 0.18, unit * 0.075)
          ..close();
        canvas.drawPath(head, Paint()..color = color);
        for (var i = 0; i < 4; i++) {
          final x = -unit * 0.02 - i * unit * 0.06;
          canvas.drawLine(Offset(x, -unit * 0.075), Offset(x, unit * 0.075),
              stroke..strokeWidth = unit * 0.042);
        }
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ImplementGlyphPainter old) =>
      old.event != event || old.color != color;
}

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

/// A real flight path: the vacuum trajectory for a given release, scaled to
/// fill the box. Not decoration for its own sake — it's the same curve the
/// analysis screen predicts from.
class FlightArcPainter extends CustomPainter {
  const FlightArcPainter({
    required this.color,
    this.speed = 11,
    this.angleDeg = 42,
    this.releaseHeight = 1.8,
    this.opacity = 1,
    this.markRelease = true,
  });

  final Color color;
  final double speed;
  final double angleDeg;
  final double releaseHeight;
  final double opacity;
  final bool markRelease;

  @override
  void paint(Canvas canvas, Size size) {
    final range =
        predictedDistance(speed, angleDeg, releaseHeight: releaseHeight);
    if (range <= 0) return;
    final theta = angleDeg * math.pi / 180;
    final vx = speed * math.cos(theta);
    final vy = speed * math.sin(theta);
    final duration =
        flightTime(speed, angleDeg, releaseHeight: releaseHeight);

    // Peak height sets the vertical scale so the arc always fills the box.
    final apex = releaseHeight + vy * vy / (2 * gravity);
    final path = Path();
    for (var i = 0; i <= 48; i++) {
      final t = duration * i / 48;
      final x = vx * t / range * size.width;
      final y = size.height *
          (1 - (releaseHeight + vy * t - 0.5 * gravity * t * t) / apex);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            color.withOpacity(0.55 * opacity),
            color.withOpacity(0.05 * opacity),
          ],
        ).createShader(Offset.zero & size),
    );

    if (!markRelease) return;
    final release = Offset(0, size.height * (1 - releaseHeight / apex));
    canvas.drawCircle(
        release, 2.5, Paint()..color = color.withOpacity(0.7 * opacity));
  }

  @override
  bool shouldRepaint(FlightArcPainter old) =>
      old.color != color ||
      old.speed != speed ||
      old.angleDeg != angleDeg ||
      old.releaseHeight != releaseHeight ||
      old.opacity != opacity;
}

/// The surface an event is thrown from: cage netting for the ring events,
/// runway lane lines for the javelin.
class ThrowSurfacePainter extends CustomPainter {
  const ThrowSurfacePainter({required this.event, required this.color});

  final ThrowEvent event;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [color.withOpacity(0.34), color.withOpacity(0.04)],
      ).createShader(rect);

    if (event == ThrowEvent.javelin) {
      // Runway: lane lines converging slightly, as they do down the track.
      for (var i = 1; i < 7; i++) {
        final y = size.height * i / 7;
        canvas.drawLine(Offset(0, y), Offset(size.width, y - 6), paint);
      }
      return;
    }
    // Cage net: a diamond mesh on the diagonal.
    const spacing = 18.0;
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height),
          paint);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0),
          paint);
    }
  }

  @override
  bool shouldRepaint(ThrowSurfacePainter old) =>
      old.event != event || old.color != color;
}
