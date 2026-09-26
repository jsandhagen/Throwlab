import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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

  /// Takes the clip straight to the release, which is where a throw is
  /// looked at from: a coach who has scrubbed off to time the block or
  /// check the finish wants back to the moment the rest is measured around
  /// without hunting for the notch on the clip line.
  void _jumpToRelease() {
    final release = widget.release;
    if (release == null) return;
    if (frameAt(release, fps) != frameAt(_seeker.position, fps)) {
      HapticFeedback.lightImpact();
    }
    _seekTo(release);
  }

  /// The offset from the release, as the button that goes there. It is the
  /// number that already says how far off the release the frame is, so it
  /// is the one to press to close the gap — set in the release's gold, in a
  /// gold outline so it reads as a thing to press rather than a caption, and
  /// with an arrow pointing the way the release lies. On the release itself
  /// there is nowhere to go, and the arrow goes with it.
  Widget _releaseJump(int offset, TextStyle? style) {
    final arrow = offset < 0
        ? Icons.arrow_forward
        : offset > 0
            ? Icons.arrow_back
            : null;
    return Tooltip(
      message: 'Jump to the release',
      child: InkWell(
        key: const ValueKey('release-jump'),
        borderRadius: BorderRadius.circular(10),
        onTap: offset == 0 ? null : _jumpToRelease,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 1, 4, 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: releaseColor.withOpacity(0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('R ${formatSinceRelease(offset, fps)}',
                  style: style?.copyWith(color: releaseColor)),
              if (arrow != null) ...[
                const SizedBox(width: 2),
                Icon(arrow, size: 12, color: releaseColor),
              ] else
                const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// The clock, and under it where the frame sits: the offset from the
  /// release when one is marked — which is also the way back to it — and
  /// the frame number either way.
  Widget _readout(VideoPlayerValue value) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: small.color?.withOpacity(0.7));
    final release = widget.release;
    final frame = frameAt(value.position, fps);
    final offset = release == null ? null : frame - frameAt(release, fps);
    const tabular = [FontFeature.tabularFigures()];
    // On its side there is one line to spend, beside the rail: the clock,
    // then the offset from the release where there is one, else the frame.
    if (widget.horizontal) {
      final style = small?.copyWith(fontFeatures: tabular);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${formatPosition(value.position)}  ·  ',
              overflow: TextOverflow.ellipsis, style: style),
          if (offset != null)
            _releaseJump(offset, style)
          else
            Text('frame $frame', style: style),
        ],
      );
    }
    final style = muted?.copyWith(fontFeatures: tabular);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatPosition(value.position),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: tabular)),
        if (offset != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _releaseJump(offset, style),
              Flexible(
                child: Text(' · f $frame',
                    overflow: TextOverflow.ellipsis, style: style),
              ),
            ],
          )
        else
          Text('frame $frame', overflow: TextOverflow.ellipsis, style: style),
      ],
    );
  }

  /// Marks the release on the frame on screen; on the release frame itself
  /// it takes it off again. Anywhere else with one already marked, it moves
  /// it — a release is re-marked far more often than it is cleared.
  ///
  /// It says what it is under it. A flag on its own was read as a bookmark,
  /// or as nothing — and the release is the one mark the whole screen
  /// counts from, so the button that sets it is the one worth a word.
  Widget? _releaseFlag(VideoPlayerValue value) {
    final onChanged = widget.onReleaseChanged;
    if (onChanged == null) return null;
    final release = widget.release;
    final onIt = release != null &&
        frameAt(release, fps) == frameAt(value.position, fps);
    final color = release == null
        ? Theme.of(context).colorScheme.onSurface
        : releaseColor;
    return Tooltip(
      message: onIt
          ? 'Clear the release'
          : release == null
              ? 'Mark the release here'
              : 'Move the release here',
      child: InkResponse(
        key: const ValueKey('release-flag'),
        radius: 26,
        onTap: () {
          controller.pause();
          onChanged(onIt ? null : _seeker.position);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(onIt ? Icons.flag : Icons.outlined_flag,
                  size: 20, color: color),
              Text(
                release == null ? 'RELEASE' : (onIt ? 'CLEAR R' : 'MOVE R'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: color.withOpacity(0.85),
                    ),
              ),
            ],
          ),
        ),
      ),
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
                    // Shrinks rather than overflowing, as the right-hand
                    // side does: the release pill is wider than the text it
                    // replaced, and a narrow phone is short of it.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: readout,
                    ),
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

  /// How long after the wheel is let go the player's own reports are left
  /// alone: a scrub hands back to the decoder with a seek or two in flight,
  /// and following each of them would wobble the wheel it just set down.
  static const _handBack = Duration(milliseconds: 350);

  late final FrameSeeker _seeker = FrameSeeker(widget.controller);
  late final Ticker _coastTicker;
  late final AnimationController _settle;
  final ScrubAccumulator _scrub = ScrubAccumulator();
  final FrameHaptics _haptics = FrameHaptics();
  FrictionSimulation? _coast;
  Timer? _quiet;

  /// Where the wheel is turned to, in fractional frames: one number, which
  /// is what is drawn and what the frame is read off. The frame stepped to
  /// is always the nearest one to it, so the tick under the needle and the
  /// picture on screen are never a frame apart.
  final ValueNotifier<double> _shown = ValueNotifier(0);

  /// The frame the wheel is on, as stepped — counted here rather than read
  /// off the player, which is a seek or a still behind the finger, so a
  /// click lands on the frame it belongs to.
  int _frame = 0;

  /// While a finger or a fling has it, the wheel answers to that alone.
  bool _inHand = false;

  /// Where an ease toward a resting frame started and is going.
  double _settleFrom = 0;
  double _settleTo = 0;

  double get _lastFrame => math.max(_haptics.lastFrame, 0).toDouble();

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy ticker that is never flung would be created
    // during dispose(), when looking up the TickerMode is illegal.
    _coastTicker = createTicker(_onCoast);
    _settle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160))
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_settle.value);
        _shown.value = _settleFrom + (_settleTo - _settleFrom) * t;
      });
    _shown.value = _settleTo =
        frameAt(widget.controller.value.position, widget.fps).toDouble();
    widget.controller.addListener(_follow);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    _quiet?.cancel();
    _coastTicker.dispose();
    _settle.dispose();
    _shown.dispose();
    super.dispose();
  }

  Duration get _frameStep => Duration(
      microseconds: (Duration.microsecondsPerSecond / widget.fps).round());

  /// Eases the wheel to rest on [frame], from wherever it is drawn now: the
  /// one way it ever gets to a new place without a hand on it, so it never
  /// jumps.
  void _easeTo(double frame) {
    if (frame == _settleTo && (_settle.isAnimating || _shown.value == frame)) {
      return;
    }
    _settleFrom = _shown.value;
    _settleTo = frame;
    _settle.forward(from: 0);
  }

  /// Follows the player while nobody is turning the wheel: continuously
  /// while it plays, and eased onto the frame it stops on.
  void _follow() {
    if (_inHand || _quiet != null) return;
    final value = widget.controller.value;
    if (value.isPlaying) {
      _settle.stop();
      _settleTo = _shown.value = value.position.inMicroseconds /
          Duration.microsecondsPerSecond *
          widget.fps;
      return;
    }
    _easeTo(frameAt(value.position, widget.fps).toDouble());
  }

  /// Turns the wheel by [frames] (fractional), steps to the frame nearest
  /// where it now is, and says so in the hand and to the player. Returns
  /// whether it ran into an end.
  bool _turn(double frames) {
    final raw = _shown.value + frames;
    final clamped = raw.clamp(0.0, _lastFrame);
    _shown.value = clamped;
    final from = _frame;
    _frame = _haptics.step(from, raw.round());
    final moved = _frame - from;
    if (moved != 0) {
      if (widget.onScrubBy != null) {
        widget.onScrubBy!(moved);
      } else {
        _seeker.seekBy(_frameStep * moved);
      }
    }
    return clamped != raw;
  }

  void _onDragStart(DragStartDetails details) {
    widget.controller.pause();
    _coastTicker.stop();
    _coast = null;
    _settle.stop();
    _quiet?.cancel();
    _quiet = null;
    _inHand = true;
    _scrub.reset();
    final release = widget.release;
    _haptics
      ..lastFrame = frameAt(widget.controller.value.duration, widget.fps)
      ..releaseFrame = release == null ? null : frameAt(release, widget.fps);
    // Picked up on the frame it was resting on or easing to, so the first
    // move steps from there rather than from half way through an ease.
    _frame = _settleTo.round();
    _shown.value = _frame.toDouble();
    widget.onScrubStart?.call();
  }

  /// A drag to the right is forward, at the drag's own acceleration: the
  /// accumulator is asked only for the gain, and the wheel keeps its own
  /// position.
  void _onDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;
    _scrub.addDrag(dx, _pixelsPerFrame, timestamp: details.sourceTimeStamp);
    _turn(dx * _scrub.lastGain / _pixelsPerFrame);
  }

  void _onDragEnd(DragEndDetails details) {
    // The fling picks up at the rate the wheel was actually turning — the
    // drag's acceleration folded in — so it carries on rather than
    // snapping back to 1× at the release.
    final velocity =
        details.velocity.pixelsPerSecond.dx * _scrub.lastGain / _pixelsPerFrame;
    if (velocity.abs() * _pixelsPerFrame < _restVelocity) {
      _letGo();
      return;
    }
    // One smooth curve from the release speed to rest, rather than a
    // velocity decayed and added up tick by tick.
    _coast = FrictionSimulation(_decayPerSecond, _shown.value, velocity);
    _coastTicker.start();
  }

  void _onCoast(Duration elapsed) {
    final coast = _coast;
    if (coast == null) return;
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final hitEnd = _turn(coast.x(t) - _shown.value);
    if (hitEnd || coast.dx(t).abs() * _pixelsPerFrame < _restVelocity) {
      _coastTicker.stop();
      _coast = null;
      _letGo();
    }
  }

  /// Out of the hand: eases onto the frame it stepped to, then — once the
  /// scrub's own handoff to the decoder has had time to land — follows the
  /// player again.
  void _letGo() {
    _inHand = false;
    _easeTo(_frame.toDouble());
    widget.onScrubEnd?.call();
    _quiet?.cancel();
    _quiet = Timer(_handBack, () {
      _quiet = null;
      if (mounted) _follow();
    });
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
      child: ValueListenableBuilder<double>(
        valueListenable: _shown,
        builder: (context, frames, _) => SizedBox(
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
        ),
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

  /// How far apart the numbers go, in seconds and in frames, for a scale at
  /// [fps] frames a second drawn [spacing] pixels a frame: the shortest
  /// round interval of time that is a whole number of frames and leaves
  /// [minLabelGap] between numbers. Whole frames because a number is only
  /// ever on a tick — a twentieth of a second at 30 fps is a frame and a
  /// half, and numbering it put every other number between two ticks, a
  /// scale that read as unevenly cut. A rate no round interval divides is
  /// numbered every so many frames instead.
  static ({double seconds, int frames}) labelInterval(
      double fps, double spacing) {
    for (final step in _labelSteps) {
      final exact = step * fps;
      final whole = exact.round();
      if (whole < 1 || (exact - whole).abs() > 0.05) continue;
      if (whole * spacing >= minLabelGap) return (seconds: step, frames: whole);
    }
    for (final whole in const [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]) {
      if (whole * spacing >= minLabelGap) {
        return (seconds: whole / fps, frames: whole);
      }
    }
    return (seconds: 1000 / fps, frames: 1000);
  }

  /// A number on the scale: signed seconds from the release, which reads
  /// 'R' on the release itself, or plain seconds into the clip.
  static String label(double seconds, double step, {required bool relative}) {
    final decimals = step >= 1
        ? 0
        : step >= 0.1
            ? 1
            : step >= 0.01
                ? 2
                : 3;
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

    // Numbered ticks, every so many frames from the zero, so each one is
    // on a frame's own tick.
    final interval = labelInterval(fps, spacing);
    final zero = release == null ? 0 : frameAt(release!, fps);
    final firstK = ((frames - reachFrames - zero) / interval.frames).floor();
    final lastK = ((frames + reachFrames - zero) / interval.frames).ceil();
    final base = labelStyle ?? const TextStyle(fontSize: 10);
    for (var k = firstK; k <= lastK; k++) {
      final frame = zero + k * interval.frames;
      if (frame < 0) continue;
      final at = project(frame.toDouble());
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
          text: label(k * interval.seconds, interval.seconds,
              relative: release != null),
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
