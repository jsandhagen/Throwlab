import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/utils/scrub_frames.dart';

void main() {
  group('ScrubFrames.indexForPosition', () {
    test('every frame extracted (stride 1) maps position to frame number', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      expect(frames.indexForPosition(Duration.zero), 0);
      expect(frames.indexForPosition(const Duration(seconds: 1)), 60);
      expect(
          frames.indexForPosition(const Duration(milliseconds: 500)), 30);
    });

    test('strided extraction divides the source frame by the stride', () {
      // 120 source frames at 60 fps kept as 40 images (every 3rd).
      final frames =
          ScrubFrames(dir: '/none', count: 40, stride: 3, fps: 60);
      // 0.5 s = source frame 30 -> image 10.
      expect(
          frames.indexForPosition(const Duration(milliseconds: 500)), 10);
      expect(frames.indexForPosition(Duration.zero), 0);
    });

    test('clamps within the available frames', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      // 2 s would be frame 120, but only 0..119 exist.
      expect(frames.indexForPosition(const Duration(seconds: 2)), 119);
      expect(
          frames.indexForPosition(const Duration(seconds: -1)), 0);
    });

    test('picks the frame whose window contains the position', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      // At 60 fps frame 1 is on screen from 16.67 ms until 33.33 ms, so
      // every position in between is frame 1 — including 25 ms, which a
      // nearest-rounding would have called frame 2 and shown the wrong
      // still over the video.
      expect(frames.indexForPosition(const Duration(milliseconds: 17)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 24)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 25)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 33)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 34)), 2);
    });

    test('a position exactly on a frame boundary is that frame', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 50);
      // Exact boundaries: 20 ms per frame, so 20 ms is frame 1, not 0.
      expect(frames.indexForPosition(const Duration(milliseconds: 20)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 40)), 2);
      expect(frames.indexForPosition(const Duration(milliseconds: 100)), 5);
    });

    test('mid-frame seek targets map back to the frame they aimed at', () {
      // Seeks aim half a frame in (see AnalysisScreen._positionForImage);
      // those positions must resolve to the frame they were built from.
      for (final stride in [1, 2, 5]) {
        final frames = ScrubFrames(
            dir: '/none', count: 500, stride: stride, fps: 60);
        for (final index in [0, 1, 7, 42, 99]) {
          final us =
              ((index * stride + 0.5) * Duration.microsecondsPerSecond / 60)
                  .round();
          expect(frames.indexForPosition(Duration(microseconds: us)), index,
              reason: 'stride $stride, index $index');
        }
      }
    });
  });

  group('ScrubFrames with real frame timestamps', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('scrubframes');
    });
    tearDown(() async => dir.delete(recursive: true));

    Future<ScrubFrames> framesWithTimes(
        List<double> times, {int stride = 1, double fps = 30}) async {
      await File('${dir.path}/times.csv').writeAsString(times.join('\n'));
      final frames = ScrubFrames(
          dir: dir.path, count: times.length, stride: stride, fps: fps);
      await frames.loadTimes('times.csv');
      return frames;
    }

    test('a clip that does not start at zero maps without a frame of lag',
        () async {
      // Every frame sits one frame-duration later than index/fps implies.
      // The fps arithmetic would name the still before the right one - the
      // "always one frame behind" handoff.
      const step = 1 / 30;
      final times = [for (var i = 0; i < 10; i++) step + i * step];
      final frames = await framesWithTimes(times);
      for (var i = 0; i < 10; i++) {
        final mid = Duration(
            microseconds: ((times[i] + step / 2) * 1e6).round());
        expect(frames.indexForPosition(mid), i, reason: 'still $i');
      }
    });

    test('positionForIndex lands inside the frame it names', () async {
      const step = 1 / 30;
      final times = [for (var i = 0; i < 10; i++) 0.5 + i * step];
      final frames = await framesWithTimes(times);
      for (var i = 0; i < 10; i++) {
        final target = frames.positionForIndex(i);
        final seconds = target.inMicroseconds / 1e6;
        expect(seconds, greaterThan(times[i]));
        if (i + 1 < times.length) {
          expect(seconds, lessThan(times[i + 1]));
        }
        // And the round trip is stable.
        expect(frames.indexForPosition(target), i);
      }
    });

    test('uneven (variable rate) spacing still maps exactly', () async {
      final times = [0.0, 0.031, 0.070, 0.099, 0.140, 0.171];
      final frames = await framesWithTimes(times);
      expect(frames.indexForPosition(const Duration(milliseconds: 0)), 0);
      expect(frames.indexForPosition(const Duration(milliseconds: 30)), 0);
      expect(frames.indexForPosition(const Duration(milliseconds: 31)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 69)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 70)), 2);
      expect(frames.indexForPosition(const Duration(milliseconds: 200)), 5);
      for (var i = 0; i < times.length; i++) {
        expect(frames.indexForPosition(frames.positionForIndex(i)), i);
      }
    });

    test('a short or missing times file falls back to the arithmetic',
        () async {
      await File('${dir.path}/times.csv').writeAsString('0.0\n0.033');
      final frames =
          ScrubFrames(dir: dir.path, count: 10, stride: 1, fps: 30);
      await frames.loadTimes('times.csv');
      // Fallback: 25 ms at 30 fps is inside frame 0 (0-33.3 ms).
      expect(frames.indexForPosition(const Duration(milliseconds: 25)), 0);
      expect(frames.indexForPosition(const Duration(milliseconds: 40)), 1);

      final none = ScrubFrames(dir: dir.path, count: 10, stride: 1, fps: 30);
      await none.loadTimes('absent.csv');
      expect(none.indexForPosition(const Duration(milliseconds: 40)), 1);
    });

    test('strided stills use their own recorded times', () async {
      // Every 3rd frame of a 30 fps clip.
      final times = [for (var i = 0; i < 8; i++) i * 3 / 30];
      final frames = await framesWithTimes(times, stride: 3);
      expect(frames.indexForPosition(const Duration(milliseconds: 100)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 199)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 200)), 2);
      for (var i = 0; i < times.length; i++) {
        expect(frames.indexForPosition(frames.positionForIndex(i)), i);
      }
    });
  });
}
