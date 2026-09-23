// Concepts for the app's own mark, drawn where it is actually used: the
// launcher icon at the size a store and a home screen show it, the app
// bar's 32 px on the dark theme, and the results sheet's white paper.
//
//   flutter test --update-goldens tool/preview/logo_preview.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/widgets/sector_art.dart';

import 'harness.dart';

const _out = '../../build/preview';

const _blue = Color(0xFF4FC3F7);

enum Concept { a1, a2, b1, b2 }

void main() {
  testWidgets('logo concepts', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final surface = ThrowLabApp.theme.colorScheme.surface;

    Widget tile(Concept c, double size) => ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Container(
            width: size,
            height: size,
            color: Colors.white,
            padding: EdgeInsets.all(size * 0.1),
            child: CustomPaint(painter: _LogoPainter(c)),
          ),
        );

    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in Concept.values) ...[
                Text(
                    switch (c) {
                      Concept.a1 => 'A1 · Flask, javelin, shot and discus',
                      Concept.a2 => 'A2 · All four implements',
                      Concept.b1 => 'B1 · The field in the flask',
                      Concept.b2 => 'B2 · The flask is the sector',
                    },
                    style: ThrowLabApp.theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    tile(c, 150),
                    const SizedBox(width: 14),
                    tile(c, 48),
                    const SizedBox(width: 14),
                    // The app bar's own 32 px, on the theme's surface.
                    Container(
                      color: surface,
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CustomPaint(painter: _LogoPainter(c))),
                    ),
                    const SizedBox(width: 14),
                    // The empty state's 140 px, on the dark theme.
                    Container(
                      color: surface,
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                          width: 90,
                          height: 90,
                          child: CustomPaint(painter: _LogoPainter(c))),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
    ));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('$_out/logo_concepts.png'));
  });
}

/// An Erlenmeyer flask in the unit square: a neck, a shoulder that rolls
/// into the cone with no kink in it, and rounded corners at the base.
class _Flask {
  _Flask({
    this.nw = 0.075,
    this.lipY = 0.12,
    this.neckY = 0.35,
    required this.shoulder,
    required this.corner,
    this.baseY = 0.87,
  });

  final double nw, lipY, neckY, baseY;

  /// Where the shoulder hands over to the cone, and where the cone hands
  /// over to the corner — both on the left, mirrored for the right.
  final Offset shoulder, corner;

  static const cx = 0.5;

  Offset get _d {
    final d = corner - shoulder;
    return d / d.distance;
  }

  // The shoulder's control point sits where the neck's line meets the
  // cone's, so the curve leaves one tangent and arrives on the other.
  Offset get _shoulderCtl =>
      shoulder - _d * ((shoulder.dx - (cx - nw)) / _d.dx);
  Offset get _cornerCtl => corner + _d * ((baseY - corner.dy) / _d.dy);
  Offset get _foot =>
      Offset(_cornerCtl.dx + (cx - _cornerCtl.dx) * 0.28, baseY);

  Path path(double s, {bool closed = true}) {
    Offset m(Offset o) => Offset(2 * cx - o.dx, o.dy);
    final p = Path()..moveTo((cx - nw) * s, lipY * s);
    void to(Offset o) => p.lineTo(o.dx * s, o.dy * s);
    void quad(Offset c, Offset o) =>
        p.quadraticBezierTo(c.dx * s, c.dy * s, o.dx * s, o.dy * s);
    to(Offset(cx - nw, neckY));
    quad(_shoulderCtl, shoulder);
    to(corner);
    quad(_cornerCtl, _foot);
    to(m(_foot));
    quad(m(_cornerCtl), m(corner));
    to(m(shoulder));
    quad(m(_shoulderCtl), Offset(cx + nw, neckY));
    to(Offset(cx + nw, lipY));
    if (closed) p.close();
    return p;
  }

  Path lip(double s, double overhang) => Path()
    ..moveTo((cx - nw - overhang) * s, lipY * s)
    ..lineTo((cx + nw + overhang) * s, lipY * s);
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.concept);

  final Concept concept;

  static final _wide = _Flask(
    shoulder: const Offset(0.39, 0.46),
    corner: const Offset(0.2, 0.80),
  );

  // Walls leaning at the sector's own half-angle: a flask whose cone is a
  // throwing sector, so the arcs struck inside it are the field's own.
  static final _sector = () {
    final lean = sectorLean;
    const top = Offset(0.415, 0.40);
    const baseY = 0.82;
    return _Flask(
      nw: 0.07,
      lipY: 0.10,
      neckY: 0.31,
      shoulder: top,
      corner: Offset(top.dx - lean * (baseY - top.dy), baseY),
      baseY: 0.88,
    );
  }();

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = _blue;

  /// A javelin with nothing on it: a shaft tapering to a point at the
  /// front and a finer one at the back.
  Path _javelin(Offset from, Offset to, double half) {
    final len = (to - from).distance;
    final u = (to - from) / len, n = Offset(-u.dy, u.dx);
    Offset at(double t, double w) => from + u * (len * t) + n * w;
    return Path()
      ..addPolygon([
        at(0, 0),
        at(0.35, half * 0.8),
        at(0.80, half),
        at(1, 0),
        at(0.80, -half),
        at(0.35, -half * 0.8),
      ], true);
  }

  /// A discus seen face on: a disc with the plate cut out of it.
  void _discus(Canvas canvas, Offset c, double r, double stroke) {
    canvas.drawCircle(c, r, _stroke(_blue, stroke));
    canvas.drawCircle(c, r * 0.28, _fill);
  }

  /// The hammer: ball, wire, and the triangle it is held by.
  void _hammer(Canvas canvas, Offset ball, double r, Offset handle, double wire,
      double loop) {
    canvas.drawCircle(ball, r, _fill);
    canvas.drawLine(ball, handle, _stroke(_blue, wire));
    final u = (handle - ball) / (handle - ball).distance;
    final n = Offset(-u.dy, u.dx);
    final tri = Path()
      ..addPolygon([
        handle,
        handle + u * loop + n * loop * 0.7,
        handle + u * loop - n * loop * 0.7,
      ], true);
    canvas.drawPath(tri, _stroke(_blue, wire));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final wall = s * 0.05;
    canvas.saveLayer(Offset.zero & size, Paint());
    switch (concept) {
      case Concept.a1 || Concept.a2:
        final f = _wide;
        final body = f.path(s), open = f.path(s, closed: false);
        if (concept == Concept.a1) {
          canvas.drawPath(
              _javelin(Offset(0.03 * s, 0.84 * s), Offset(0.98 * s, 0.14 * s),
                  s * 0.028),
              _fill);
          // The glass cut out of the shaft where it passes behind a wall.
          canvas.drawPath(open,
              _stroke(Colors.black, wall * 1.7)..blendMode = BlendMode.clear);
        }
        // The liquid, and the implements rising through it.
        canvas.save();
        canvas.clipPath(body);
        canvas.drawRect(Rect.fromLTRB(0, 0.60 * s, s, s),
            Paint()..color = _blue.withValues(alpha: 0.28));
        canvas.restore();
        canvas.drawLine(Offset(0.285 * s, 0.60 * s),
            Offset(0.715 * s, 0.60 * s), _stroke(_blue, s * 0.022));
        if (concept == Concept.a1) {
          canvas.drawCircle(Offset(0.42 * s, 0.73 * s), s * 0.055, _fill);
          _discus(canvas, Offset(0.585 * s, 0.70 * s), s * 0.052, s * 0.022);
        } else {
          canvas.drawCircle(Offset(0.37 * s, 0.76 * s), s * 0.048, _fill);
          _discus(canvas, Offset(0.63 * s, 0.76 * s), s * 0.048, s * 0.02);
          // The hammer let down through the neck, its handle above the lip.
          _hammer(canvas, Offset(0.5 * s, 0.69 * s), s * 0.06,
              Offset(0.5 * s, 0.04 * s), s * 0.018, s * 0.0);
          canvas.drawPath(
              Path()
                ..addPolygon([
                  Offset(0.5 * s, 0.075 * s),
                  Offset(0.44 * s, -0.005 * s),
                  Offset(0.56 * s, -0.005 * s),
                ], true),
              _stroke(_blue, s * 0.022));
          // The javelin standing in the flask like a rod left in it.
          canvas.drawPath(
              _javelin(Offset(0.60 * s, 0.84 * s), Offset(0.94 * s, 0.02 * s),
                  s * 0.022),
              _fill);
          canvas.drawPath(open,
              _stroke(Colors.black, wall * 1.7)..blendMode = BlendMode.clear);
        }
        canvas.drawPath(open, _stroke(_blue, wall));
        canvas.drawPath(f.lip(s, 0.05), _stroke(_blue, wall));
      case Concept.b1:
        final f = _wide;
        final body = f.path(s), open = f.path(s, closed: false);
        // Solid liquid to the shoulder, so the field reads white on it.
        const surfaceY = 0.50;
        canvas.save();
        canvas.clipPath(body);
        canvas.drawRect(Rect.fromLTRB(0, surfaceY * s, s, s), _fill);
        final apex = Offset(0.5 * s, surfaceY * s + s * 0.045);
        final white = _stroke(Colors.white, s * 0.024);
        final reach = 0.5 * s;
        canvas.drawLine(apex + Offset(-sectorLean, 1) * s * 0.045,
            apex + Offset(-sectorLean * reach, reach), white);
        canvas.drawLine(apex + Offset(sectorLean, 1) * s * 0.045,
            apex + Offset(sectorLean * reach, reach), white);
        final half = sectorHalfAngleDeg * math.pi / 180;
        for (final r in [0.17, 0.28]) {
          canvas.drawArc(Rect.fromCircle(center: apex, radius: r * s),
              math.pi / 2 - half, half * 2, false, white);
        }
        canvas.drawCircle(apex, s * 0.04, _stroke(Colors.white, s * 0.02));
        canvas.restore();
        canvas.drawPath(open, _stroke(_blue, wall));
        canvas.drawPath(f.lip(s, 0.05), _stroke(_blue, wall));
      case Concept.b2:
        final f = _sector;
        final body = f.path(s), open = f.path(s, closed: false);
        // The apex the walls lean out of, above the flask: the arcs are
        // struck round it, so they are the field's own marker lines.
        final lean = sectorLean;
        final apex =
            Offset(0.5 * s, (f.shoulder.dy - (0.5 - f.shoulder.dx) / lean) * s);
        final half = sectorHalfAngleDeg * math.pi / 180;
        final surface = (0.56 * s) - apex.dy;
        canvas.save();
        canvas.clipPath(body);
        // The liquid's surface is itself an arc of the sector.
        canvas.drawPath(
            Path()
              ..moveTo(apex.dx, apex.dy)
              ..arcTo(Rect.fromCircle(center: apex, radius: s * 2),
                  math.pi / 2 - half * 3, half * 6, false)
              ..close(),
            Paint()..color = Colors.transparent);
        canvas.drawPath(
            Path.combine(
                PathOperation.difference,
                Path()..addRect(Offset.zero & size),
                Path()
                  ..addOval(Rect.fromCircle(center: apex, radius: surface))),
            _fill);
        final white = _stroke(Colors.white, s * 0.024);
        for (final r in [surface + 0.12 * s, surface + 0.24 * s]) {
          canvas.drawArc(Rect.fromCircle(center: apex, radius: r),
              math.pi / 2 - half * 1.5, half * 3, false, white);
        }
        canvas.restore();
        canvas.drawPath(open, _stroke(_blue, wall));
        canvas.drawPath(f.lip(s, 0.05), _stroke(_blue, wall));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => true;
}
