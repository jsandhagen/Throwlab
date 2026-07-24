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

    test('rounds to the nearest frame', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      // 25 ms at 60 fps is 1.5 frames -> rounds to 2.
      expect(frames.indexForPosition(const Duration(milliseconds: 25)), 2);
      // 24 ms is 1.44 frames -> rounds to 1.
      expect(frames.indexForPosition(const Duration(milliseconds: 24)), 1);
    });
  });
}
