import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/video_optimizer.dart';
import '../utils/frame_seeker.dart';
import '../utils/scrub_frames.dart';
import '../utils/scrub_shuttle.dart';
import '../utils/time_format.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/drawing_rail.dart';
import '../widgets/playback_controls.dart';
import '../widgets/scrub_still.dart';

enum ComparisonMode { sideBySide, overlay }

/// Compares two throws. Scrub each video to its release frame and set the
/// sync point; once both are set the clips link automatically and a single
/// scrubber (plus all transport controls) drives both videos with the
/// release frames aligned. The link can be toggled to re-adjust one clip.
class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key, required this.videoA, required this.videoB});

  final ThrowVideo videoA;
  final ThrowVideo videoB;

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen>
    with TickerProviderStateMixin {
  late final VideoPlayerController _controllerA;
  late final VideoPlayerController _controllerB;
  late final FrameSeeker _seekerA = FrameSeeker(_controllerA);
  late final FrameSeeker _seekerB = FrameSeeker(_controllerB);

  /// The same still-overlay scrub path the analysis screen uses, one per
  /// clip: dragging a wheel here plays the pre-extracted frames rather than
  /// hammering the decoder with seeks. Clips imported before the stills
  /// existed have none, and fall back to seeking as before.
  ///
  /// Both are built in initState rather than lazily: each owns a ticker, and
  /// a comparison closed before the clips finished loading would otherwise
  /// create those tickers inside dispose(), when looking up the TickerMode is
  /// illegal.
  ScrubFrames? _framesA, _framesB;
  late final ScrubShuttle _shuttleA;
  late final ScrubShuttle _shuttleB;

  /// One set of annotations per clip — they are different videos, so a mark
  /// on A has no meaning on B. The tool, colour and weight are shared: the
  /// rail sets them on whichever pane was drawn on last, and a listener
  /// carries them to the other, so picking the pen once arms both panes.
  final DrawingController _drawA = DrawingController();
  final DrawingController _drawB = DrawingController();

  /// The pane the rail acts on: the last one drawn in, so undo and clear go
  /// where the marks just went.
  late DrawingController _activeDrawing = _drawA;

  ComparisonMode _mode = ComparisonMode.sideBySide;

  /// Panes crop to fill by default: two half-screen boxes letterbox a clip
  /// down to a stamp, and the throw is what matters, not the sky above it.
  /// Each pane can be dragged to put the athlete where you want them.
  bool _fill = true;
  double _overlayOpacity = 0.5;
  double _speed = 0.5;
  bool _linked = false;

  Duration _syncA = Duration.zero;
  Duration _syncB = Duration.zero;

  void _setSync({Duration? a, Duration? b}) {
    setState(() {
      _syncA = a ?? _syncA;
      _syncB = b ?? _syncB;
      // Both release frames marked → start driving the clips together.
      if (_syncA != Duration.zero && _syncB != Duration.zero) _linked = true;
    });
  }

  double get _fps => widget.videoA.fps;

  /// The stills a clip already has, or null: the comparison screen consumes
  /// what the analysis screen extracted rather than extracting its own.
  ScrubFrames? _framesFor(ThrowVideo video) {
    final dir = video.scrubFramesDir;
    if (dir == null || video.scrubFrameCount <= 0) return null;
    return ScrubFrames(
      dir: dir,
      count: video.scrubFrameCount,
      stride: video.scrubFrameStride,
      fps: video.fps,
    )..loadTimes(VideoOptimizer.framesTimesFile);
  }

  @override
  void initState() {
    super.initState();
    _framesA = _framesFor(widget.videoA);
    _framesB = _framesFor(widget.videoB);
    _controllerA = VideoPlayerController.file(File(widget.videoA.path))
      ..initialize().then((_) => mounted ? setState(() {}) : null)
          .catchError((Object _) => mounted ? setState(() {}) : null);
    _controllerB = VideoPlayerController.file(File(widget.videoB.path))
      ..initialize().then((_) => mounted ? setState(() {}) : null)
          .catchError((Object _) => mounted ? setState(() {}) : null);
    _shuttleA = ScrubShuttle(
      controller: _controllerA,
      seeker: _seekerA,
      fps: widget.videoA.fps,
      vsync: this,
      frames: _framesA,
    );
    _shuttleB = ScrubShuttle(
      controller: _controllerB,
      seeker: _seekerB,
      fps: widget.videoB.fps,
      vsync: this,
      frames: _framesB,
    );
    _drawA.addListener(_syncToolsFromA);
    _drawB.addListener(_syncToolsFromB);
  }

  void _syncToolsFromA() => _copyTools(_drawA, _drawB);
  void _syncToolsFromB() => _copyTools(_drawB, _drawA);

  /// Mirrors the pen settings onto the other pane. Guarded on equality so the
  /// two controllers' listeners can't bounce a change back and forth.
  void _copyTools(DrawingController from, DrawingController to) {
    if (to.tool == from.tool &&
        to.color == from.color &&
        to.strokeWidth == from.strokeWidth) {
      return;
    }
    to.tool = from.tool;
    to.color = from.color;
    to.strokeWidth = from.strokeWidth;
  }

  /// The rail follows the finger: draw in a pane and undo/clear act on it.
  void _activateDrawing(DrawingController controller) {
    if (identical(controller, _activeDrawing)) return;
    setState(() => _activeDrawing = controller);
  }

  @override
  void dispose() {
    _drawA.removeListener(_syncToolsFromA);
    _drawB.removeListener(_syncToolsFromB);
    _drawA.dispose();
    _drawB.dispose();
    _shuttleA.dispose();
    _shuttleB.dispose();
    _framesA?.dispose();
    _framesB?.dispose();
    _controllerA.dispose();
    _controllerB.dispose();
    super.dispose();
  }

  bool get _ready =>
      (_controllerA.value.isInitialized || _controllerA.value.hasError) &&
      (_controllerB.value.isInitialized || _controllerB.value.hasError);

  Duration _clampToDuration(Duration position, VideoPlayerController c) =>
      Duration(
        microseconds: position.inMicroseconds
            .clamp(0, c.value.duration.inMicroseconds),
      );

  /// Seeks B so both videos sit at the same offset from their sync points.
  void _followWithB() {
    final offset = _controllerA.value.position - _syncA;
    _controllerB.seekTo(_clampToDuration(_syncB + offset, _controllerB));
  }

  void _seekBoth(Duration positionA) {
    _controllerA.pause();
    _controllerB.pause();
    _seekerA.seekTo(positionA);
    _seekerB.seekTo(_syncB + (positionA - _syncA));
  }

  Future<void> _stepBoth(int frames) async {
    final step = Duration(
        microseconds: (Duration.microsecondsPerSecond / _fps).round());
    _seekBoth(await _seekerA.freshPosition() + step * frames);
  }

  void _togglePlay() {
    if (_controllerA.value.isPlaying) {
      _controllerA.pause();
      _controllerB.pause();
    } else {
      _controllerA.setPlaybackSpeed(_speed);
      _controllerB.setPlaybackSpeed(_speed);
      _followWithB();
      _controllerA.play();
      _controllerB.play();
    }
    setState(() {});
  }

  Widget _player(ScrubShuttle shuttle, DrawingController drawing,
      {double opacity = 1}) {
    final controller = shuttle.controller;
    if (controller.value.hasError) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Couldn\'t open this video — the file may have '
              'been removed. Re-import the clip.'),
        ),
      );
    }
    return controller.value.isInitialized
        ? _VideoPane(
            shuttle: shuttle,
            drawing: drawing,
            fill: _fill,
            videoOpacity: opacity,
            onDraw: () => _activateDrawing(drawing),
          )
        : const Center(child: CircularProgressIndicator());
  }

  /// Fractional frame of B carried between linked steps: the clips can have
  /// been shot at different rates, so A's whole frames scale to a fraction of
  /// B's and the remainder has to survive to the next step or the two drift
  /// apart over a long scrub.
  double _linkedRemainderB = 0;

  void _startLinkedScrub() {
    _linkedRemainderB = 0;
    // The wheel pauses the clip it is attached to; the other one is ours.
    _controllerB.pause();
    _shuttleA.begin();
    _shuttleB.begin();
  }

  /// One wheel, both clips: A moves by the frames the finger asked for and B
  /// by the same amount of *time*, so they stay aligned on their sync points.
  void _linkedScrubBy(int frames) {
    _shuttleA.by(frames);
    final scaled =
        frames * widget.videoB.fps / widget.videoA.fps + _linkedRemainderB;
    final whole = scaled.truncate();
    _linkedRemainderB = scaled - whole;
    _shuttleB.by(whole);
  }

  void _endLinkedScrub() {
    _shuttleA.end();
    _shuttleB.end();
  }

  Widget _wheel(ScrubShuttle shuttle, ThrowVideo video,
      {bool linked = false, double height = 36}) {
    return ScrubWheel(
      controller: shuttle.controller,
      fps: video.fps,
      captureFps: video.captureFps,
      height: height,
      // Linked, one wheel drives both clips; unlinked, each wheel scrubs its
      // own clip — either way through the shuttle, so the stills carry the
      // drag instead of the decoder.
      onScrubStart: linked ? _startLinkedScrub : shuttle.begin,
      onScrubBy: linked ? _linkedScrubBy : shuttle.by,
      onScrubEnd: linked ? _endLinkedScrub : shuttle.end,
    );
  }

  Widget _syncRow(String label, ScrubShuttle shuttle, ThrowVideo video,
      Duration sync, ValueChanged<Duration> onSet) {
    final seeker = shuttle.seeker;
    final controller = shuttle.controller;
    final fps = video.fps;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => Row(
        children: [
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  child: Slider(
                    value: value.position.inMilliseconds
                        .clamp(0, value.duration.inMilliseconds)
                        .toDouble(),
                    max: value.duration.inMilliseconds == 0
                        ? 1
                        : value.duration.inMilliseconds.toDouble(),
                    onChanged: (ms) {
                      controller.pause();
                      seeker.seekTo(
                          snapToFrame(Duration(milliseconds: ms.round()), fps));
                    },
                  ),
                ),
                // Frame-precise scrubbing per clip while they're unlinked —
                // the slider can't resolve single frames.
                _wheel(shuttle, video, height: 30),
              ],
            ),
          ),
          TextButton.icon(
            icon: Icon(sync == Duration.zero
                ? Icons.flag_outlined
                : Icons.flag),
            label: Text(sync == Duration.zero
                ? 'Set release'
                : formatPosition(sync)),
            // freshPosition: the cached position can lag the displayed
            // frame right after pausing, mismarking the release.
            onPressed: () async => onSet(await seeker.freshPosition()),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Single scrubber shown while linked: drags both videos through their
  /// sync points on A's timeline.
  Widget _linkedRow() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controllerA,
      builder: (context, value, _) {
        final durationMs = value.duration.inMilliseconds;
        return Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.link, size: 18),
            const SizedBox(width: 6),
            const Text('A·B', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 24,
                    child: Slider(
                      value: value.position.inMilliseconds
                          .clamp(0, durationMs)
                          .toDouble(),
                      max: durationMs == 0 ? 1 : durationMs.toDouble(),
                      onChanged: (ms) => _seekBoth(snapToFrame(
                          Duration(milliseconds: ms.round()),
                          widget.videoA.fps)),
                    ),
                  ),
                  // One wheel through both clips, on A's timeline.
                  _wheel(_shuttleA, widget.videoA, linked: true),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        );
      },
    );
  }

  /// The two clips, side by side along the screen's long edge or stacked as
  /// a ghost overlay.
  Widget _panes(bool landscape) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _mode == ComparisonMode.sideBySide
          // Split along the screen's long edge so each video gets a usable
          // size in both orientations.
          ? (landscape
              ? Row(
                  children: [
                    Expanded(child: _player(_shuttleA, _drawA)),
                    const VerticalDivider(width: 2),
                    Expanded(child: _player(_shuttleB, _drawB)),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: _player(_shuttleA, _drawA)),
                    const Divider(height: 2),
                    Expanded(child: _player(_shuttleB, _drawB)),
                  ],
                ))
          : Stack(
              alignment: Alignment.center,
              children: [
                _player(_shuttleA, _drawA),
                // The ghost fades the clip, not the marks drawn on it — an
                // annotation you can barely see is no use for pointing
                // something out.
                _player(_shuttleB, _drawB, opacity: _overlayOpacity),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.videoA.event.label}: compare throws'),
        actions: [
          IconButton(
            tooltip: _fill
                ? 'Show each whole frame'
                : 'Fill each pane (crop, drag to reframe)',
            icon: Icon(_fill ? Icons.fit_screen : Icons.crop),
            onPressed: () => setState(() => _fill = !_fill),
          ),
          SegmentedButton<ComparisonMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: ComparisonMode.sideBySide,
                  icon: Icon(Icons.splitscreen),
                  tooltip: 'Side by side'),
              ButtonSegment(
                  value: ComparisonMode.overlay,
                  icon: Icon(Icons.layers),
                  tooltip: 'Ghost overlay'),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _panes(landscape)),
                        // Same rail as the analysis screen, in the same
                        // corner: it acts on the pane last drawn in, and the
                        // tool it sets arms both.
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: SingleChildScrollView(
                            reverse: true,
                            child: DrawingRail(
                                controller: _activeDrawing,
                                initiallyOpen: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_mode == ComparisonMode.overlay)
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        const Text('Ghost'),
                        Expanded(
                          child: Slider(
                            value: _overlayOpacity,
                            onChanged: (v) =>
                                setState(() => _overlayOpacity = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  // Landscape height is scarce: the sync rows share a line
                  // there instead of stacking.
                  if (_linked)
                    _linkedRow()
                  else if (landscape)
                    Row(
                      children: [
                        Expanded(
                          child: _syncRow('A', _shuttleA, widget.videoA,
                              _syncA, (d) => _setSync(a: d)),
                        ),
                        Expanded(
                          child: _syncRow('B', _shuttleB, widget.videoB,
                              _syncB, (d) => _setSync(b: d)),
                        ),
                      ],
                    )
                  else ...[
                    _syncRow('A', _shuttleA, widget.videoA, _syncA,
                        (d) => _setSync(a: d)),
                    _syncRow('B', _shuttleB, widget.videoB, _syncB,
                        (d) => _setSync(b: d)),
                  ],
                  // Wrap, not Row: on a narrow phone the transport plus the
                  // speed menu and "Go to release" runs past the screen, and
                  // a clipped control is one you can't press.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Both back one frame',
                        iconSize: 38,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () => _stepBoth(-1),
                      ),
                      IconButton(
                        iconSize: 56,
                        icon: Icon(_controllerA.value.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle),
                        onPressed: _togglePlay,
                      ),
                      IconButton(
                        tooltip: 'Both forward one frame',
                        iconSize: 38,
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => _stepBoth(1),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: _linked
                            ? 'Unlink: scrub A and B separately'
                            : 'Link A and B: one scrubber drives both',
                        isSelected: _linked,
                        icon: Icon(_linked ? Icons.link : Icons.link_off),
                        onPressed: () => setState(() => _linked = !_linked),
                      ),
                      const SizedBox(width: 8),
                      SpeedMenuButton(
                        speed: _speed,
                        onChanged: (s) {
                          setState(() => _speed = s);
                          _controllerA.setPlaybackSpeed(s);
                          _controllerB.setPlaybackSpeed(s);
                        },
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        icon: const Icon(Icons.flag_circle),
                        label: const Text('Go to release'),
                        onPressed: () => _seekBoth(_syncA),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}

/// One clip in the comparison, cropped to fill its pane and draggable
/// inside it.
///
/// Fitting the whole frame into half a screen shrinks a throw to a stamp
/// with the sky and the runway taking the space — so the pane fills instead
/// and the surplus hangs outside the clip rect. Which part shows is the
/// user's call: drag to reframe, pinch to zoom in further, double-tap to
/// recentre. The clip's own aspect ratio is never touched, so nothing is
/// ever stretched.
class _VideoPane extends StatefulWidget {
  const _VideoPane({
    required this.shuttle,
    required this.drawing,
    required this.fill,
    this.videoOpacity = 1,
    this.onDraw,
  });

  /// The clip's scrub path; the pane shows the player and, while a scrub is
  /// running, the still the shuttle has raised over it.
  final ScrubShuttle shuttle;

  /// This clip's annotations. While a drawing tool is selected the pane's
  /// drags draw instead of reframing the crop.
  final DrawingController drawing;

  VideoPlayerController get controller => shuttle.controller;

  /// Cover the pane (cropping the overflow) rather than fit inside it.
  final bool fill;

  /// Fades the clip (the ghost overlay), leaving the annotations solid.
  final double videoOpacity;

  /// Called when a mark is made here, so the rail can act on this pane.
  final VoidCallback? onDraw;

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  /// Extra zoom on top of the base fit, and the drag away from centre.
  double _zoom = 1;
  Offset _pan = Offset.zero;
  double _zoomAtGestureStart = 1;

  /// The clip's rect inside the pane at the moment of the last build, so a
  /// touch anywhere in the pane can be placed on the frame it landed on.
  Rect _videoRect = Rect.zero;

  /// A one-finger drag started an annotation, so a second finger arriving
  /// (a pinch) has a stray stroke to throw away.
  bool _activeStroke = false;

  /// Where the finger actually landed. A scale gesture is only granted once
  /// the touch has travelled, so its focal point is already a slop's worth
  /// along the drag — which plants an arrow's tail where nobody touched.
  Offset? _pointerDown;

  /// A pane touch as a fraction of the clip's frame (0..1 on both axes), the
  /// space annotations are stored in so they stay put when the pane is
  /// resized, reframed or zoomed.
  Offset _normalize(Offset local) => Offset(
        (local.dx - _videoRect.left) / _videoRect.width,
        (local.dy - _videoRect.top) / _videoRect.height,
      );

  bool get _drawingActive => widget.drawing.tool != DrawTool.none;

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtGestureStart = _zoom;
    if (details.pointerCount > 1) {
      // A pinch that began as a one-finger drag: discard the stray stroke.
      if (_activeStroke) widget.drawing.undo();
      _activeStroke = false;
      return;
    }
    _activeStroke = false;
    if (!_drawingActive || _videoRect.isEmpty) return;
    _activeStroke = beginAnnotation(
        widget.drawing, _normalize(_pointerDown ?? details.localFocalPoint));
    if (_activeStroke) widget.onDraw?.call();
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size pane) {
    // Two fingers pinch and reframe whatever the tool is, so a drawing can
    // still be lined up on the detail it is marking.
    if (details.pointerCount > 1 || !_drawingActive) {
      setState(() {
        _zoom = (_zoomAtGestureStart * details.scale).clamp(1.0, 4.0);
        _pan = _clampPan(
            _pan + details.focalPointDelta, pane, _contentSize(pane));
      });
      return;
    }
    if (_activeStroke) {
      extendAnnotation(widget.drawing, _normalize(details.localFocalPoint));
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.drawing.tool != DrawTool.angle || _videoRect.isEmpty) return;
    addAngleVertex(widget.drawing, _normalize(details.localPosition));
    widget.onDraw?.call();
  }

  /// The clip's size inside the pane at the current fit and zoom.
  Size _contentSize(Size pane) {
    final ratio = widget.controller.value.aspectRatio;
    var width = pane.width;
    var height = width / ratio;
    final fitsInside = height <= pane.height;
    // Cover takes whichever axis leaves no gap; contain takes the other.
    if (widget.fill ? fitsInside : !fitsInside) {
      height = pane.height;
      width = height * ratio;
    }
    return Size(width * _zoom, height * _zoom);
  }

  /// Keeps the clip covering the pane on any axis where it is bigger, and
  /// centred on any axis where it is not — so a drag can never open a gap.
  Offset _clampPan(Offset pan, Size pane, Size content) {
    double axis(double offset, double paneExtent, double contentExtent) {
      final slack = (contentExtent - paneExtent) / 2;
      return slack <= 0 ? 0 : offset.clamp(-slack, slack);
    }

    return Offset(axis(pan.dx, pane.width, content.width),
        axis(pan.dy, pane.height, content.height));
  }

  @override
  void didUpdateWidget(_VideoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching between crop and whole-frame starts from a clean view.
    if (oldWidget.fill != widget.fill) {
      _zoom = 1;
      _pan = Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final pane = constraints.biggest;
      final content = _contentSize(pane);
      final pan = _clampPan(_pan, pane, content);
      _videoRect = Rect.fromLTWH(
        (pane.width - content.width) / 2 + pan.dx,
        (pane.height - content.height) / 2 + pan.dy,
        content.width,
        content.height,
      );
      return ClipRect(
        child: Listener(
          onPointerDown: (event) => _pointerDown = event.localPosition,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onScaleStart: _onScaleStart,
            onScaleUpdate: (details) => _onScaleUpdate(details, pane),
            onScaleEnd: (_) => _activeStroke = false,
            onDoubleTap: () => setState(() {
              _zoom = 1;
              _pan = Offset.zero;
            }),
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: _videoRect,
                  // The still and the annotations share the player's rect,
                  // so both land exactly on the frame underneath.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: widget.videoOpacity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoPlayer(widget.controller),
                            ScrubStill(shuttle: widget.shuttle),
                          ],
                        ),
                      ),
                      DrawingCanvas(
                          controller: widget.drawing, zoomScale: _zoom),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
