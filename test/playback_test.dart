import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/utils/time_format.dart';
import 'package:throwlab/widgets/playback_controls.dart';

void main() {
  group('snapToFrame', () {
    test('rounds to the nearest frame boundary at 30 fps', () {
      // One frame at 30 fps is 33333 µs; 40 ms sits closest to frame 1.
      expect(
        snapToFrame(const Duration(milliseconds: 40), 30),
        const Duration(microseconds: 33333),
      );
    });

    test('rounds to the nearest frame boundary at 240 fps', () {
      // One frame at 240 fps is 4166.67 µs; 10 ms is closest to frame 2.
      expect(
        snapToFrame(const Duration(milliseconds: 10), 240),
        const Duration(microseconds: 8333),
      );
    });

    test('keeps positions already on a frame boundary', () {
      expect(snapToFrame(Duration.zero, 60), Duration.zero);
      expect(
        snapToFrame(const Duration(seconds: 1), 60),
        const Duration(seconds: 1),
      );
    });
  });

  group('frameAt', () {
    test('names the frame on screen, not the nearest boundary', () {
      // Frame 1 at 60 fps runs 16.67-33.33 ms; every position inside it
      // reads as frame 1.
      expect(frameAt(const Duration(milliseconds: 17), 60), 1);
      expect(frameAt(const Duration(milliseconds: 25), 60), 1);
      expect(frameAt(const Duration(milliseconds: 33), 60), 1);
      expect(frameAt(const Duration(milliseconds: 34), 60), 2);
    });

    test('agrees with the mid-frame positions seeks aim at', () {
      for (final frame in [0, 1, 13, 240]) {
        final us =
            ((frame + 0.5) * Duration.microsecondsPerSecond / 30).round();
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
