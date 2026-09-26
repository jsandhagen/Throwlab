import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../utils/frame_seeker.dart';
import '../utils/frame_timing.dart';
import '../utils/scrub.dart';
import '../utils/time_format.dart';
import 'gold.dart';

const kPlaybackSpeeds = [0.1, 0.25, 0.5, 0.75, 1.0];

/// Drag distance that advances the video one frame when scrubbing:
/// ~1 px per millisecond of REAL time the frame represents, so normal-speed
/// clips (33 ms frames) advance gently enough for seeks to keep rendering,
/// while slow-mo clips (4 ms frames) stay quick to traverse. Clamped so
/// both extremes remain usable.
double scrubPixelsPerFrame(double captureFps) =>
    captureFps <= 0 ? 8.0 : (1000 / captureFps).clamp(4.0, 40.0);

/// Snaps [position] to the seek target for the nearest frame, so slider
/// jumps land on exact frames instead of arbitrary milliseconds between
/// them. The target sits a [kSeekLead] short of the frame's own boundary
/// because the player renders the first frame at or after the position it is
/// given — snapping to the boundary itself lands on the next frame whenever
/// the clip's real timestamp is a rounding error above it.
Duration snapToFrame(Duration position, double fps) {
  final frameUs = Duration.microsecondsPerSecond / fps;
  final frame = (position.inMicroseconds / frameUs).round();
  // In seconds: where that frame starts, and how far apart frames are.
  final target = seekTargetSeconds(frame / fps, 1 / fps);
  return Duration(
      microseconds: (target * Duration.microsecondsPerSecond).round());
}

/// The gold a throw's release is marked in, wherever it is marked: the
/// notch on the clip line, the tick on the scale, the offset under the clock.
/// The medal's own metal, because the release is the moment the rest of the
/// clip is read against, and one color for it everywhere is what lets the
/// notch, the tick and the readout be recognized as the same thing.
Color get releaseColor => Medal.gold.flat;

/// What the hand feels as the clip moves under it: a click for every frame
/// the scale passes, the way a jog wheel on an editing desk has a detent per
/// frame, so frames can be counted without looking away from the athlete.
///
/// Three kinds, because three different things happen. A frame is Android's
/// clock tick ([HapticFeedback.selectionClick]); crossing the release is a
/// heavier one, so it can be found by feel; running into either end of the
/// clip is heavier again, once, because a scale that stops answering reads as
/// a drag that didn't take. Clicks are held to one per [minGap]: a fling
/// crosses a hundred frames a second, and a click for each is a buzz, where
/// a capped run is a ripple that slows down as the fling does. The release
/// and the end are never held back — they are the two that mean something.
///
/// Nothing here asks whether haptics are wanted: the phone's own touch
/// feedback setting mutes all three, which is where that is decided.
class FrameHaptics {
  FrameHaptics({Duration Function()? clock}) : _clock = clock ?? _elapsed;

  static const minGap = Duration(milliseconds: 35);

  static final Stopwatch _watch = Stopwatch()..start();
  static Duration _elapsed() => _watch.elapsed;

  final Duration Function() _clock;
  Duration? _lastClick;
  bool _atEnd = false;

  /// The frame the release is on, or null when none is marked.
  int? releaseFrame;

  /// The last frame of the clip; the far end the scale stops at.
  int lastFrame = 0;

  /// Moves from [from] towards [requested], clamped to the clip, and says so
  /// in the hand. Returns the frame it landed on.
  int step(int from, int requested) {
    final to = requested.clamp(0, math.max(lastFrame, 0)).toInt();
    if (to == from) {
      if (requested != from && !_atEnd) {
        _atEnd = true;
        HapticFeedback.mediumImpact();
      }
      return to;
    }
    _atEnd = false;
    final release = releaseFrame;
    if (release != null &&
        ((from < release && to >= release) ||
            (from > release && to <= release))) {
      _lastClick = _clock();
      HapticFeedback.lightImpact();
      return to;
    }
    final now = _clock();
    final last = _lastClick;
    if (last == null || now - last >= minGap) {
      _lastClick = now;
      HapticFeedback.selectionClick();
    }
    return to;
  }
}

/// Transport controls for a single video: the clip as one line with the
/// release notched into it, the scale under that for frame-precise work, and
/// the clock beside play and the frame steps.
class PlaybackControls extends StatefulWidget {
  const PlaybackControls({
    super.key,
    required this.controller,
    required this.fps,
    this.captureFps,
    this.trailing,
    this.dense = false,
    this.horizontal = false,
    this.release,
    this.onReleaseChanged,
    this.timers = const [],
    this.onScrubStart,
    this.onScrubBy,
    this.onScrubEnd,
  });

  final VideoPlayerController controller;
  final double fps;

  /// Real recorded frame rate (slow-mo clips); defaults to [fps]. Sets the
  /// scrub wheel's sensitivity via [scrubPixelsPerFrame].
  final double? captureFps;

  final Widget? trailing;

  /// Compact sizing for use as an overlay on top of the video.
  final bool dense;

  /// Lays everything out on a single line (the clip line and the scale
  /// stacked in the middle) so short landscape screens keep the video
  /// visible.
  final bool horizontal;

  /// The throw's release, or null when none is marked. The scale counts
  /// from it and the readout carries the offset to it.
  final Duration? release;

  /// Marks the release at the frame on screen, or clears it (null). Left
  /// null, there is no flag to mark one with.
  final ValueChanged<Duration?>? onReleaseChanged;

  /// Where the timers on the frame were dropped, and in what color: each is
  /// notched into the clip line so the moment a phase was timed from can be
  /// found again.
  final List<(Duration, Color)> timers;

  /// When set, the scrub wheel routes its motion through these instead of
  /// seeking the player itself — letting the host drive the smooth
  /// still-overlay scrub path (see AnalysisScreen). Left null (e.g. the
  /// comparison screen) the wheel seeks the player directly as before.
  final VoidCallback? onScrubStart;
  final ValueChanged<int>? onScrubBy;
  final VoidCallback? onScrubEnd;

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  late final FrameSeeker _seeker = FrameSeeker(widget.controller);
  final FrameHaptics _haptics = FrameHaptics();
  Timer? _repeat;

  VideoPlayerController get controller => widget.controller;
  double get fps => widget.fps;

  Duration get _frameStep =>
      Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _stepBy(int frames) {
    controller.pause();
    final from = frameAt(_seeker.position, fps);
    _haptics
      ..lastFrame = frameAt(controller.value.duration, fps)
      ..releaseFrame =
          widget.release == null ? null : frameAt(widget.release!, fps);
    final to = _haptics.step(from, from + frames);
    if (to == from) return;
    _seeker.seekBy(_frameStep * (to - from));
  }

  /// Held down, a frame step keeps stepping: a phase is a dozen frames, and
  /// a dozen taps is a dozen chances to lose count.
  void _startRepeat(int frames) {
    _repeat?.cancel();
    _stepBy(frames);
    _repeat = Timer.periodic(
        const Duration(milliseconds: 90), (_) => _stepBy(frames));
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Widget _stepButton({required bool forward, required double size}) =>
      GestureDetector(
        onLongPressStart: (_) => _startRepeat(forward ? 1 : -1),
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: IconButton(
          tooltip: forward ? 'Forward one frame' : 'Back one frame',
          iconSize: size,
          icon: Icon(forward ? Icons.skip_next : Icons.skip_previous),
          onPressed: () => _stepBy(forward ? 1 : -1),
        ),
      );

  void _seekTo(Duration target) {
    controller.pause();
    _seeker.seekTo(snapToFrame(target, fps));
  }

  /// The clock, and under it where the frame sits: the offset from the
  /// release when one is marked, and the frame number either way.
  Widget _readout(VideoPlayerValue value) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: small.color?.withOpacity(0.7));
    final release = widget.release;
    final frame = frameAt(value.position, fps);
    final sinceRelease = release == null
        ? null
        : 'R ${formatSinceRelease(frame - frameAt(release, fps), fps)}';
    const tabular = [FontFeature.tabularFigures()];
    // On its side there is one line to spend, beside the rail: the clock,
    // then the offset from the release where there is one, else the frame.
    if (widget.horizontal) {
      return Text.rich(
        TextSpan(children: [
          TextSpan(text: formatPosition(value.position)),
          const TextSpan(text: '  ·  '),
          if (release != null)
            TextSpan(
              text: sinceRelease,
              style: TextStyle(color: releaseColor),
            )
          else
            TextSpan(text: 'frame $frame'),
        ]),
        overflow: TextOverflow.ellipsis,
        style: small?.copyWith(fontFeatures: tabular),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatPosition(value.position),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: tabular)),
        Text.rich(
          TextSpan(children: [
            if (release != null) ...[
              TextSpan(
                text: sinceRelease,
                style: TextStyle(color: releaseColor),
              ),
              const TextSpan(text: ' · '),
            ],
            TextSpan(text: release == null ? 'frame $frame' : 'f $frame'),
          ]),
          overflow: TextOverflow.ellipsis,
          style: muted?.copyWith(fontFeatures: tabular),
        ),
      ],
    );
  }

  /// Marks the release on the frame on screen; on the release frame itself
  /// it takes it off again. Anywhere else with one already marked, it moves
  /// it — a release is re-marked far more often than it is cleared.
  Widget? _releaseFlag(VideoPlayerValue value) {
    final onChanged = widget.onReleaseChanged;
    if (onChanged == null) return null;
    final release = widget.release;
    final onIt = release != null &&
        frameAt(release, fps) == frameAt(value.position, fps);
    return IconButton(
      key: const ValueKey('release-flag'),
      tooltip: onIt
          ? 'Clear the release'
          : release == null
              ? 'Mark the release here'
              : 'Move the release here',
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      color: release == null ? null : releaseColor,
      icon: Icon(onIt ? Icons.flag : Icons.outlined_flag),
      onPressed: () {
        controller.pause();
        onChanged(onIt ? null : _seeker.position);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final dense = widget.dense;
        final clipLine = ClipLine(
          value: value,
          release: widget.release,
          timers: widget.timers,
          onSeek: _seekTo,
        );
        final flag = _releaseFlag(value);
        final readout = _readout(value);
        final stepSize = widget.horizontal ? 26.0 : (dense ? 30.0 : 38.0);
        final stepBack = _stepButton(forward: false, size: stepSize);
        final playPause = IconButton(
          iconSize: widget.horizontal ? 38 : (dense ? 44 : 56),
          icon: Icon(value.isPlaying ? Icons.pause_circle : Icons.play_circle),
          onPressed: () =>
              value.isPlaying ? controller.pause() : controller.play(),
        );
        final stepForward = _stepButton(forward: true, size: stepSize);
        final speed = SpeedMenuButton(
          speed: value.playbackSpeed,
          onChanged: controller.setPlaybackSpeed,
        );
        final wheel = ScrubWheel(
          controller: controller,
          fps: fps,
          captureFps: widget.captureFps,
          release: widget.release,
          onScrubStart: widget.onScrubStart,
          onScrubBy: widget.onScrubBy,
          onScrubEnd: widget.onScrubEnd,
          height: widget.horizontal ? 32 : 40,
        );

        if (widget.horizontal) {
          return Row(
            children: [
              const SizedBox(width: 12),
              readout,
              if (flag != null) flag,
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 18, child: clipLine),
                    wheel,
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
            SizedBox(height: 22, child: clipLine),
            wheel,
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child:
                        Align(alignment: Alignment.centerLeft, child: readout),
                  ),
                ),
                stepBack,
                playPause,
                stepForward,
                Expanded(
                  // Shrinks rather than overflowing on a phone narrower
                  // than the three transport buttons expect.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Beside the speed rather than the clock: the
                        // clock's column is the one short of width.
                        if (flag != null) flag,
                        speed,
                        if (widget.trailing != null) widget.trailing!,
                        const SizedBox(width: 12),
                      ],
                    ),
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

/// The whole clip as one hairline: what has been played in the theme's
/// primary, the release notched into it in gold and each timer in its own
/// ink. Tap or drag anywhere on it to go there — it is the slider it
/// replaced, drawn at the weight of a line on a scale rather than of a
/// control, since the scale under it is the control.
class ClipLine extends StatelessWidget {
  const ClipLine({
    super.key,
    required this.value,
    required this.onSeek,
    this.release,
    this.timers = const [],
  });

  final VideoPlayerValue value;
  final ValueChanged<Duration> onSeek;
  final Duration? release;
  final List<(Duration, Color)> timers;

  static const double inset = 18;

  void _seekAt(double dx, double width) {
    final span = width - 2 * inset;
    if (span <= 0) return;
    final t = ((dx - inset) / span).clamp(0.0, 1.0);
    onSeek(Duration(microseconds: (value.duration.inMicroseconds * t).round()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        key: const ValueKey('clip-line'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekAt(d.localPosition.dx, constraints.maxWidth),
        onHorizontalDragUpdate: (d) =>
            _seekAt(d.localPosition.dx, constraints.maxWidth),
        child: CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _ClipLinePainter(
            position: value.position,
            duration: value.duration,
            release: release,
            timers: timers,
            track: Colors.white.withOpacity(0.28),
            played: scheme.primary,
            releaseColor: releaseColor,
          ),
        ),
      ),
    );
  }
}

class _ClipLinePainter extends CustomPainter {
  _ClipLinePainter({
    required this.position,
    required this.duration,
    required this.release,
    required this.timers,
    required this.track,
    required this.played,
    required this.releaseColor,
  });

  final Duration position, duration;
  final Duration? release;
  final List<(Duration, Color)> timers;
  final Color track, played, releaseColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = ClipLine.inset;
    final span = size.width - 2 * inset;
    if (span <= 0) return;
    final total = duration.inMicroseconds;
    double xOf(Duration d) =>
        inset +
        span * (total <= 0 ? 0 : (d.inMicroseconds / total).clamp(0.0, 1.0));
    final y = size.height * 0.62;
    canvas.drawLine(
        Offset(inset, y),
        Offset(inset + span, y),
        Paint()
          ..color = track
          ..strokeWidth = 1);
    final at = xOf(position);
    canvas.drawLine(
        Offset(inset, y),
        Offset(at, y),
        Paint()
          ..color = played
          ..strokeWidth = 1.5);
    // Notches hang above the line, pointing at the moment they mark, so
    // they read as marks on it rather than as more playheads.
    void notch(double x, Color color) {
      final path = Path()
        ..moveTo(x - 3.5, y - 8)
        ..lineTo(x + 3.5, y - 8)
        ..lineTo(x, y - 2.5)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    for (final (from, color) in timers) {
      notch(xOf(from), color);
    }
    if (release != null) notch(xOf(release!), releaseColor);
    canvas.drawCircle(Offset(at, y), 3.5, Paint()..color = played);
  }

  @override
  bool shouldRepaint(_ClipLinePainter old) =>
      position != old.position ||
      duration != old.duration ||
      release != old.release ||
      timers != old.timers ||
      track != old.track ||
      played != old.played;
}

/// The scale: a wheel turned under a fixed needle. Drag to step through
/// frames, flick it and it keeps spinning. It carries a tick per frame and
/// a numbered tick at a round interval of time, counted from the release
/// once one is marked (so the numbers are the ones a coach says out loud:
/// 'five hundredths before release') and from the start of the clip until
/// then.
///
/// It feels like a wheel because it behaves like one. A drag to the right
/// goes forward, as it does on the frame itself, and the surface moves with
/// the finger — so the later frames are on the left, rolling round to the
/// needle as the drum is turned, the way the numbers on a jog dial or a
/// combination lock come to the mark. Both the other ways were tried: a
/// ruler reading left to right under a rightward drag ran against the
/// thumb, and one pulled leftward like a tape felt backwards. While it is being turned it
/// draws where the finger has taken it — the frames it has stepped plus the
/// part of a frame not stepped yet — rather than where the player has got
/// to, which lags a scrub by a seek; let go, it eases into the frame it
/// stopped on like a detent, and only then goes back to following the
/// player. And it is drawn as a drum seen face on: ticks close up and dim
/// toward the edges, and the numbers are foreshortened with them.
/// Sensitivity scales with the clip's real frame rate (see
/// [scrubPixelsPerFrame]), and every frame it passes is a click in the hand
/// ([FrameHaptics]).
class ScrubWheel extends StatefulWidget {
  const ScrubWheel({
    super.key,
    required this.controller,
    required this.fps,
    this.captureFps,
    this.release,
    this.height = 40,
    this.onScrubStart,
    this.onScrubBy,
    this.onScrubEnd,
  });

  final VideoPlayerController controller;
  final double fps;
  final double? captureFps;

  /// The throw's release: the zero the numbers count from, and a detent
  /// in the hand. Null counts from the start of the clip.
  final Duration? release;
  final double height;

  /// When set, wheel motion is reported as frame steps through these instead
  /// of seeking the player directly, so the host can drive the smooth scrub
  /// overlay (and momentum feeds it too).
  final VoidCallback? onScrubStart;
  final ValueChanged<int>? onScrubBy;
  final VoidCallback? onScrubEnd;

  @override
  State<ScrubWheel> createState() => _ScrubWheelState();
}

class _ScrubWheelState extends State<ScrubWheel> with TickerProviderStateMixin {
  double get _pixelsPerFrame =>
      scrubPixelsPerFrame(widget.captureFps ?? widget.fps);

  /// Fraction of fling velocity left after one second of coasting.
  static const _decayPerSecond = 0.02;

  /// Coasting stops below this speed (px/s) — about 5 frames/s.
  static const _restVelocity = 40.0;

  /// How long the wheel keeps its own reading after it has settled, for the
  /// player to catch up with the frame it was turned to — past that it
  /// follows the player again, wherever the player is.
  static const _handBack = Duration(milliseconds: 400);

  late final FrameSeeker _seeker = FrameSeeker(widget.controller);
  late final Ticker _ticker;
  late final AnimationController _settle;
  final ScrubAccumulator _scrub = ScrubAccumulator();
  final FrameHaptics _haptics = FrameHaptics();
  double _velocity = 0;
  Duration _lastTick = Duration.zero;
  Timer? _release;
  double _settleFrom = 0;

  /// The frame the wheel has been turned to in this gesture. Counted here
  /// rather than read off the player, which is a seek or a still behind the
  /// finger, so a click lands on the frame it belongs to.
  int _frame = 0;

  /// Where the wheel is drawn while it is in the hand, in fractional frames;
  /// null when it is following the player.
  final ValueNotifier<double?> _held = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy ticker that is never flung would be created
    // during dispose(), when looking up the TickerMode is illegal.
    _ticker = createTicker(_onTick);
    _settle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160))
      ..addListener(_onSettle)
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        _release?.cancel();
        _release = Timer(_handBack, () => _held.value = null);
      });
  }

  @override
  void dispose() {
    _release?.cancel();
    _ticker.dispose();
    _settle.dispose();
    _held.dispose();
    super.dispose();
  }

  Duration get _frameStep => Duration(
      microseconds: (Duration.microsecondsPerSecond / widget.fps).round());

  /// Routes a frame step either to the host's smooth scrub path (when wired)
  /// or straight to the player's seeker, clamped to the clip and felt.
  void _emit(int frames) {
    if (frames != 0) {
      final from = _frame;
      _frame = _haptics.step(from, from + frames);
      final moved = _frame - from;
      if (moved != 0) {
        if (widget.onScrubBy != null) {
          widget.onScrubBy!(moved);
        } else {
          _seeker.seekBy(_frameStep * moved);
        }
      }
    }
    _held.value = (_frame + _scrub.fraction)
        .clamp(0.0, math.max(_haptics.lastFrame, 0).toDouble());
  }

  /// Accelerated step from a live finger drag: to the right is forward.
  void _onDragUpdate(DragUpdateDetails details) {
    _emit(_scrub.addDrag(details.delta.dx, _pixelsPerFrame,
        timestamp: details.sourceTimeStamp));
  }

  void _onDragStart(DragStartDetails details) {
    widget.controller.pause();
    _ticker.stop();
    _settle.stop();
    _release?.cancel();
    _velocity = 0;
    _scrub.reset();
    final release = widget.release;
    _haptics
      ..lastFrame = frameAt(widget.controller.value.duration, widget.fps)
      ..releaseFrame = release == null ? null : frameAt(release, widget.fps);
    // Picked up where it was drawn, whether that is still settling or
    // following the player.
    _frame = _held.value?.round() ?? frameAt(_seeker.position, widget.fps);
    _held.value = _frame.toDouble();
    widget.onScrubStart?.call();
  }

  void _onDragEnd(DragEndDetails details) {
    // Hand the fling off at the rate the finger was actually scrubbing —
    // the drag's acceleration folded in — so momentum continues the motion
    // instead of snapping back to 1× at release.
    _velocity = details.velocity.pixelsPerSecond.dx * _scrub.lastGain;
    if (_velocity.abs() < _restVelocity) {
      _settleIn();
      widget.onScrubEnd?.call();
      return;
    }
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    // Coast at 1× — the velocity already carries the drag's acceleration.
    _emit(_scrub.addRaw(_velocity * dt, _pixelsPerFrame));
    _velocity *= math.pow(_decayPerSecond, dt);
    if (_velocity.abs() < _restVelocity) {
      _ticker.stop();
      _settleIn();
      // Momentum spent: the scrub session is over.
      widget.onScrubEnd?.call();
    }
  }

  /// Eases the part of a frame the wheel was left between into the frame
  /// it stepped to, so it comes to rest on a tick the way a detented wheel
  /// does rather than snapping there.
  void _settleIn() {
    _settleFrom = _held.value ?? _frame.toDouble();
    _settle.forward(from: 0);
  }

  void _onSettle() {
    final t = Curves.easeOutCubic.transform(_settle.value);
    _held.value = _settleFrom + (_frame - _settleFrom) * t;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      key: const ValueKey('scrub-wheel'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, _held]),
        builder: (context, _) {
          final value = widget.controller.value;
          final held = _held.value;
          // In the hand, where the hand has it. Playing, where the clip is,
          // continuously. Paused, on the tick of the frame on screen: a seek
          // lands a little short of the frame it shows, and the needle has
          // to sit on that frame's tick.
          final frames = held ??
              (value.isPlaying
                  ? value.position.inMicroseconds /
                      Duration.microsecondsPerSecond *
                      widget.fps
                  : frameAt(value.position, widget.fps).toDouble());
          return SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: ScalePainter(
                frames: frames,
                fps: widget.fps,
                spacing: _pixelsPerFrame,
                release: widget.release,
                tickColor: Colors.white,
                needleColor: theme.colorScheme.primary,
                releaseColor: releaseColor,
                labelStyle: theme.textTheme.labelSmall,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The round intervals a scale is numbered at, in seconds.
const _labelSteps = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0];

/// The wheel itself, seen face on. A frame is a tick [spacing] pixels apart
/// *on the drum's surface*, which is what they are in the middle, under the
/// needle, where the finger is; toward the edges the surface turns away, so
/// the same spacing projects closer and closer together and dims with the
/// light falling off it. The numbered ticks fall at the shortest round
/// interval of time that leaves [minLabelGap] between numbers at the middle
/// — so a 240 fps clip is read in hundredths and a 30 fps one in tenths,
/// each at the density it can actually be scrubbed at.
class ScalePainter extends CustomPainter {
  ScalePainter({
    required this.frames,
    required this.fps,
    required this.spacing,
    required this.release,
    required this.tickColor,
    required this.needleColor,
    required this.releaseColor,
    this.labelStyle,
  });

  /// Where the wheel is turned to, in frames (fractional between them).
  final double frames;
  final double fps;
  final double spacing;
  final Duration? release;
  final Color tickColor, needleColor, releaseColor;

  /// Handed down from the theme: a painter's TextSpan inherits nothing, and
  /// left alone the numbers would be in the engine's fallback face.
  final TextStyle? labelStyle;

  static const double minLabelGap = 44;

  /// How far round the drum the visible face reaches either side of the
  /// needle. Short of a quarter turn, so the last ticks at the edge are
  /// still ticks rather than a smear.
  static const double _reach = 1.3;

  /// The labeled interval, in seconds, for a scale at [fps] frames a second
  /// drawn [spacing] pixels a frame.
  static double labelStep(double fps, double spacing) {
    final pxPerSecond = fps * spacing;
    for (final step in _labelSteps) {
      if (step * pxPerSecond >= minLabelGap) return step;
    }
    return _labelSteps.last;
  }

  /// A number on the scale: signed seconds from the release, which reads
  /// 'R' on the release itself, or plain seconds into the clip.
  static String label(double seconds, double step, {required bool relative}) {
    final decimals = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    final text = seconds.abs().toStringAsFixed(decimals);
    if (!relative) return text;
    if (double.parse(text) == 0) return 'R';
    return '${seconds < 0 ? '-' : '+'}$text';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fps <= 0 || spacing <= 0) return;
    final half = size.width / 2;
    // The drum's radius, in the surface's own pixels: the visible face
    // spans [_reach] radians either side, projected onto the half width.
    final radius = half / math.sin(_reach);
    // Ticks hang from the top edge; the numbers sit under them.
    final majorLength = size.height * 0.4;
    final minorLength = majorLength * 0.45;

    /// Where a point [frame] frames round the surface lands on screen, and
    /// how squarely it faces the eye (1 under the needle, 0 edge on) —
    /// null once it has turned out of view.
    (double, double)? project(double frame) {
      // Later frames sit to the left of the needle, so that turning the
      // drum to the right brings them round to it.
      final angle = (frames - frame) * spacing / radius;
      if (angle.abs() > _reach) return null;
      return (half + radius * math.sin(angle), math.cos(angle));
    }

    // A tick per frame.
    final reachFrames = _reach * radius / spacing;
    for (var f = (frames - reachFrames).floor();
        f <= (frames + reachFrames).ceil();
        f++) {
      if (f < 0) continue;
      final at = project(f.toDouble());
      if (at == null) continue;
      final (x, facing) = at;
      canvas.drawLine(
          Offset(x, 2),
          Offset(x, 2 + minorLength * (0.7 + 0.3 * facing)),
          Paint()
            ..color = tickColor.withOpacity(0.08 + 0.5 * facing * facing)
            ..strokeWidth = 0.6 + 0.5 * facing);
    }

    // Numbered ticks, at a round interval from the zero.
    final step = labelStep(fps, spacing);
    final zero = release == null ? 0.0 : frameAt(release!, fps) / fps;
    final now = frames / fps;
    final span = reachFrames / fps;
    final firstK = ((now - span - zero) / step).floor();
    final lastK = ((now + span - zero) / step).ceil();
    final base = labelStyle ?? const TextStyle(fontSize: 10);
    for (var k = firstK; k <= lastK; k++) {
      final t = zero + k * step;
      if (t < 0) continue;
      final at = project(t * fps);
      if (at == null) continue;
      final (x, facing) = at;
      final isRelease = release != null && k == 0;
      final color = isRelease ? releaseColor : tickColor;
      final light = facing * facing;
      canvas.drawLine(
          Offset(x, 2),
          Offset(x, 2 + majorLength * (0.7 + 0.3 * facing)),
          Paint()
            ..color = color.withOpacity(isRelease ? light : 0.12 + 0.7 * light)
            ..strokeWidth = (isRelease ? 2 : 1.2) * (0.6 + 0.4 * facing));
      // A number turned far enough away to be squashed past reading is
      // left off; its tick still says where it is.
      if (facing < 0.5) continue;
      final text = TextPainter(
        text: TextSpan(
          text: label(k * step, step, relative: release != null),
          style: base.copyWith(
            color: color.withOpacity(isRelease ? light : 0.65 * light),
            fontSize: 10,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Foreshortened with the surface it is printed on.
      canvas
        ..save()
        ..translate(x, size.height - text.height - 1)
        ..scale(facing, 1);
      text.paint(canvas, Offset(-text.width / 2, 0));
      canvas.restore();
    }

    // The needle: the frame on screen.
    canvas.drawLine(
        Offset(half, 0),
        Offset(half, 4 + majorLength),
        Paint()
          ..color = needleColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(ScalePainter old) =>
      frames != old.frames ||
      fps != old.fps ||
      spacing != old.spacing ||
      release != old.release ||
      tickColor != old.tickColor ||
      needleColor != old.needleColor ||
      labelStyle != old.labelStyle;
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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
    );
  }
}
