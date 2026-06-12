import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../utils/frame_seeker.dart';
import '../utils/time_format.dart';

const kPlaybackSpeeds = [0.1, 0.25, 0.5, 0.75, 1.0];

/// Drag distance that advances the video one frame when scrubbing:
/// ~1 px per millisecond of REAL time the frame represents, so normal-speed
/// clips (33 ms frames) advance gently enough for seeks to keep rendering,
/// while slow-mo clips (4 ms frames) stay quick to traverse. Clamped so
/// both extremes remain usable.
double scrubPixelsPerFrame(double captureFps) =>
    captureFps <= 0 ? 8.0 : (1000 / captureFps).clamp(4.0, 40.0);

/// Rounds [position] to the nearest frame boundary so seeks land on exact
/// frames instead of arbitrary milliseconds between them.
Duration snapToFrame(Duration position, double fps) {
  final frameUs = Duration.microsecondsPerSecond / fps;
  return Duration(
      microseconds: ((position.inMicroseconds / frameUs).round() * frameUs)
          .round());
}

/// Transport controls for a single video: a thin slider for coarse jumps,
/// a scrub wheel for frame-precise work, and play/step buttons centered
/// under it with the speed menu off to the side.
class PlaybackControls extends StatefulWidget {
  const PlaybackControls({
    super.key,
    required this.controller,
    required this.fps,
    this.captureFps,
    this.trailing,
    this.dense = false,
    this.horizontal = false,
  });

  final VideoPlayerController controller;
  final double fps;

  /// Real recorded frame rate (slow-mo clips); defaults to [fps]. Sets the
  /// scrub wheel's sensitivity via [scrubPixelsPerFrame].
  final double? captureFps;

  final Widget? trailing;

  /// Compact sizing for use as an overlay on top of the video.
  final bool dense;

  /// Lays everything out on a single line (slider and wheel stacked in the
  /// middle) so short landscape screens keep the video visible.
  final bool horizontal;

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  late final FrameSeeker _seeker = FrameSeeker(widget.controller);

  VideoPlayerController get controller => widget.controller;
  double get fps => widget.fps;

  Duration get _frameStep =>
      Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());

  void _stepBy(int frames) {
    controller.pause();
    _seeker.seekBy(_frameStep * frames);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration.inMilliseconds;
        final position =
            value.position.inMilliseconds.clamp(0, duration).toDouble();
        final dense = widget.dense;
        final slider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: duration == 0 ? 0 : position,
            max: duration == 0 ? 1 : duration.toDouble(),
            onChanged: (ms) {
              controller.pause();
              _seeker.seekTo(
                  snapToFrame(Duration(milliseconds: ms.round()), fps));
            },
          ),
        );
        final timeText = Text(
          '${formatPosition(value.position)}  ·  '
          'frame ${frameAt(value.position, fps)}',
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        );
        final stepBack = IconButton(
          tooltip: 'Back one frame',
          iconSize: widget.horizontal ? 26 : (dense ? 30 : 38),
          icon: const Icon(Icons.skip_previous),
          onPressed: () => _stepBy(-1),
        );
        final playPause = IconButton(
          iconSize: widget.horizontal ? 38 : (dense ? 44 : 56),
          icon: Icon(
              value.isPlaying ? Icons.pause_circle : Icons.play_circle),
          onPressed: () =>
              value.isPlaying ? controller.pause() : controller.play(),
        );
        final stepForward = IconButton(
          tooltip: 'Forward one frame',
          iconSize: widget.horizontal ? 26 : (dense ? 30 : 38),
          icon: const Icon(Icons.skip_next),
          onPressed: () => _stepBy(1),
        );
        final speed = SpeedMenuButton(
          speed: value.playbackSpeed,
          onChanged: controller.setPlaybackSpeed,
        );

        if (widget.horizontal) {
          return Row(
            children: [
              const SizedBox(width: 12),
              timeText,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 20, child: slider),
                    ScrubWheel(
                        controller: controller,
                        fps: fps,
                        captureFps: widget.captureFps,
                        height: 32),
                  ],
                ),
              ),
              stepBack,
              playPause,
              stepForward,
              speed,
              if (widget.trailing != null) widget.trailing!,
              const SizedBox(width: 8),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 26, child: slider),
            ScrubWheel(
                controller: controller,
                fps: fps,
                captureFps: widget.captureFps),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Align(
                        alignment: Alignment.centerLeft, child: timeText),
                  ),
                ),
                stepBack,
                playPause,
                stepForward,
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      speed,
                      if (widget.trailing != null) widget.trailing!,
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Flywheel scrubber: drag to step through frames, flick to keep spinning
/// with momentum. Dragging right moves forward, matching the drag-to-scrub
/// gesture on the video itself; sensitivity scales with the clip's real
/// frame rate (see [scrubPixelsPerFrame]).
class ScrubWheel extends StatefulWidget {
  const ScrubWheel({
    super.key,
    required this.controller,
    required this.fps,
    this.captureFps,
    this.height = 44,
  });

  final VideoPlayerController controller;
  final double fps;
  final double? captureFps;
  final double height;

  @override
  State<ScrubWheel> createState() => _ScrubWheelState();
}

class _ScrubWheelState extends State<ScrubWheel>
    with SingleTickerProviderStateMixin {
  double get _pixelsPerFrame =>
      scrubPixelsPerFrame(widget.captureFps ?? widget.fps);

  /// Fraction of fling velocity left after one second of coasting.
  static const _decayPerSecond = 0.02;

  /// Coasting stops below this speed (px/s) — about 5 frames/s.
  static const _restVelocity = 40.0;

  late final FrameSeeker _seeker = FrameSeeker(widget.controller);
  late final Ticker _ticker = createTicker(_onTick);
  double _accumulator = 0;
  double _velocity = 0;
  Duration _lastTick = Duration.zero;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Duration get _frameStep => Duration(
      microseconds: (Duration.microsecondsPerSecond / widget.fps).round());

  void _scrollBy(double dx) {
    _accumulator += dx;
    final frames = _accumulator ~/ _pixelsPerFrame;
    if (frames != 0) {
      _accumulator -= frames * _pixelsPerFrame;
      _seeker.seekBy(_frameStep * frames);
    }
  }

  void _onDragStart(DragStartDetails details) {
    widget.controller.pause();
    _ticker.stop();
    _velocity = 0;
    _accumulator = 0;
  }

  void _onDragEnd(DragEndDetails details) {
    _velocity = details.velocity.pixelsPerSecond.dx;
    if (_velocity.abs() < _restVelocity) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _scrollBy(_velocity * dt);
    _velocity *= math.pow(_decayPerSecond, dt);
    if (_velocity.abs() < _restVelocity) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: (details) => _scrollBy(details.delta.dx),
      onHorizontalDragEnd: _onDragEnd,
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) => SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WheelPainter(
              phase: value.position.inMicroseconds /
                  _frameStep.inMicroseconds *
                  _pixelsPerFrame,
              spacing: _pixelsPerFrame,
              tickColor: Colors.white70,
              markerColor: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tick texture that slides with the video position under a fixed center
/// marker; tick brightness falls off toward the edges to suggest the curve
/// of a physical wheel.
class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.phase,
    required this.spacing,
    required this.tickColor,
    required this.markerColor,
  });

  /// Horizontal tick offset in pixels: current frame × pixels-per-frame.
  final double phase;

  /// One tick per frame, matching the wheel's drag ratio.
  final double spacing;

  final Color tickColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final half = size.width / 2;
    final first = ((-phase) / spacing).ceil();
    final last = ((size.width - phase) / spacing).floor();
    for (var k = first; k <= last; k++) {
      final x = k * spacing + phase;
      final isMajor = k % 5 == 0;
      final tall = isMajor ? 18.0 : 10.0;
      final fade =
          (1 - math.pow((x - half) / half, 2)).clamp(0.0, 1.0).toDouble();
      final paint = Paint()
        ..color = tickColor.withOpacity(0.15 + 0.85 * fade)
        ..strokeWidth = isMajor ? 2.5 : 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(x, mid - tall / 2), Offset(x, mid + tall / 2), paint);
    }
    final marker = Paint()
      ..color = markerColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(half, mid - 13), Offset(half, mid + 13), marker);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      phase != oldDelegate.phase ||
      spacing != oldDelegate.spacing ||
      tickColor != oldDelegate.tickColor ||
      markerColor != oldDelegate.markerColor;
}

class SpeedMenuButton extends StatelessWidget {
  const SpeedMenuButton({
    super.key,
    required this.speed,
    required this.onChanged,
  });

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final s in kPlaybackSpeeds)
          PopupMenuItem(value: s, child: Text('${s}x')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text('${speed}x',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 17)),
      ),
    );
  }
}
