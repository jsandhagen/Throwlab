import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DrawTool { none, pen, line, angle }

/// All annotation points are stored normalized to the canvas (0..1 in both
/// axes) so drawings stay anchored when the video is resized or rotated.
sealed class Annotation {
  Annotation(this.color);
  final Color color;
}

class PenStroke extends Annotation {
  PenStroke(super.color, this.points);
  final List<Offset> points;
}

class LineAnnotation extends Annotation {
  LineAnnotation(super.color, this.start, this.end);
  Offset start;
  Offset end;
}

/// Three taps: first arm point, vertex, second arm point. The measured angle
/// is at the vertex.
class AngleAnnotation extends Annotation {
  AngleAnnotation(super.color);
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
  final List<Annotation> _annotations = [];

  DrawTool get tool => _tool;
  Color get color => _color;
  List<Annotation> get annotations => List.unmodifiable(_annotations);

  set tool(DrawTool value) {
    _tool = value;
    notifyListeners();
  }

  set color(Color value) {
    _color = value;
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

/// Transparent gesture + paint layer stacked over the video player.
///
/// In scrub mode ([DrawTool.none]) horizontal drags are reported through
/// [onJogFrames] so the video underneath can be stepped frame by frame.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key, required this.controller, this.onJogFrames});

  final DrawingController controller;
  final ValueChanged<int>? onJogFrames;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  /// Drag distance that advances the video by one frame.
  static const _pixelsPerFrame = 8.0;
  double _jogAccumulator = 0;

  /// Two-finger gestures belong to the pinch-zoom viewer above this layer;
  /// ignore them here so a pinch never jogs frames or leaves pen marks.
  int _activePointers = 0;

  DrawingController get controller => widget.controller;

  Offset _normalize(Offset position, Size size) => Offset(
        (position.dx / size.width).clamp(0.0, 1.0),
        (position.dy / size.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          return Listener(
            onPointerDown: (_) => _activePointers++,
            onPointerUp: (_) =>
                _activePointers = math.max(0, _activePointers - 1),
            onPointerCancel: (_) =>
                _activePointers = math.max(0, _activePointers - 1),
            child: GestureDetector(
              behavior: controller.tool == DrawTool.none
                  ? HitTestBehavior.translucent
                  : HitTestBehavior.opaque,
              onTapUp: (details) {
                if (controller.tool != DrawTool.angle) return;
                final point = _normalize(details.localPosition, size);
                final last = controller.annotations.lastOrNull;
                if (last is AngleAnnotation && !last.isComplete) {
                  last.points.add(point);
                  controller.notifyChanged();
                } else {
                  controller.add(AngleAnnotation(controller.color)
                    ..points.add(point));
                }
              },
              onPanStart: (details) {
                if (_activePointers > 1) return;
                final point = _normalize(details.localPosition, size);
                switch (controller.tool) {
                  case DrawTool.pen:
                    controller.add(PenStroke(controller.color, [point]));
                  case DrawTool.line:
                    controller
                        .add(LineAnnotation(controller.color, point, point));
                  case DrawTool.angle:
                    break;
                  case DrawTool.none:
                    _jogAccumulator = 0;
                }
              },
              onPanUpdate: (details) {
                if (_activePointers > 1) return;
                final point = _normalize(details.localPosition, size);
                final last = controller.annotations.lastOrNull;
                switch (controller.tool) {
                  case DrawTool.pen:
                    if (last is PenStroke) {
                      last.points.add(point);
                      controller.notifyChanged();
                    }
                  case DrawTool.line:
                    if (last is LineAnnotation) {
                      last.end = point;
                      controller.notifyChanged();
                    }
                  case DrawTool.angle:
                    break;
                  case DrawTool.none:
                    _jogAccumulator += details.delta.dx;
                    final frames = _jogAccumulator ~/ _pixelsPerFrame;
                    if (frames != 0 && widget.onJogFrames != null) {
                      _jogAccumulator -= frames * _pixelsPerFrame;
                      widget.onJogFrames!(frames);
                    }
                }
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: _AnnotationPainter(controller.annotations),
              ),
            ),
          );
        });
      },
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
        ..strokeWidth = 3
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
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
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
