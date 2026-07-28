import 'frame_timing.dart';

/// Formats a position as `m:ss.mmm` for the scrubber readout.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = position.inSeconds % 60;
  final millis = position.inMilliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// Frame index at [position] for footage recorded at [fps]: the frame the
/// player is showing there, which is the one whose timestamp [position] is
/// nearest (see frame_timing.dart). Seeks aim a quarter of a frame short of
/// the frame they want, because the player renders the first frame at or
/// after the position it is given; a floor of the display window would name
/// the frame before every one of those targets.
int frameAt(Duration position, double fps) => nearestFrame(
    position.inMicroseconds * fps / Duration.microsecondsPerSecond);
