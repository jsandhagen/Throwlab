import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sector_art.dart';

/// The app's own mark: an Erlenmeyer flask that is also a throwing sector.
///
/// The walls lean at the sector's own 34.92°, so the glass is the field the
/// shot, discus and hammer land in. The flask is full to where the neck
/// opens out, and the liquid carries the sector's lines: two running down
/// just inside the walls, struck round one center at the same angle, and
/// three distance arcs across them, evenly spaced. The meniscus is the
/// front of the throwing circle — or the javelin's foul line, which curves
/// the same way.
///
/// The lines are cut out of the liquid rather than drawn on it, so they are
/// whatever the mark stands on: white on the launcher tile and the results
/// sheet, the theme's own dark in the app, as the empty glass above the
/// liquid already is. That is what lets one drawing serve both.
///
/// It is drawn tight to the flask rather than centered in a square: a tall
/// narrow flask in a square box is a mark at half the size it was asked
/// for. [LogoMark] is sized by its height and takes its width from
/// [logoAspect]; the launcher icons are written from the same painter by
/// `tool/generate_icon.dart`.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: height * logoAspect,
        height: height,
        child: const CustomPaint(painter: LogoPainter()),
      );
}

/// The logo's color: the blue the theme is seeded from.
const logoBlue = Color(0xFF4FC3F7);

/// Width over height of the flask, which is the box the mark fills.
final double logoAspect = _bounds.width / _bounds.height;

// The flask in a unit square. The neck, the shoulder rolling into the cone
// without a kink, and the cone's walls on the sector's own lines.
const _cx = 0.5, _nw = 0.07, _lipY = 0.10, _neckY = 0.31, _baseY = 0.88;
const _wall = 0.05, _overhang = 0.05, _line = 0.024;
const _shoulder = Offset(0.415, 0.40);
final _corner = Offset(_shoulder.dx - sectorLean * (0.82 - _shoulder.dy), 0.82);

Offset get _dir {
  final d = _corner - _shoulder;
  return d / d.distance;
}

// The shoulder's control point sits where the neck's line meets the cone's,
// so the curve leaves one tangent and arrives on the other; the corner's is
// where the cone's line meets the base.
Offset get _shoulderCtl =>
    _shoulder - _dir * ((_shoulder.dx - (_cx - _nw)) / _dir.dx);
Offset get _cornerCtl => _corner + _dir * ((_baseY - _corner.dy) / _dir.dy);
Offset get _foot =>
    Offset(_cornerCtl.dx + (_cx - _cornerCtl.dx) * 0.28, _baseY);

Path _flask({bool closed = true}) {
  Offset m(Offset o) => Offset(2 * _cx - o.dx, o.dy);
  // The neck's walls stop at the lip's lower edge: run on into it, their
  // round ends show as seams across the top of the lip.
  const top = _lipY + _wall / 2;
  final p = Path()..moveTo(_cx - _nw, top);
  void to(Offset o) => p.lineTo(o.dx, o.dy);
  void quad(Offset c, Offset o) => p.quadraticBezierTo(c.dx, c.dy, o.dx, o.dy);
  to(const Offset(_cx - _nw, _neckY));
  quad(_shoulderCtl, _shoulder);
  to(_corner);
  quad(_cornerCtl, _foot);
  to(m(_foot));
  quad(m(_cornerCtl), m(_corner));
  to(m(_shoulder));
  quad(m(_shoulderCtl), const Offset(_cx + _nw, _neckY));
  to(const Offset(_cx + _nw, top));
  if (closed) p.close();
  return p;
}

Path get _lip => Path()
  ..moveTo(_cx - _nw - _overhang, _lipY)
  ..lineTo(_cx + _nw + _overhang, _lipY);

/// Everything the mark paints, stroke and all, in the unit square.
final Rect _bounds =
    _flask().getBounds().expandToInclude(_lip.getBounds()).inflate(_wall / 2);

class LogoPainter extends CustomPainter {
  const LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Fit the flask's own box to the height, centered across the width.
    final scale = size.height / _bounds.height;
    canvas.save();
    canvas.translate(
        (size.width - _bounds.width * scale) / 2 - _bounds.left * scale,
        -_bounds.top * scale);
    canvas.scale(scale);
    // A layer of its own, so the lines cut out of the liquid cut through to
    // whatever is behind the mark rather than to black.
    canvas.saveLayer(null, Paint());

    final body = _flask(), open = _flask(closed: false);
    Paint stroke(double width) => Paint()
      ..color = logoBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The arcs' center: below where the walls' lines meet, by as much as
    // puts the foot of each sector line just inside its wall.
    const half = sectorHalfAngleDeg * math.pi / 180;
    final apexY = _shoulder.dy - (_cx - _shoulder.dx) / sectorLean;
    final center = Offset(_cx, apexY + 0.05 / sectorLean);

    // The meniscus is its own, tighter arc: struck round the lines' center
    // it would be nearly flat across a neck this narrow.
    const surfaceY = 0.40, meniscus = 0.07;
    const surface = Offset(_cx, surfaceY - meniscus);
    final liquid = Path.combine(
        PathOperation.difference,
        body,
        Path()
          ..addOval(Rect.fromCircle(center: surface, radius: meniscus))
          ..addRect(Rect.fromLTRB(0, 0, 1, surface.dy)));

    // Each sector line leaves the meniscus exactly where it meets the glass
    // and runs to the same foot as before, so the lines and the surface
    // are one drawing: the arc the lines are struck from, and the field
    // opening under it. Where the meniscus meets the glass is found rather
    // than worked out — the shoulder there is a curve.
    Offset edge = surface + const Offset(meniscus, 0);
    for (var y = surface.dy; y <= surfaceY; y += 0.0005) {
      final x = math.sqrt(math.max(
          0.0, meniscus * meniscus - (y - surface.dy) * (y - surface.dy)));
      // Inside the glass once a point half a wall further out is still
      // inside the wall's middle line.
      if (body.contains(Offset(_cx + x + _wall / 2 / math.cos(half), y))) {
        edge = Offset(x, y);
        break;
      }
    }
    const footY = 0.82;
    final foot = sectorLean * (footY - center.dy);
    Offset along(double side, double t) {
      // In from the edge by half the line and a hair, so the line's own
      // edge meets the meniscus's rather than disappearing under the wall.
      final top = Offset(_cx + (edge.dx - _line / 2 - 0.004) * side, edge.dy);
      final bottom = Offset(_cx + foot * side, footY);
      return top + (bottom - top) * t;
    }

    canvas.save();
    canvas.clipPath(liquid);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = logoBlue);
    final cut = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _line
      ..strokeCap = StrokeCap.butt
      ..blendMode = BlendMode.clear;
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(along(side, 0), along(side, 2), cut);
    }
    // The arcs run from line to line, so they are cut to the wedge between
    // them rather than to an angle of their own.
    canvas.save();
    canvas.clipPath(Path()
      ..addPolygon(
          [along(-1, 0), along(1, 0), along(1, 2), along(-1, 2)], true));
    for (final y in const [0.54, 0.6675, 0.795]) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: y - center.dy),
          math.pi / 2 - half * 2, half * 4, false, cut);
    }
    canvas.restore();
    canvas.restore();

    canvas.drawPath(open, stroke(_wall));
    canvas.drawPath(_lip, stroke(_wall));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => false;
}
