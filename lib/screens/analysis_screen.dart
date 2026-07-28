import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../widgets/athlete_picker.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/event_glyph.dart';
import '../widgets/playback_controls.dart';
import '../widgets/throw_picker.dart';
import 'comparison_screen.dart';

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

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late final VideoPlayerController _controller;
  late final FrameSeeker _seeker = FrameSeeker(_controller);
  final DrawingController _drawing = DrawingController();

  /// Pre-extracted stills shown while dragging so scrubbing stays smooth
  /// regardless of the codec's seek cost; null when the clip has none.
  ScrubFrames? _frames;

  /// Frames are being extracted for a clip imported before the feature; the
  /// scrub overlay switches on once ready.
  bool _preparingFrames = false;

  /// A drag is actively scrubbing (show the still overlay), and the brief
  /// hold afterwards while the real video catches up to the last frame.
  bool _scrubbing = false;

  /// The current touch has actually moved. Until it does no still is shown
  /// and the player is not seeked, so a tap leaves the frame alone.
  bool _scrubMoved = false;

  bool _handoff = false;
  Timer? _handoffTimer;
  VoidCallback? _handoffWatch;
  ScrubFrames? _handoffFrames;

  // Shuttle scrubbing: the finger sets a target frame, and a per-vsync
  // follower advances the *shown* frame toward it at a rate that scales with
  // the gap — so a fast scroll plays the frames through quickly (the video
  // speeds up to match) instead of teleporting and skipping.
  late final Ticker _scrubTicker;
  double _fingerIndex = 0;
  double _displayIndex = 0;
  int _lastShown = -1;
  Duration _lastScrubTick = Duration.zero;

  /// Fraction of the finger→display gap closed per vsync (proportional catch-
  /// up: far gap plays fast, small gap tracks precisely).
  static const _catchUp = 0.3;

  /// Ceiling on how many frames/second the shuttle plays through, so a huge
  /// gap can't jump — it fast-forwards smoothly instead of skipping. At ~2x
  /// the clip's own rate it shows roughly every other frame during a fast
  /// spin, which reads as smooth speed-up rather than a stride.
  static const _maxCatchUpFramesPerSec = 120.0;

  /// Wall-clock spacing between decoder nudges while the shuttle is running.
  /// The extracted stills are what's on screen mid-scrub, so the player only
  /// has to stay roughly nearby for a quick handoff at the end. Seeking it on
  /// every shuttle frame meant a flick fired up to
  /// [_maxCatchUpFramesPerSec] platform seeks a second, each one flushing
  /// ExoPlayer's decode pipeline — which is what made a flick stutter and
  /// stall. ~10/s keeps the time/frame readout and the wheel live for a
  /// fraction of the work.
  static const _nudgeSpacing = Duration(milliseconds: 100);

  /// When the last decoder nudge was issued, and for which frame; null/-1
  /// until the first.
  DateTime? _lastNudge;
  int _lastNudgedIndex = -1;

  /// How long the still is held after the player reports it reached the
  /// target, covering the gap between a seek being accepted and its frame
  /// reaching the surface. Short enough not to feel like lag, long enough
  /// to cover a few frames of render latency.
  static const _renderSettle = Duration(milliseconds: 120);

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
    // Created eagerly: a lazy ticker on a screen left without scrubbing
    // would be created inside dispose(), when looking up the TickerMode is
    // illegal.
    _scrubTicker = createTicker(_onScrubTick);
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
      if (_scrubbing || _handoff || _scrubTicker.isActive) return false;
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
    while (mounted && (_scrubbing || _handoff || _scrubTicker.isActive)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) {
      next.dispose();
      return;
    }
    final old = _frames;
    setState(() {
      _frames = next;
      _preparingFrames = false;
    });
    // Release the old set only after the tree has rebound to the new one.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _stopHandoff();
    _scrubTicker.stop();
    _scrubTicker.dispose();
    _frames?.dispose();
    _controller.dispose();
    _drawing.dispose();
    super.dispose();
  }

  /// Shows the pre-extracted stills for the duration of a scrub drag. No-op
  /// when the clip has no extracted frames, so scrubbing then falls back to
  /// the seek path unchanged.
  void _beginScrub() {
    if (_frames == null) return;
    _stopHandoff();
    _controller.pause();
    _scrub.reset();
    if (!_scrubTicker.isActive) {
      final start = _frames!.indexForPosition(_seeker.position).toDouble();
      _fingerIndex = start;
      _displayIndex = start;
      _lastShown = -1;
      _lastNudge = null;
      _lastNudgedIndex = -1;
      _frames!.reset();
      // Decode the starting still now so it is ready the instant the finger
      // moves; nothing is shown until then.
      _frames!.showIndex(start.round());
      _scrubMoved = false;
    } else {
      // Grabbed again while the shuttle was still catching up: continue from
      // the frame currently on screen, already in the moved state.
      _fingerIndex = _displayIndex;
      _scrubMoved = true;
    }
    setState(() {
      _scrubbing = true;
      _handoff = false;
    });
  }

  /// Starts the shuttle the first time a scrub actually moves. Touching the
  /// video is not a scrub: the stills only exist every [ScrubFrames.stride]
  /// frames, so covering the video with the nearest one — and seeking the
  /// player onto that grid — shifted the picture by up to a stride even
  /// though the finger never travelled. Nothing happens until it does.
  void _beginShuttle() {
    if (_scrubMoved) return;
    _scrubMoved = true;
    _lastScrubTick = Duration.zero;
    _scrubTicker.start();
    setState(() {});
  }

  /// Lets the shuttle finish playing to the finger's frame, then hands off to
  /// live video. The still overlay stays up across the handoff.
  void _endScrub() {
    if (!_scrubbing) return;
    // A touch that never moved changed nothing — no overlay was raised and
    // the player was never seeked, so there is nothing to hand back.
    if (!_scrubMoved) {
      setState(() {
        _scrubbing = false;
        _handoff = false;
      });
      return;
    }
    setState(() {
      _scrubbing = false;
      _handoff = _frames != null;
    });
    if (_frames == null) return;
    if (!_scrubTicker.isActive) _startVideoHandoff(_displayIndex.round());
  }

  /// Per-vsync shuttle: eases the shown frame toward the finger's target so a
  /// fast scroll plays the frames through quickly (video speeds up to match)
  /// instead of jumping, and a slow scroll tracks frame for frame. Also nudges
  /// the hidden decoder along so the time/frame readout stays live and the
  /// eventual handoff is quick.
  void _onScrubTick(Duration elapsed) {
    final frames = _frames;
    if (frames == null) {
      _scrubTicker.stop();
      return;
    }
    final dt = ((elapsed - _lastScrubTick).inMicroseconds /
            Duration.microsecondsPerSecond)
        .clamp(0.0, 0.05);
    _lastScrubTick = elapsed;
    final gap = _fingerIndex - _displayIndex;
    if (gap.abs() < 0.5) {
      _displayIndex = _fingerIndex;
      // Caught up: seek for real, so the readout and any handoff are exact.
      _showAndSeek(_displayIndex.round(), force: true);
      if (!_scrubbing) {
        _scrubTicker.stop();
        _startVideoHandoff(_displayIndex.round());
      }
      return;
    }
    final maxStep = _maxCatchUpFramesPerSec / frames.stride * dt;
    var step = gap * _catchUp;
    if (step > maxStep) step = maxStep;
    if (step < -maxStep) step = -maxStep;
    _displayIndex += step;
    _showAndSeek(_displayIndex.round());
  }

  /// Shows an extracted still, and occasionally nudges the hidden decoder
  /// toward it. [force] issues the seek regardless of spacing — used when the
  /// shuttle settles, so the player ends up exactly where the scrub stopped.
  void _showAndSeek(int imageIndex, {bool force = false}) {
    if (imageIndex != _lastShown) {
      _lastShown = imageIndex;
      _frames!.showIndex(imageIndex);
    }
    // Tracked separately from [_lastShown]: a throttled tick still advances
    // the shown still, so a later forced nudge for that same frame must not
    // be mistaken for one already sent to the decoder.
    if (imageIndex == _lastNudgedIndex) return;
    final now = DateTime.now();
    final last = _lastNudge;
    if (!force && last != null && now.difference(last) < _nudgeSpacing) {
      return;
    }
    _lastNudge = now;
    _lastNudgedIndex = imageIndex;
    _seeker.seekTo(_positionForImage(imageIndex));
  }

  /// Where to seek so the video shows the still at [imageIndex]. ScrubFrames
  /// answers from the clip's own frame timestamps where it has them, and aims
  /// just short of the still's timestamp because the player renders the first
  /// frame at or after a seek — so the handoff lands on the frame the still
  /// was showing rather than the one after it.
  Duration _positionForImage(int imageIndex) =>
      _frames!.positionForIndex(imageIndex);

  /// Keeps the last still on screen when the finger lifts until the video
  /// decoder has actually seeked to that frame, so the handoff from stills
  /// back to live video is seamless instead of a visible jump.
  void _startVideoHandoff(int imageIndex) {
    _stopHandoff();
    final frames = _frames;
    final target = _positionForImage(imageIndex);
    _seeker.seekTo(target);
    // Under one frame: at 1.5 the still was dropped while the player was
    // still a whole frame away, so the picture stepped as the video took
    // over. A target sits a quarter frame short of the frame it names, so
    // the player reporting either the requested time or the frame's own
    // timestamp is within this.
    final toleranceUs =
        0.6 * Duration.microsecondsPerSecond / widget.video.fps;
    void watch() {
      // The still on screen has to be the one being handed back. A scrub
      // ends faster than 1440p JPEGs decode, so the overlay is often still
      // showing the neighbour that stood in for the frame the finger stopped
      // on — and swapping *that* for the video is itself the frame the
      // picture appears to skip. Waiting costs nothing: the still and the
      // video then show the same frame, so the switch is invisible.
      if (frames != null && frames.shownIndex != imageIndex) return;
      final delta =
          (_controller.value.position.inMicroseconds - target.inMicroseconds)
              .abs();
      if (delta > toleranceUs) return;
      // Arrived — but only in the player's bookkeeping. The position is
      // reported when the seek is accepted, not when the decoded frame
      // reaches the surface, so dropping the still here uncovers whatever
      // frame the texture still holds: the picture steps to the old frame
      // and then snaps to the right one. Stop watching and give the
      // texture a moment to actually show the frame we asked for.
      _stopHandoff();
      _handoffTimer = Timer(_renderSettle, () {
        if (mounted) setState(() => _handoff = false);
      });
    }

    _handoffWatch = watch;
    _controller.addListener(watch);
    // The decode that finally puts the right still on screen is the other
    // half of the condition above, and it arrives on its own notifier.
    _handoffFrames = frames;
    frames?.current.addListener(watch);
    // watch() may fire immediately below and replace this with the shorter
    // render-settle timer; this is the ceiling for the seek never landing.
    // Hold the (correct) still until the video actually arrives. seekTo can
    // take a second or more to render on some devices, so the fallback is
    // generous — showing the right frame a touch soft beats flashing the
    // wrong one and then jumping.
    _handoffTimer = Timer(const Duration(milliseconds: 2500), () {
      _stopHandoff();
      if (mounted) setState(() => _handoff = false);
    });
    watch();
  }

  void _stopHandoff() {
    if (_handoffWatch != null) {
      _controller.removeListener(_handoffWatch!);
      // The instance the listener went on, not whatever _frames is now: a
      // re-extraction can swap the set out between arming and stopping.
      _handoffFrames?.current.removeListener(_handoffWatch!);
      _handoffFrames = null;
      _handoffWatch = null;
    }
    _handoffTimer?.cancel();
    _handoffTimer = null;
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
      final point = _normalizeCanvas(canvasPoint);
      final last = _drawing.annotations.lastOrNull;
      if (last is AngleAnnotation && !last.isComplete) {
        last.points.add(point);
        _drawing.notifyChanged();
      } else {
        _drawing.add(AngleAnnotation(_drawing.color, _drawing.strokeWidth)
          ..points.add(point));
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
    switch (_drawing.tool) {
      case DrawTool.pen:
        _drawing.add(PenStroke(_drawing.color, _drawing.strokeWidth,
            [_normalizeCanvas(canvasPoint)]));
        _activeStroke = true;
      case DrawTool.line:
        final p = _normalizeCanvas(canvasPoint);
        _drawing.add(LineAnnotation(_drawing.color, _drawing.strokeWidth, p, p));
        _activeStroke = true;
      case DrawTool.arrow:
        // Tail where the drag starts, head where it ends.
        final p = _normalizeCanvas(canvasPoint);
        _drawing
            .add(ArrowAnnotation(_drawing.color, _drawing.strokeWidth, p, p));
        _activeStroke = true;
      case DrawTool.curvedArrow:
        _drawing.add(CurvedArrowAnnotation(_drawing.color, _drawing.strokeWidth,
            [_normalizeCanvas(canvasPoint)]));
        _activeStroke = true;
      case DrawTool.angle:
        break;
      case DrawTool.none:
        _scrub.reset();
        _beginScrub();
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
      case DrawTool.arrow:
        if (_activeStroke && last is ArrowAnnotation) {
          last.end = _normalizeCanvas(canvasPoint);
          _drawing.notifyChanged();
        }
      case DrawTool.curvedArrow:
        if (_activeStroke && last is CurvedArrowAnnotation) {
          last.points.add(_normalizeCanvas(canvasPoint));
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
    _scrubByFrames(_scrub.addDrag(dx, _pixelsPerFrame, timestamp: timestamp));
  }

  /// Advances the scrub by [frames] source frames — from the video drag or
  /// the scrub wheel. With the atlas active it moves the finger's target
  /// (the shuttle plays the shown frame toward it, stride-aware); otherwise
  /// it seeks directly.
  void _scrubByFrames(int frames) {
    if (frames == 0) return;
    final atlas = _frames;
    if (_scrubbing && atlas != null) {
      _beginShuttle();
      _fingerIndex = (_fingerIndex + frames / atlas.stride)
          .clamp(0.0, (atlas.count - 1).toDouble());
    } else {
      _jogFrames(frames);
    }
  }

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
                                  // Smooth-scrub overlay: cached stills that
                                  // track the finger, covering the video only
                                  // once a drag actually moves (and across
                                  // the brief handoff back). A touch that
                                  // never travels leaves the video alone.
                                  if (_frames != null &&
                                      ((_scrubbing && _scrubMoved) ||
                                          _handoff))
                                    Positioned.fill(
                                      child: ValueListenableBuilder<ui.Image?>(
                                        valueListenable: _frames!.current,
                                        builder: (_, image, __) => image == null
                                            ? const SizedBox.shrink()
                                            // contain, not fill: the stills
                                            // now carry the video's exact
                                            // aspect, and preserving their
                                            // own geometry means any future
                                            // mismatch letterboxes by a
                                            // pixel instead of stretching
                                            // the picture mid-scrub.
                                            : RawImage(
                                                image: image,
                                                fit: BoxFit.contain),
                                      ),
                                    ),
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

  String get _throwLabel =>
      '${widget.video.event.label} · ${widget.video.gender.label}';

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
                padding: EdgeInsets.only(bottom: landscape ? 76 : 150),
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

/// Vertical, collapsible tool rail anchored to the bottom-right corner of
/// the video, kept short enough for a landscape phone: the tools that build
/// on a drag (line, arrow, curved arrow) share one menu button, and the pen
/// weight and colour are menus too, so the column stays ~7 buttons instead
/// of the 17 controls it offers. The chevron collapses it to a single
/// button in the same corner, keeping the right-center and upper-right of
/// the frame — where the throw happens — unobstructed.
class _DrawingRail extends StatefulWidget {
  const _DrawingRail({required this.controller});

  final DrawingController controller;

  @override
  State<_DrawingRail> createState() => _DrawingRailState();
}

class _DrawingRailState extends State<_DrawingRail> {
  bool _open = true;

  DrawingController get controller => widget.controller;

  /// The two modes worth a button of their own: scrubbing without drawing,
  /// and the freehand pen.
  static const _directTools = [
    (DrawTool.none, Icons.pan_tool_alt, 'Scrub only'),
    (DrawTool.pen, Icons.draw, 'Freehand pen'),
  ];

  /// The measured shapes, sharing one menu button that shows whichever is
  /// selected — four more icons on the rail is what ran it off a landscape
  /// screen.
  static const _shapeTools = [
    (DrawTool.line, Icons.timeline, 'Straight line'),
    (DrawTool.arrow, Icons.arrow_right_alt, 'Arrow (drag tail to head)'),
    (
      DrawTool.curvedArrow,
      Icons.turn_slight_right,
      'Curved arrow (trace a path, head where you lift)'
    ),
    (DrawTool.angle, Icons.square_foot, 'Angle (tap 3 points, vertex second)'),
  ];

  static const _thicknessLabels = ['Thin', 'Medium', 'Thick'];

  /// The shape the menu button offers on a single tap — whichever shape is
  /// active, or the plain arrow before one has been chosen.
  (DrawTool, IconData, String) get _shape => _shapeTools.firstWhere(
        (entry) => entry.$1 == controller.tool,
        orElse: () => _shapeTools[1],
      );

  ButtonStyle? _styleFor(bool selected, ColorScheme scheme) => selected
      ? IconButton.styleFrom(backgroundColor: scheme.primaryContainer)
      : null;

  Widget _toolButton(DrawTool tool, IconData icon, String tip,
      ColorScheme scheme) {
    return IconButton(
      tooltip: tip,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 36),
      isSelected: controller.tool == tool,
      style: _styleFor(controller.tool == tool, scheme),
      icon: Icon(icon),
      onPressed: () => controller.tool = tool,
    );
  }

  /// A rail-sized menu button: tapping the icon picks [onTap] straight
  /// away, the small chevron opens the rest.
  Widget _menuButton<T>({
    required Key key,
    required String tooltip,
    required Widget icon,
    required bool selected,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
    VoidCallback? onTap,
    ColorScheme? scheme,
  }) {
    final button = PopupMenuButton<T>(
      key: key,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => items,
      onSelected: onSelected,
      child: Container(
        width: 40,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected && scheme != null
              ? scheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const Icon(Icons.arrow_drop_down, size: 14),
          ],
        ),
      ),
    );
    return button;
  }

  /// A bar drawn at [width], the way that pen paints.
  Widget _weightPreview(double width, Color color) => Container(
        width: 18,
        height: math.max(2, width),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(width),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final (shapeTool, shapeIcon, shapeTip) = _shape;
        return Material(
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
                      _toolButton(_directTools[0].$1, _directTools[0].$2,
                          _directTools[0].$3, scheme),
                      _toolButton(_directTools[1].$1, _directTools[1].$2,
                          _directTools[1].$3, scheme),
                      // Lines and arrows share a button: same gesture, and
                      // three more icons is what ran the rail off a
                      // landscape screen.
                      _menuButton<DrawTool>(
                        key: const ValueKey('rail-shapes'),
                        tooltip: shapeTip,
                        icon: Icon(shapeIcon, size: 20),
                        selected: controller.tool == shapeTool,
                        scheme: scheme,
                        items: [
                          for (final (tool, icon, tip) in _shapeTools)
                            PopupMenuItem(
                              value: tool,
                              child: Row(
                                children: [
                                  Icon(icon, size: 20),
                                  const SizedBox(width: 12),
                                  Flexible(child: Text(tip.split(' (').first)),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (tool) => controller.tool = tool,
                      ),
                      const SizedBox(height: 2),
                      _menuButton<double>(
                        key: const ValueKey('rail-width'),
                        tooltip: 'Line width',
                        icon: _weightPreview(
                            controller.strokeWidth, controller.color),
                        selected: false,
                        items: [
                          for (final (index, width) in kStrokeWidths.indexed)
                            PopupMenuItem(
                              value: width,
                              child: Row(
                                children: [
                                  SizedBox(
                                      width: 24,
                                      child: _weightPreview(
                                          width, controller.color)),
                                  const SizedBox(width: 12),
                                  Text('${_thicknessLabels[index]} line'),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (width) => controller.strokeWidth = width,
                      ),
                      _menuButton<Color>(
                        key: const ValueKey('rail-colour'),
                        tooltip: 'Colour',
                        icon: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: controller.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                        selected: false,
                        items: [
                          for (final (index, color)
                              in kAnnotationColors.indexed)
                            PopupMenuItem(
                              value: color,
                              child: Row(
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
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
                                  const SizedBox(width: 12),
                                  Text(_colorNames[index]),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (color) => controller.color = color,
                      ),
                      const SizedBox(height: 2),
                      IconButton(
                        tooltip: 'Undo',
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 40, height: 36),
                        icon: const Icon(Icons.undo),
                        onPressed: controller.undo,
                      ),
                      _menuButton<String>(
                        key: const ValueKey('rail-more'),
                        tooltip: 'More',
                        icon: const Icon(Icons.more_horiz, size: 20),
                        selected: false,
                        items: const [
                          PopupMenuItem(
                            value: 'clear',
                            child: Row(children: [
                              Icon(Icons.layers_clear, size: 20),
                              SizedBox(width: 12),
                              Text('Clear drawings'),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'hide',
                            child: Row(children: [
                              Icon(Icons.keyboard_arrow_down, size: 20),
                              SizedBox(width: 12),
                              Text('Hide tools'),
                            ]),
                          ),
                        ],
                        onSelected: (choice) {
                          if (choice == 'clear') {
                            controller.clear();
                          } else {
                            setState(() => _open = false);
                          }
                        },
                      ),
                    ],
            ),
          ),
        );
      },
    );
  }
}

/// Names for the annotation colours, in [kAnnotationColors] order, for the
/// rail's colour menu.
const _colorNames = ['Orange', 'Green', 'Cyan', 'Pink', 'White'];
