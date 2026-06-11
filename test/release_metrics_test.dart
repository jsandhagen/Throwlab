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
      );
      expect(m.releaseAngleDeg, closeTo(45, 1e-6));
    });

    test('angle of attack is attitude minus flight path', () {
      // Javelin axis horizontal, flying upward at 45° → nose 45° below
      // the flight path.
      final m = computeReleaseMetrics(
        refA: tip,
        refB: tail,
        pointA: const Offset(100, 200),
        pointB: const Offset(150, 150),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        withAttackAngle: true,
      );
      expect(m.attackAngleDeg, closeTo(-45, 1e-6));
    });

    test('attack angle tolerates swapped tip/tail taps', () {
      final swapped = computeReleaseMetrics(
        refA: tail,
        refB: tip,
        pointA: const Offset(100, 200),
        pointB: const Offset(150, 150),
        referenceMeters: 2.6,
        dtSeconds: 0.05,
        withAttackAngle: true,
      );
      expect(swapped.attackAngleDeg, closeTo(-45, 1e-6));
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

  group('VideoOptimizer.parseRate', () {
    test('parses plain and decimal rates', () {
      expect(VideoOptimizer.parseRate('240'), 240);
      expect(VideoOptimizer.parseRate('239.880000'), closeTo(239.88, 1e-9));
    });

    test('parses fractional rates', () {
      expect(VideoOptimizer.parseRate('30000/1001'),
          closeTo(29.97, 0.001));
    });

    test('rejects garbage', () {
      expect(VideoOptimizer.parseRate(null), isNull);
      expect(VideoOptimizer.parseRate(''), isNull);
      expect(VideoOptimizer.parseRate('0/0'), isNull);
      expect(VideoOptimizer.parseRate('abc'), isNull);
    });
  });
}
