import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../utils/time_format.dart';
import '../utils/zoom_detail.dart';
import '../widgets/angular.dart';
import '../widgets/athlete_picker.dart';
import '../widgets/detail_still.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/drawing_rail.dart';
import '../widgets/event_glyph.dart';
import '../widgets/playback_controls.dart';
import '../widgets/scrub_still.dart';
import '../widgets/throw_actions.dart';
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

  /// Stands in for ffmpeg when set, so a widget test — which has no ffmpeg
  /// behind it — can see what a zoomed frame asks to have drawn.
  @visibleForTesting
  static DetailRenderer? debugRenderDetail;

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

  /// The sharp still over a zoomed frame once it settles — see
  /// zoom_detail.dart.
  late final ZoomDetail _detail = ZoomDetail(_renderDetail);
  Timer? _detailTimer;

  /// The frame [_detail] was last asked for, so a picture that moves off it
  /// takes the still down with it.
  Duration? _detailAt;

  /// The clip has played since the last still: where it paused is somewhere
  /// inside a frame rather than a position anybody seeked to.
  bool _playedSinceDetail = false;

  /// Whether the file under the player is the file ffmpeg would open. A
  /// playback copy owed a remake is replaced on disk while this screen
  /// keeps playing the old one, and a crop measured on one cut out of the
  /// other would land the wrong piece of picture on the frame. Most remakes
  /// turn out to be a probe and nothing more, and those give it back.
  late bool _canSharpen;

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

  /// How much height the filmstrip costs the bottom overlay.
  static const double _stripHeight = 52;

  /// Where the coach last left the strip of stills. Remembered, because it
  /// is a preference about how they work rather than about this throw —
  /// and because paging through a session replaces this screen with the
  /// next throw's, which would otherwise pull the strip back down under the
  /// finger that just put it away.
  static const _stripKey = 'throwlab.throwStrip';

  /// The session shows on top by default: a strip of stills is how a throw
  /// is picked out, and it is the first thing wanted on opening one.
  bool _stripOpen = true;

  _MeasureStep? _measureStep;
  Offset? _refA, _refB, _pointA, _pointB;
  double _measureDt = 0;
  bool _detecting = false;

  /// Javelin tip/tail auto-detection failed once → plain tap flow.
  bool _manualJavelin = false;

  /// How the measurement reached where it is, which is what an undo has to
  /// walk back through: the later frame reached through Next on found
  /// markers, and both later markers found rather than tapped.
  bool _viaConfirm = false;
  bool _autoPoints = false;

  /// Where a finger is down on the frame while measuring, in global
  /// coordinates — what the loupe magnifies. Null when none is, or when a
  /// second finger turns the touch into a pinch.
  Offset? _loupeAt;
  final Set<int> _pointers = {};

  /// The stack everything is laid out in, for placing the loupe in it.
  final GlobalKey _stageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Without this, opening throw 7 of 8 leaves the strip scrolled to the
    // start, showing everything except the throw actually on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerStrip());
    unawaited(_loadStripDock());
    _openFailed = !File(widget.video.path).existsSync();
    _controller = VideoPlayerController.file(
      File(widget.video.path),
      // Said out loud rather than left to the default: on Android the mixing
      // option is process-wide and applied when a player is created, so a
      // comparison opened earlier in the session would otherwise leave every
      // clip opened after it mixing. One clip on screen takes the audio.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
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
    _canSharpen = !widget.video.optimizePending &&
        widget.video.playbackVersion >= VideoOptimizer.playbackVersion;
    _controller.addListener(_onPictureMoved);
    _shuttle.addListener(_onPictureMoved);
    if (!_openFailed) {
      _controller.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {
        if (mounted) setState(() => _openFailed = true);
      });
      final needsFrames = _frames == null ||
          widget.video.optimizePending ||
          widget.video.scrubFramesVersion < VideoOptimizer.scrubFramesVersion ||
          widget.video.playbackVersion < VideoOptimizer.playbackVersion;
      if (_mayHaveMissedRate) {
        // Asked first: stills extracted at a rate that is about to change
        // would be extracted again.
        unawaited(_recheckFrameRate().then((reopening) {
          if (reopening || !mounted || !needsFrames) return;
          _prepareScrubFrames();
          setState(() {});
        }));
      } else if (needsFrames) {
        _prepareScrubFrames();
      }
    }
  }

  /// A clip stored at 30 fps with no slow-motion rate is what every import
  /// came to while the probe was failing silently (see
  /// [VideoOptimizer.probeFrameRates]), so it is asked again — one probe,
  /// cheap beside opening the clip. A clip that really was 30 answers 30 and
  /// nothing happens.
  bool get _mayHaveMissedRate =>
      widget.video.fps == 30 && widget.video.captureFps == 30;

  /// Reads the playback copy's own frame rate, and where it is not what the
  /// clip was stored with, puts it right and opens the throw again: the
  /// shuttle, the stills and the frame counting were all built on the old
  /// rate when this screen opened. The stills are re-extracted on the way
  /// back in. Returns whether the screen is being replaced.
  ///
  /// Only the playback rate can be recovered this way — the copy was made
  /// without the slow-motion tag — so a slow-motion clip keeps whatever
  /// capture rate it is set to until somebody types the right one in.
  Future<bool> _recheckFrameRate() async {
    final video = widget.video;
    final rates = await VideoOptimizer.probeFrameRates(video.path);
    if (!mounted || rates == null) return false;
    if ((rates.playback - video.fps).abs() < 0.5) return false;
    video
      ..fps = rates.playback
      ..captureFps = rates.capture
      ..scrubFramesVersion = 0;
    await context.read<VideoLibrary>().update(video);
    // Never out from under a finger that is scrubbing.
    while (mounted && _shuttle.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return true;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) =>
            AnalysisScreen(video: video, siblings: widget.siblings),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    return true;
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
    if (widget.video.optimizePending ||
        widget.video.playbackVersion < VideoOptimizer.playbackVersion) {
      // A clip filmed at a meet was saved as the camera shot it, so it is
      // owed the encode an import does up front — its pixels may be the
      // right shape while its keyframes are seconds apart, which is what
      // makes an exact seek slow.
      final remade = await VideoOptimizer.remakePlaybackCopy(
          widget.video.path, widget.video.id,
          force: widget.video.optimizePending);
      if (!mounted) return;
      if (remade != null) widget.video.path = remade;
      // Nothing was re-encoded: the file under the player is still the file
      // on disk.
      if (remade == null && !widget.video.optimizePending) _canSharpen = true;
      widget.video.playbackVersion = VideoOptimizer.playbackVersion;
      widget.video.optimizePending = false;
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
    _detailTimer?.cancel();
    _detail.dispose();
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
        microseconds:
            (Duration.microsecondsPerSecond / widget.video.fps).round());
    _seeker.seekBy(step * frames);
  }

  // ---- The sharp still over a zoomed frame ----

  /// Keeps the still honest as the picture changes: it comes down the moment
  /// the clip plays, a scrub puts its own stills up, or the paused frame is
  /// another one, and a new one is asked for once things stop moving.
  void _onPictureMoved() {
    final value = _controller.value;
    if (value.isPlaying) _playedSinceDetail = true;
    if (value.isPlaying || _shuttle.overlayVisible) {
      _dropDetail();
      return;
    }
    final at = _detailAt;
    if (at != null &&
        _frameTarget(value.position, playedSince: false).at != at) {
      _dropDetail();
    }
    _scheduleDetail();
  }

  void _dropDetail() {
    _detailTimer?.cancel();
    _detailAt = null;
    _detail.clear();
  }

  ({Duration at, bool seek}) _frameTarget(Duration position,
          {required bool playedSince}) =>
      detailTarget(
        position: position,
        lastSeek: playedSince ? null : FrameSeeker.lastTargetOf(_controller),
        fps: widget.video.fps,
      );

  /// Asks for a still once the picture has been left alone a moment. Every
  /// pinch, pan and step comes through here, so it is the quiet after the
  /// last of them that renders, rather than each of them.
  void _scheduleDetail() {
    _detailTimer?.cancel();
    if (!_canSharpen || _openFailed || !_controller.value.isInitialized) {
      return;
    }
    if (_controller.value.isPlaying) return;
    _detailTimer = Timer(const Duration(milliseconds: 220), _sharpen);
  }

  void _sharpen() {
    if (!mounted || _controller.value.isPlaying) return;
    // A scrub in flight comes back through [_onPictureMoved] when its
    // handoff is done, which is when there is a frame worth drawing.
    if (_shuttle.busy) return;
    final box = _canvasBox;
    final frame = _controller.value.size;
    if (box == null || frame.isEmpty) return;
    final canvas = box.size;
    final visible = visibleCanvasRect(
      viewport: _viewport,
      canvas: canvas,
      zoom: _zoomScale,
      offset: _zoomOffset,
    );
    final crop = visible == null
        ? null
        : detailCropFor(
            frameWidth: frame.width.round(),
            frameHeight: frame.height.round(),
            visible: Rect.fromLTRB(
              visible.left / canvas.width,
              visible.top / canvas.height,
              visible.right / canvas.width,
              visible.bottom / canvas.height,
            ),
            magnification: _zoomScale *
                MediaQuery.devicePixelRatioOf(context) *
                canvas.width /
                frame.width,
          );
    if (crop == null) {
      _dropDetail();
      return;
    }
    final target = _frameTarget(_controller.value.position,
        playedSince: _playedSinceDetail);
    _playedSinceDetail = false;
    // Onto the frame it is already showing — see [detailTarget].
    if (target.seek) _seeker.seekTo(target.at);
    if (_detailAt != target.at) _detail.clear();
    _detailAt = target.at;
    _detail.request(DetailJob(at: target.at, crop: crop));
  }

  Future<ui.Image?> _renderDetail(DetailJob job) async {
    final debug = AnalysisScreen.debugRenderDetail;
    if (debug != null) return debug(job);
    final bytes = await VideoOptimizer.renderDetail(widget.video.path,
        at: job.at, crop: job.crop);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  // ---- Zoom + unified gestures ----
  //
  // One ScaleGestureRecognizer owns every touch on the video: two fingers
  // zoom/pan, one finger scrubs, draws, or drags a measurement/angle node.
  // (InteractiveViewer's own recognizer used to race the drawing layer's,
  // which made pinch-zoom land unpredictably.)

  /// Drag distance that advances the video by one frame in scrub mode,
  /// scaled to the clip's real frame duration like the wheel.
  double get _pixelsPerFrame => scrubPixelsPerFrame(widget.video.captureFps);

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
    return Offset(p.dx.clamp(0.0, size.width), p.dy.clamp(0.0, size.height));
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
    if (_drawing.tool == DrawTool.timer) {
      TimerMarker? hitMarker;
      for (final annotation in _drawing.annotations) {
        if (annotation is! TimerMarker) continue;
        final d = (_denormalizeCanvas(annotation.at) - canvasPoint).distance;
        if (d < best) {
          best = d;
          hitMarker = annotation;
        }
      }
      final marker = hitMarker;
      if (marker == null) return null;
      return (p) {
        marker.at = _normalizeCanvas(p);
        _drawing.notifyChanged();
      };
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
    } else if (_drawing.tool == DrawTool.timer) {
      dropTimer(
          _drawing, _normalizeCanvas(canvasPoint), _controller.value.position);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _zoomScale;
    _gestureStartOffset = _zoomOffset;
    _gestureStartFocal = details.localFocalPoint;
    _nodeDrag = null;
    if (details.pointerCount > 1) {
      // A pinch that began as a one-finger drag: discard the stray stroke.
      if (_activeStroke) _drawing.discardStroke();
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
      final scale = (_gestureStartScale * details.scale).clamp(1.0, 8.0);
      // Keep the content point that started under the fingers under them.
      final anchor =
          (_gestureStartFocal - _gestureStartOffset) / _gestureStartScale;
      setState(() {
        _zoomScale = scale;
        _zoomOffset =
            _clampZoomOffset(details.localFocalPoint - anchor * scale, scale);
      });
      // The still already up stays where it is — it is placed in the
      // frame's coordinates and moves with it — and a new one for what is
      // now on screen is asked for once the fingers stop.
      _scheduleDetail();
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
    _scheduleDetail();
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
    final pair = await pickThrowsToCompare(
      context,
      library: context.read<VideoLibrary>(),
      against: widget.video,
    );
    if (pair == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComparisonScreen(videoA: pair.$1, videoB: pair.$2),
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

  /// Marks the throw's release at [position], or clears it. Kept on the
  /// clip, so the comparison lines up on the same moment without being told
  /// it again.
  Future<void> _setRelease(Duration? position) async {
    setState(() => widget.video.release = position);
    await context.read<VideoLibrary>().update(widget.video);
  }

  Future<void> _editFps() async {
    await editCaptureFps(context, context.read<VideoLibrary>(), widget.video);
    if (mounted) setState(() {});
  }

  // ---- Release measurement ----

  bool get _isJavelin => widget.video.event == ThrowEvent.javelin;

  String get _refWord => switch (widget.video.event) {
        ThrowEvent.discus => 'disc',
        ThrowEvent.javelin => 'javelin',
        _ => 'ball',
      };

  /// Which frame the step is taken on, and how far through the four taps
  /// it is: said above the instruction so a coach knows where they are
  /// without reading the sentence again.
  String get _measureStepLabel {
    final later = '+${(_measureDt * 1000).round()} ms';
    final (frame, step) = switch (_measureStep!) {
      _MeasureStep.refA => ('Release frame', 1),
      _MeasureStep.refB || _MeasureStep.refConfirm => ('Release frame', 2),
      _MeasureStep.pointA => (_isJavelin ? later : 'Release frame', 3),
      _MeasureStep.pointB => (later, 4),
      _MeasureStep.review => ('Check', 4),
    };
    return '$frame · $step / 4';
  }

  /// Taps placed so far, out of four — the segments under the instruction.
  int get _measureDone => switch (_measureStep!) {
        _MeasureStep.refA => 0,
        _MeasureStep.refB => 1,
        _MeasureStep.refConfirm || _MeasureStep.pointA => 2,
        _MeasureStep.pointB => 3,
        _MeasureStep.review => 4,
      };

  /// One short instruction; the step label above it says which frame.
  String get _measureInstruction {
    // The release is marked by the first tap when none is, so until then
    // the frame on screen has to be put there by hand.
    final scrub =
        widget.video.release == null ? 'Scrub to the release, then ' : '';
    return switch (_measureStep!) {
      _MeasureStep.refA => _isJavelin
          ? '${scrub}tap ${_manualJavelin ? '' : 'near '}the javelin tip'
          : '${scrub}tap one edge of the $_refWord',
      _MeasureStep.refConfirm => 'Drag the tip and tail to fit, then Next',
      _MeasureStep.refB => _isJavelin
          ? 'Tap the javelin tail'
          : 'Tap the opposite edge of the $_refWord',
      _MeasureStep.pointA => _isJavelin
          ? 'Tap the javelin tip again'
          : 'Tap the center of the $_refWord',
      _MeasureStep.pointB => _isJavelin
          ? 'Tap the javelin tail again'
          : 'Tap the same spot on the $_refWord again',
      _MeasureStep.review => 'Drag any marker to fit, then Calculate',
    };
  }

  void _startMeasure() {
    if (!_controller.value.isInitialized) return;
    _controller.pause();
    // A measurement is taken on the release frame, so with one marked it
    // starts there rather than asking for it to be found again.
    final release = widget.video.release;
    if (release != null) {
      _seeker.seekTo(snapToFrame(release, widget.video.fps));
    }
    setState(() {
      _refA = _refB = _pointA = _pointB = null;
      _detecting = false;
      _manualJavelin = false;
      _viaConfirm = false;
      _autoPoints = false;
      _measureStep = _MeasureStep.refA;
    });
  }

  /// Takes back the last tap: its marker comes off, and a jump to the later
  /// frame that tap made is jumped back. The one correction that works the
  /// same on every step, rather than a re-tap on one and a drag on another.
  void _undoMeasureTap() {
    final step = _measureStep;
    if (step == null || _detecting) return;
    void back() => _jogFrames(-_jumpFrames);
    setState(() {
      switch (step) {
        case _MeasureStep.refA:
          break;
        case _MeasureStep.refB:
          _refA = null;
          _measureStep = _MeasureStep.refA;
        case _MeasureStep.refConfirm:
          _refA = _refB = null;
          _manualJavelin = false;
          _measureStep = _MeasureStep.refA;
        case _MeasureStep.pointA:
          if (_isJavelin) {
            back();
            if (_viaConfirm) {
              // Back to the found markers, to be fitted and confirmed again.
              _viaConfirm = false;
              _measureStep = _MeasureStep.refConfirm;
            } else {
              _refB = null;
              _measureStep = _MeasureStep.refB;
            }
          } else {
            _refB = null;
            _measureStep = _MeasureStep.refB;
          }
        case _MeasureStep.pointB:
          if (!_isJavelin) back();
          _pointA = null;
          _measureStep = _MeasureStep.pointA;
        case _MeasureStep.review:
          if (_autoPoints) {
            back();
            _autoPoints = false;
            _viaConfirm = false;
            _pointA = _pointB = null;
            _measureStep = _MeasureStep.refConfirm;
          } else {
            _pointB = null;
            _measureStep = _MeasureStep.pointB;
          }
      }
    });
  }

  void _cancelMeasure() {
    setState(() {
      _measureStep = null;
      _loupeAt = null;
      _detecting = false;
      _refA = _refB = _pointA = _pointB = null;
    });
  }

  /// Frames spanning ~100 ms of real time. File frames each represent
  /// 1/captureFps s.
  int get _jumpFrames => math.max(2, (widget.video.captureFps * 0.1).round());

  /// Jumps forward ~100 ms of REAL time so the speed math uses the same dt
  /// regardless of frame rate. The longer baseline (vs 50 ms) halves
  /// marker-noise error; the midpoint gravity correction in the metrics
  /// removes the path-curvature cost of the wider interval.
  void _jumpForward() {
    _measureDt = _jumpFrames / widget.video.captureFps;
    _jogFrames(_jumpFrames);
  }

  void _onMeasureTap(Offset position) {
    // The first tap is taken on the release frame, so it is the release:
    // marked here it is on the clip for the scale and the comparison.
    if (_measureStep == _MeasureStep.refA) {
      final here = _seeker.position;
      final release = widget.video.release;
      if (release == null ||
          frameAt(release, widget.video.fps) !=
              frameAt(here, widget.video.fps)) {
        unawaited(_setRelease(here));
      }
    }
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
      _viaConfirm = true;
      if (found == null) {
        _measureStep = _MeasureStep.pointA; // manual re-tap flow
      } else {
        _autoPoints = true;
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
    final ballistic = event == ThrowEvent.shotPut || event == ThrowEvent.hammer;
    final height = _releaseHeights[event]!;
    final optimal = optimalAngleDeg(metrics.speed, releaseHeight: height);
    final lost = distanceLostToAngle(metrics.speed, metrics.releaseAngleDeg,
        releaseHeight: height);
    final predicted = predictedDistance(metrics.speed, metrics.releaseAngleDeg,
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
              Row(
                children: [
                  Text('Release metrics',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 10),
                  const _BetaBadge(),
                ],
              ),
              const SizedBox(height: 12),
              _metricRow(
                  'Release speed', '~${metrics.speed.toStringAsFixed(1)} m/s'),
              _metricRow('Release angle',
                  '${metrics.releaseAngleDeg.toStringAsFixed(1)}°'),
              if (attack != null)
                _metricRow(
                    'Angle of attack',
                    '${attack >= 0 ? '+' : ''}${attack.toStringAsFixed(1)}° '
                        '(nose ${attack >= 0 ? 'up' : 'down'})'),
              if (ballistic) ...[
                _metricRow(
                    'Predicted distance', '~${predicted.toStringAsFixed(2)} m'),
                _metricRow('Optimal angle', '${optimal.toStringAsFixed(1)}°'),
                _metricRow('Lost to angle', '${lost.toStringAsFixed(2)} m'),
              ],
              const SizedBox(height: 8),
              Text(
                'Beta. These numbers only hold when the camera is exactly '
                'side-on — square to the throw, 90° to the direction it '
                'goes. A few degrees off the line and the speed and angle '
                'both drift.'
                '${ballistic ? ' Distance assumes a '
                    '~${height.toStringAsFixed(1)} m release height.' : ' '
                    'Distance is left off ${event.label.toLowerCase()} — its '
                    'aerodynamic lift and drag aren\'t modeled yet.'}',
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Future<void> _saveToNote(ReleaseMetrics metrics) async {
    final attack = metrics.attackAngleDeg;
    final summary = '~${metrics.speed.toStringAsFixed(1)} m/s @ '
        '${metrics.releaseAngleDeg.toStringAsFixed(1)}°'
        '${attack == null ? '' : ', AoA ${attack >= 0 ? '+' : ''}${attack.toStringAsFixed(1)}°'}';
    widget.video.note =
        widget.video.note.isEmpty ? summary : '${widget.video.note} · $summary';
    await context.read<VideoLibrary>().update(widget.video);
    if (mounted) {
      setState(() {}); // note icon switches to "has a note"
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to note: $summary')));
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
                  // Turned, or the tools moved: what is on screen is a
                  // different piece of the frame at a different size.
                  if (constraints.biggest != _viewport) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scheduleDetail();
                    });
                  }
                  _viewport = constraints.biggest;
                  // Re-clamp in case the viewport changed (e.g. rotation),
                  // and keep the stored pan equal to the one being drawn:
                  // the pinch anchor reads it back on the next gesture.
                  _zoomOffset = _clampZoomOffset(_zoomOffset, _zoomScale);
                  final offset = _zoomOffset;
                  return Listener(
                    onPointerDown: (event) {
                      _pointerDown = event.position;
                      _onStagePointerDown(event);
                    },
                    onPointerMove: _onStagePointerMove,
                    onPointerUp: _onStagePointerUp,
                    onPointerCancel: _onStagePointerUp,
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
                                    // Over the stills as well as the video:
                                    // it is only ever up when neither of
                                    // them is moving.
                                    Positioned.fill(
                                        child: DetailStill(detail: _detail)),
                                    // Rebuilt off the player's own value so
                                    // a dropped timer counts as the clip
                                    // moves; nothing else on the canvas
                                    // cares where the clip is.
                                    ValueListenableBuilder<VideoPlayerValue>(
                                      valueListenable: _controller,
                                      builder: (context, value, _) =>
                                          DrawingCanvas(
                                        controller: _drawing,
                                        zoomScale: _zoomScale,
                                        position: value.position,
                                      ),
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

  /// What the throw is, and nothing about where it sits in the set: which
  /// of eight throws is on screen is answered by the strip of stills, and
  /// spending the title on it says nothing a coach needed.
  String get _throwLabel => '${widget.video.event.label} · '
      '${widget.video.implementSpec.weightLabel}';

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
        // The title names the throw, and tapping it asks about the throw:
        // when it was taken, how far it went, what was written down, and
        // the edits for all three. The same sheet the library opens on a
        // long press, so there is one place a throw is described.
        Expanded(
          child: InkWell(
            key: const ValueKey('throw-title'),
            borderRadius: BorderRadius.circular(8),
            onTap: _showThrowInfo,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: title,
            ),
          ),
        ),
      // Upright, the header carries the two things done *with* a throw and
      // nothing about it: who threw it, the note and the frame rate describe
      // the throw, and the title already opens the sheet that describes it.
      // The rail on its side keeps them, where there is a whole edge of room.
      if (vertical) ...[
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
      ],
      IconButton(
        tooltip: 'Compare with another throw',
        icon: const Icon(Icons.compare),
        onPressed: _compareWithAnother,
      ),
      IconButton(
        tooltip: 'Measure release — speed & angle (beta)',
        icon: const Icon(Icons.speed),
        onPressed: _measureStep == null ? _startMeasure : null,
      ),
      if (vertical)
        IconButton(
          tooltip: 'Set capture frame rate '
              '(${widget.video.captureFps.toStringAsFixed(0)} fps)',
          icon: const Icon(Icons.shutter_speed),
          onPressed: _editFps,
        ),
    ];
  }

  /// The measuring instructions: which frame and which of the four taps,
  /// one short sentence, a segment per tap, and the three things that can be
  /// done about it. Set as type on the header's scrim across the top when
  /// upright, and as a [pill] beside the left rail on its side.
  Widget? _measureBanner({required bool pill}) {
    if (_measureStep == null) return null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instruction = _detecting
        ? 'Finding the javelin…'
        : _measureInstruction.replaceRange(
            0, 1, _measureInstruction[0].toUpperCase());
    final done = _measureDone;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _measureStepLabel.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: scheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
            if (_detecting)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(instruction, style: theme.textTheme.titleMedium),
        // Said as the measurement begins: the whole result rests on the
        // camera being square to the throw, and this is a beta tool that
        // can't tell when it wasn't.
        if (!_detecting && _measureStep == _MeasureStep.refA)
          Text(
            'Beta — needs an exact side-on (90°) camera angle.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 2,
                  color: i < done
                      ? scheme.primary
                      : scheme.onSurface.withOpacity(0.18),
                ),
              ),
            ],
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: _cancelMeasure,
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('measure-undo'),
              onPressed: _measureStep == _MeasureStep.refA || _detecting
                  ? null
                  : _undoMeasureTap,
              child: const Text('Undo tap'),
            ),
            const Spacer(),
            if (_measureStep == _MeasureStep.refConfirm)
              TextButton(
                onPressed: _detecting ? null : _confirmRefAndJump,
                child: const Text('Next'),
              ),
            if (_measureStep == _MeasureStep.review)
              TextButton(
                onPressed: _showResults,
                child: const Text('Calculate'),
              ),
          ],
        ),
      ],
    );
    if (!pill) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: body,
      );
    }
    // On its side the pill stands over the frame, so it carries the
    // surface the rails do rather than sitting bare on the picture.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Material(
        color: scheme.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: body,
        ),
      ),
    );
  }

  /// A round magnifier over the frame while a finger is down on it during a
  /// measurement. A javelin tip is a few pixels across and a fingertip forty,
  /// so the one thing the finger covers is the one thing being placed; the
  /// loupe shows it three times over, with hairlines crossing on the exact
  /// point, off to the side of the finger rather than under it. It
  /// magnifies what is painted — the sharp still over a zoomed frame
  /// included — so it is the clip's own pixels drawn larger, never a guess.
  Widget? _loupe() {
    final at = _loupeAt;
    final stage = _stageKey.currentContext?.findRenderObject();
    if (at == null ||
        _measureStep == null ||
        stage is! RenderBox ||
        !stage.hasSize) {
      return null;
    }
    const size = 120.0;
    const lift = 96.0;
    final local = stage.globalToLocal(at);
    final bounds = stage.size;
    // Above the finger, or below it where there is no room above.
    final above = local.dy - lift - size / 2 >= 0;
    final center = Offset(
      local.dx.clamp(size / 2 + 4, bounds.width - size / 2 - 4),
      above ? local.dy - lift : local.dy + lift,
    );
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(size),
          magnificationScale: 3,
          focalPointOffset: local - center,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: Colors.white70, width: 1.5),
            ),
            shadows: [BoxShadow(color: Colors.black54, blurRadius: 12)],
          ),
          child: const CustomPaint(painter: _LoupeCrosshair()),
        ),
      ),
    );
  }

  void _onStagePointerDown(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_measureStep == null) return;
    setState(() => _loupeAt = _pointers.length == 1 ? event.position : null);
  }

  void _onStagePointerMove(PointerMoveEvent event) {
    if (_measureStep == null || _pointers.length != 1) return;
    setState(() => _loupeAt = event.position);
  }

  void _onStagePointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_loupeAt != null) setState(() => _loupeAt = null);
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
  Future<void> _showThrowInfo() async {
    await showThrowActions(context, widget.video);
    // The sheet edits the throw in place — the athlete, the distance, the
    // note — and the header is drawn from it.
    if (mounted) setState(() {});
  }

  /// The tab the strip is put away on and pulled back down by, hanging off
  /// the bottom edge of it. On the panel rather than in the header, which is
  /// already back, a title and five actions wide on a 390px screen — and a
  /// handle on the thing it moves is the one nobody has to be told about.
  ///
  /// A grab bar and nothing else. It sits over the frame, and every pixel of
  /// chrome there is a pixel of the throw: the tab is a way back to the
  /// stills, not a control worth a card and three buttons of its own. What is
  /// drawn is a bar barely wider than a thumbnail's corner; what is *hit* is
  /// the box around it, so the thing stays easy to find with a thumb while
  /// being nearly invisible to the eye.
  ///
  /// It carries the header's own surface behind it rather than sitting bare
  /// on the video, and hangs flush off the band's bottom edge. A bar alone
  /// disappears against a bright frame — a sky, an infield in full sun —
  /// which is a handle nobody can find on exactly the throws this app is
  /// pointed at; and a tab a shade off the header, or a few pixels under it,
  /// reads as something that fell off it.
  ///
  /// Tap it or pull it. A bar across the top of a panel is the shape of
  /// something that gets dragged, so a thumb that comes down on it and
  /// pushes is asking for the tray whether or not anybody said it could —
  /// and a drag that did nothing would read as a handle that was stuck.
  /// Both gestures land on the same toggle, so the tray is never left half
  /// way: past [_pullSlop] in the direction that has somewhere to go, it
  /// opens or shuts on its own animation.
  Widget _stripHandle() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: GestureDetector(
        key: const ValueKey('throw-strip-handle'),
        // The whole box takes the tap, not just the bar painted inside it.
        behavior: HitTestBehavior.opaque,
        onTap: _toggleStrip,
        onVerticalDragStart: (_) {
          _pulled = 0;
          _pullSpent = false;
        },
        onVerticalDragUpdate: _pullHandle,
        child: Tooltip(
          message: _stripOpen ? 'Hide the session' : 'Show the session',
          child: SizedBox(
            width: 72,
            height: 26,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 44,
                height: 15,
                alignment: Alignment.center,
                // The header's own band, so the tab is the header carried
                // on down rather than a second piece of chrome under it.
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Container(
                  width: 22,
                  height: 3,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadStripDock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final open = prefs.getBool(_stripKey) ?? true;
      if (open == _stripOpen) return;
      setState(() => _stripOpen = open);
    } catch (_) {
      // Storage that will not answer just means the strip stays showing.
    }
  }

  /// How far the handle has been dragged in the current gesture, and
  /// whether that gesture has already moved the tray.
  double _pulled = 0;
  bool _pullSpent = false;

  /// Enough travel to read a direction off. Small on purpose: what separates
  /// a pull from a tap is Flutter's own `kTouchSlop`, which the gesture has
  /// already cleared before the first of these arrives — a thumb that moves
  /// less than that never gets here, it lands on [_toggleStrip] as a tap.
  /// Stacking a second threshold of any size on top of that would only make
  /// the tray answer late.
  static const double _pullSlop = 4;

  /// Opens the tray on a pull down and shuts it on a push up, once per
  /// gesture. Dragging the way it cannot go — down when it is already
  /// showing — does nothing rather than toggling: a pull has a direction
  /// and it should mean what it points at, unlike the tap, which is the
  /// gesture for 'whichever way it is now, change it'.
  void _pullHandle(DragUpdateDetails drag) {
    if (_pullSpent) return;
    _pulled += drag.delta.dy;
    final opening = _pulled > _pullSlop && !_stripOpen;
    final closing = _pulled < -_pullSlop && _stripOpen;
    if (!opening && !closing) return;
    // Acted on mid-gesture rather than on release, so the tray comes with
    // the thumb instead of after it.
    _pullSpent = true;
    _toggleStrip();
  }

  void _toggleStrip() {
    setState(() => _stripOpen = !_stripOpen);
    // The strip is only in the tree once it is down, so it is centered on
    // the open rather than at init.
    if (_stripOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerStrip());
    }
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_stripKey, _stripOpen);
      } catch (_) {
        // It has already moved; it just won't be there next time.
      }
    }());
  }

  void _centerStrip() {
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
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 30),
      icon: Icon(forward ? Icons.chevron_right : Icons.chevron_left),
      onPressed: target == null ? null : () => _openThrow(target),
    );
  }

  /// The set as a row of stills beneath the video: where this throw sits in
  /// the session, and a one-tap jump to any other. Coaches pick a throw out
  /// by looking at it, which a list of "Shot Put · Men · 2026-09-02" rows
  /// never allowed.
  ///
  /// The pager sits in here, at the ends of the stills it steps through,
  /// rather than out on the tab: next and previous are about the set, and the
  /// set is what this tray is. Out on the tab they were two buttons and a
  /// card's worth of chrome standing on the frame of every throw, including
  /// the throws nobody was paging through.
  Widget _filmstrip() {
    final scheme = Theme.of(context).colorScheme;
    // No surface of its own: it is laid in the header's band, which is what
    // keeps it a drawer in front of the throw rather than stills floating
    // over it — and one surface, so the header, the strip and the tab have
    // no seam between them.
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
                          color: current ? scheme.primary : Colors.transparent,
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
  ///
  /// The row itself is a solid band in the same surface as the strip and
  /// its tab, so the three read as one drawer: the strip slides out of the
  /// header and the tab hangs flush off whichever of them is lowest. On a
  /// fading scrim the tab hung off nothing — the header's edge was wherever
  /// the gradient happened to give out over the frame, which was never where
  /// the tab started.
  Widget _topOverlay() {
    final banner = _measureBanner(pill: false);
    // Opaque: any translucency lets the top edge of the frame show through
    // as a seam across the band wherever the letterbox gives way to it.
    final band = Theme.of(context).colorScheme.surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          color: band,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: _headerActions(vertical: false)),
                // Under the header rather than along the bottom. A strip of
                // stills is how a throw is picked out — by looking at it —
                // and it is the first thing wanted on opening one, so it
                // shows; but the bottom of the screen is where the
                // scrubber, the transport and the drawing tools all already
                // are, and a strip down there was in the way of all three.
                if (_set.length > 1)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _stripOpen
                        ? _filmstrip()
                        : const SizedBox(width: double.infinity),
                  ),
              ],
            ),
          ),
        ),
        if (_set.length > 1) _stripHandle(),
        if (banner != null)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: banner,
          ),
      ],
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

  /// Bottom scrim: scrubber and transport controls, plus whatever the
  /// screen is busy preparing. Landscape lays the controls on one line to
  /// give the short screen back to the video.
  ///
  /// It used to carry a line naming the calibration reference and the two
  /// gestures. The reference is already stated where it is used — on the
  /// measure sheet, and on the card in the library — and the gestures are
  /// learned on the first drag; what the line actually cost was a strip of
  /// the black band the drawing tools now sit in.
  Widget _bottomOverlay() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final toolsOnFrame = _toolsOnFrame;
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
              ),
            // Upright the tools belong with the rest of the chrome rather
            // than floating over the frame at a guessed inset: laid out
            // here they sit hard against the scrubber whatever else the
            // overlay is carrying, and have the width of the screen to
            // spread along.
            if (!toolsOnFrame)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: DrawingRail(
                    controller: _drawing,
                    axis: Axis.horizontal,
                  ),
                ),
              ),
            // Rebuilt off the drawing so a timer dropped on the frame is
            // notched into the clip line as it lands.
            ListenableBuilder(
              listenable: _drawing,
              builder: (context, _) => PlaybackControls(
                controller: _controller,
                fps: widget.video.fps,
                captureFps: widget.video.captureFps,
                dense: true,
                horizontal: landscape,
                release: widget.video.release,
                onReleaseChanged: _setRelease,
                timers: [
                  for (final annotation in _drawing.annotations)
                    if (annotation is TimerMarker)
                      (annotation.from, annotation.color),
                ],
                // Route the wheel through the same smooth shuttle the video
                // drag uses, so fast wheel spins play through frames instead
                // of hammering the slow decoder seek.
                onScrubStart: _beginScrub,
                onScrubBy: _scrubByFrames,
                onScrubEnd: _endScrub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Roughly what the transport takes at the foot of an upright screen:
  /// the clip line, the scale and the row of play and the frame steps.
  static const double _transportHeight = 128;

  /// Roughly what the drawing bar takes laid along the bottom.
  static const double _toolbarHeight = 56;

  /// Whether the drawing tools stand on the picture, up the right edge, or
  /// lie in the band under it. Which is decided by the *picture*, not the
  /// screen: a clip filmed on its side and watched upright leaves a band of
  /// black under the frame, and the tools lie in it; the same clip filmed
  /// upright fills the screen, and a bar laid along the bottom of it sat on
  /// the athlete's feet and the circle — a fifth of the frame, and the part
  /// of it a throw is judged from. So the bar goes under the frame only
  /// where the band is deep enough to hold it and the transport together;
  /// anywhere else the tools float as the column the rail on its side
  /// already is.
  bool get _toolsOnFrame {
    final media = MediaQuery.of(context);
    if (media.orientation == Orientation.landscape) return true;
    if (!_controller.value.isInitialized) return false;
    final aspect = _controller.value.aspectRatio;
    if (aspect <= 0) return false;
    final screen = media.size;
    final frame = math.min(screen.height, screen.width / aspect);
    final band = (screen.height - frame) / 2;
    return band < _transportHeight + _toolbarHeight + media.padding.bottom;
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
    final loupe = _loupe();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        key: _stageKey,
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
                  child: Align(alignment: Alignment.topLeft, child: banner),
                ),
              ),
          ] else
            Positioned(top: 0, left: 0, right: 0, child: _topOverlay()),
          // On its side the frame fills the screen, so the tools float over
          // it as a column up the right edge — past the release and the
          // flight, which is the least of the picture to stand in front of
          // — clear of the header rail down the left and of the transport
          // along the bottom. Upright they live in the bottom overlay
          // instead, where the letterbox already leaves room for them.
          if (!landscape && _toolsOnFrame)
            Positioned(
              // Under the header and whatever hangs off it, and clear of the
              // transport: the rail is handed the box it has to fit, which
              // decides whether it takes one run or two.
              top: MediaQuery.paddingOf(context).top +
                  kToolbarHeight +
                  (_set.length > 1 ? (_stripOpen ? _stripHeight : 0) + 26 : 0) +
                  8,
              right: 4,
              bottom:
                  MediaQuery.paddingOf(context).bottom + _transportHeight + 4,
              left: 64,
              child: Align(
                alignment: Alignment.bottomRight,
                child: DrawingRail(
                  controller: _drawing,
                  axis: Axis.vertical,
                ),
              ),
            ),
          if (landscape)
            Positioned(
              top: 0,
              left: 64,
              right: 4,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  // Handed the whole box it has to fit into, since that is
                  // what decides whether the tools take one run or two.
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: DrawingRail(
                      controller: _drawing,
                      axis: Axis.vertical,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomOverlay(),
          ),
          if (loupe != null) loupe,
        ],
      ),
    );
  }
}

/// Hairlines across the loupe, broken around the middle so the pixel being
/// placed is left clear rather than drawn over — dark, with a light edge,
/// so they read against a sky and against the implement alike.
class _LoupeCrosshair extends CustomPainter {
  const _LoupeCrosshair();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const gap = 6.0;
    final reach = size.width / 2 - 14;
    void hairlines(Paint paint) {
      canvas.drawLine(c - Offset(reach, 0), c - const Offset(gap, 0), paint);
      canvas.drawLine(c + const Offset(gap, 0), c + Offset(reach, 0), paint);
      canvas.drawLine(c - Offset(0, reach), c - const Offset(0, gap), paint);
      canvas.drawLine(c + const Offset(0, gap), c + Offset(0, reach), paint);
    }

    hairlines(Paint()
      ..color = Colors.white54
      ..strokeWidth = 2.5);
    hairlines(Paint()
      ..color = Colors.black
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_LoupeCrosshair oldDelegate) => false;
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

/// A small 'BETA' tag for the release-metrics sheet, so the numbers are read
/// as an estimate a beta tool produced rather than a measurement to trust to
/// the centimeter.
class _BetaBadge extends StatelessWidget {
  const _BetaBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: ShapeDecoration(
        color: scheme.tertiaryContainer,
        shape: angularShape(6),
      ),
      child: Text(
        'BETA',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
      ),
    );
  }
}
