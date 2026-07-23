import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/javelin_detector.dart';
import '../services/video_library.dart';
import '../utils/frame_seeker.dart';
import '../utils/projectile.dart';
import '../utils/release_metrics.dart';
import '../utils/scrub.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/playback_controls.dart';

const kAnnotationColors = [
  Colors.orangeAccent,
  Colors.lightGreenAccent,
  Colors.cyanAccent,
  Colors.pinkAccent,
  Colors.white,
];

/// Typical release heights (m) used for the vacuum-ballistics predictions.
const _releaseHeights = {
  ThrowEvent.shotPut: 2.1,
  ThrowEvent.discus: 1.5,
  ThrowEvent.hammer: 1.2,
  ThrowEvent.javelin: 1.8,
};

enum _MeasureStep { refA, refB, refConfirm, pointA, pointB, review }

/// Single-throw breakdown: slow motion, frame stepping, drawing, and
/// tap-to-measure release metrics.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.video});

  final ThrowVideo video;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final VideoPlayerController _controller;
  late final FrameSeeker _seeker = FrameSeeker(_controller);
  final DrawingController _drawing = DrawingController();

  bool _openFailed = false;

  _MeasureStep? _measureStep;
  Offset? _refA, _refB, _pointA, _pointB;
  double _measureDt = 0;
  bool _detecting = false;

  /// Javelin tip/tail auto-detection failed once → plain tap flow.
  bool _manualJavelin = false;

  @override
  void initState() {
    super.initState();
    _openFailed = !File(widget.video.path).existsSync();
    _controller = VideoPlayerController.file(File(widget.video.path));
    if (!_openFailed) {
      _controller.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {
        if (mounted) setState(() => _openFailed = true);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _drawing.dispose();
    super.dispose();
  }

  /// Steps the video by [frames] while dragging across it in scrub mode.
  void _jogFrames(int frames) {
    _controller.pause();
    final step = Duration(
        microseconds: (Duration.microsecondsPerSecond / widget.video.fps)
            .round());
    _seeker.seekBy(step * frames);
  }

  // ---- Zoom + unified gestures ----
  //
  // One ScaleGestureRecognizer owns every touch on the video: two fingers
  // zoom/pan, one finger scrubs, draws, or drags a measurement/angle node.
  // (InteractiveViewer's own recognizer used to race the drawing layer's,
  // which made pinch-zoom land unpredictably.)

  /// Drag distance that advances the video by one frame in scrub mode,
  /// scaled to the clip's real frame duration like the wheel.
  double get _pixelsPerFrame =>
      scrubPixelsPerFrame(widget.video.captureFps);

  Size _viewport = Size.zero;
  double _zoomScale = 1;
  Offset _zoomOffset = Offset.zero;
  double _gestureStartScale = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;
  final ScrubAccumulator _scrub = ScrubAccumulator();
  bool _activeStroke = false;
  void Function(Offset canvasPoint)? _nodeDrag;

  /// Where the (aspect-fitted) video sits inside the viewport, pre-zoom.
  Rect get _videoRect {
    final ratio = _controller.value.aspectRatio;
    var w = _viewport.width;
    var h = w / ratio;
    if (h > _viewport.height) {
      h = _viewport.height;
      w = h * ratio;
    }
    return Rect.fromLTWH(
        (_viewport.width - w) / 2, (_viewport.height - h) / 2, w, h);
  }

  /// Screen position → position relative to the video's top-left corner,
  /// in the video's own (unzoomed) coordinates. All stored points live in
  /// this space, which is what makes measurements zoom-proof.
  Offset _toCanvas(Offset screen) =>
      (screen - _zoomOffset) / _zoomScale - _videoRect.topLeft;

  Offset _normalizeCanvas(Offset canvasPoint) {
    final r = _videoRect;
    return Offset((canvasPoint.dx / r.width).clamp(0.0, 1.0),
        (canvasPoint.dy / r.height).clamp(0.0, 1.0));
  }

  Offset _denormalizeCanvas(Offset normalized) {
    final r = _videoRect;
    return Offset(normalized.dx * r.width, normalized.dy * r.height);
  }

  Offset _clampToVideo(Offset p) {
    final r = _videoRect;
    return Offset(p.dx.clamp(0.0, r.width), p.dy.clamp(0.0, r.height));
  }

  /// Keeps the zoomed content covering the viewport (no gaps at edges).
  Offset _clampZoomOffset(Offset off, double scale) => Offset(
        off.dx.clamp(_viewport.width * (1 - scale), 0.0),
        off.dy.clamp(_viewport.height * (1 - scale), 0.0),
      );

  /// Finds a draggable node near [canvasPoint]: a measurement crosshair
  /// while measuring, or an angle-annotation point when the angle tool is
  /// active. Returns the setter that moves it, or null.
  void Function(Offset)? _hitTestNode(Offset canvasPoint) {
    var best = 28 / _zoomScale; // ~finger-sized in screen px
    if (_measureStep != null) {
      void Function(Offset)? hit;
      void check(Offset? p, void Function(Offset) move) {
        if (p == null) return;
        final d = (p - canvasPoint).distance;
        if (d < best) {
          best = d;
          hit = move;
        }
      }

      check(_refA, (p) => _refA = p);
      check(_refB, (p) => _refB = p);
      check(_pointA, (p) => _pointA = p);
      check(_pointB, (p) => _pointB = p);
      final found = hit;
      if (found == null) return null;
      return (p) => setState(() => found(p));
    }
    if (_drawing.tool == DrawTool.angle) {
      final r = _videoRect;
      AngleAnnotation? hitAnnotation;
      var hitIndex = 0;
      for (final annotation in _drawing.annotations) {
        if (annotation is! AngleAnnotation) continue;
        for (var i = 0; i < annotation.points.length; i++) {
          final p = Offset(annotation.points[i].dx * r.width,
              annotation.points[i].dy * r.height);
          final d = (p - canvasPoint).distance;
          if (d < best) {
            best = d;
            hitAnnotation = annotation;
            hitIndex = i;
          }
        }
      }
      if (hitAnnotation == null) return null;
      final annotation = hitAnnotation;
      return (p) {
        annotation.points[hitIndex] = _normalizeCanvas(p);
        _drawing.notifyChanged();
      };
    }
    return null;
  }

  void _onVideoTap(Offset screenPos) {
    if (_detecting) return;
    final canvasPoint = _toCanvas(screenPos);
    final r = _videoRect;
    if (canvasPoint.dx < 0 ||
        canvasPoint.dy < 0 ||
        canvasPoint.dx > r.width ||
        canvasPoint.dy > r.height) {
      return;
    }
    if (_measureStep != null) {
      _onMeasureTap(canvasPoint);
      return;
    }
    if (_drawing.tool == DrawTool.angle) {
      final point = _normalizeCanvas(canvasPoint);
      final last = _drawing.annotations.lastOrNull;
      if (last is AngleAnnotation && !last.isComplete) {
        last.points.add(point);
        _drawing.notifyChanged();
      } else {
        _drawing.add(AngleAnnotation(_drawing.color)..points.add(point));
      }
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _zoomScale;
    _gestureStartOffset = _zoomOffset;
    _gestureStartFocal = details.localFocalPoint;
    _nodeDrag = null;
    if (details.pointerCount > 1) {
      // A pinch that began as a one-finger drag: discard the stray stroke.
      if (_activeStroke) _drawing.undo();
      _activeStroke = false;
      return;
    }
    _activeStroke = false;
    final canvasPoint = _toCanvas(details.localFocalPoint);
    _nodeDrag = _hitTestNode(canvasPoint);
    if (_nodeDrag != null) return;
    if (_measureStep != null) {
      // While reviewing, free drags scrub so both frames can be checked.
      if (_measureStep == _MeasureStep.review) _scrub.reset();
      return;
    }
    switch (_drawing.tool) {
      case DrawTool.pen:
        _drawing
            .add(PenStroke(_drawing.color, [_normalizeCanvas(canvasPoint)]));
        _activeStroke = true;
      case DrawTool.line:
        final p = _normalizeCanvas(canvasPoint);
        _drawing.add(LineAnnotation(_drawing.color, p, p));
        _activeStroke = true;
      case DrawTool.angle:
        break;
      case DrawTool.none:
        _scrub.reset();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      final scale =
          (_gestureStartScale * details.scale).clamp(1.0, 8.0);
      // Keep the content point that started under the fingers under them.
      final anchor =
          (_gestureStartFocal - _gestureStartOffset) / _gestureStartScale;
      setState(() {
        _zoomScale = scale;
        _zoomOffset = _clampZoomOffset(
            details.localFocalPoint - anchor * scale, scale);
      });
      return;
    }
    final canvasPoint = _toCanvas(details.localFocalPoint);
    if (_nodeDrag != null) {
      _nodeDrag!(_clampToVideo(canvasPoint));
      return;
    }
    if (_measureStep != null) {
      if (_measureStep == _MeasureStep.review) {
        _jogBy(details.focalPointDelta.dx, details.sourceTimeStamp);
      }
      return;
    }
    final last = _drawing.annotations.lastOrNull;
    switch (_drawing.tool) {
      case DrawTool.pen:
        if (_activeStroke && last is PenStroke) {
          last.points.add(_normalizeCanvas(canvasPoint));
          _drawing.notifyChanged();
        }
      case DrawTool.line:
        if (_activeStroke && last is LineAnnotation) {
          last.end = _normalizeCanvas(canvasPoint);
          _drawing.notifyChanged();
        }
      case DrawTool.angle:
        break;
      case DrawTool.none:
        _jogBy(details.focalPointDelta.dx, details.sourceTimeStamp);
    }
  }

  /// Jog by screen-space drag distance so scrubbing feels the same at any
  /// zoom level, accelerating the frame step with drag speed.
  void _jogBy(double dx, Duration? timestamp) {
    final frames =
        _scrub.addDrag(dx, _pixelsPerFrame, timestamp: timestamp);
    if (frames != 0) _jogFrames(frames);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _nodeDrag = null;
  }

  /// Read/edit the throw's note without leaving the video.
  Future<void> _editNote() async {
    final controller = TextEditingController(text: widget.video.note);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'e.g. "PB attempt, slight headwind"'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    widget.video.note = note.trim();
    await context.read<VideoLibrary>().update(widget.video);
    if (mounted) setState(() {});
  }

  Future<void> _editFps() async {
    final fieldController = TextEditingController(
        text: widget.video.captureFps.toStringAsFixed(0));
    final fps = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recorded frame rate'),
        content: TextField(
          controller: fieldController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'capture fps',
            helperText: 'Auto-detected on import; override if the '
                'slow-mo rate was read wrong (usually 120 or 240)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
                context, double.tryParse(fieldController.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (fps != null && fps > 0) {
      widget.video.captureFps = fps;
      if (mounted) {
        await context.read<VideoLibrary>().update(widget.video);
        setState(() {});
      }
    }
  }

  // ---- Release measurement ----

  bool get _isJavelin => widget.video.event == ThrowEvent.javelin;

  String get _refWord => switch (widget.video.event) {
        ThrowEvent.discus => 'disc',
        ThrowEvent.javelin => 'javelin',
        _ => 'ball',
      };

  String get _measureInstruction => switch (_measureStep!) {
        _MeasureStep.refA => _isJavelin
            ? (_manualJavelin
                ? 'Pause on the release frame, then tap the javelin TIP'
                : 'Pause on the release frame, then tap near the javelin '
                    'TIP')
            : 'Pause on the release frame, then tap one edge of the '
                '$_refWord',
        _MeasureStep.refConfirm =>
          'Drag the tip/tail markers to fine-tune (re-tap near the tip to '
              'retry), then tap Next',
        _MeasureStep.refB => _isJavelin
            ? 'Now tap the javelin TAIL'
            : 'Tap the opposite edge of the $_refWord',
        _MeasureStep.pointA => _isJavelin
            ? 'Jumped ${(_measureDt * 1000).round()} ms forward — tap '
                'the javelin TIP again'
            : 'Tap the center of the $_refWord',
        _MeasureStep.pointB => _isJavelin
            ? 'Now tap the javelin TAIL again'
            : 'Jumped ${(_measureDt * 1000).round()} ms forward — tap the '
                'same spot on the $_refWord again',
        _MeasureStep.review =>
          'Drag any marker to fine-tune, then tap Calculate',
      };

  void _startMeasure() {
    if (!_controller.value.isInitialized) return;
    _controller.pause();
    setState(() {
      _refA = _refB = _pointA = _pointB = null;
      _detecting = false;
      _manualJavelin = false;
      _measureStep = _MeasureStep.refA;
    });
  }

  void _cancelMeasure() {
    setState(() {
      _measureStep = null;
      _detecting = false;
      _refA = _refB = _pointA = _pointB = null;
    });
  }

  /// Frames spanning ~100 ms of real time. File frames each represent
  /// 1/captureFps s.
  int get _jumpFrames =>
      math.max(2, (widget.video.captureFps * 0.1).round());

  /// Jumps forward ~100 ms of REAL time so the speed math uses the same dt
  /// regardless of frame rate. The longer baseline (vs 50 ms) halves
  /// marker-noise error; the midpoint gravity correction in the metrics
  /// removes the path-curvature cost of the wider interval.
  void _jumpForward() {
    _measureDt = _jumpFrames / widget.video.captureFps;
    _jogFrames(_jumpFrames);
  }

  void _onMeasureTap(Offset position) {
    switch (_measureStep!) {
      case _MeasureStep.refA:
        if (_isJavelin && !_manualJavelin) {
          _autoDetectRef(position);
          return;
        }
        setState(() {
          _refA = position;
          _measureStep = _MeasureStep.refB;
        });
      case _MeasureStep.refConfirm:
        // A re-tap re-runs detection seeded from the new tap, for when
        // the first attempt latched onto the wrong edge.
        _autoDetectRef(position);
      case _MeasureStep.refB:
        // Javelin re-taps tip and tail on the later frame, so the jump
        // happens as soon as the release-frame pair is done.
        if (_isJavelin) _jumpForward();
        setState(() {
          _refB = position;
          _measureStep = _MeasureStep.pointA;
        });
      case _MeasureStep.pointA:
        if (!_isJavelin) _jumpForward();
        setState(() {
          _pointA = position;
          _measureStep = _MeasureStep.pointB;
        });
      case _MeasureStep.pointB:
        setState(() {
          _pointB = position;
          _measureStep = _MeasureStep.review;
        });
      case _MeasureStep.review:
        break; // Markers are adjusted by dragging, not tapping.
    }
  }

  /// Runs tip/tail detection on the release frame, seeded by a tap near
  /// the tip. On failure the flow falls back to manual taps, reusing the
  /// tap as the TIP.
  Future<void> _autoDetectRef(Offset canvasPoint) async {
    setState(() => _detecting = true);
    JavelinDetection? found;
    try {
      found = await JavelinDetector.detect(
        videoPath: widget.video.path,
        position: await _seeker.freshPosition(),
        nearPoint: _normalizeCanvas(canvasPoint),
      );
    } catch (_) {
      found = null;
    }
    if (!mounted ||
        (_measureStep != _MeasureStep.refA &&
            _measureStep != _MeasureStep.refConfirm)) {
      return;
    }
    setState(() {
      _detecting = false;
      if (found == null) {
        _manualJavelin = true;
        _refA = canvasPoint;
        _refB = null;
        _measureStep = _MeasureStep.refB;
      } else {
        _refA = _denormalizeCanvas(found.tip);
        _refB = _denormalizeCanvas(found.tail);
        _measureStep = _MeasureStep.refConfirm;
      }
    });
    if (found == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't spot the javelin — your tap marks the "
              'TIP; now tap the TAIL')));
    }
  }

  /// Confirms the (possibly hand-adjusted) release markers, jumps the
  /// measurement interval, and re-finds the shaft on the new frame.
  Future<void> _confirmRefAndJump() async {
    final tip = _refA, tail = _refB;
    if (tip == null || tail == null) return;
    setState(() => _detecting = true);
    final pos = await _seeker.freshPosition();
    _jumpForward();
    // Extract the target frame directly rather than waiting on the
    // player's seek; both land on the same frame.
    final target = pos +
        Duration(
            microseconds: (_jumpFrames *
                    Duration.microsecondsPerSecond /
                    widget.video.fps)
                .round());
    JavelinDetection? found;
    try {
      found = await JavelinDetector.detect(
        videoPath: widget.video.path,
        position: target,
        previousTip: _normalizeCanvas(tip),
        previousTail: _normalizeCanvas(tail),
      );
    } catch (_) {
      found = null;
    }
    if (!mounted || _measureStep != _MeasureStep.refConfirm) return;
    setState(() {
      _detecting = false;
      if (found == null) {
        _measureStep = _MeasureStep.pointA; // manual re-tap flow
      } else {
        _pointA = _denormalizeCanvas(found.tip);
        _pointB = _denormalizeCanvas(found.tail);
        _measureStep = _MeasureStep.review;
      }
    });
    if (found == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't re-find the javelin on this frame — "
              'tap its TIP again')));
    }
  }

  void _showResults() {
    final metrics = computeReleaseMetrics(
      refA: _refA!,
      refB: _refB!,
      pointA: _pointA!,
      pointB: _pointB!,
      referenceMeters: widget.video.implementSpec.nominalSize,
      dtSeconds: _measureDt,
      javelin: _isJavelin,
    );
    final event = widget.video.event;
    final ballistic =
        event == ThrowEvent.shotPut || event == ThrowEvent.hammer;
    final height = _releaseHeights[event]!;
    final optimal =
        optimalAngleDeg(metrics.speed, releaseHeight: height);
    final lost = distanceLostToAngle(
        metrics.speed, metrics.releaseAngleDeg,
        releaseHeight: height);
    final predicted = predictedDistance(
        metrics.speed, metrics.releaseAngleDeg,
        releaseHeight: height);
    final attack = metrics.attackAngleDeg;

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Release metrics',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _metricRow('Release speed',
                  '~${metrics.speed.toStringAsFixed(1)} m/s'),
              _metricRow('Release angle',
                  '${metrics.releaseAngleDeg.toStringAsFixed(1)}°'),
              if (attack != null)
                _metricRow(
                    'Angle of attack',
                    '${attack >= 0 ? '+' : ''}${attack.toStringAsFixed(1)}° '
                        '(nose ${attack >= 0 ? 'up' : 'down'})'),
              if (ballistic) ...[
                _metricRow('Predicted distance',
                    '~${predicted.toStringAsFixed(2)} m'),
                _metricRow('Optimal angle',
                    '${optimal.toStringAsFixed(1)}°'),
                _metricRow('Lost to angle',
                    '${lost.toStringAsFixed(2)} m'),
              ],
              const SizedBox(height: 8),
              Text(
                ballistic
                    ? 'Estimates assume a side-on tripod and '
                        '~${height.toStringAsFixed(1)} m release height.'
                    : 'Distance prediction is skipped for '
                        '${event.label.toLowerCase()} — aerodynamic '
                        'lift/drag isn\'t modeled yet. Estimates assume '
                        'a side-on tripod.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _saveToNote(metrics),
                    child: const Text('Save to note'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(_cancelMeasure);
  }

  Widget _metricRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _saveToNote(ReleaseMetrics metrics) async {
    final attack = metrics.attackAngleDeg;
    final summary = '~${metrics.speed.toStringAsFixed(1)} m/s @ '
        '${metrics.releaseAngleDeg.toStringAsFixed(1)}°'
        '${attack == null ? '' : ', AoA ${attack >= 0 ? '+' : ''}${attack.toStringAsFixed(1)}°'}';
    widget.video.note = widget.video.note.isEmpty
        ? summary
        : '${widget.video.note} · $summary';
    await context.read<VideoLibrary>().update(widget.video);
    if (mounted) {
      setState(() {}); // note icon switches to "has a note"
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to note: $summary')));
    }
  }

  Widget _videoArea() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _openFailed || _controller.value.hasError
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Couldn\'t open this video — the file may have '
                'been removed from the device. Delete this entry '
                'and re-import the clip.',
                textAlign: TextAlign.center,
              ),
            )
          : _controller.value.isInitialized
              ? LayoutBuilder(builder: (context, constraints) {
                  _viewport = constraints.biggest;
                  // Re-clamp in case the viewport changed (e.g. rotation).
                  final offset = _clampZoomOffset(_zoomOffset, _zoomScale);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _onVideoTap(details.localPosition),
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: ClipRect(
                      child: Transform(
                        transform: Matrix4.identity()
                          ..translate(offset.dx, offset.dy)
                          ..scale(_zoomScale),
                        child: SizedBox(
                          width: _viewport.width,
                          height: _viewport.height,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _controller.value.aspectRatio,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  VideoPlayer(_controller),
                                  DrawingCanvas(controller: _drawing),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      size: Size.infinite,
                                      painter: _MeasurePainter(
                                        refA: _refA,
                                        refB: _refB,
                                        pointA: _pointA,
                                        pointB: _pointB,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                })
              : const CircularProgressIndicator(),
    );
  }

  /// Back button, title, and the measure/fps actions, with the measurement
  /// instruction banner underneath while measuring. Portrait gets a
  /// full-width scrim; landscape gets a compact top-left pill so the short
  /// screen keeps the video (and its upper-right action area) visible.
  Widget _topOverlay() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final title = Text(
      '${widget.video.event.label} · '
      '${widget.video.gender.label}',
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final actions = [
      IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      if (landscape)
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220), child: title)
      else
        Expanded(child: title),
      IconButton(
        tooltip: widget.video.note.isEmpty ? 'Add note' : 'Note',
        icon: Icon(widget.video.note.isEmpty
            ? Icons.note_add_outlined
            : Icons.sticky_note_2),
        onPressed: _editNote,
      ),
      IconButton(
        tooltip: 'Measure release (speed & angles)',
        icon: const Icon(Icons.speed),
        onPressed: _measureStep == null ? _startMeasure : null,
      ),
      IconButton(
        tooltip:
            'Set capture frame rate (${widget.video.captureFps.toStringAsFixed(0)} fps)',
        icon: const Icon(Icons.shutter_speed),
        onPressed: _editFps,
      ),
    ];
    final banner = _measureStep == null
        ? null
        : Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            // Landscape shows the instructions as a pill beside the
            // header pill instead of a full-width band over the video.
            borderRadius: landscape ? BorderRadius.circular(24) : null,
            clipBehavior: landscape ? Clip.antiAlias : Clip.none,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize:
                    landscape ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (_detecting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.straighten, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: landscape ? FlexFit.loose : FlexFit.tight,
                    child: Text(
                        _detecting
                            ? 'Finding the javelin…'
                            : _measureInstruction,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  TextButton(
                    onPressed: _cancelMeasure,
                    child: const Text('Cancel'),
                  ),
                  if (_measureStep == _MeasureStep.refConfirm)
                    FilledButton(
                      onPressed: _detecting ? null : _confirmRefAndJump,
                      child: const Text('Next'),
                    ),
                  if (_measureStep == _MeasureStep.review)
                    FilledButton(
                      onPressed: _showResults,
                      child: const Text('Calculate'),
                    ),
                ],
              ),
            ),
          );

    if (landscape) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 4, right: 4),
          child: Row(
            children: [
              Material(
                color:
                    Theme.of(context).colorScheme.surface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
              if (banner != null) ...[
                const SizedBox(width: 8),
                Flexible(child: banner),
              ],
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: actions),
            if (banner != null) banner,
          ],
        ),
      ),
    );
  }

  /// Bottom scrim: calibration hint, scrubber, and transport controls.
  /// Landscape drops the hint and lays the controls on one line to give
  /// the short screen back to the video.
  Widget _bottomOverlay(ImplementSpec spec) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!landscape)
              Text(
                'Ref: ${spec.referenceLabel.toLowerCase()} '
                '${(spec.nominalSize * 100).toStringAsFixed(1)} cm '
                '· drag video to scrub · pinch to zoom',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            PlaybackControls(
              controller: _controller,
              fps: widget.video.fps,
              captureFps: widget.video.captureFps,
              dense: true,
              horizontal: landscape,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Coach's Eye-style layout: the video owns the whole screen and the
    // controls float over it — transport along the bottom, a collapsible
    // drawing rail on the right.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _videoArea()),
          Positioned(top: 0, left: 0, right: 0, child: _topOverlay()),
          Positioned(
            top: 0,
            right: 4,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                // Hugs the bottom-right corner: the throw action lives in
                // the right-center and upper-right of the frame, and the
                // inset keeps it clear of the scrubber/transport overlay
                // (a single shorter row in landscape).
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 76
                        : 150),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: SingleChildScrollView(
                    reverse: true,
                    child: _DrawingRail(controller: _drawing),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomOverlay(widget.video.implementSpec),
          ),
        ],
      ),
    );
  }
}

/// Crosshairs and guide lines for the four measurement taps.
class _MeasurePainter extends CustomPainter {
  _MeasurePainter({this.refA, this.refB, this.pointA, this.pointB});

  final Offset? refA, refB, pointA, pointB;

  @override
  void paint(Canvas canvas, Size size) {
    final refPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    void crosshair(Offset p, Paint paint) {
      canvas.drawCircle(p, 9, paint);
      canvas.drawLine(p - const Offset(14, 0), p - const Offset(4, 0), paint);
      canvas.drawLine(p + const Offset(4, 0), p + const Offset(14, 0), paint);
      canvas.drawLine(p - const Offset(0, 14), p - const Offset(0, 4), paint);
      canvas.drawLine(p + const Offset(0, 4), p + const Offset(0, 14), paint);
      // Filled center dot over a dark halo: the exact measured point,
      // readable against both bright sky and the implement itself.
      canvas.drawCircle(p, 3, Paint()..color = Colors.black54);
      canvas.drawCircle(p, 1.8, Paint()..color = paint.color);
    }

    // Lines first so the precise center dots stay visible on top.
    if (refA != null && refB != null) {
      canvas.drawLine(refA!, refB!, refPaint);
    }
    if (pointA != null && pointB != null) {
      canvas.drawLine(pointA!, pointB!, pointPaint);
    }
    if (refA != null) crosshair(refA!, refPaint);
    if (refB != null) crosshair(refB!, refPaint);
    if (pointA != null) crosshair(pointA!, pointPaint);
    if (pointB != null) crosshair(pointB!, pointPaint);
  }

  @override
  bool shouldRepaint(_MeasurePainter oldDelegate) =>
      refA != oldDelegate.refA ||
      refB != oldDelegate.refB ||
      pointA != oldDelegate.pointA ||
      pointB != oldDelegate.pointB;
}

/// Vertical, collapsible tool rail anchored to the bottom-right corner of
/// the video: drawing tools, colors, undo/clear. The bottom arrow collapses
/// it to a single button in the same corner, keeping the right-center and
/// upper-right of the frame — where the throw happens — unobstructed.
class _DrawingRail extends StatefulWidget {
  const _DrawingRail({required this.controller});

  final DrawingController controller;

  @override
  State<_DrawingRail> createState() => _DrawingRailState();
}

class _DrawingRailState extends State<_DrawingRail> {
  bool _open = true;

  DrawingController get controller => widget.controller;

  static const _tools = [
    (DrawTool.none, Icons.pan_tool_alt, 'Scrub only'),
    (DrawTool.pen, Icons.draw, 'Freehand pen'),
    (DrawTool.line, Icons.timeline, 'Straight line'),
    (DrawTool.angle, Icons.square_foot, 'Angle (tap 3 points, vertex second)'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Material(
        color: scheme.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: !_open
                ? [
                    IconButton(
                      tooltip: 'Drawing tools',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.draw),
                      onPressed: () => setState(() => _open = true),
                    ),
                  ]
                : [
                    for (final (tool, icon, tip) in _tools)
                      IconButton(
                        tooltip: tip,
                        visualDensity: VisualDensity.compact,
                        isSelected: controller.tool == tool,
                        style: controller.tool == tool
                            ? IconButton.styleFrom(
                                backgroundColor: scheme.primaryContainer)
                            : null,
                        icon: Icon(icon),
                        onPressed: () => controller.tool = tool,
                      ),
                    const SizedBox(height: 6),
                    for (final color in kAnnotationColors)
                      GestureDetector(
                        onTap: () => controller.color = color,
                        child: Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: controller.color == color
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    IconButton(
                      tooltip: 'Undo',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.undo),
                      onPressed: controller.undo,
                    ),
                    IconButton(
                      tooltip: 'Clear drawings',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.layers_clear),
                      onPressed: controller.clear,
                    ),
                    IconButton(
                      tooltip: 'Hide tools',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => setState(() => _open = false),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
