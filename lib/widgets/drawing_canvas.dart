import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DrawTool { none, pen, line, angle }

/// Selectable pen thicknesses, thin → thick, in video-canvas pixels. The
/// middle one is the default.
const kStrokeWidths = [1.5, 3.0, 6.0];

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
  const DrawingCanvas({super.key, required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _AnnotationPainter(controller.annotations),
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter(this.annotations);

  final List<Annotation> annotations;

  Offset _denormalize(Offset point, Size size) =>
      Offset(point.dx * size.width, point.dy * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      final paint = Paint()
        ..color = annotation.color
        ..strokeWidth = annotation.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      switch (annotation) {
        case PenStroke(:final points):
          if (points.length < 2) continue;
          final path = Path()
            ..moveTo(_denormalize(points.first, size).dx,
                _denormalize(points.first, size).dy);
          for (final point in points.skip(1)) {
            final p = _denormalize(point, size);
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
        case LineAnnotation(:final start, :final end):
          canvas.drawLine(
              _denormalize(start, size), _denormalize(end, size), paint);
        case AngleAnnotation():
          _paintAngle(canvas, size, annotation, paint);
      }
    }
  }

  void _paintAngle(
      Canvas canvas, Size size, AngleAnnotation angle, Paint paint) {
    final points =
        angle.points.map((p) => _denormalize(p, size)).toList();
    final dotPaint = Paint()..color = angle.color;
    // Vertex dots grow with the pen so a thin angle stays precise and a
    // thick one stays visible.
    final dotRadius = 2.5 + angle.width / 2;
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
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, points[1] + const Offset(10, 10));
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) => true;
}
