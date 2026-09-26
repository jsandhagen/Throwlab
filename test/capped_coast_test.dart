import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/widgets/playback_controls.dart';

void main() {
  test('a hard flick holds the cap, then slows off it without a step', () {
    final coast =
        CappedCoast(decayPerSecond: 0.02, start: 10, velocity: -600, cap: 120);
    var last = coast.x(0);
    for (var t = 0.01; t < 3; t += 0.01) {
      final x = coast.x(t);
      // Never faster than the cap, and always the way it was flung.
      expect(last - x, lessThanOrEqualTo(120 * 0.01 + 1e-9));
      expect(x, lessThanOrEqualTo(last));
      expect(coast.dx(t).abs(), lessThanOrEqualTo(120 + 1e-9));
      last = x;
    }
    // Harder flicks carry further: they spend longer at the cap.
    final softer =
        CappedCoast(decayPerSecond: 0.02, start: 10, velocity: -300, cap: 120);
    expect(coast.x(3), lessThan(softer.x(3)));
  });

  test('a flick under the cap is the plain friction curve', () {
    final coast =
        CappedCoast(decayPerSecond: 0.02, start: 5, velocity: 80, cap: 120);
    final plain = FrictionSimulation(0.02, 5, 80);
    for (final t in [0.0, 0.2, 0.7, 1.5]) {
      expect(coast.x(t), closeTo(plain.x(t), 1e-9));
      expect(coast.dx(t), closeTo(plain.dx(t), 1e-9));
    }
  });
}
