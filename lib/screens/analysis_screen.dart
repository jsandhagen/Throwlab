import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/javelin_detector.dart';
import '../services/video_library.dart';
import '../services/video_optimizer.dart';
import '../utils/frame_seeker.dart';
import '../utils/projectile.dart';
import '../utils/release_metrics.dart';
import '../utils/scrub.dart';
import '../utils/scrub_frames.dart';
import '../utils/scrub_shuttle.dart';
import '../widgets/athlete_picker.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/drawing_rail.dart';
import '../widgets/event_glyph.dart';
import '../widgets/playback_controls.dart';
import '../widgets/scrub_still.dart';
import '../widgets/throw_picker.dart';
import 'comparison_screen.dart';

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
  const AnalysisScreen({
    super.key,
    required this.video,
    this.siblings = const [],
  });

  final ThrowVideo video;

  /// The throws [video] was opened alongside — one athlete's, or one
  /// event's. Given them, the screen pages through the set instead of
  /// making a coach walk back to the library between throws of the same
  /// session. Empty means "on its own"; [video] is folded in either way,
  /// so a caller can hand over a whole group without first checking that
  /// it contains this throw.
  final List<ThrowVideo> siblings;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late final VideoPlayerController _controller;
  late final FrameSeeker _seeker = FrameSeeker(_controller);
  final DrawingController _drawing = DrawingController();

  /// Pre-extracted stills shown while dragging so scrubbing stays smooth
  /// regardless of the codec's seek cost; null when the clip has none.
  ScrubFrames? _frames;

  /// The smooth-scrub path — still overlay, shuttle, handoff — shared with
  /// the comparison screen so a drag behaves the same on both. Built in
  /// initState, not lazily: it owns a ticker, and a screen closed without
  /// ever scrubbing would otherwise create that ticker inside dispose(),
  /// when looking up the TickerMode is illegal.
  late final ScrubShuttle _shuttle;

  /// Frames are being extracted for a clip imported before the feature; the
  /// scrub overlay switches on once ready.
  bool _preparingFrames = false;

  bool _openFailed = false;

  /// Every throw in the set, oldest first, so the count a coach reads
  /// ("3 of 8") follows the order the session was thrown rather than the
  /// order the library happens to hold. Clips that share a timestamp — a
  /// whole session imported at once, none of it carrying camera metadata —
  /// fall back to id order, which at least keeps the numbering stable
  /// between visits instead of shuffling on every sort.
  late final List<ThrowVideo> _set = _orderedSet();

  final ScrollController _strip = ScrollController();

  /// A filmstrip cell plus its gap. The ListView's itemExtent and the
  /// centring maths below have to agree, so they read it from here.
  static const double _stripExtent = 72;

  /// How much height the filmstrip costs the bottom overlay — the drawing
  /// rail is inset by it too, so the tools stay clear of the stills.
  static const double _stripHeight = 52;

  _MeasureStep? _measureStep;
  Offset? _refA, _refB, _pointA, _pointB;
  double _measureDt = 0;
  bool _detecting = false;

  /// Javelin tip/tail auto-detection failed once → plain tap flow.
  bool _manualJavelin = false;

  @override
  void initState() {
    super.initState();
    // Without this, opening throw 7 of 8 leaves the strip scrolled to the
    // start, showing everything except the throw actually on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreStrip());
    _openFailed = !File(widget.video.path).existsSync();
    _controller = VideoPlayerController.file(File(widget.video.path));
    final framesDir = widget.video.scrubFramesDir;
    if (framesDir != null && widget.video.scrubFrameCount > 0) {
      _frames = ScrubFrames(
        dir: framesDir,
        count: widget.video.scrubFrameCount,
        stride: widget.video.scrubFrameStride,
        fps: widget.video.fps,
      )..loadTimes(VideoOptimizer.framesTimesFile);
    }
    _shuttle = ScrubShuttle(
      controller: _controller,
      seeker: _seeker,
      fps: widget.video.fps,
      vsync: this,
      frames: _frames,
    );
    if (!_openFailed) {
      _controller.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {
        if (mounted) setState(() => _openFailed = true);
      });
      if (_frames == null ||
          widget.video.scrubFramesVersion <
              VideoOptimizer.scrubFramesVersion ||
          widget.video.playbackVersion < VideoOptimizer.playbackVersion) {
        _prepareScrubFrames();
      }
    }
  }

  /// True once nothing has scrubbed for a clear stretch, so a resolution
  /// upgrade can run without stealing CPU from an active scrub. Returns false
  /// (having waited) whenever a scrub interrupts the stretch, so the caller
  /// can poll it in a loop.
  Future<bool> _idleForUpgrade() async {
    const quiet = Duration(milliseconds: 400);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(quiet);
      if (!mounted) return true;
      if (_shuttle.busy) return false;
    }
    return true;
  }

  /// Extracts scrub frames for a clip imported before the feature existed,
  /// and re-extracts when the stored stills predate the current resolution
  /// cap — the old set keeps serving scrubs until the new one is ready.
  /// Best-effort: on failure whatever scrub path exists stays.
  Future<void> _prepareScrubFrames() async {
    final library = context.read<VideoLibrary>();
    // Called from initState, so set the flag directly — the first build picks
    // it up, and setState is only used once we're past initState (below).
    _preparingFrames = true;
    // An upgrade competes with a scrub it isn't needed for: the clip already
    // has usable stills, while ffmpeg re-encoding at full resolution saturates
    // the CPU the shuttle needs to decode them. Hold off until the scrub
    // settles. A clip with no stills at all skips the wait — its scrubbing is
    // bad until this finishes, so sooner is better.
    if (_frames != null) {
      while (mounted && !await _idleForUpgrade()) {}
      if (!mounted) return;
    }
    // Bring the playback copy up to the current recipe first: the stills are
    // extracted *from* it, so re-extracting against a stale copy would just
    // reproduce the mismatch. Only clips with genuinely non-square pixels are
    // re-encoded — the rest cost one probe — and the current player keeps
    // showing the old file until the screen is reopened, so a scrub in flight
    // is never pulled out from under the finger.
    if (widget.video.playbackVersion < VideoOptimizer.playbackVersion) {
      final remade = await VideoOptimizer.remakePlaybackCopy(
          widget.video.path, widget.video.id);
      if (!mounted) return;
      if (remade != null) widget.video.path = remade;
      widget.video.playbackVersion = VideoOptimizer.playbackVersion;
      await library.update(widget.video);
    }
    final result = await VideoOptimizer.extractScrubFrames(
        widget.video.path, widget.video.id, widget.video.fps);
    if (result == null) {
      if (mounted) setState(() => _preparingFrames = false);
      return;
    }
    widget.video.scrubFramesDir = result.dir;
    widget.video.scrubFrameCount = result.count;
    widget.video.scrubFrameStride = result.stride;
    widget.video.scrubFrameLongSide = VideoOptimizer.scrubFrameMax;
    widget.video.scrubFramesVersion = VideoOptimizer.scrubFramesVersion;
    await library.update(widget.video);
    final next = ScrubFrames(
      dir: result.dir,
      count: result.count,
      stride: result.stride,
      fps: widget.video.fps,
    );
    await next.loadTimes(VideoOptimizer.framesTimesFile);
    // Wait out any scrub in progress: the overlay is showing the old
    // ScrubFrames mid-drag and it can't be torn down underneath.
    while (mounted && _shuttle.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) {
      next.dispose();
      return;
    }
    final old = _frames;
    setState(() {
      _frames = next;
      _shuttle.frames = next;
      _preparingFrames = false;
    });
    // Release the old set only after the tree has rebound to the new one.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _shuttle.dispose();
    _frames?.dispose();
    _strip.dispose();
    _controller.dispose();
    _drawing.dispose();
    super.dispose();
  }

  /// Starts a scrub: the shuttle raises the still overlay, and the drag
  /// accumulator that turns finger travel into frame steps starts fresh.
  void _beginScrub() {
    _scrub.reset();
    _shuttle.begin();
  }

  void _endScrub() => _shuttle.end();

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

  /// Global position of the last touch-down on the video, captured before
  /// the gesture arena resolves so a stroke can start where the finger
  /// actually landed.
  Offset? _pointerDown;

  /// The annotation layer itself — the aspect-fitted video box the strokes
  /// and markers are painted into.
  final GlobalKey _canvasKey = GlobalKey();

  RenderBox? get _canvasBox {
    final object = _canvasKey.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  /// Size of the painted video box. Everything stored is normalized to it.
  Size get _canvasSize => _canvasBox?.size ?? Size.zero;

  /// Touch position → position relative to the video's top-left corner, in
  /// the video's own (unzoomed) coordinates — the space the annotations and
  /// measurement markers are painted in, which is what makes them
  /// zoom-proof.
  ///
  /// Asking the painted layer where the touch landed (rather than
  /// re-deriving the letterbox rect and undoing the zoom transform by hand)
  /// keeps ink under the finger even when the stage's geometry isn't what
  /// the gesture math assumed — a stale pan offset after the viewport
  /// changed, say. [globalPosition] must be a global (screen) position.
  Offset? _toCanvas(Offset globalPosition) =>
      _canvasBox?.globalToLocal(globalPosition);

  Offset _normalizeCanvas(Offset canvasPoint) {
    final size = _canvasSize;
    if (size.isEmpty) return Offset.zero;
    return Offset((canvasPoint.dx / size.width).clamp(0.0, 1.0),
        (canvasPoint.dy / size.height).clamp(0.0, 1.0));
  }

  Offset _denormalizeCanvas(Offset normalized) {
    final size = _canvasSize;
    return Offset(normalized.dx * size.width, normalized.dy * size.height);
  }

  Offset _clampToVideo(Offset p) {
    final size = _canvasSize;
    return Offset(
        p.dx.clamp(0.0, size.width), p.dy.clamp(0.0, size.height));
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
      AngleAnnotation? hitAnnotation;
      var hitIndex = 0;
      for (final annotation in _drawing.annotations) {
        if (annotation is! AngleAnnotation) continue;
        for (var i = 0; i < annotation.points.length; i++) {
          final p = _denormalizeCanvas(annotation.points[i]);
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

  void _onVideoTap(Offset globalPosition) {
    if (_detecting) return;
    final canvasPoint = _toCanvas(globalPosition);
    if (canvasPoint == null) return;
    final size = _canvasSize;
    if (canvasPoint.dx < 0 ||
        canvasPoint.dy < 0 ||
        canvasPoint.dx > size.width ||
        canvasPoint.dy > size.height) {
      return;
    }
    if (_measureStep != null) {
      _onMeasureTap(canvasPoint);
      return;
    }
    if (_drawing.tool == DrawTool.angle) {
      addAngleVertex(_drawing, _normalizeCanvas(canvasPoint));
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
    // Where the finger actually landed, not where the recognizer won the
    // arena: a scale gesture is only granted once the touch has travelled,
    // so details.focalPoint is already a slop's worth along the drag. That
    // offset hides inside a pen scribble but plants an arrow's tail (and a
    // line's start) somewhere the user didn't touch.
    final canvasPoint = _toCanvas(_pointerDown ?? details.focalPoint);
    if (canvasPoint == null) return;
    _nodeDrag = _hitTestNode(canvasPoint);
    if (_nodeDrag != null) return;
    if (_measureStep != null) {
      // While reviewing, free drags scrub so both frames can be checked.
      if (_measureStep == _MeasureStep.review) {
        _scrub.reset();
        _beginScrub();
      }
      return;
    }
    if (_drawing.tool == DrawTool.none) {
      _scrub.reset();
      _beginScrub();
      return;
    }
    _activeStroke = beginAnnotation(_drawing, _normalizeCanvas(canvasPoint));
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
    final canvasPoint = _toCanvas(details.focalPoint);
    if (canvasPoint == null) return;
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
    if (_drawing.tool == DrawTool.none) {
      _jogBy(details.focalPointDelta.dx, details.sourceTimeStamp);
      return;
    }
    if (_activeStroke) {
      extendAnnotation(_drawing, _normalizeCanvas(canvasPoint));
    }
  }

  /// Jog by screen-space drag distance so scrubbing feels the same at any
  /// zoom level, accelerating the frame step with drag speed.
  void _jogBy(double dx, Duration? timestamp) {
    _scrubByFrames(_scrub.addDrag(dx, _pixelsPerFrame, timestamp: timestamp));
  }

  /// Advances the scrub by [frames] source frames — from the video drag or
  /// the scrub wheel.
  void _scrubByFrames(int frames) => _shuttle.by(frames);

  void _onScaleEnd(ScaleEndDetails details) {
    _endScrub();
    _nodeDrag = null;
    // The stroke is finished. Leaving this set made the next pinch — which
    // discards the stray stroke a one-finger drag may have started — delete
    // the annotation just drawn, whenever both fingers landed together and
    // no one-finger start ran in between.
    _activeStroke = false;
  }

  /// Picks a second throw and opens them side by side, without going back
  /// to the library first — the comparison you want is usually the one you
  /// think of while watching.
  Future<void> _compareWithAnother() async {
    _controller.pause();
    final other = await pickThrowToCompare(
      context,
      videos: context.read<VideoLibrary>().videos,
      against: widget.video,
    );
    if (other == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComparisonScreen(videoA: widget.video, videoB: other),
      ),
    );
  }

  /// Read/edit the throw's note without leaving the video.
  /// Tags (or re-tags) who threw it, picking from athletes already in the
  /// library. Clips imported before tagging existed start out unassigned,
  /// so this is the only way they ever get a name.
  Future<void> _editAthlete() async {
    final library = context.read<VideoLibrary>();
    var name = widget.video.athlete;
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Athlete'),
        content: SingleChildScrollView(
          child: AthletePicker(
            known: library.knownAthletes,
            value: name,
            onChanged: (value) => name = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    widget.video.athlete = saved.trim();
    await library.update(widget.video);
    if (mounted) setState(() {});
  }

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
                  // Re-clamp in case the viewport changed (e.g. rotation),
                  // and keep the stored pan equal to the one being drawn:
                  // the pinch anchor reads it back on the next gesture.
                  _zoomOffset = _clampZoomOffset(_zoomOffset, _zoomScale);
                  final offset = _zoomOffset;
                  return Listener(
                    onPointerDown: (event) => _pointerDown = event.position,
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _onVideoTap(details.globalPosition),
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
                                key: _canvasKey,
                                fit: StackFit.expand,
                                children: [
                                  VideoPlayer(_controller),
                                  // Smooth-scrub overlay: cached stills
                                  // that track the finger, covering the video
                                  // only once a drag actually moves (and
                                  // across the brief handoff back). A touch
                                  // that never travels leaves the video alone.
                                  Positioned.fill(
                                      child: ScrubStill(shuttle: _shuttle)),
                                  DrawingCanvas(
                                    controller: _drawing,
                                    zoomScale: _zoomScale,
                                  ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      size: Size.infinite,
                                      painter: _MeasurePainter(
                                        refA: _refA,
                                        refB: _refB,
                                        pointA: _pointA,
                                        pointB: _pointB,
                                        zoomScale: _zoomScale,
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
                    ),
                  );
                })
              : const CircularProgressIndicator(),
    );
  }

  String get _throwLabel {
    final throwName =
        '${widget.video.event.label} · '
        '${widget.video.implementSpec.weightLabel}';
    return _set.length > 1
        ? '$throwName · ${_index + 1} of ${_set.length}'
        : throwName;
  }

  /// Back, then the per-throw actions. [vertical] lays them out for the
  /// left rail, where the title is carried by the implement glyph's tooltip
  /// rather than a line of text a 56px rail has no room for.
  List<Widget> _headerActions({required bool vertical}) {
    final title = Text(
      _throwLabel,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    return [
      IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      // Portrait pages from the filmstrip's own chevrons; adding them here
      // too would push an already seven-wide header off a 390px screen.
      if (vertical && _set.length > 1) ...[
        _pagerButton(forward: false),
        _pagerButton(forward: true),
      ],
      if (vertical)
        Tooltip(
          message: _throwLabel,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: EventGlyph(widget.video.event,
                color: eventColor(widget.video.event)),
          ),
        )
      else
        Expanded(child: title),
      IconButton(
        tooltip: widget.video.athlete.isEmpty
            ? 'Tag athlete'
            : 'Athlete: ${widget.video.athlete}',
        icon: Icon(widget.video.athlete.isEmpty
            ? Icons.person_add_alt
            : Icons.person),
        onPressed: _editAthlete,
      ),
      IconButton(
        tooltip: widget.video.note.isEmpty ? 'Add note' : 'Note',
        icon: Icon(widget.video.note.isEmpty
            ? Icons.note_add_outlined
            : Icons.sticky_note_2),
        onPressed: _editNote,
      ),
      IconButton(
        tooltip: 'Compare with another throw',
        icon: const Icon(Icons.compare),
        onPressed: _compareWithAnother,
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
  }

  /// The measuring instructions, as a full-width band (portrait) or a
  /// rounded [pill] that sits beside the left rail (landscape).
  Widget? _measureBanner({required bool pill}) {
    if (_measureStep == null) return null;
    return Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            // Landscape shows the instructions as a pill beside the left
            // rail instead of a full-width band over the video.
            borderRadius: pill ? BorderRadius.circular(24) : null,
            clipBehavior: pill ? Clip.antiAlias : Clip.none,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize:
                    pill ? MainAxisSize.min : MainAxisSize.max,
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
                    fit: pill ? FlexFit.loose : FlexFit.tight,
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
  }

  List<ThrowVideo> _orderedSet() {
    final byId = {for (final video in widget.siblings) video.id: video};
    byId[widget.video.id] = widget.video;
    return byId.values.toList()
      ..sort((a, b) {
        final byDate = a.displayDate.compareTo(b.displayDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
  }

  /// Where the open throw sits in [_set] — never -1, since [_orderedSet]
  /// folds it in.
  int get _index => _set.indexWhere((video) => video.id == widget.video.id);

  ThrowVideo? get _earlierThrow => _index > 0 ? _set[_index - 1] : null;
  ThrowVideo? get _laterThrow =>
      _index < _set.length - 1 ? _set[_index + 1] : null;

  /// Swaps this screen for another throw in the same set.
  ///
  /// pushReplacement, not push: paging through eight throws should leave
  /// one screen on the stack, so Back still lands on the library instead of
  /// retracing every throw looked at along the way. Each throw gets a fresh
  /// state, which is what the player, the scrub frames and the drawing
  /// layer all want anyway.
  void _openThrow(ThrowVideo video) {
    if (video.id == widget.video.id) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) =>
            AnalysisScreen(video: video, siblings: _set),
        // The frame should change like a channel, not like a page arriving.
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  /// Scrolls the strip so the open throw sits in the middle of it.
  void _centreStrip() {
    if (!mounted || !_strip.hasClients) return;
    final target = _index * _stripExtent +
        _stripExtent / 2 -
        _strip.position.viewportDimension / 2;
    _strip.jumpTo(target.clamp(0.0, _strip.position.maxScrollExtent));
  }

  /// One step through the set. The ends stop rather than wrap: "next"
  /// quietly looping back to the first throw would read as a bug halfway
  /// through a session.
  Widget _pagerButton({required bool forward}) {
    final target = forward ? _laterThrow : _earlierThrow;
    return IconButton(
      tooltip: forward ? 'Next throw' : 'Previous throw',
      icon: Icon(forward ? Icons.chevron_right : Icons.chevron_left),
      onPressed: target == null ? null : () => _openThrow(target),
    );
  }

  /// The set as a row of stills beneath the video: where this throw sits in
  /// the session, and a one-tap jump to any other. Coaches pick a throw out
  /// by looking at it, which a list of "Shot Put · Men · 2026-09-02" rows
  /// never allowed.
  Widget _filmstrip() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _stripHeight,
      child: Row(
        children: [
          _pagerButton(forward: false),
          Expanded(
            child: ListView.builder(
              controller: _strip,
              scrollDirection: Axis.horizontal,
              itemExtent: _stripExtent,
              itemCount: _set.length,
              itemBuilder: (context, i) {
                final video = _set[i];
                final current = i == _index;
                return Center(
                  child: GestureDetector(
                    onTap: () => _openThrow(video),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        // A transparent border on the others keeps every
                        // cell the same size, so the strip doesn't shift
                        // sideways as the selection moves.
                        border: Border.all(
                          color:
                              current ? scheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Opacity(
                        opacity: current ? 1 : 0.55,
                        child: ThrowThumbnail(video, width: 56, height: 36),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _pagerButton(forward: true),
        ],
      ),
    );
  }

  /// Portrait header: back, title and the per-throw actions across the top,
  /// with the measuring instructions underneath.
  Widget _topOverlay() {
    final banner = _measureBanner(pill: false);
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
            Row(children: _headerActions(vertical: false)),
            if (banner != null) banner,
          ],
        ),
      ),
    );
  }

  /// Landscape header: the same actions as a rail down the left edge, back
  /// arrow at the top. A landscape phone is ~360px tall — every row across
  /// the top costs a tenth of the frame, while the left edge is where a
  /// right-handed thumb isn't and where a pillarboxed clip leaves black.
  Widget _leftRail() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _headerActions(vertical: true),
              ),
            ),
          ),
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
            if (_preparingFrames)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                      _frames == null
                          ? 'Preparing smooth scrubbing…'
                          : 'Sharpening scrub frames…',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white70)),
                ],
              )
            else if (!landscape)
              Text(
                'Ref: ${spec.weightLabel} '
                '${spec.referenceLabel.toLowerCase()} '
                '${(spec.nominalSize * 100).toStringAsFixed(1)} cm '
                '· drag video to scrub · pinch to zoom',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            if (!landscape && _set.length > 1) _filmstrip(),
            PlaybackControls(
              controller: _controller,
              fps: widget.video.fps,
              captureFps: widget.video.captureFps,
              dense: true,
              horizontal: landscape,
              // Route the wheel through the same smooth shuttle the video
              // drag uses, so fast wheel spins play through frames instead
              // of hammering the slow decoder seek.
              onScrubStart: _beginScrub,
              onScrubBy: _scrubByFrames,
              onScrubEnd: _endScrub,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Coach's Eye-style layout: the video owns the whole screen and the
    // controls float over it. Portrait puts the header across the top and
    // the drawing tools down the right; landscape has ~360px of height to
    // spend, so both move to edges that cost none of it — the header
    // becomes a left rail, the tools a bar above the transport.
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final banner = landscape ? _measureBanner(pill: true) : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _videoArea()),
          if (landscape) ...[
            Positioned(top: 0, left: 0, bottom: 0, child: _leftRail()),
            if (banner != null)
              Positioned(
                top: 4,
                left: 64,
                right: 8,
                child: SafeArea(
                  bottom: false,
                  child: Align(
                      alignment: Alignment.topLeft, child: banner),
                ),
              ),
          ] else
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
                    bottom: landscape
                        ? 60
                        : (_set.length > 1 ? 150 + _stripHeight : 150)),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: SingleChildScrollView(
                    reverse: true,
                    child: DrawingRail(controller: _drawing),
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
  _MeasurePainter({
    this.refA,
    this.refB,
    this.pointA,
    this.pointB,
    this.zoomScale = 1,
  });

  final Offset? refA, refB, pointA, pointB;

  /// Markers keep a fixed size on screen: zooming in is how a marker gets
  /// placed precisely, so one that grew with the picture would cover the
  /// pixel it marks.
  final double zoomScale;

  @override
  void paint(Canvas canvas, Size size) {
    double px(double pixels) => pixels / zoomScale;
    final refPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = px(2)
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = px(2)
      ..style = PaintingStyle.stroke;

    void crosshair(Offset p, Paint paint) {
      canvas.drawCircle(p, px(9), paint);
      canvas.drawLine(p - Offset(px(14), 0), p - Offset(px(4), 0), paint);
      canvas.drawLine(p + Offset(px(4), 0), p + Offset(px(14), 0), paint);
      canvas.drawLine(p - Offset(0, px(14)), p - Offset(0, px(4)), paint);
      canvas.drawLine(p + Offset(0, px(4)), p + Offset(0, px(14)), paint);
      // Filled center dot over a dark halo: the exact measured point,
      // readable against both bright sky and the implement itself.
      canvas.drawCircle(p, px(3), Paint()..color = Colors.black54);
      canvas.drawCircle(p, px(1.8), Paint()..color = paint.color);
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
      pointB != oldDelegate.pointB ||
      zoomScale != oldDelegate.zoomScale;
}
