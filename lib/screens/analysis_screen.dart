import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/video_library.dart';
import '../utils/frame_seeker.dart';
import '../utils/projectile.dart';
import '../utils/release_metrics.dart';
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

enum _MeasureStep { refA, refB, pointA, pointB }

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
            ? 'Pause on the release frame, then tap the javelin TIP'
            : 'Pause on the release frame, then tap one edge of the '
                '$_refWord',
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
      };

  void _startMeasure() {
    if (!_controller.value.isInitialized) return;
    _controller.pause();
    setState(() {
      _refA = _refB = _pointA = _pointB = null;
      _measureStep = _MeasureStep.refA;
    });
  }

  void _cancelMeasure() {
    setState(() {
      _measureStep = null;
      _refA = _refB = _pointA = _pointB = null;
    });
  }

  /// Jumps forward a fixed slice of REAL time (~50 ms) so the speed math
  /// uses the same dt regardless of frame rate. File frames each represent
  /// 1/captureFps s of real time.
  void _jumpForward() {
    final frames = math.max(2, (widget.video.captureFps * 0.05).round());
    _measureDt = frames / widget.video.captureFps;
    _jogFrames(frames);
  }

  void _onMeasureTap(Offset position) {
    switch (_measureStep!) {
      case _MeasureStep.refA:
        setState(() {
          _refA = position;
          _measureStep = _MeasureStep.refB;
        });
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
          _measureStep = null;
        });
        _showResults();
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
              // Pinch with two fingers to zoom in on the implement; one
              // finger keeps scrubbing/drawing/tapping. Coordinates stay in
              // the video's own space, so measurements are zoom-proof.
              ? InteractiveViewer(
                  maxScale: 8,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(_controller),
                          DrawingCanvas(
                            controller: _drawing,
                            onJogFrames: _jogFrames,
                          ),
                          IgnorePointer(
                            ignoring: _measureStep == null,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) =>
                                  _onMeasureTap(details.localPosition),
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
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const CircularProgressIndicator(),
    );
  }

  /// Top scrim: back button, title, and the measure/fps actions, with the
  /// measurement instruction banner underneath while measuring.
  Widget _topOverlay() {
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
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    '${widget.video.event.label} · '
                    '${widget.video.gender.label}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
              ],
            ),
            if (_measureStep != null)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.straighten, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_measureInstruction,
                            style:
                                Theme.of(context).textTheme.bodyMedium),
                      ),
                      TextButton(
                        onPressed: _cancelMeasure,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom scrim: calibration hint, scrubber, and transport controls.
  Widget _bottomOverlay(ImplementSpec spec) {
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
              dense: true,
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
              child: Center(
                child: SingleChildScrollView(
                  child: _DrawingRail(controller: _drawing),
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
    }

    if (refA != null) crosshair(refA!, refPaint);
    if (refB != null) crosshair(refB!, refPaint);
    if (refA != null && refB != null) {
      canvas.drawLine(refA!, refB!, refPaint);
    }
    if (pointA != null) crosshair(pointA!, pointPaint);
    if (pointB != null) crosshair(pointB!, pointPaint);
    if (pointA != null && pointB != null) {
      canvas.drawLine(pointA!, pointB!, pointPaint);
    }
  }

  @override
  bool shouldRepaint(_MeasurePainter oldDelegate) =>
      refA != oldDelegate.refA ||
      refB != oldDelegate.refB ||
      pointA != oldDelegate.pointA ||
      pointB != oldDelegate.pointB;
}

/// Vertical, collapsible tool rail floating over the right edge of the
/// video: drawing tools, colors, undo/clear. Collapses to a single button
/// so it never crowds the footage.
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
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() => _open = false),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
