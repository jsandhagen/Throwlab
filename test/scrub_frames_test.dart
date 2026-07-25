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
}
