import 'frame_timing.dart';

/// Formats a position as `m:ss.mmm` for the scrubber readout.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = position.inSeconds % 60;
  final millis = position.inMilliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// The gap between two frames of a clip, to the hundredth of a second —
/// what a timer dropped on the frame reads. Signed, because a timer is
/// dropped at the moment being measured *from* and a coach scrubs back
/// through a throw as often as forward; at the frame it was dropped on it
/// reads a plain zero rather than a signed one, so it doesn't flicker
/// between +0.00 and -0.00 around its own anchor.
String formatDelta(Duration delta) {
  final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
  final rounded = (seconds * 100).round() / 100;
  if (rounded == 0) return '0.00 s';
  return '${rounded < 0 ? '-' : '+'}${rounded.abs().toStringAsFixed(2)} s';
}

/// Frame index at [position] for footage recorded at [fps]: the frame the
/// player is showing there, which is the one whose timestamp [position] is
/// nearest (see frame_timing.dart). Seeks aim a quarter of a frame short of
/// the frame they want, because the player renders the first frame at or
/// after the position it is given; a floor of the display window would name
/// the frame before every one of those targets.
int frameAt(Duration position, double fps) => nearestFrame(
    position.inMicroseconds * fps / Duration.microsecondsPerSecond);
