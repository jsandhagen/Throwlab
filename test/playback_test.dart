import 'package:flutter_test/flutter_test.dart';

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
}
