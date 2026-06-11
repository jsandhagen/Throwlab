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

  /// Where the video will be once pending seeks complete.
  Duration get position =>
      _pending ?? _inFlight ?? controller.value.position;

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
