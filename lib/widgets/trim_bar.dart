import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/clip_trim.dart';
import 'playback_controls.dart';

/// The whole clip as a strip of its own stills, with the part being kept
/// framed between two handles.
///
/// Stills rather than a bare line, because where a throw starts and ends is
/// picked by looking — the athlete stepping into the ring, the implement
/// landing — and a line says nothing about which second is which. The part
/// cut off stays in view, darkened, so it is plain what is going.
///
/// A drag that starts on a handle moves that end; anywhere else it moves
/// the playhead, as the clip line does. The release is notched in the
/// medal's gold, as it is on the clip line, so a cut that would take it off
/// is seen before it is made.
class TrimBar extends StatefulWidget {
  const TrimBar({
    super.key,
    required this.range,
    required this.frame,
    required this.onFirst,
    required this.onLast,
    required this.onSeek,
    this.release,
    this.stills = const [],
    this.height = 56,
  });

  final TrimRange range;

  /// The frame on screen, where the playhead is drawn.
  final int frame;
  final ValueChanged<int> onFirst;
  final ValueChanged<int> onLast;
  final ValueChanged<int> onSeek;

  /// The release frame, or null when none is marked.
  final int? release;

  /// Stills evenly across the clip, first to last; empty draws a plain
  /// track, for a clip whose stills are not cut yet.
  final List<String> stills;
  final double height;

  /// Room either side of the strip for a handle standing outside it.
  static const double handle = 16;

  @override
  State<TrimBar> createState() => _TrimBarState();
}

enum _Grip { first, last, playhead }

class _TrimBarState extends State<TrimBar> {
  _Grip? _grip;

  int _frameAt(double dx, double width) {
    final span = width - 2 * TrimBar.handle;
    if (span <= 0) return 0;
    final t = ((dx - TrimBar.handle) / span).clamp(0.0, 1.0);
    return (t * widget.range.frameCount)
        .floor()
        .clamp(0, widget.range.frameCount - 1);
  }

  double _xOf(int frame, double width) {
    final span = width - 2 * TrimBar.handle;
    return TrimBar.handle + span * frame / widget.range.frameCount;
  }

  void _start(double dx, double width) {
    final range = widget.range;
    final left = _xOf(range.first, width) - TrimBar.handle / 2;
    final right = _xOf(range.last + 1, width) + TrimBar.handle / 2;
    // A handle is hit generously — a thumb is wider than it — and when the
    // two are close together the nearer one wins, so a kept stretch of a
    // few frames can still be widened from either end.
    const reach = 24.0;
    final toLeft = (dx - left).abs();
    final toRight = (dx - right).abs();
    if (toLeft <= reach || toRight <= reach) {
      _grip = toLeft <= toRight ? _Grip.first : _Grip.last;
    } else {
      _grip = _Grip.playhead;
    }
    _move(dx, width);
  }

  void _move(double dx, double width) {
    final frame = _frameAt(dx, width);
    switch (_grip) {
      case _Grip.first:
        widget.onFirst(frame);
      case _Grip.last:
        widget.onLast(frame);
      case _Grip.playhead:
        widget.onSeek(frame);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          key: const ValueKey('trim-bar'),
          behavior: HitTestBehavior.opaque,
          // A tap only ever moves the playhead: a handle nudged by a tap
          // that meant to look at a frame is a cut nobody asked for.
          onTapUp: (d) => widget.onSeek(_frameAt(d.localPosition.dx, width)),
          onHorizontalDragStart: (d) => _start(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _move(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _grip = null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    TrimBar.handle, 10, TrimBar.handle, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: widget.stills.isEmpty
                      ? ColoredBox(color: Colors.white.withOpacity(0.12))
                      : Row(
                          children: [
                            for (final still in widget.stills)
                              Expanded(
                                child: Image.file(
                                  File(still),
                                  fit: BoxFit.cover,
                                  height: double.infinity,
                                  cacheHeight: 96,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                      color: Colors.white.withOpacity(0.12)),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              CustomPaint(
                painter: _TrimPainter(
                  range: widget.range,
                  frame: widget.frame,
                  release: widget.release,
                  frameColor: scheme.primary,
                  gripColor: scheme.onPrimary,
                  releaseColor: releaseColor,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TrimPainter extends CustomPainter {
  _TrimPainter({
    required this.range,
    required this.frame,
    required this.release,
    required this.frameColor,
    required this.gripColor,
    required this.releaseColor,
  });

  final TrimRange range;
  final int frame;
  final int? release;
  final Color frameColor, gripColor, releaseColor;

  @override
  void paint(Canvas canvas, Size size) {
    const h = TrimBar.handle;
    final span = size.width - 2 * h;
    if (span <= 0) return;
    double xOf(int f) => h + span * f / range.frameCount;
    const top = 10.0;
    final bottom = size.height - 4;
    final left = xOf(range.first);
    final right = xOf(range.last + 1);

    // What is going: the strip darkened either side of what is kept.
    final shade = Paint()..color = Colors.black.withOpacity(0.62);
    canvas.drawRect(Rect.fromLTRB(h, top, left, bottom), shade);
    canvas.drawRect(Rect.fromLTRB(right, top, size.width - h, bottom), shade);

    // What is kept: a frame round it, thick at the ends where the handles
    // are, so it reads as one thing held at both ends.
    final frameFill = Paint()..color = frameColor;
    canvas.drawRect(Rect.fromLTRB(left, top, right, top + 2.5), frameFill);
    canvas.drawRect(
        Rect.fromLTRB(left, bottom - 2.5, right, bottom), frameFill);
    final leftGrip = RRect.fromRectAndCorners(
      Rect.fromLTRB(left - h, top, left, bottom),
      topLeft: const Radius.circular(5),
      bottomLeft: const Radius.circular(5),
    );
    final rightGrip = RRect.fromRectAndCorners(
      Rect.fromLTRB(right, top, right + h, bottom),
      topRight: const Radius.circular(5),
      bottomRight: const Radius.circular(5),
    );
    canvas.drawRRect(leftGrip, frameFill);
    canvas.drawRRect(rightGrip, frameFill);
    final grip = Paint()
      ..color = gripColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final mid = (top + bottom) / 2;
    for (final x in [left - h / 2, right + h / 2]) {
      canvas.drawLine(Offset(x, mid - 7), Offset(x, mid + 7), grip);
    }

    // The release, notched above the strip the way the clip line notches it.
    final r = release;
    if (r != null) {
      final x = xOf(r) + span / range.frameCount / 2;
      final path = Path()
        ..moveTo(x - 4, 0)
        ..lineTo(x + 4, 0)
        ..lineTo(x, top - 2)
        ..close();
      canvas.drawPath(path, Paint()..color = releaseColor);
    }

    // The playhead, on the middle of the frame on screen.
    final at = xOf(frame) + span / range.frameCount / 2;
    canvas.drawLine(
      Offset(at, top - 2),
      Offset(at, bottom + 2),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TrimPainter old) =>
      range != old.range ||
      frame != old.frame ||
      release != old.release ||
      frameColor != old.frameColor;
}
