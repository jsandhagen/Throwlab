/// Below this drag speed (logical px/s) scrubbing stays 1:1 and
/// frame-precise — the range you live in for deliberate analysis.
const double kScrubSlowSpeed = 450;

/// At or above this drag speed the acceleration is fully applied.
const double kScrubFastSpeed = 4500;

/// Largest frames-per-pixel multiplier, reached at [kScrubFastSpeed]. Kept
/// moderate so a normal analysis drag stays close to 1:1 and doesn't leap
/// between frames, while a genuine flick still covers a whole clip.
const double kScrubMaxGain = 6;

/// Frames-per-pixel multiplier for a drag moving at [speed] logical px/s.
/// Flat at 1.0 through [kScrubSlowSpeed], then eases in (t² so precision
/// lingers just past the threshold) up to [kScrubMaxGain] at
/// [kScrubFastSpeed]. This is what makes scrub speed track finger speed.
double scrubGain(double speed) {
  if (speed <= kScrubSlowSpeed) return 1;
  final t = ((speed - kScrubSlowSpeed) / (kScrubFastSpeed - kScrubSlowSpeed))
      .clamp(0.0, 1.0);
  return 1 + t * t * (kScrubMaxGain - 1);
}

/// Turns finger drag distance into whole frame steps, accelerating the
/// ratio with drag speed so a slow drag advances one frame at a time while
/// a fast flick covers the whole clip — the "variable speed depending on
/// scrubbing speed" feel of a physical jog wheel. Fractional frames are
/// retained between calls so no drag distance is ever dropped.
class ScrubAccumulator {
  /// EMA weight kept from the previous speed estimate. Pointer deltas are
  /// noisy frame to frame; smoothing keeps the gain (and so the scrub rate)
  /// from flickering under a steady drag.
  static const double _speedSmoothing = 0.6;

  double _frameAccumulator = 0;
  double _smoothedSpeed = 0;
  int? _lastMicros;
  double _lastGain = 1;

  /// The acceleration multiplier applied to the most recent [addDrag]. A
  /// fling handoff scales its coast velocity by this so the momentum picks
  /// up exactly where the finger left off instead of snapping back to 1×.
  double get lastGain => _lastGain;

  /// Clears carried-over fraction, speed history, and gain. Call at the
  /// start of every fresh drag.
  void reset() {
    _frameAccumulator = 0;
    _smoothedSpeed = 0;
    _lastMicros = null;
    _lastGain = 1;
  }

  /// Accelerated step from a live finger drag. [dx] is the horizontal drag
  /// delta (logical px), [pixelsPerFrame] the clip's base sensitivity, and
  /// [timestamp] the pointer event time used to measure drag speed. Without
  /// a usable timestamp it falls back to unaccelerated 1:1 stepping.
  /// Returns the signed whole number of frames to advance.
  int addDrag(double dx, double pixelsPerFrame, {Duration? timestamp}) {
    final micros = timestamp?.inMicroseconds;
    if (micros != null && _lastMicros != null && micros > _lastMicros!) {
      final dt = (micros - _lastMicros!) / Duration.microsecondsPerSecond;
      final speed = dx.abs() / dt;
      _smoothedSpeed =
          _smoothedSpeed * _speedSmoothing + speed * (1 - _speedSmoothing);
      _lastGain = scrubGain(_smoothedSpeed);
    } else if (micros == null) {
      _lastGain = 1;
    }
    // First event of a drag (no prior timestamp): keep last gain (1 after a
    // reset) until a delta gives us a speed to work from.
    if (micros != null) _lastMicros = micros;
    return _emit(dx * _lastGain, pixelsPerFrame);
  }

  /// Unaccelerated step: straight [dx] / [pixelsPerFrame] with the fraction
  /// carried over. Used for momentum coasting, where the fling velocity
  /// already carries the drag's acceleration and re-accelerating the decay
  /// would fight the slowdown.
  int addRaw(double dx, double pixelsPerFrame) => _emit(dx, pixelsPerFrame);

  int _emit(double pixels, double pixelsPerFrame) {
    if (pixelsPerFrame <= 0) return 0;
    _frameAccumulator += pixels / pixelsPerFrame;
    final frames = _frameAccumulator.truncate();
    _frameAccumulator -= frames;
    return frames;
  }
}
