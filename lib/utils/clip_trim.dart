import 'dart:math' as math;

import '../models/throw_video.dart';
import 'frame_timing.dart';

/// The stretch of a clip kept by a trim, in whole frames.
///
/// Frames rather than times, because a trim is judged by eye on a frame and
/// has to land on that frame: a cut asked for in seconds lands on whichever
/// frame the encoder rounds it to, and a throw cut a frame short of the
/// release has lost the one frame it was kept for. [first] and [last] are
/// both kept.
class TrimRange {
  const TrimRange({
    required this.first,
    required this.last,
    required this.frameCount,
    required this.fps,
  });

  /// The whole clip, which is what the trim screen opens on.
  factory TrimRange.whole(Duration duration, double fps) {
    final count = framesIn(duration, fps);
    return TrimRange(first: 0, last: count - 1, frameCount: count, fps: fps);
  }

  final int first;
  final int last;
  final int frameCount;
  final double fps;

  /// How many frames the clip has, at least one — a clip too short to
  /// report a duration is still a frame somebody is looking at.
  static int framesIn(Duration duration, double fps) =>
      math.max(1, (duration.inMicroseconds * fps / 1e6).round());

  /// The shortest a clip can be trimmed to: a fifth of a second, which is
  /// the release and a frame or two either side of it at any rate a phone
  /// films at. Shorter and the scale under it has nothing to count.
  static const minimum = Duration(milliseconds: 200);

  int get minFrames => math.max(2, (minimum.inMicroseconds * fps / 1e6).ceil());

  int get keptFrames => last - first + 1;

  /// Whether anything would actually be cut.
  bool get isWhole => first <= 0 && last >= frameCount - 1;

  /// When frame [frame] starts.
  Duration at(int frame) => Duration(microseconds: (frame * 1e6 / fps).round());

  /// Where to seek to be shown frame [frame] — a little short of it, by the
  /// rule every seek in the app follows (see frame_timing.dart).
  Duration seekTarget(int frame) => Duration(
      microseconds: (seekTargetSeconds(frame / fps, 1 / fps) * 1e6).round());

  /// The frame a player position is showing.
  int frameAt(Duration position) =>
      nearestFrame(position.inMicroseconds * fps / 1e6)
          .clamp(0, frameCount - 1);

  Duration get start => at(first);

  /// The end of the last kept frame, not its start — a clip of one frame
  /// still lasts a frame.
  Duration get end => at(last + 1);

  Duration get length => end - start;

  /// Moves the start to [frame], never closer to the end than [minFrames].
  TrimRange withFirst(int frame) => TrimRange(
        first: frame.clamp(0, math.max(0, last - minFrames + 1)),
        last: last,
        frameCount: frameCount,
        fps: fps,
      );

  /// Moves the end to [frame], never closer to the start than [minFrames].
  TrimRange withLast(int frame) => TrimRange(
        first: first,
        last: frame.clamp(
            math.min(frameCount - 1, first + minFrames - 1), frameCount - 1),
        frameCount: frameCount,
        fps: fps,
      );

  /// Where [release] falls in the trimmed clip, or null when the trim cut
  /// it off. The kept clip starts at its first frame, so every position in
  /// it is the old one less [start] — the same moment, counted from a new
  /// zero, which is what keeps the scale's numbers on the frames they were
  /// on.
  Duration? releaseAfter(Duration? release) {
    if (release == null) return null;
    final frame = frameAt(release);
    // Judged by frame rather than by time: a release is stored where a seek
    // left the player, a fraction of a frame short of the frame it shows.
    if (frame < first || frame > last) return null;
    final shifted = release - start;
    return shifted.isNegative ? Duration.zero : shifted;
  }

  @override
  bool operator ==(Object other) =>
      other is TrimRange &&
      other.first == first &&
      other.last == last &&
      other.frameCount == frameCount &&
      other.fps == fps;

  @override
  int get hashCode => Object.hash(first, last, frameCount, fps);
}

/// What a trim changes about a throw beyond the file it plays: the release
/// moves with the clip, or goes with the part cut off, and the scrub stills
/// are of a clip that no longer exists. The directory is kept on the throw
/// so it is still reclaimed on a delete, and the next extraction writes
/// over it; with no count, nothing reads a still out of it in the meantime.
void applyTrim(ThrowVideo video, TrimRange range) {
  video.release = range.releaseAfter(video.release);
  video.scrubFrameCount = 0;
  video.scrubFramesVersion = 0;
}
