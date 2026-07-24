import 'dart:math' as math;

import 'package:video_player/video_player.dart';

/// Coalesces rapid seek requests so only one platform seek is in flight at
/// a time. Jump seeks ([seekTo]) go straight to the newest target; scrub
/// seeks ([seekBy]) chase it a few frames per platform seek, so the video
/// plays through the frames at the scrub speed instead of teleporting
/// between distant ones when the finger moves fast. Frame steps chain off
/// the requested position rather than the player's reported position, so
/// scrubbing stays responsive while the player is still decoding.
class FrameSeeker {
  FrameSeeker(this.controller, {double? fps})
      : _frameUs = fps != null && fps > 0
            ? (Duration.microsecondsPerSecond / fps).round()
            : null;

  final VideoPlayerController controller;

  /// One frame of media time; null when the clip's rate is unknown, which
  /// turns chasing off ([seekBy] then jumps like [seekTo]).
  final int? _frameUs;

  Duration? _pending;
  Duration? _inFlight;
  bool _smooth = false;
  bool _pumping = false;
  Duration? _accumulatedDelta;

  /// Last position handed to the platform. While the player stays paused
  /// and nothing else seeks it, [VideoPlayerValue.position] equals this
  /// exactly, which lets [freshPosition] answer without a platform round
  /// trip — mid-scrub, that round trip is what used to freeze the video
  /// for hundreds of milliseconds and then leap.
  Duration? _lastTarget;

  /// Where the video will be once pending seeks complete.
  Duration get position =>
      _pending ?? _inFlight ?? controller.value.position;

  /// Like [position], but asks the platform where the video actually is
  /// when no seek is queued and no seek of ours still matches the cached
  /// value. The cached [VideoPlayerValue.position] only refreshes every
  /// ~500 ms during playback, so right after pausing it can lag the
  /// displayed frame — relative jumps based on it land backwards.
  Future<Duration> freshPosition() async {
    final queued = _pending ?? _inFlight;
    if (queued != null) return queued;
    final cached = _lastTarget;
    if (cached != null &&
        !controller.value.isPlaying &&
        cached == controller.value.position) {
      return cached;
    }
    try {
      return await controller.position ?? controller.value.position;
    } catch (_) {
      return controller.value.position;
    }
  }

  /// Seeks relative to [freshPosition]. Steps that arrive while the
  /// position fetch is in flight fold into one jump, so rapid frame
  /// stepping never loses ticks.
  Future<void> seekBy(Duration delta) async {
    final queued = _pending ?? _inFlight;
    if (queued != null) {
      _request(queued + delta, smooth: true);
      return;
    }
    if (_accumulatedDelta != null) {
      _accumulatedDelta = _accumulatedDelta! + delta;
      return;
    }
    _accumulatedDelta = delta;
    final base = await freshPosition();
    final total = _accumulatedDelta!;
    _accumulatedDelta = null;
    _request(base + total, smooth: true);
  }

  void seekTo(Duration target) => _request(target, smooth: false);

  void _request(Duration target, {required bool smooth}) {
    _smooth = smooth;
    _pending = Duration(
      microseconds: target.inMicroseconds
          .clamp(0, controller.value.duration.inMicroseconds),
    );
    _pump();
  }

  /// Minimum spacing between platform seeks. On Android, seekTo's future
  /// completes when the command reaches ExoPlayer, not when the seek
  /// finishes — back-to-back seeks flush the decoder before it can render,
  /// so unpaced scrubbing leaps between distant frames whenever the finger
  /// slows. ~20 renders/s still reads as continuous motion.
  static const _seekSpacing = Duration(milliseconds: 50);

  /// Most frames a chasing seek may advance per platform seek. With
  /// [_seekSpacing] this caps smooth scrubbing at [maxSmoothFrameRate];
  /// under it every rendered step is small enough to read as motion.
  static const _maxChaseFrames = 3;

  /// Furthest the rendered position may trail a scrub target before it
  /// jumps ahead, bounding catch-up time when a gesture outruns
  /// [maxSmoothFrameRate].
  static const _maxLagFrames = 24;

  /// Fastest media rate (frames per second) chasing can render; scrub
  /// momentum should clamp to this so a fling coasts smoothly instead of
  /// outrunning the decoder and skipping.
  static double get maxSmoothFrameRate =>
      _maxChaseFrames *
      Duration.millisecondsPerSecond /
      _seekSpacing.inMilliseconds;

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_pending != null) {
        final target = _pending!;
        final next = _smooth
            ? _chase(_inFlight ?? controller.value.position, target)
            : target;
        if (next == target) _pending = null;
        // [_inFlight] (the truth about where the video is heading) stays
        // alive while the platform finishes, so position reads during the
        // window stay correct.
        _inFlight = next;
        await controller.seekTo(next);
        _lastTarget = next;
        await Future<void>.delayed(_seekSpacing);
      }
    } finally {
      _inFlight = null;
      _pumping = false;
    }
  }

  /// Next bounded step from [from] toward [target]: at most
  /// [_maxChaseFrames] of progress so intermediate frames get rendered,
  /// but never more than [_maxLagFrames] behind the goal.
  Duration _chase(Duration from, Duration target) {
    final frameUs = _frameUs;
    if (frameUs == null) return target;
    final gapUs = target.inMicroseconds - from.inMicroseconds;
    final stepUs = frameUs * _maxChaseFrames;
    if (gapUs.abs() <= stepUs) return target;
    final lagUs = frameUs * _maxLagFrames;
    final nextUs = gapUs > 0
        ? math.max(
            from.inMicroseconds + stepUs, target.inMicroseconds - lagUs)
        : math.min(
            from.inMicroseconds - stepUs, target.inMicroseconds + lagUs);
    return Duration(microseconds: nextUs);
  }
}
