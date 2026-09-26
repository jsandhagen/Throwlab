import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/services/video_optimizer.dart';
import 'package:throwlab/utils/release_metrics.dart';

void main() {
  group('computeReleaseMetrics', () {
    // 100 px between reference taps = 2.6 m javelin → 0.026 m/px.
    const tip = Offset(300, 100);
    const tail = Offset(200, 100);

    test('horizontal throw to the right', () {
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: const Offset(100, 200),
        pointB: const Offset(150, 200),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        gravity: 0,
      );
      expect(m.speed, closeTo(50 * 0.026 / 0.05, 1e-6)); // 26 m/s
      expect(m.releaseAngleDeg, closeTo(0, 1e-6));
    });

    test('45° throw (screen y points down)', () {
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: const Offset(100, 200),
        pointB: const Offset(150, 150),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        gravity: 0,
      );
      expect(m.releaseAngleDeg, closeTo(45, 1e-6));
    });

    test('leftward throw reads the same as rightward', () {
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: const Offset(150, 200),
        pointB: const Offset(100, 150),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        gravity: 0,
      );
      expect(m.releaseAngleDeg, closeTo(45, 1e-6));
    });

    test('javelin: midpoint speed, flight path, and attack angle', () {
      // Axis horizontal on both frames; midpoint moves (50, -50) px →
      // flying up at 45° with the nose 45° below the flight path.
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: tip + const Offset(50, -50),
        pointB: tail + const Offset(50, -50),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        gravity: 0,
        javelin: true,
      );
      expect(
          m.speed, closeTo(math.sqrt(50 * 50 + 50 * 50) * 0.026 / 0.05, 1e-6));
      expect(m.releaseAngleDeg, closeTo(45, 1e-6));
      expect(m.attackAngleDeg, closeTo(-45, 1e-6));
    });

    test('javelin: tolerates swapped tip/tail taps on one frame', () {
      final swapped = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: tail + const Offset(50, -50), // tail tapped first here
        pointB: tip + const Offset(50, -50),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        gravity: 0,
        javelin: true,
      );
      expect(swapped.releaseAngleDeg, closeTo(45, 1e-6));
      expect(swapped.attackAngleDeg, closeTo(-45, 1e-6));
    });

    test('javelin: tolerates consistently reversed tap order', () {
      final reversed = computeReleaseMetrics(
        refA: tail,
        refB: tip,
        pointA: tail + const Offset(50, -50),
        pointB: tip + const Offset(50, -50),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        gravity: 0,
        javelin: true,
      );
      expect(reversed.releaseAngleDeg, closeTo(45, 1e-6));
      expect(reversed.attackAngleDeg, closeTo(-45, 1e-6));
    });

    test('midpoint gravity correction recovers release velocity', () {
      // True release velocity (20 across, 10 up) m/s at 0.026 m/px over
      // dt = 0.1 s. The measured chord is the midpoint velocity, whose
      // vertical component gravity has already cut by g·dt/2.
      const g = 9.80665, dt = 0.1, mpp = 0.026;
      const vx = 20.0, vy = 10.0;
      final dxPx = vx * dt / mpp;
      final dyPx = -(vy - g * dt / 2) * dt / mpp; // screen y points down
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: const Offset(100, 200),
        pointB: Offset(100 + dxPx, 200 + dyPx),
        referenceMeters: 2.6,
        dtSeconds: dt,
      );
      expect(m.speed, closeTo(math.sqrt(vx * vx + vy * vy), 1e-6));
      expect(
          m.releaseAngleDeg, closeTo(math.atan2(vy, vx) * 180 / math.pi, 1e-6));
    });

    test('degenerate input returns zeros instead of NaN', () {
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tip,
        pointA: Offset.zero,
        pointB: const Offset(1, 1),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
      );
      expect(m.speed, 0);
    });
  });

  group('VideoOptimizer.isPlaybackGeometryCurrent', () {
    bool current(double sar, int w, int h) =>
        VideoOptimizer.isPlaybackGeometryCurrent(
            sampleAspect: sar, width: w, height: h);

    test('macroblock-sized square-pixel clips need no remake', () {
      expect(current(1, 800, 1440), isTrue);
      expect(current(1, 1920, 1072), isTrue);
    });

    test('off-macroblock dimensions are coded with a crop rectangle', () {
      // 810 codes as 816, 1080 as 1088: the padding rides along in the
      // texture and squeezes the picture inside its box.
      expect(current(1, 810, 1440), isFalse);
      expect(current(1, 1080, 1920), isFalse);
      // Height counts too.
      expect(current(1, 800, 1450), isFalse);
    });

    test('non-square pixels need a remake whatever the size', () {
      expect(current(1.00744, 800, 1440), isFalse);
      expect(current(0.9, 800, 1440), isFalse);
    });

    test('an unreadable size is left alone rather than re-encoded blindly', () {
      expect(current(1, 0, 0), isTrue);
    });
  });

  group('VideoOptimizer.parseRate', () {
    test('parses plain and decimal rates', () {
      expect(VideoOptimizer.parseRate('240'), 240);
      expect(VideoOptimizer.parseRate('239.880000'), closeTo(239.88, 1e-9));
    });

    test('parses fractional rates', () {
      expect(VideoOptimizer.parseRate('30000/1001'), closeTo(29.97, 0.001));
    });

    test('rejects garbage', () {
      expect(VideoOptimizer.parseRate(null), isNull);
      expect(VideoOptimizer.parseRate(''), isNull);
      expect(VideoOptimizer.parseRate('0/0'), isNull);
      expect(VideoOptimizer.parseRate('abc'), isNull);
    });
  });

  group('VideoOptimizer.readFrameRates', () {
    test('a 60 fps phone clip reads as 60', () {
      final rates = VideoOptimizer.readFrameRates('''
avg_frame_rate=60/1
r_frame_rate=60/1
duration=4.016667
nb_frames=241
TAG:creation_time=2026-09-20T14:02:11.000000Z
TAG:creation_time=2026-09-20T14:02:11.000000Z
''')!;
      expect(rates.playback, 60);
      expect(rates.capture, 60);
      expect(rates.recordedAt, DateTime.utc(2026, 9, 20, 14, 2, 11));
    });

    test('a slow-motion tag is the capture rate', () {
      final rates = VideoOptimizer.readFrameRates('''
avg_frame_rate=30/1
r_frame_rate=30/1
TAG:com.android.capture.fps=240.000000
''')!;
      expect(rates.playback, 30);
      expect(rates.capture, 240);
    });

    test('no average falls back to the frames counted, then the guess', () {
      expect(
          VideoOptimizer.readFrameRates('''
avg_frame_rate=0/0
r_frame_rate=90000/1
duration=2.000000
nb_frames=120
''')!.playback,
          60);
      expect(
          VideoOptimizer.readFrameRates('''
avg_frame_rate=0/0
r_frame_rate=25/1
''')!.playback,
          25);
    });

    test('nothing readable is no answer, not 30', () {
      expect(VideoOptimizer.readFrameRates(''), isNull);
      expect(VideoOptimizer.readFrameRates('avg_frame_rate=0/0'), isNull);
    });
  });

  group('VideoOptimizer.colorTagsFor', () {
    String tags({String? colorSpace, int? height}) =>
        VideoOptimizer.colorTagsFor(colorSpace: colorSpace, height: height);

    test('says Rec. 709 for HD that says nothing itself', () {
      // The case the scrub handoff shifted color on: the player reads
      // untagged HD as 709 and ffmpeg's scaler reads it as 601, so the
      // still and the frame it hands back to were converted two ways.
      expect(tags(height: 1080), contains('bt709'));
      expect(tags(colorSpace: '', height: 720), contains('bt709'));
      expect(tags(colorSpace: 'unknown', height: 1440), contains('bt709'));
    });

    test('leaves a clip that has already said alone', () {
      expect(tags(colorSpace: 'bt709', height: 1080), '');
      expect(tags(colorSpace: 'smpte170m', height: 1080), '');
    });

    test('leaves standard definition alone, which really is Rec. 601', () {
      expect(tags(height: 480), '');
      expect(tags(height: 576), '');
    });

    test('says nothing about a clip it could not measure', () {
      expect(tags(), '');
    });
  });

  group('VideoOptimizer.jpegColorFilter', () {
    String filter({String? colorSpace, int? height}) =>
        VideoOptimizer.jpegColorFilter(colorSpace: colorSpace, height: height);
    String reads({String? colorSpace, int? height}) =>
        VideoOptimizer.readMatrixFor(colorSpace: colorSpace, height: height);

    test('always writes the matrix a JPEG is read with', () {
      // The shift a scrub drag showed: ffmpeg left the clip's own
      // coefficients in the file and Flutter read them as full-range
      // Rec. 601, because that is what a JPEG is. Both ends are named now,
      // whatever the clip turns out to be in.
      for (final space in ['bt709', 'smpte170m', 'unknown', '']) {
        expect(filter(colorSpace: space, height: 1440),
            contains('out_color_matrix=bt601'));
        expect(
            filter(colorSpace: space, height: 1440), contains('out_range=pc'));
      }
    });

    test('reads a clip in the color it declares', () {
      expect(reads(colorSpace: 'bt709', height: 480), 'bt709');
      expect(reads(colorSpace: 'bt470bg', height: 1440), 'bt601');
      expect(reads(colorSpace: 'smpte170m', height: 1440), 'bt601');
      expect(reads(colorSpace: 'bt2020nc', height: 2160), 'bt2020');
    });

    test('guesses an untagged clip the way the player guesses it', () {
      // Same rule as colorTagsFor writes, so a clip tagged by one recipe and
      // a clip left untagged by an older one come out the same color.
      expect(reads(height: 1080), 'bt709');
      expect(reads(colorSpace: 'unknown', height: 720), 'bt709');
      expect(reads(colorSpace: 'N/A', height: 480), 'bt601');
    });

    test('leaves a clip it could not measure to ffmpeg', () {
      expect(reads(), 'auto');
      expect(filter(), contains('in_color_matrix=auto'));
    });
  });
}
