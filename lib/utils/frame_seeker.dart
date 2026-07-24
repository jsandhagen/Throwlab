import 'dart:async';

import 'package:video_player/video_player.dart';

/// Coalesces rapid seek requests so only one platform seek is in flight at a
/// time, always jumping straight to the most recent target. Frame steps chain
/// off the requested position rather than the player's reported position, so
/// scrubbing stays responsive while the player is still decoding.
class FrameSeeker {
  FrameSeeker(this.controller);

  final VideoPlayerController controller;

  Duration? _pending;
  Duration? _inFlight;
  bool _pumping = false;
  Duration? _accumulatedDelta;

  /// Where the video will be once pending seeks complete.
  Duration get position =>
      _pending ?? _inFlight ?? controller.value.position;

  /// Like [position], but asks the platform where the video actually is
  /// when no seek is queued. The cached [VideoPlayerValue.position] only
  /// refreshes every ~500 ms during playback, so right after pausing it can
  /// lag the displayed frame — relative jumps based on it land backwards.
  Future<Duration> freshPosition() async {
    final queued = _pending ?? _inFlight;
    if (queued != null) return queued;
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
      seekTo(queued + delta);
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
    seekTo(base + total);
  }

  void seekTo(Duration target) {
    _pending = Duration(
      microseconds: target.inMicroseconds
          .clamp(0, controller.value.duration.inMicroseconds),
    );
    _pump();
  }

  /// Floor between platform seeks. Each seekTo flushes ExoPlayer's pipeline,
  /// so firing faster than this just cancels frames before they can render;
  /// ~60/s is the display's own ceiling anyway.
  static const _minSpacing = Duration(milliseconds: 16);

  /// How long to wait for a seek to actually show before giving up and
  /// moving to the next target. This was the old fixed cadence; it's now
  /// only the fallback for when the player never reports arrival, so most
  /// seeks release far sooner and scrubbing renders well past 20 frames/s.
  static const _maxSpacing = Duration(milliseconds: 50);

  /// A reported position this close to the target counts as rendered.
  static const _arrivedTolerance = Duration(milliseconds: 12);

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_pending != null) {
        final startedAt = DateTime.now();
        final target = _pending!;
        _pending = null;
        _inFlight = target;
        await controller.seekTo(target);
        // Keeps [_inFlight] (where the video is heading) alive across the
        // wait so position reads stay correct.
        await _settle(target, startedAt);
      }
    } finally {
      _inFlight = null;
      _pumping = false;
    }
  }

  /// Paces the next seek by real render feedback instead of a fixed sleep:
  /// hold for at least [_minSpacing] so seeks can't machine-gun and cancel
  /// each other, then release the moment the player reports it reached the
  /// target frame — falling back to [_maxSpacing] if that report never
  /// arrives. Every issued seek renders before the next fires (no flushed,
  /// skipped frames), and the cadence tracks how fast the device can decode
  /// rather than a worst-case constant.
  Future<void> _settle(Duration target, DateTime startedAt) async {
    final completer = Completer<void>();
    void check() {
      if (completer.isCompleted) return;
      if (DateTime.now().difference(startedAt) < _minSpacing) return;
      final delta =
          controller.value.position.inMicroseconds - target.inMicroseconds;
      if (delta.abs() <= _arrivedTolerance.inMicroseconds) {
        completer.complete();
      }
    }

    controller.addListener(check);
    // Re-check once the floor elapses (the frame may already be showing) and
    // once the ceiling elapses (release no matter what).
    final minTimer = Timer(_minSpacing, check);
    final maxRemaining = _maxSpacing - DateTime.now().difference(startedAt);
    final maxTimer = Timer(
      maxRemaining.isNegative ? Duration.zero : maxRemaining,
      () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    check();
    try {
      await completer.future;
    } finally {
      controller.removeListener(check);
      minTimer.cancel();
      maxTimer.cancel();
    }
  }
}
