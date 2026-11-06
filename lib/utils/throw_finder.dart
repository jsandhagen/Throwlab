import 'dart:math' as math;
import 'dart:typed_data';

import '../models/throw_event.dart';
import 'clip_trim.dart';

/// Finding the throw in a clip somebody filmed of themselves.
///
/// An athlete filming alone presses record, walks to the ring, sets up,
/// throws, fetches the implement and walks back to stop the camera: two
/// minutes of clip, and the throw is a few seconds of it. Nothing in the
/// file says where — so it is read off the picture, as how much of it
/// changes from one moment to the next.
///
/// That alone would pick the wrong thing. The walk away from the camera and
/// the walk back to it fill the frame, and a throw twenty meters off moves a
/// twentieth of it — on raw motion the walk wins every time. What separates
/// them is where they are in the clip: the walk away is what the clip starts
/// with and the walk back is what it ends with, and the throw is in between,
/// after a pause in the ring that every throw has. So the motion touching
/// each end is set aside up to the first moment the picture settles, and the
/// throw is the biggest burst in what is left. Where the picture never
/// settles at all — a camera held in a hand, which is somebody filming
/// somebody else and stopping it themselves — there is nothing to find, and
/// it says so rather than guessing.
///
/// No machine learning and no pose: a coach cutting the wrong two seconds
/// out of a throw is worse off than one handed the whole clip, so this only
/// ever answers when the shape of the clip is the shape above, and the cut
/// it proposes is looked at before it is made.

/// How often the picture is sampled, per second of the file. A throw's fast
/// part is a third of a second to a second, which this catches in five to
/// fifteen samples, and decoding to it costs nothing beyond the decode.
const motionSampleRate = 15.0;

/// The side of the square each sample is shrunk to. Squashed to a square
/// whatever the clip's shape, since nothing here is measured — only whether
/// a pixel changed — and an athlete twenty meters off is still a few pixels
/// tall in it.
const motionSide = 96;

/// How far a pixel has to move, in gray levels on a shrunk frame, to count
/// as changed. Above a phone's sensor noise and compression flicker once
/// the frame has been averaged down, below an athlete against grass.
const _changed = 14;

/// How much of each sample changed from the one before, 0..1, for a run of
/// [side] x [side] gray frames laid end to end.
///
/// The frame's own brightness shift is taken out first: a phone's exposure
/// walks as a cloud crosses or the athlete leaves the frame, and every
/// pixel getting a shade darker is not motion.
List<double> motionActivity(Uint8List frames, {int side = motionSide}) {
  final pixels = side * side;
  final count = frames.length ~/ pixels;
  final activity = List<double>.filled(count, 0);
  for (var f = 1; f < count; f++) {
    final a = (f - 1) * pixels;
    final b = f * pixels;
    var sum = 0;
    for (var i = 0; i < pixels; i++) {
      sum += frames[b + i] - frames[a + i];
    }
    final shift = sum / pixels;
    var moved = 0;
    for (var i = 0; i < pixels; i++) {
      if ((frames[b + i] - frames[a + i] - shift).abs() > _changed) moved++;
    }
    activity[f] = moved / pixels;
  }
  // The first sample has nothing before it; it moved as much as the next.
  if (count > 1) activity[0] = activity[1];
  return activity;
}

/// Where the throw is in a clip, in seconds of the file's own timeline.
class ThrowWindow {
  const ThrowWindow({
    required this.start,
    required this.end,
    required this.peak,
    required this.duration,
  });

  /// What to keep, and the moment in it the picture moved most — near the
  /// release, which is what the review shows.
  final double start;
  final double end;
  final double peak;

  /// How long the whole clip is.
  final double duration;

  double get length => end - start;

  /// The window as whole frames of a clip at [fps], never shorter than a
  /// trim is allowed to be.
  TrimRange toRange(Duration clip, double fps) {
    final whole = TrimRange.whole(clip, fps);
    final first = (start * fps).floor().clamp(0, whole.frameCount - 1);
    final last = ((end * fps).ceil() - 1).clamp(first, whole.frameCount - 1);
    return whole.withFirst(first).withLast(last);
  }

  @override
  String toString() => 'ThrowWindow($start–$end of $duration, peak $peak)';
}

/// How long each event takes either side of the moment it moves fastest, in
/// real seconds.
///
/// [lead] is the least kept before it and [maxLead] the furthest the motion
/// leading up to it is followed back: a put is a glide or a spin, a discus
/// has its swings, a hammer three winds and its turns, and a javelin a
/// run-up that can be most of the frame's width. [follow] and [maxFollow]
/// are the same after it — the reverse and the implement leaving, and not
/// the walk out to fetch it.
typedef ThrowTiming = ({
  double lead,
  double maxLead,
  double follow,
  double maxFollow,
});

ThrowTiming throwTiming(ThrowEvent event) => switch (event) {
      ThrowEvent.shotPut => (lead: 2.5, maxLead: 6, follow: 2, maxFollow: 3),
      ThrowEvent.discus => (lead: 3.5, maxLead: 7, follow: 2, maxFollow: 3),
      ThrowEvent.hammer => (lead: 5, maxLead: 10, follow: 2, maxFollow: 3.5),
      ThrowEvent.javelin => (lead: 5, maxLead: 10, follow: 2.5, maxFollow: 4),
    };

/// A clip shorter than this, in real seconds, was already stopped by
/// somebody: there is nothing worth cutting.
const worthSearching = 12.0;

/// Finds the throw in [activity] — [motionActivity] at [rate] samples per
/// second of the file — or null when the clip is not one a throw can be
/// told apart in.
///
/// [slowdown] is how many seconds of the file a real second takes: one for
/// a clip that plays at the speed it was filmed, eight for 240 fps stored
/// to play at 30. Every length here is a length of the throw, so it is
/// measured in real seconds and stretched by it.
ThrowWindow? findThrow(
  List<double> activity, {
  required double rate,
  required ThrowEvent event,
  double slowdown = 1,
}) {
  final n = activity.length;
  if (n < 2 || rate <= 0 || slowdown <= 0) return null;
  final duration = n / rate;
  if (duration / slowdown < worthSearching) return null;
  final perReal = rate * slowdown;
  int samples(double seconds) => math.max(1, (seconds * perReal).round());

  final s = _smooth(activity, samples(0.2));
  final sorted = [...s]..sort();
  final floor = sorted[((sorted.length - 1) * 0.2).round()];
  // Still, for this clip: its own quiet with room for a breeze in a tree,
  // and never so fine that a sensor's grain counts as somebody moving.
  final quiet = floor * 2 + 0.004;

  // The walk away and the walk back: whatever the clip starts and ends
  // moving with, up to where the picture first settles.
  final settle = samples(0.6);
  final edge = samples(0.5);
  var from = 0;
  if (s.take(edge).any((v) => v > quiet)) {
    from = _settles(s, 0, 1, quiet, settle);
  }
  var to = n - 1;
  if (s.skip(n - edge).any((v) => v > quiet)) {
    to = _settles(s, n - 1, -1, quiet, settle);
  }
  if (from < 0 || to < 0 || to - from < samples(1)) return null;

  var peak = from;
  for (var i = from; i <= to; i++) {
    if (s[i] > s[peak]) peak = i;
  }
  // Nothing in between moved enough to be anybody throwing anything.
  if (s[peak] < quiet * 1.5) return null;

  // The throw's own motion, followed out from its peak while it is still a
  // fifth of the way up from still, across dips shorter than a half-second
  // — a glide's pause, a hammer's low point.
  final level = quiet + 0.2 * (s[peak] - quiet);
  final bridge = samples(0.5);
  int reach(int step, int limit) {
    var last = peak;
    var gap = 0;
    for (var i = peak + step;
        i >= 0 && i < n && (i - peak).abs() <= limit;
        i += step) {
      if (s[i] > level) {
        last = i;
        gap = 0;
      } else if (++gap > bridge) {
        break;
      }
    }
    return last;
  }

  final timing = throwTiming(event);
  final pad = samples(1);
  final first = math.min(
      reach(-1, samples(timing.maxLead)) - pad, peak - samples(timing.lead));
  final last = math.max(
      reach(1, samples(timing.maxFollow)) + pad, peak + samples(timing.follow));
  final start = math.max(0.0, first / rate);
  final end = math.min(duration, (last + 1) / rate);
  // Cutting a couple of seconds off a clip is not worth a look at it.
  if ((duration - (end - start)) / slowdown < 5) return null;
  return ThrowWindow(
    start: start,
    end: end,
    peak: peak / rate,
    duration: duration,
  );
}

/// A centered moving average over [width] samples.
List<double> _smooth(List<double> values, int width) {
  if (width <= 1) return values;
  final half = width ~/ 2;
  final sums = List<double>.filled(values.length + 1, 0);
  for (var i = 0; i < values.length; i++) {
    sums[i + 1] = sums[i] + values[i];
  }
  return [
    for (var i = 0; i < values.length; i++)
      () {
        final a = math.max(0, i - half);
        final b = math.min(values.length, i + half + 1);
        return (sums[b] - sums[a]) / (b - a);
      }(),
  ];
}

/// Walks from [start] in [step] to the first run of [run] samples at or
/// under [quiet], and returns where that run begins — or -1 when the
/// picture never settles.
int _settles(List<double> s, int start, int step, double quiet, int run) {
  var held = 0;
  for (var i = start; i >= 0 && i < s.length; i += step) {
    if (s[i] <= quiet) {
      if (++held >= run) return i - step * (run - 1);
    } else {
      held = 0;
    }
  }
  return -1;
}
