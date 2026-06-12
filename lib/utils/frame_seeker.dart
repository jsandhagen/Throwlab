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

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_pending != null) {
        final target = _pending!;
        _pending = null;
        _inFlight = target;
        await controller.seekTo(target);
      }
    } finally {
      _inFlight = null;
      _pumping = false;
    }
  }
}
