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

// The field in the flask. The meniscus is its own tight arc — struck round
// the lines' center it would be nearly flat across a neck this narrow — and
// each sector line's outer edge leaves it exactly where it meets the glass.
// The arcs are struck round a center set just below where the walls' lines
// meet, and run line to line.
// The surface sits just low enough that the meniscus meets the glass below
// the shoulder, where the wall is straight: meeting it on the curve, a line
// leaving the corner at the sector's angle runs on under the turning wall.
const _surfaceY = 0.44, _meniscus = 0.09, _footY = 0.82;
const _surface = Offset(_cx, _surfaceY - _meniscus);

/// The inside edge of the left wall, walked down from the lip: the wall's
/// middle line — neck, shoulder, cone — moved in by half the wall. Worked
/// out along the curve rather than guessed at across it, because the
/// meniscus meets the glass on the shoulder, where the wall is turning.
List<Offset> _innerEdge() {
  const steps = 800;
  final points = <Offset>[];
  void add(Offset at, Offset along) {
    final d = along / along.distance;
    points.add(at + Offset(d.dy, -d.dx) * (_wall / 2));
  }

  const top = Offset(_cx - _nw, _lipY), neck = Offset(_cx - _nw, _neckY);
  for (var i = 0; i <= steps; i++) {
    add(Offset.lerp(top, neck, i / steps)!, neck - top);
  }
  final c = _shoulderCtl, e = _shoulder;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final at = neck * ((1 - t) * (1 - t)) + c * (2 * (1 - t) * t) + e * (t * t);
    add(at, (c - neck) * (2 * (1 - t)) + (e - c) * (2 * t));
  }
  for (var i = 1; i <= steps; i++) {
    add(Offset.lerp(e, _corner, i / steps)!, _corner - e);
  }
  return points;
}

/// Where the meniscus meets the glass on the left: the first point down the
/// wall's inside edge that is below the surface's center and outside it.
final Offset _meets = _innerEdge().firstWhere(
    (p) => p.dy > _surface.dy && (p - _surface).distance >= _meniscus);

final Path _liquid = () {
  const half = sectorHalfAngleDeg * math.pi / 180;
  final apexY = _shoulder.dy - (_cx - _shoulder.dx) / sectorLean;
  final center = Offset(_cx, apexY + 0.05 / sectorLean);

  var liquid = Path.combine(
      PathOperation.difference,
      _flask(),
      Path()
        ..addOval(Rect.fromCircle(center: _surface, radius: _meniscus))
        ..addRect(Rect.fromLTRB(0, 0, 1, _surface.dy)));

  // A line's outer edge leaves the glass exactly where the meniscus meets
  // it and runs to a foot just inside the wall at the base, opening a
  // little less than the wall does, so it parts from the glass at once
  // rather than running under it. The line is the band from that edge in
  // by its own width.
  final top = _meets;
  final bottom =
      Offset(_cx - sectorLean * (_footY - center.dy) - _line / 2, _footY);
  final u = (bottom - top) / (bottom - top).distance;
  final inward = Offset(-u.dy, u.dx) * -_line;
  final outerTop = top - u * 0.1, outerBottom = top + u * 1.0;
  Offset mirror(Offset o) => Offset(2 * _cx - o.dx, o.dy);
  Path line(bool right) {
    final band = [
      outerTop,
      outerBottom,
      outerBottom + inward,
      outerTop + inward
    ];
    return Path()..addPolygon(right ? band.map(mirror).toList() : band, true);
  }

  final lines = Path.combine(PathOperation.union, line(false), line(true));
  liquid = Path.combine(PathOperation.difference, liquid, lines);

  // The arcs, each a band struck round the center, cut to the wedge
  // between the lines so they run from one to the other.
  const steps = 96;
  final arcs = Path();
  for (final y in const [0.54, 0.6675, 0.795]) {
    final r = y - center.dy;
    Offset at(double radius, double a) =>
        center + Offset(math.sin(a), math.cos(a)) * radius;
    arcs.addPolygon([
      for (var i = 0; i <= steps; i++)
        at(r + _line / 2, -half * 2 + half * 4 * i / steps),
      for (var i = steps; i >= 0; i--)
        at(r - _line / 2, -half * 2 + half * 4 * i / steps),
    ], true);
  }
  final between = Path()
    ..addPolygon([
      outerTop,
      mirror(outerTop),
      mirror(outerBottom),
      outerBottom,
    ], true);
  liquid = Path.combine(PathOperation.difference, liquid,
      Path.combine(PathOperation.intersect, arcs, between));
  return liquid;
}();

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
    final open = _flask(closed: false);
    Paint stroke(double width) => Paint()
      ..color = logoBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // One fill, with the field already cut out of it: filled and then cut,
    // the edges of the two leave a hairline of the meniscus across each
    // line.
    canvas.drawPath(_liquid, Paint()..color = logoBlue);
    canvas.drawPath(open, stroke(_wall));
    canvas.drawPath(_lip, stroke(_wall));
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => false;
}
