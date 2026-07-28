import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DrawTool { none, pen, line, arrow, curvedArrow, angle }

/// Selectable pen thicknesses, thin → thick, in video-canvas pixels. The
/// middle one is the default.
const kStrokeWidths = [1.5, 3.0, 6.0];

/// How much of a zoom the ink takes on. Annotations are painted inside the
/// zoom transform, so left alone a stroke thickens one-for-one — at 8x a
/// hairline is a 24 px slab covering the very detail it was drawn to point
/// at. The square root keeps ink growing with the picture, just slower: 4x
/// zoom doubles a stroke instead of quadrupling it.
double inkScaleFor(double zoomScale) =>
    zoomScale <= 1 ? 1 : math.sqrt(zoomScale);

/// Rounds a sampled freehand path into a curve: each touch sample becomes
/// the control point of a quadratic through its neighbours' midpoints. The
/// stroke follows the same route, without the flat facets a raw polyline
/// shows once the video is zoomed into.
Path smoothPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 3) {
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path;
  }
  for (var i = 1; i < points.length - 1; i++) {
    final midpoint = (points[i] + points[i + 1]) / 2;
    path.quadraticBezierTo(
        points[i].dx, points[i].dy, midpoint.dx, midpoint.dy);
  }
  return path..lineTo(points.last.dx, points.last.dy);
}

/// All annotation points are stored normalized to the canvas (0..1 in both
/// axes) so drawings stay anchored when the video is resized or rotated.
sealed class Annotation {
  Annotation(this.color, this.width);
  final Color color;

  /// Stroke thickness, kept per annotation so changing the pen doesn't
  /// re-weight drawings that are already on the frame.
  final double width;
}

class PenStroke extends Annotation {
  PenStroke(super.color, super.width, this.points);
  final List<Offset> points;
}

class LineAnnotation extends Annotation {
  LineAnnotation(super.color, super.width, this.start, this.end);
  Offset start;
  Offset end;
}

/// Drawn tail → head, so the arrow points where the drag finished.
class ArrowAnnotation extends Annotation {
  ArrowAnnotation(super.color, super.width, this.start, this.end);
  Offset start;
  Offset end;
}

/// A freehand path with a head on the end: the arc an implement or a joint
/// travelled, pointing the way it went. Straight arrows can't trace a pull
/// or a hip path, which curve by definition.
class CurvedArrowAnnotation extends Annotation {
  CurvedArrowAnnotation(super.color, super.width, this.points);
  final List<Offset> points;
}

/// Three taps: first arm point, vertex, second arm point. The measured angle
/// is at the vertex.
class AngleAnnotation extends Annotation {
  AngleAnnotation(super.color, super.width);
  final List<Offset> points = [];

  bool get isComplete => points.length == 3;

  double? get degrees {
    if (!isComplete) return null;
    final a = points[0] - points[1];
    final b = points[2] - points[1];
    if (a.distance == 0 || b.distance == 0) return null;
    final cosine =
        (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
    return math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

class DrawingController extends ChangeNotifier {
  DrawTool _tool = DrawTool.none;
  Color _color = Colors.orangeAccent;
  double _strokeWidth = kStrokeWidths[1];
  final List<Annotation> _annotations = [];

  DrawTool get tool => _tool;
  Color get color => _color;
  double get strokeWidth => _strokeWidth;
  List<Annotation> get annotations => List.unmodifiable(_annotations);

  set tool(DrawTool value) {
    _tool = value;
    notifyListeners();
  }

  set color(Color value) {
    _color = value;
    notifyListeners();
  }

  set strokeWidth(double value) {
    _strokeWidth = value;
    notifyListeners();
  }

  void add(Annotation annotation) {
    _annotations.add(annotation);
    notifyListeners();
  }

  void notifyChanged() => notifyListeners();

  void undo() {
    if (_annotations.isEmpty) return;
    final last = _annotations.last;
    // Remove an in-progress angle one point at a time.
    if (last is AngleAnnotation && last.points.length > 1) {
      last.points.removeLast();
    } else {
      _annotations.removeLast();
    }
    notifyListeners();
  }

  void clear() {
    _annotations.clear();
    notifyListeners();
  }
}

/// Paint-only annotation layer stacked over the video player. Gestures are
/// handled by the screen, which owns a single recognizer for zooming,
/// scrubbing, drawing, and node dragging — separate competing recognizers
/// made pinch-zoom land unpredictably.
class DrawingCanvas extends StatelessWidget {
  const DrawingCanvas({
    super.key,
    required this.controller,
    this.zoomScale = 1,
  });

  final DrawingController controller;

  /// The stage's current zoom, so ink can be drawn at a damped weight
  /// instead of blowing up with the picture (see [inkScaleFor]).
  final double zoomScale;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _AnnotationPainter(controller.annotations, zoomScale),
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter(this.annotations, this.zoomScale);

  final List<Annotation> annotations;
  final double zoomScale;

  Offset _denormalize(Offset point, Size size) =>
      Offset(point.dx * size.width, point.dy * size.height);

  /// Canvas-space length that lands as [width] × the damped zoom on screen.
  double _ink(double width) => width * inkScaleFor(zoomScale) / zoomScale;

  /// Canvas-space length that lands as a fixed [pixels] on screen, for
  /// labels — chrome that reads the same at every zoom.
  double _fixed(double pixels) => pixels / zoomScale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      final paint = Paint()
        ..color = annotation.color
        ..strokeWidth = _ink(annotation.width)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      switch (annotation) {
        case PenStroke(:final points):
          if (points.length < 2) continue;
          canvas.drawPath(
              smoothPath(points.map((p) => _denormalize(p, size)).toList()),
              paint);
        case LineAnnotation(:final start, :final end):
          canvas.drawLine(
              _denormalize(start, size), _denormalize(end, size), paint);
        case ArrowAnnotation():
          _paintArrow(canvas, size, annotation, paint);
        case CurvedArrowAnnotation():
          _paintCurvedArrow(canvas, size, annotation, paint);
        case AngleAnnotation():
          _paintAngle(canvas, size, annotation, paint);
      }
    }
  }

  void _paintArrow(
      Canvas canvas, Size size, ArrowAnnotation arrow, Paint paint) {
    final start = _denormalize(arrow.start, size);
    final end = _denormalize(arrow.end, size);
    final delta = end - start;
    final length = delta.distance;
    if (length == 0) return;
    // The head scales with the pen, but never takes more than half a short
    // arrow — a flick stays an arrow instead of becoming a triangle.
    final head = math.min(_ink(arrow.width) * 5, length * 0.5);
    final direction = delta / length;
    canvas.drawLine(start, end - direction * head, paint);
    _paintHead(canvas, end, direction, head, arrow.color);
  }

  void _paintCurvedArrow(
      Canvas canvas, Size size, CurvedArrowAnnotation arrow, Paint paint) {
    final points = arrow.points.map((p) => _denormalize(p, size)).toList();
    if (points.length < 2) return;
    final tip = points.last;
    // Aim the head down the last stretch of the path rather than the final
    // pair of samples, which are a pixel apart and jitter with the finger.
    final head = math.min(_ink(arrow.width) * 5, _length(points) * 0.5);
    final shaftEnd = _walkBack(points, head);
    final delta = tip - shaftEnd;
    if (delta.distance == 0) return;
    canvas.drawPath(smoothPath(points), paint);
    _paintHead(canvas, tip, delta / delta.distance, head, arrow.color);
  }

  /// Filled triangle pointing along [direction], its tip at [tip].
  void _paintHead(Canvas canvas, Offset tip, Offset direction, double length,
      Color color) {
    final base = tip - direction * length;
    final normal = Offset(-direction.dy, direction.dx) * (length * 0.45);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + normal.dx, base.dy + normal.dy)
        ..lineTo(base.dx - normal.dx, base.dy - normal.dy)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  double _length(List<Offset> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    return total;
  }

  /// The point [distance] back along the path from its end.
  Offset _walkBack(List<Offset> points, double distance) {
    var remaining = distance;
    for (var i = points.length - 1; i > 0; i--) {
      final segment = points[i - 1] - points[i];
      final step = segment.distance;
      if (step >= remaining) {
        return step == 0 ? points[i - 1] : points[i] + segment / step * remaining;
      }
      remaining -= step;
    }
    return points.first;
  }

  void _paintAngle(
      Canvas canvas, Size size, AngleAnnotation angle, Paint paint) {
    final points =
        angle.points.map((p) => _denormalize(p, size)).toList();
    final dotPaint = Paint()..color = angle.color;
    // Vertex dots grow with the pen so a thin angle stays precise and a
    // thick one stays visible.
    final dotRadius = _ink(2.5 + angle.width / 2);
    for (final point in points) {
      canvas.drawCircle(point, dotRadius, dotPaint);
    }
    if (points.length >= 2) {
      canvas.drawLine(points[1], points[0], paint);
    }
    if (points.length == 3) {
      canvas.drawLine(points[1], points[2], paint);
      final degrees = angle.degrees;
      if (degrees == null) return;
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${degrees.toStringAsFixed(1)}°',
          style: TextStyle(
            color: angle.color,
            fontSize: _fixed(16),
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(blurRadius: _fixed(4), color: Colors.black),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
          canvas, points[1] + Offset(_fixed(10), _fixed(10)));
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) => true;
}
