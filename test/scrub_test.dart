import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/utils/scrub.dart';

void main() {
  group('scrubGain', () {
    test('stays 1:1 at and below the slow threshold', () {
      expect(scrubGain(0), 1);
      expect(scrubGain(kScrubSlowSpeed), 1);
      expect(scrubGain(kScrubSlowSpeed - 1), 1);
    });

    test('reaches the max gain at the fast threshold', () {
      expect(scrubGain(kScrubFastSpeed), closeTo(kScrubMaxGain, 1e-9));
      expect(scrubGain(kScrubFastSpeed * 10), closeTo(kScrubMaxGain, 1e-9));
    });

    test('rises monotonically between the thresholds', () {
      var previous = scrubGain(kScrubSlowSpeed);
      for (var s = kScrubSlowSpeed; s <= kScrubFastSpeed; s += 100) {
        final gain = scrubGain(s);
        expect(gain, greaterThanOrEqualTo(previous));
        expect(gain, inInclusiveRange(1, kScrubMaxGain));
        previous = gain;
      }
    });

    test('eases in — precision lingers just past the slow threshold', () {
      // A quarter of the way into the ramp, gain has climbed less than a
      // quarter of the way to the max (t² curve).
      final quarter = kScrubSlowSpeed + (kScrubFastSpeed - kScrubSlowSpeed) / 4;
      final linearQuarter = 1 + 0.25 * (kScrubMaxGain - 1);
      expect(scrubGain(quarter), lessThan(linearQuarter));
    });
  });

  group('ScrubAccumulator', () {
    test('a slow drag advances one frame per pixelsPerFrame (no boost)', () {
      final scrub = ScrubAccumulator();
      // 5 px over 100 ms = 50 px/s, well under the slow threshold.
      var frames = 0;
      var t = Duration.zero;
      for (var i = 0; i < 4; i++) {
        t += const Duration(milliseconds: 100);
        frames += scrub.addDrag(5, 10, timestamp: t);
      }
      // 20 px of drag / 10 px-per-frame = 2 frames, unaccelerated.
      expect(frames, 2);
      expect(scrub.lastGain, 1);
    });

    test('a fast drag covers far more frames than the raw ratio', () {
      final slow = ScrubAccumulator();
      final fast = ScrubAccumulator();
      // Same 200 px of travel, delivered slowly vs. in a quick flick.
      var slowFrames = 0;
      var t = Duration.zero;
      for (var i = 0; i < 20; i++) {
        t += const Duration(milliseconds: 100); // 10 px / 100 ms = 100 px/s
        slowFrames += slow.addDrag(10, 10, timestamp: t);
      }
      var fastFrames = 0;
      t = Duration.zero;
      for (var i = 0; i < 20; i++) {
        t += const Duration(milliseconds: 2); // 10 px / 2 ms = 5000 px/s
        fastFrames += fast.addDrag(10, 10, timestamp: t);
      }
      expect(slowFrames, 20); // 200 px / 10 = 20 frames, 1:1
      expect(fastFrames, greaterThan(slowFrames * 4));
      expect(fast.lastGain, greaterThan(slow.lastGain));
    });

    test('retains the fractional frame across calls', () {
      final scrub = ScrubAccumulator();
      var t = const Duration(milliseconds: 100);
      // 6 px / 10 px-per-frame = 0.6 frame → 0 this call.
      expect(scrub.addDrag(6, 10, timestamp: t), 0);
      t += const Duration(milliseconds: 100);
      // Another 0.6 → 1.2 accumulated → 1 frame, 0.2 carried.
      expect(scrub.addDrag(6, 10, timestamp: t), 1);
    });

    test('reset drops carried fraction and speed history', () {
      final scrub = ScrubAccumulator();
      scrub.addDrag(6, 10, timestamp: const Duration(milliseconds: 100));
      scrub.reset();
      expect(scrub.lastGain, 1);
      // Fraction was cleared, so a lone 0.6-frame step emits nothing.
      expect(scrub.addDrag(6, 10,
          timestamp: const Duration(milliseconds: 200)), 0);
    });

    test('scrubs backward symmetrically', () {
      final scrub = ScrubAccumulator();
      var t = const Duration(milliseconds: 100);
      expect(scrub.addDrag(-15, 10, timestamp: t), -1); // -1.5 → -1
      t += const Duration(milliseconds: 100);
      expect(scrub.addDrag(-15, 10, timestamp: t), -2); // -0.5 - 1.5 = -2.0
    });

    test('addRaw steps 1:1 without acceleration (coast path)', () {
      final scrub = ScrubAccumulator();
      expect(scrub.addRaw(25, 10), 2); // 2.5 → 2 frames, 0.5 carried
      expect(scrub.addRaw(25, 10), 3); // 0.5 + 2.5 = 3.0 → 3 frames
    });

    test('falls back to 1:1 when timestamps are missing', () {
      final scrub = ScrubAccumulator();
      expect(scrub.addDrag(100, 10), 10); // no timestamp → gain 1
      expect(scrub.lastGain, 1);
    });
  });
}
