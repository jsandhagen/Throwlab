/// Formats a position as `m:ss.mmm` for the scrubber readout.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = position.inSeconds % 60;
  final millis = position.inMilliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// Frame index at [position] for footage recorded at [fps].
int frameAt(Duration position, double fps) =>
    (position.inMicroseconds * fps / Duration.microsecondsPerSecond).round();
