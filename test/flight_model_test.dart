import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/elite_releases.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/screens/release_calculator_screen.dart';
import 'package:throwlab/utils/flight_model.dart';
import 'package:throwlab/utils/projectile.dart';

ImplementSpec _senior(ThrowEvent e) => e.defaultImplement;

void main() {
  group('flyThrow', () {
    test('a shot flies almost exactly as it would in a vacuum', () {
      const r = Release(speed: 13.5, angleDeg: 37, height: 2.1);
      final air = flyThrow(ThrowEvent.shotPut, _senior(ThrowEvent.shotPut), r);
      final vacuum = predictedDistance(13.5, 37, releaseHeight: 2.1);
      expect(air.distance, lessThan(vacuum));
      expect(air.distance, closeTo(vacuum, vacuum * 0.015));
    });

    test('drag costs a hammer meters at championship speed', () {
      const r = Release(speed: 28, angleDeg: 40, height: 1.5);
      final air = flyThrow(ThrowEvent.hammer, _senior(ThrowEvent.hammer), r);
      final vacuum = predictedDistance(28, 40, releaseHeight: 1.5);
      expect(vacuum - air.distance, inInclusiveRange(1, 5));
    });

    test('nothing thrown goes nowhere', () {
      const r = Release(speed: 0, angleDeg: 40, height: 2);
      expect(
          flyThrow(ThrowEvent.discus, _senior(ThrowEvent.discus), r).distance,
          0);
    });

    test('the path starts in the hand and ends on the ground', () {
      const r = Release(speed: 25, angleDeg: 35, height: 1.8);
      final f = flyThrow(ThrowEvent.javelin, _senior(ThrowEvent.javelin), r);
      expect(f.path.first, const Offset(0, 1.8));
      expect(f.path.last.dy, 0);
      expect(f.path.last.dx, closeTo(f.distance, 1e-9));
      expect(f.apex, greaterThan(1.8));
    });

    test('a headwind carries a discus further', () {
      const r = Release(speed: 24, angleDeg: 36, height: 1.7, attackDeg: -8);
      final spec = _senior(ThrowEvent.discus);
      final still = flyThrow(ThrowEvent.discus, spec, r).distance;
      final head =
          flyThrow(ThrowEvent.discus, spec, r.copyWith(wind: -4)).distance;
      final tail =
          flyThrow(ThrowEvent.discus, spec, r.copyWith(wind: 4)).distance;
      expect(head, greaterThan(still));
      expect(tail, lessThan(still));
    });

    test('a javelin nose held well above the path costs distance', () {
      const r = Release(speed: 29, angleDeg: 35, height: 1.8);
      final spec = _senior(ThrowEvent.javelin);
      final flat = flyThrow(ThrowEvent.javelin, spec, r).distance;
      final nosey =
          flyThrow(ThrowEvent.javelin, spec, r.copyWith(attackDeg: 10))
              .distance;
      expect(nosey, lessThan(flat - 2));
    });

    test('an elite javelin release lands where finals are won', () {
      final range = eliteRanges[ThrowEvent.javelin]!;
      final r = Release(
          speed: range.typicalSpeed,
          angleDeg: range.typicalAngle,
          height: range.typicalHeight);
      final d =
          flyThrow(ThrowEvent.javelin, _senior(ThrowEvent.javelin), r).distance;
      expect(d, inInclusiveRange(range.marks.$1 - 3, range.marks.$2 + 3));
    });
  });

  group('bestAngle', () {
    test('matches the closed form for a shot, where air hardly counts', () {
      const r = Release(speed: 13.5, angleDeg: 37, height: 2.1);
      final best =
          bestAngle(ThrowEvent.shotPut, _senior(ThrowEvent.shotPut), r);
      expect(best.angleDeg,
          closeTo(optimalAngleDeg(13.5, releaseHeight: 2.1), 0.6));
    });

    test('no neighboring angle throws further', () {
      for (final event in ThrowEvent.values) {
        final range = eliteRanges[event]!;
        final r = Release(
            speed: range.typicalSpeed,
            angleDeg: range.typicalAngle,
            height: range.typicalHeight,
            attackDeg: event == ThrowEvent.discus ? -8 : 0);
        final spec = _senior(event);
        final best = bestAngle(event, spec, r);
        for (final d in [-1.0, 1.0]) {
          final other =
              flyThrow(event, spec, r.copyWith(angleDeg: best.angleDeg + d))
                  .distance;
          expect(other, lessThanOrEqualTo(best.distance + 1e-6),
              reason: event.label);
        }
        // Every event's best is somewhere a coach would recognize.
        expect(best.angleDeg, inInclusiveRange(25, 46), reason: event.label);
      }
    });
  });

  test('a meter a second is worth far more than a degree', () {
    for (final event in ThrowEvent.values) {
      final range = eliteRanges[event]!;
      final r = Release(
          speed: range.typicalSpeed,
          angleDeg: range.typicalAngle,
          height: range.typicalHeight);
      final worth = sensitivity(event, _senior(event), r);
      expect(worth.perSpeed, greaterThan(2), reason: event.label);
      expect(worth.perSpeed, greaterThan(worth.perDegree.abs() * 5),
          reason: event.label);
    }
  });

  group('elite releases', () {
    test('every measured speed sits inside its event\'s typical range', () {
      for (final r in eliteReleases) {
        final range = eliteRanges[r.event]!;
        expect(r.speed, inInclusiveRange(range.speed.$1, range.speed.$2),
            reason: r.athlete);
        expect(r.event.specFor(r.weightKg).weightKg, r.weightKg,
            reason: '${r.athlete} is filed under a weight the event has');
      }
    });

    test('a fully measured shot release comes back within a few percent', () {
      for (final r in eliteReleases
          .where((r) => r.complete && r.event == ThrowEvent.shotPut)) {
        final d = flyThrow(
                r.event,
                r.event.specFor(r.weightKg),
                Release(
                    speed: r.speed, angleDeg: r.angleDeg!, height: r.height!))
            .distance;
        expect(d, closeTo(r.mark, r.mark * 0.03), reason: r.athlete);
      }
    });
  });

  group('ReleaseCalculatorScreen', () {
    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen));
    }

    String distance(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('whatIfDistance'))).data!;

    testWidgets('opens on a measured release and can go back to it',
        (tester) async {
      await pump(
          tester,
          const ReleaseCalculatorScreen(
            event: ThrowEvent.shotPut,
            implementKg: 7.26,
            measured: Release(speed: 12, angleDeg: 38, height: 2.0),
          ));
      expect(find.text('YOUR MEASURED THROW'), findsOneWidget);
      expect(find.text('12.0 m/s'), findsOneWidget);
      final measured = distance(tester);

      await tester.scrollUntilVisible(find.text('Try'), 300);
      await tester.tap(find.text('Try'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text("TOM WALSH'S RELEASE"), -300);
      expect(distance(tester), isNot(measured));

      await tester.tap(find.text('Back to the measured throw'));
      await tester.pump();
      expect(distance(tester), measured);
    });

    testWidgets('switching event shows its own references', (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      expect(find.text('Attack'), findsNothing);
      await tester.tap(find.byTooltip('Discus'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Attack'), 200);
      await tester.scrollUntilVisible(find.text('Daniel Ståhl'), 300);
      expect(find.text('Andrius Gudžius'), findsOneWidget);
    });
  });
}
