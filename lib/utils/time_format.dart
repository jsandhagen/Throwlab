/// Formats a position as `m:ss.mmm` for the scrubber readout.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = position.inSeconds % 60;
  final millis = position.inMilliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// Frame index at [position] for footage recorded at [fps]: the frame whose
/// display window contains [position], so the readout names the frame that
/// is actually on screen. Rounding instead would flip to the next frame past
/// the halfway point — and seeks deliberately target mid-frame, which is
/// exactly where that goes wrong. The epsilon keeps a position sitting on a
/// frame boundary from reporting the frame before it.
int frameAt(Duration position, double fps) =>
    (position.inMicroseconds * fps / Duration.microsecondsPerSecond + 1e-6)
        .floor();
