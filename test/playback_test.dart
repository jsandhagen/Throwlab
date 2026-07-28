import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/utils/frame_timing.dart';
import 'package:throwlab/utils/time_format.dart';
import 'package:throwlab/widgets/playback_controls.dart';

void main() {
  group('snapToFrame', () {
    test('aims a quarter frame short of the nearest boundary at 30 fps', () {
      // One frame at 30 fps is 33333 µs; 40 ms sits closest to frame 1, and
      // the seek for frame 1 aims a quarter frame before it so the player —
      // which renders the first frame at or after the position — lands on
      // frame 1 rather than frame 2.
      expect(
        snapToFrame(const Duration(milliseconds: 40), 30),
        const Duration(microseconds: 25000),
      );
    });

    test('aims a quarter frame short of the nearest boundary at 240 fps', () {
      // One frame at 240 fps is 4166.67 µs; 10 ms is closest to frame 2.
      expect(
        snapToFrame(const Duration(milliseconds: 10), 240),
        const Duration(microseconds: 7292),
      );
    });

    test('never aims before the start of the clip', () {
      expect(snapToFrame(Duration.zero, 60), Duration.zero);
      expect(snapToFrame(const Duration(milliseconds: 4), 60), Duration.zero);
    });

    test('a snapped position still names the frame it was snapped to', () {
      for (final fps in [30.0, 60.0, 240.0]) {
        for (final frame in [0, 1, 7, 199]) {
          final us = (frame * Duration.microsecondsPerSecond / fps).round();
          final snapped = snapToFrame(Duration(microseconds: us), fps);
          expect(frameAt(snapped, fps), frame, reason: '$fps fps, $frame');
        }
      }
    });
  });

  group('frameAt', () {
    test('names the frame whose timestamp the position is nearest', () {
      // Frame 1 at 60 fps is stamped 16.67 ms and frame 2 at 33.33 ms, so
      // the readout flips to 2 halfway between them. Positions the app seeks
      // to sit a quarter frame *before* a stamp, which is why this is a
      // nearest and not a floor of the display window.
      expect(frameAt(const Duration(milliseconds: 13), 60), 1);
      expect(frameAt(const Duration(milliseconds: 17), 60), 1);
      expect(frameAt(const Duration(milliseconds: 24), 60), 1);
      expect(frameAt(const Duration(milliseconds: 26), 60), 2);
      expect(frameAt(const Duration(milliseconds: 33), 60), 2);
    });

    test('a position exactly between two frames names the earlier', () {
      // 25 ms at 60 fps is level with frame 1 and heading for frame 2.
      final us = (1.5 * Duration.microsecondsPerSecond / 60).round();
      expect(frameAt(Duration(microseconds: us), 60), 1);
    });

    test('agrees with the positions seeks aim at', () {
      for (final frame in [0, 1, 13, 240]) {
        final us = (seekTargetSeconds(frame / 30, 1 / 30) *
                Duration.microsecondsPerSecond)
            .round();
        expect(frameAt(Duration(microseconds: us), 30), frame);
      }
    });

    test('exact frame boundaries report that frame', () {
      expect(frameAt(Duration.zero, 30), 0);
      expect(frameAt(const Duration(seconds: 1), 30), 30);
      expect(frameAt(const Duration(milliseconds: 500), 30), 15);
    });
  });
}
