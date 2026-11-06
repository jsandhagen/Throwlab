import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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

/// How high the liquid stands for a flask [fill] of the way full, as a y in
/// the unit square.
///
/// By volume, not by height: the flask is a cone, wide at the base, so a
/// level that rose at one speed would race through the first half of a
/// download and crawl through the last. Worked out once, by counting the
/// liquid's area a row at a time.
double _levelFor(double fill) {
  final table = _volume;
  final at = fill.clamp(0.0, 1.0) * table.last.area;
  for (var i = 1; i < table.length; i++) {
    if (table[i].area >= at) {
      final a = table[i - 1], b = table[i];
      final t = b.area == a.area ? 0.0 : (at - a.area) / (b.area - a.area);
      return a.y + (b.y - a.y) * t;
    }
  }
  return table.last.y;
}

final List<({double y, double area})> _volume = () {
  final b = _liquid.getBounds();
  const rows = 160, columns = 120;
  final table = <({double y, double area})>[(y: b.bottom, area: 0)];
  var area = 0.0;
  for (var r = 0; r < rows; r++) {
    final y = b.bottom - (r + 0.5) * b.height / rows;
    var inside = 0;
    for (var c = 0; c < columns; c++) {
      if (_liquid.contains(Offset(b.left + (c + 0.5) * b.width / columns, y))) {
        inside++;
      }
    }
    area += inside;
    table.add((y: b.bottom - (r + 1) * b.height / rows, area: area));
  }
  return table;
}();

class LogoPainter extends CustomPainter {
  const LogoPainter({this.fill = 1, this.ripple = 0, this.phase = 0});

  /// How full the flask is, by volume, 0 to 1. Full is the mark itself;
  /// anything less is the mark as a progress gauge — see [FillingFlask].
  final double fill;

  /// How much the surface is moving, 0 (still) to 1, and where along its
  /// swell it has got to, in radians.
  final double ripple;
  final double phase;

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
    if (fill >= 1) {
      canvas.drawPath(_liquid, Paint()..color = logoBlue);
    } else {
      // The whole of what it is filling towards, faintly, so the level is
      // read against something; then the liquid up to a surface that is
      // flat, or swelling while there is something arriving. The meniscus
      // only comes in at the very top, so a full flask is the mark again.
      canvas.drawPath(_liquid, Paint()..color = logoBlue.withOpacity(0.14));
      final b = _liquid.getBounds();
      final level = _levelFor(fill);
      final surface = Path()..moveTo(b.left - 0.01, level);
      const steps = 24;
      for (var i = 0; i <= steps; i++) {
        final x = b.left - 0.01 + (b.width + 0.02) * i / steps;
        surface.lineTo(
            x, level + ripple * 0.007 * math.sin(x * 38 + phase));
      }
      surface
        ..lineTo(b.right + 0.01, b.bottom + 0.01)
        ..lineTo(b.left - 0.01, b.bottom + 0.01)
        ..close();
      canvas.save();
      canvas.clipPath(surface);
      canvas.drawPath(_liquid, Paint()..color = logoBlue);
      canvas.restore();
    }
    canvas.drawPath(open, stroke(_wall));
    canvas.drawPath(_lip, stroke(_wall));
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.fill != fill || old.ripple != ripple || old.phase != phase;
}

/// The mark as a progress gauge: the flask filling to [progress], for the
/// two waits in the app that know how far along they are — optimizing an
/// imported clip, and downloading an update.
///
/// The level eases to each new reading rather than jumping to it, since
/// both report in lurches, and the surface swells only while readings are
/// arriving: a download that has stalled at 55% looks still, where a flat
/// bar at 55% says the same thing whether it is moving or not. Null is a
/// wait that has not said how far along it is yet, and is the empty glass —
/// the caller says so in words. Reduced motion sets the level and leaves
/// the surface flat.
class FillingFlask extends StatefulWidget {
  const FillingFlask({super.key, required this.height, this.progress});

  final double height;
  final double? progress;

  @override
  State<FillingFlask> createState() => _FillingFlaskState();
}

class _FillingFlaskState extends State<FillingFlask>
    with SingleTickerProviderStateMixin {
  /// Made the first time a reading comes in: a flask that is never
  /// updated never needs one.
  Ticker? _ticker;
  double _shown = 0;
  double _ripple = 0;
  double _phase = 0;
  Duration _last = Duration.zero;

  /// When the last reading came in, on the ticker's clock.
  Duration _heard = Duration.zero;
  bool _fresh = false;

  double get _target => widget.progress ?? 0;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _shown = _target;
  }

  @override
  void didUpdateWidget(FillingFlask old) {
    super.didUpdateWidget(old);
    if (widget.progress == old.progress) return;
    if (_still) {
      _shown = _target;
      return;
    }
    _fresh = true;
    final ticker = _ticker ??= createTicker(_tick);
    if (!ticker.isActive) {
      _last = Duration.zero;
      ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_fresh) {
      _heard = elapsed;
      _fresh = false;
    }
    // Moving for a moment after each reading, then settling.
    final since = (elapsed - _heard).inMilliseconds / 1000;
    final wanted = since < 1.2 ? 1.0 : 0.0;
    _ripple += (wanted - _ripple) * (1 - math.exp(-dt / 0.35));
    _phase += dt * 5;
    _shown += (_target - _shown) * (1 - math.exp(-dt / 0.3));
    final settled =
        (_shown - _target).abs() < 0.001 && wanted == 0 && _ripple < 0.01;
    setState(() {
      if (settled) {
        _shown = _target;
        _ripple = 0;
      }
    });
    if (settled) _ticker?.stop();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    return Semantics(
      label: 'Progress',
      value: progress == null ? null : '${(progress * 100).round()}%',
      child: SizedBox(
        width: widget.height * logoAspect,
        height: widget.height,
        child: CustomPaint(
          painter: LogoPainter(
            // Never quite full while it is still going: full is the mark,
            // and the meniscus coming in is what says it is done.
            fill: progress != null && progress >= 1 ? 1 : math.min(_shown, 0.995),
            ripple: _ripple,
            phase: _phase,
          ),
        ),
      ),
    );
  }
}
