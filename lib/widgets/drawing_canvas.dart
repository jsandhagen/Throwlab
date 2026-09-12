import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../utils/time_format.dart';

enum DrawTool { none, pen, line, arrow, curvedArrow, circle, angle, timer }

/// Selectable pen thicknesses, thin → thick, in video-canvas pixels. The
/// middle one is the default.
const kStrokeWidths = [1.5, 3.0, 6.0];

/// Annotation colors, in the order the rail offers them: two rows of five,
/// the bright end of the wheel first because grass, sky and a red runway
/// are what a stroke has to carry against. Black is last and is there for
/// the one background the bright ones lose on — a white sky.
const kAnnotationColors = <({Color color, String name})>[
  (color: Colors.orangeAccent, name: 'Orange'),
  (color: Colors.yellowAccent, name: 'Yellow'),
  (color: Colors.lightGreenAccent, name: 'Green'),
  (color: Colors.cyanAccent, name: 'Cyan'),
  (color: Colors.white, name: 'White'),
  (color: Colors.redAccent, name: 'Red'),
  (color: Colors.pinkAccent, name: 'Pink'),
  (color: Colors.purpleAccent, name: 'Purple'),
  (color: Colors.blueAccent, name: 'Blue'),
  (color: Colors.black, name: 'Black'),
];

/// How much of a zoom the ink takes on. Annotations are painted inside the
/// zoom transform, so left alone a stroke thickens one-for-one — at 8x a
/// hairline is a 24 px slab covering the very detail it was drawn to point
/// at. The square root keeps ink growing with the picture, just slower: 4x
/// zoom doubles a stroke instead of quadrupling it.
double inkScaleFor(double zoomScale) =>
    zoomScale <= 1 ? 1 : math.sqrt(zoomScale);

/// The path with its last [distance] trimmed off, cut mid-segment where it
/// has to be. An arrow's shaft stops where its head begins: drawn to the tip
/// instead, the stroke's round cap bulges out past the head's point as a
/// blob, which is why the straight arrow shortens its line too.
List<Offset> trimPathEnd(List<Offset> points, double distance) {
  var remaining = distance;
  for (var i = points.length - 1; i > 0; i--) {
    final segment = points[i - 1] - points[i];
    final step = segment.distance;
    if (step >= remaining) {
      final cut =
          step == 0 ? points[i - 1] : points[i] + segment / step * remaining;
      return [...points.take(i), cut];
    }
    remaining -= step;
  }
  return [points.first];
}

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

/// A ring drawn out from its middle: press on what is being circled and
/// drag to the rim. Sizing a circle from the middle keeps the thing it is
/// about — a hip, a hand, where the implement landed — under the finger
/// that started it, which a corner-to-corner box does not.
///
/// [edge] is a point on the rim rather than a radius, because a radius is a
/// length and the two axes normalize by different amounts: stored as a
/// point, the ring is struck at the screen-space distance between the two
/// and stays round at any size of frame.
class CircleAnnotation extends Annotation {
  CircleAnnotation(super.color, super.width, this.center, this.edge);
  Offset center;
  Offset edge;
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

/// A stopwatch dropped on the frame: it holds the moment it was dropped at
/// and reads the gap from there to wherever the clip is now, so scrubbing
/// forward times a phase — block to release, ground contact, the delivery —
/// without anybody doing arithmetic on two frame numbers.
///
/// [from] is a position in the clip rather than a frame index, because that
/// is what the player reports and what the readout under the scrubber is
/// already counting in; a frame index would have to be converted back
/// through the clip's own frame times to be compared with it.
class TimerMarker extends Annotation {
  TimerMarker(super.color, super.width, this.at, this.from);

  /// Where the box sits on the frame, normalized like everything else.
  Offset at;

  /// The frame it was dropped on, which is the zero it counts from.
  final Duration from;
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
    final cosine = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
    return math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

/// One reversible edit to the drawing. The history is kept as edits rather
/// than as snapshots of the whole frame because annotations are mutable —
/// a line's end follows the finger, an angle grows a vertex at a time — so
/// a snapshot would have to deep-copy every stroke on every touch move.
sealed class _Edit {
  /// Puts the drawing back the way it was before this edit.
  void undo(List<Annotation> annotations);

  /// Does it again.
  void redo(List<Annotation> annotations);
}

/// An annotation was drawn. It is matched by identity, so the object the
/// drag went on mutating is the one that comes back.
class _Drawn extends _Edit {
  _Drawn(this.annotation);
  final Annotation annotation;

  @override
  void undo(List<Annotation> annotations) => annotations.remove(annotation);

  @override
  void redo(List<Annotation> annotations) => annotations.add(annotation);
}

/// A vertex joined an angle already on the frame, so tapping out an angle
/// comes back a point at a time rather than all three at once.
class _VertexPlaced extends _Edit {
  _VertexPlaced(this.angle, this.point);
  final AngleAnnotation angle;
  final Offset point;

  @override
  void undo(List<Annotation> annotations) => angle.points.removeLast();

  @override
  void redo(List<Annotation> annotations) => angle.points.add(point);
}

/// The frame was wiped. Undoing brings the lot back, which is what makes
/// clear worth a button of its own instead of a confirmation.
class _Wiped extends _Edit {
  _Wiped(this.annotations);
  final List<Annotation> annotations;

  @override
  void undo(List<Annotation> into) => into.addAll(annotations);

  @override
  void redo(List<Annotation> into) => into.clear();
}

class DrawingController extends ChangeNotifier {
  DrawTool _tool = DrawTool.none;
  Color _color = kAnnotationColors.first.color;
  double _strokeWidth = kStrokeWidths[1];
  final List<Annotation> _annotations = [];

  /// What has been done, oldest first, and what has been undone out of it,
  /// newest last. A fresh edit drops the redo stack — the usual rule, and
  /// the only one that can't leave a redo pointing at a frame that no
  /// longer exists.
  final List<_Edit> _done = [];
  final List<_Edit> _undone = [];

  DrawTool get tool => _tool;
  Color get color => _color;
  double get strokeWidth => _strokeWidth;
  List<Annotation> get annotations => List.unmodifiable(_annotations);

  bool get canUndo => _done.isNotEmpty;
  bool get canRedo => _undone.isNotEmpty;

  // The pen setters are no-ops when the value is already what was asked
  // for. The comparison screen mirrors one pane's pen onto the other
  // through a listener on each controller, and a notification for a
  // setting that did not change is a change bouncing back — which is a
  // loop with no end to it.

  set tool(DrawTool value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    notifyListeners();
  }

  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    notifyListeners();
  }

  void _record(_Edit edit) {
    edit.redo(_annotations);
    _done.add(edit);
    _undone.clear();
    notifyListeners();
  }

  void add(Annotation annotation) => _record(_Drawn(annotation));

  /// Adds [point] to an angle that is already on the frame.
  void placeAngleVertex(AngleAnnotation angle, Offset point) =>
      _record(_VertexPlaced(angle, point));

  /// A drag carried the annotation it started on somewhere new. That is the
  /// same edit going on, not another one, so it only repaints.
  void notifyChanged() => notifyListeners();

  /// Throws the edit in progress away without leaving it to be redone — a
  /// stroke a pinch turned out to be, which the user never meant to draw.
  void discardStroke() {
    if (_done.isEmpty) return;
    _done.removeLast().undo(_annotations);
    notifyListeners();
  }

  void undo() {
    if (_done.isEmpty) return;
    final edit = _done.removeLast()..undo(_annotations);
    _undone.add(edit);
    notifyListeners();
  }

  void redo() {
    if (_undone.isEmpty) return;
    final edit = _undone.removeLast()..redo(_annotations);
    _done.add(edit);
    notifyListeners();
  }

  void clear() {
    if (_annotations.isEmpty) return;
    _record(_Wiped(List.of(_annotations)));
  }
}

/// Starts whatever the active tool draws at normalized [point], and reports
/// whether an annotation was begun — a pinch that started life as a
/// one-finger drag undoes the stray stroke. The tap-driven angle tool (and
/// scrub-only mode) start nothing here.
bool beginAnnotation(DrawingController controller, Offset point) {
  switch (controller.tool) {
    case DrawTool.pen:
      controller
          .add(PenStroke(controller.color, controller.strokeWidth, [point]));
      return true;
    case DrawTool.line:
      controller.add(LineAnnotation(
          controller.color, controller.strokeWidth, point, point));
      return true;
    case DrawTool.arrow:
      // Tail where the drag starts, head where it ends.
      controller.add(ArrowAnnotation(
          controller.color, controller.strokeWidth, point, point));
      return true;
    case DrawTool.curvedArrow:
      controller.add(CurvedArrowAnnotation(
          controller.color, controller.strokeWidth, [point]));
      return true;
    case DrawTool.circle:
      // Middle where the press landed, rim where the drag gets to.
      controller.add(CircleAnnotation(
          controller.color, controller.strokeWidth, point, point));
      return true;
    case DrawTool.angle:
    case DrawTool.timer:
    case DrawTool.none:
      return false;
  }
}

/// Carries the annotation [beginAnnotation] started on to [point].
void extendAnnotation(DrawingController controller, Offset point) {
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
    case DrawTool.arrow:
      if (last is ArrowAnnotation) {
        last.end = point;
        controller.notifyChanged();
      }
    case DrawTool.curvedArrow:
      if (last is CurvedArrowAnnotation) {
        last.points.add(point);
        controller.notifyChanged();
      }
    case DrawTool.circle:
      if (last is CircleAnnotation) {
        last.edge = point;
        controller.notifyChanged();
      }
    case DrawTool.angle:
    case DrawTool.timer:
    case DrawTool.none:
      break;
  }
}

/// Adds a vertex to the angle being tapped out, beginning a new angle once
/// the last one has all three of its points.
void addAngleVertex(DrawingController controller, Offset point) {
  final last = controller.annotations.lastOrNull;
  if (last is AngleAnnotation && !last.isComplete) {
    controller.placeAngleVertex(last, point);
  } else {
    controller.add(AngleAnnotation(controller.color, controller.strokeWidth)
      ..points.add(point));
  }
}

/// Drops a timer at normalized [point], counting from [from] — the frame the
/// clip is showing as it is placed.
void dropTimer(DrawingController controller, Offset point, Duration from) =>
    controller.add(
        TimerMarker(controller.color, controller.strokeWidth, point, from));

/// Paint-only annotation layer stacked over the video player. Gestures are
/// handled by the screen, which owns a single recognizer for zooming,
/// scrubbing, drawing, and node dragging — separate competing recognizers
/// made pinch-zoom land unpredictably.
class DrawingCanvas extends StatelessWidget {
  const DrawingCanvas({
    super.key,
    required this.controller,
    this.zoomScale = 1,
    this.position = Duration.zero,
  });

  final DrawingController controller;

  /// The stage's current zoom, so ink can be drawn at a damped weight
  /// instead of blowing up with the picture (see [inkScaleFor]).
  final double zoomScale;

  /// Where the clip is now, which is what a [TimerMarker] counts to. It is
  /// the player's own position — the same one the frame readout under the
  /// scrubber is counting — so a box on the frame can never disagree with
  /// the numbers beside it.
  final Duration position;

  @override
  Widget build(BuildContext context) {
    // A painter builds its own TextSpans, which inherit nothing — left to
    // itself the canvas sets its labels in the engine's fallback face while
    // the rest of the app is in Barlow. Handing the theme's own style down
    // keeps them the same type without naming a family here.
    final labelStyle =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _AnnotationPainter(
              controller.annotations, zoomScale, position, labelStyle),
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter(
      this.annotations, this.zoomScale, this.position, this.labelStyle);

  final List<Annotation> annotations;
  final double zoomScale;
  final Duration position;

  /// The app's own type, for the two things on the canvas that are words
  /// rather than ink: an angle's reading and a timer's.
  final TextStyle labelStyle;

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
        case CircleAnnotation(:final center, :final edge):
          final middle = _denormalize(center, size);
          final radius = (_denormalize(edge, size) - middle).distance;
          // A press that never travelled is a tap, not a ring.
          if (radius < 1) continue;
          canvas.drawCircle(middle, radius, paint);
        case AngleAnnotation():
          _paintAngle(canvas, size, annotation, paint);
        case TimerMarker():
          _paintTimer(canvas, size, annotation);
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
    // The shaft stops where the head starts, so the stroke's round cap stays
    // under the filled head instead of poking through its point.
    final shaft = trimPathEnd(points, head);
    final delta = tip - shaft.last;
    if (delta.distance == 0) return;
    if (shaft.length >= 2) canvas.drawPath(smoothPath(shaft), paint);
    _paintHead(canvas, tip, delta / delta.distance, head, arrow.color);
  }

  /// Filled triangle pointing along [direction], its tip at [tip].
  void _paintHead(
      Canvas canvas, Offset tip, Offset direction, double length, Color color) {
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

  /// A small solid box reading the gap from the frame it was dropped on,
  /// centered on where it was put. Solid rather than translucent because it
  /// is read at a glance against whatever the frame happens to be, and set
  /// in tabular figures so the number doesn't jitter sideways as it counts.
  void _paintTimer(Canvas canvas, Size size, TimerMarker marker) {
    final label = TextPainter(
      text: TextSpan(
        text: formatDelta(position - marker.from),
        style: labelStyle.copyWith(
          color: marker.color,
          fontSize: _fixed(14),
          fontWeight: FontWeight.w600,
          // Tabular figures so the number doesn't shuffle sideways as it
          // counts, which on a box this small reads as a wobble.
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final padX = _fixed(8);
    final padY = _fixed(5);
    final box = Rect.fromCenter(
      center: _denormalize(marker.at, size),
      width: label.width + padX * 2,
      height: label.height + padY * 2,
    );
    final rounded = RRect.fromRectAndRadius(box, Radius.circular(_fixed(6)));
    canvas.drawRRect(rounded, Paint()..color = const Color(0xFF101214));
    canvas.drawRRect(
        rounded,
        Paint()
          ..color = marker.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ink(marker.width) * 0.6);
    label.paint(canvas, Offset(box.left + padX, box.top + padY));
  }

  void _paintAngle(
      Canvas canvas, Size size, AngleAnnotation angle, Paint paint) {
    final points = angle.points.map((p) => _denormalize(p, size)).toList();
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
          style: labelStyle.copyWith(
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
      textPainter.paint(canvas, points[1] + Offset(_fixed(10), _fixed(10)));
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter oldDelegate) => true;
}
