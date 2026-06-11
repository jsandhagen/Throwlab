import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/utils/projectile.dart';

void main() {
  group('predictedDistance', () {
    test('matches the closed form for a ground-level 45° release', () {
      // R = v^2 / g at 45 degrees from ground level.
      expect(predictedDistance(10, 45),
          closeTo(100 / gravity, 1e-9));
    });

    test('complementary angles land at the same distance from ground level',
        () {
      expect(predictedDistance(13, 30),
          closeTo(predictedDistance(13, 60), 1e-9));
    });

    test('release height adds distance', () {
      expect(predictedDistance(13, 38, releaseHeight: 2.1),
          greaterThan(predictedDistance(13, 38)));
    });

    test('zero speed goes nowhere', () {
      expect(predictedDistance(0, 40, releaseHeight: 2), 0);
    });
  });

  group('optimalAngleDeg', () {
    test('is 45° from ground level', () {
      expect(optimalAngleDeg(14), closeTo(45, 1e-9));
    });

    test('drops below 45° with an elevated release', () {
      final angle = optimalAngleDeg(13.5, releaseHeight: 2.1);
      expect(angle, lessThan(45));
      expect(angle, greaterThan(35));
    });

    test('no other angle beats the optimum', () {
      const speed = 13.5;
      const height = 2.1;
      final best = predictedDistance(
          speed, optimalAngleDeg(speed, releaseHeight: height),
          releaseHeight: height);
      for (var angle = 20.0; angle <= 60; angle += 1) {
        expect(predictedDistance(speed, angle, releaseHeight: height),
            lessThanOrEqualTo(best + 1e-9));
      }
    });
  });

  group('flightTime', () {
    test('matches 2·v·sinθ/g from ground level', () {
      expect(flightTime(10, 90), closeTo(20 / gravity, 1e-9));
    });
  });

  group('distanceLostToAngle', () {
    test('is zero at the optimal angle and positive elsewhere', () {
      const speed = 12.0;
      const height = 2.0;
      final optimal = optimalAngleDeg(speed, releaseHeight: height);
      expect(distanceLostToAngle(speed, optimal, releaseHeight: height),
          closeTo(0, 1e-9));
      expect(distanceLostToAngle(speed, optimal - 8, releaseHeight: height),
          greaterThan(0));
    });
  });
}
