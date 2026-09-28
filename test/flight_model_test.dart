import 'dart:math' as math;

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

    test('a javelin released nose-up settles to the attack it was measured to',
        () {
      // Bartlett and Best have a nose held above the path costing meters.
      // On the measured moment the javelin trims itself to about 11° of
      // attack whatever it left the hand at, so ten degrees nose-up costs
      // little — the tunnel's answer, and the one the model now gives.
      const r = Release(speed: 29, angleDeg: 35, height: 1.8);
      final spec = _senior(ThrowEvent.javelin);
      final flat = flyThrow(ThrowEvent.javelin, spec, r).distance;
      final nosey =
          flyThrow(ThrowEvent.javelin, spec, r.copyWith(attackDeg: 10))
              .distance;
      expect((nosey - flat).abs(), lessThan(1.5));
    });

    test('a javelin released turning moves where it lands', () {
      const r = Release(speed: 29, angleDeg: 35, height: 1.8);
      final spec = _senior(ThrowEvent.javelin);
      final still = flyThrow(ThrowEvent.javelin, spec, r).distance;
      final up = flyThrow(ThrowEvent.javelin, spec, r.copyWith(pitchRate: 20))
          .distance;
      final down =
          flyThrow(ThrowEvent.javelin, spec, r.copyWith(pitchRate: -20))
              .distance;
      expect(up, isNot(closeTo(still, 0.1)));
      expect(down, isNot(closeTo(still, 0.1)));
      // A pitch rate is ignored by what doesn't pitch.
      final discus = _senior(ThrowEvent.discus);
      const d = Release(speed: 24, angleDeg: 36, height: 1.7, attackDeg: -8);
      expect(
          flyThrow(ThrowEvent.discus, discus, d.copyWith(pitchRate: 20))
              .distance,
          flyThrow(ThrowEvent.discus, discus, d).distance);
    });

    test('an elite javelin release lands where finals are won, untuned', () {
      // Nothing in the javelin was set to make this pass: it is the
      // tunnel's table, the rules' dimensions and the typical releases.
      for (final field in EliteField.values) {
        final range = eliteRanges[ThrowEvent.javelin]![field]!;
        final r = Release(
            speed: range.typicalSpeed,
            angleDeg: range.typicalAngle,
            height: range.typicalHeight);
        final d = flyThrow(ThrowEvent.javelin,
                ThrowEvent.javelin.specFor(range.weightKg), r)
            .distance;
        expect(d, inInclusiveRange(range.marks.$1, range.marks.$2),
            reason: field.name);
      }
    });

    test('no slider setting sends a javelin anywhere impossible', () {
      // The corners: slow and steep, tumbling on a pitch rate, where the
      // attack runs far past what the tunnel measured.
      for (final v in [10.0, 33.0]) {
        for (final a in [0.0, 60.0]) {
          for (final attack in [-20.0, 20.0]) {
            for (final rate in [-30.0, 30.0]) {
              final d = flyThrow(
                      ThrowEvent.javelin,
                      _senior(ThrowEvent.javelin),
                      Release(
                          speed: v,
                          angleDeg: a,
                          height: 2,
                          attackDeg: attack,
                          pitchRate: rate))
                  .distance;
              expect(d, inInclusiveRange(0, 140),
                  reason: '$v m/s $a° $attack° $rate°/s');
            }
          }
        }
      }
    });
  });

  group('Aero', () {
    test('a stalled discus keeps its lost lift until well under the stall', () {
      final aero = Aero.of(ThrowEvent.discus, _senior(ThrowEvent.discus));
      double deg(double d) => d * 3.141592653589793 / 180;
      // Attached below the stall, and less once the flow has let go.
      expect(aero.lift(deg(27), stalled: true), lessThan(aero.lift(deg(27))));
      expect(aero.stallsAt(deg(30)), isTrue);
      expect(aero.recoversAt(deg(27)), isFalse);
      expect(aero.recoversAt(deg(24)), isTrue);
      // Lift is gone only face on to the air, not 15° past the stall.
      expect(aero.lift(deg(60), stalled: true), greaterThan(0));
      expect(aero.lift(deg(90), stalled: true), closeTo(0, 1e-9));
    });

    test('the javelin flies on the tunnel\'s table', () {
      double deg(double d) => d * math.pi / 180;
      final aero = Aero.of(ThrowEvent.javelin, _senior(ThrowEvent.javelin));
      expect(aero.drag(0), closeTo(1.30, 1e-9));
      expect(aero.lift(deg(8)), closeTo(1.40, 1e-9));
      expect(aero.lift(deg(-8)), closeTo(-1.40, 1e-9));
      // Nose-up under the trim and nose-down over it: the shape the table
      // is there for.
      expect(aero.moment(deg(8)), greaterThan(0));
      expect(aero.moment(deg(14)), lessThan(0));
      // Past what was measured the lift runs out by side-on, rather than
      // holding its 30° value round to flying tail first.
      expect(aero.lift(deg(60)), lessThan(aero.lift(deg(30))));
      expect(aero.lift(deg(90)), closeTo(0, 1e-9));
      // Referenced to the thickest cross-section, as the paper does.
      expect(aero.area, closeTo(math.pi * 0.0295 * 0.0295 / 4, 1e-12));
      final women =
          Aero.of(ThrowEvent.javelin, ThrowEvent.javelin.specFor(0.6));
      expect(women.area, closeTo(math.pi * 0.0247 * 0.0247 / 4, 1e-12));
    });
  });

  test('a javelin\'s pitch damping comes off the table it flies on', () {
    // C_Nα / 12 for a uniform shaft, the normal force's slope read as the
    // secant to 8° — not a number tuned to make the rocking look right.
    final aero = Aero.of(ThrowEvent.javelin, _senior(ThrowEvent.javelin));
    expect(aero.pitchDamping,
        closeTo((1.40 / (8 * math.pi / 180) + 1.30) / 12, 1e-9));
  });

  group('gapShares', () {
    test('the shares add up to the gap, and only what moved gets one', () {
      final spec12 = ThrowEvent.shotPut.specFor(5.44);
      const a = Release(speed: 11.4, angleDeg: 33.5, height: 1.95);
      const b = Release(speed: 13.5, angleDeg: 36, height: 1.95);
      final shares = gapShares(ThrowEvent.shotPut, spec12, a, b);
      expect(shares.keys.toSet(), {Lever.speed, Lever.angle});
      final gap = flyThrow(ThrowEvent.shotPut, spec12, b).distance -
          flyThrow(ThrowEvent.shotPut, spec12, a).distance;
      expect(shares.values.reduce((x, y) => x + y), closeTo(gap, 1e-9));
      // Speed is nearly all of it, which is the point of the list.
      expect(shares[Lever.speed]!, greaterThan(gap * 0.9));
    });

    test('adds up with every lever moved, wind and pitch included', () {
      final spec = _senior(ThrowEvent.javelin);
      const a = Release(speed: 26, angleDeg: 32, height: 1.8);
      const b = Release(
          speed: 28,
          angleDeg: 35,
          height: 1.9,
          attackDeg: 4,
          wind: -2,
          pitchRate: -10);
      final shares = gapShares(ThrowEvent.javelin, spec, a, b);
      expect(shares, hasLength(Lever.values.length));
      final gap = flyThrow(ThrowEvent.javelin, spec, b).distance -
          flyThrow(ThrowEvent.javelin, spec, a).distance;
      expect(shares.values.reduce((x, y) => x + y), closeTo(gap, 1e-9));
    });

    test('an angle carries the speed it costs', () {
      // Raised on its own, with the speed following it the way the
      // calculator's own angle does: one row, the whole gap, never a speed
      // row gone red that nobody touched.
      for (final event in [ThrowEvent.shotPut, ThrowEvent.javelin]) {
        final spec = _senior(event);
        final loss = typicalSpeedLossPerDeg(event);
        const a = Release(speed: 20, angleDeg: 32, height: 1.9, attackDeg: 4);
        final b = a.copyWith(angleDeg: 35, speed: a.speed - loss * 3);
        final gap = flyThrow(event, spec, b).distance -
            flyThrow(event, spec, a).distance;
        final shares = gapShares(event, spec, a, b, speedLossPerDeg: loss);
        expect(shares.keys, [Lever.angle], reason: event.name);
        expect(shares[Lever.angle]!, closeTo(gap, 1e-9));

        // Speed added on top of that is the speed's own, and the two still
        // add up to the gap.
        final c = b.copyWith(speed: b.speed + 1);
        final both = gapShares(event, spec, a, c, speedLossPerDeg: loss);
        final gap2 = flyThrow(event, spec, c).distance -
            flyThrow(event, spec, a).distance;
        expect(both.keys.toSet(), {Lever.speed, Lever.angle});
        expect(both[Lever.speed]!, greaterThan(0));
        expect(both.values.reduce((x, y) => x + y), closeTo(gap2, 1e-9));
      }
    });

    test('nothing moved is nothing to split', () {
      const r = Release(speed: 13, angleDeg: 37, height: 2);
      final spec = _senior(ThrowEvent.shotPut);
      expect(gapShares(ThrowEvent.shotPut, spec, r, r), isEmpty);
    });
  });

  group('bestAngle', () {
    ({double angleDeg, double distance, double speed}) finalBest(
        ThrowEvent event, EliteField field,
        {bool speedFalls = true}) {
      final range = eliteRanges[event]![field]!;
      return bestAngle(
          event,
          event.specFor(range.weightKg),
          Release(
              speed: range.typicalSpeed,
              angleDeg: range.typicalAngle,
              height: range.typicalHeight,
              attackDeg: range.attackDeg),
          speedLossPerDeg: speedFalls ? typicalSpeedLossPerDeg(event) : 0);
    }

    test('a javelin thrower\'s best angle is where finals release', () {
      for (final field in EliteField.values) {
        // The flight alone is best near 40°; the speed an athlete gives up
        // going higher brings it into the thirties, where finals are thrown.
        expect(finalBest(ThrowEvent.javelin, field, speedFalls: false).angleDeg,
            inInclusiveRange(38, 43),
            reason: field.name);
        expect(finalBest(ThrowEvent.javelin, field).angleDeg,
            inInclusiveRange(33, 37),
            reason: field.name);
      }
    });

    test('a putter\'s best angle comes down off the flight\'s', () {
      final flight =
          finalBest(ThrowEvent.shotPut, EliteField.men, speedFalls: false);
      final putter = finalBest(ThrowEvent.shotPut, EliteField.men);
      expect(flight.angleDeg, greaterThan(41));
      expect(putter.angleDeg, inInclusiveRange(36, 40));
    });

    test('the speed falls from the release it was handed, and only there', () {
      const r = Release(speed: 28, angleDeg: 34, height: 1.8);
      final spec = _senior(ThrowEvent.javelin);
      final best = bestAngle(ThrowEvent.javelin, spec, r, speedLossPerDeg: 0.1);
      expect(best.speed, closeTo(28 - 0.1 * (best.angleDeg - 34), 1e-9));
      // And the distance it reports is that release's, not a held one.
      expect(
          best.distance,
          closeTo(
              flyThrow(ThrowEvent.javelin, spec,
                      r.copyWith(angleDeg: best.angleDeg, speed: best.speed))
                  .distance,
              1e-9));
    });

    test('a hammer thrower\'s best angle is where elite throwers release', () {
      // Held, the flight is best in the mid forties; the loss the hammer is
      // backed out with brings it into the 37–42° throwers use.
      for (final field in EliteField.values) {
        expect(finalBest(ThrowEvent.hammer, field, speedFalls: false).angleDeg,
            greaterThan(43),
            reason: field.name);
        final range = eliteRanges[ThrowEvent.hammer]![field]!;
        expect(finalBest(ThrowEvent.hammer, field).angleDeg,
            inInclusiveRange(range.angleDeg.$1, range.angleDeg.$2),
            reason: field.name);
      }
    });

    test('a discus thrower\'s best angle is where elite throwers release', () {
      // Flown rolling, the flight alone is best in the high thirties — not
      // the twenties a discus held level in one plane was best at — and the
      // loss backed out of it brings it onto a final's typical release.
      for (final field in EliteField.values) {
        final flight =
            finalBest(ThrowEvent.discus, field, speedFalls: false).angleDeg;
        expect(flight, inInclusiveRange(37, 41), reason: field.name);
        final range = eliteRanges[ThrowEvent.discus]![field]!;
        expect(finalBest(ThrowEvent.discus, field).angleDeg,
            inInclusiveRange(range.angleDeg.$1, range.angleDeg.$2),
            reason: field.name);
      }
    });

    test('a discus flies the way Hubbard and Cheng\'s does', () {
      // Their 3-D model's best men's release at 25 m/s is 38.4° and 69.4 m.
      // Nothing here was tuned to it.
      final spec = _senior(ThrowEvent.discus);
      var best = (angle: 0.0, attack: 0.0, distance: 0.0);
      for (var attack = -14.0; attack <= 0; attack += 2) {
        final b = bestAngle(ThrowEvent.discus, spec,
            Release(speed: 25, angleDeg: 38, height: 1.7, attackDeg: attack));
        if (b.distance > best.distance) {
          best = (angle: b.angleDeg, attack: attack, distance: b.distance);
        }
      }
      expect(best.angle, inInclusiveRange(35, 41));
      expect(best.distance, closeTo(69.4, 2));
    });

    test('matches the closed form for a shot, where air hardly counts', () {
      const r = Release(speed: 13.5, angleDeg: 37, height: 2.1);
      final best =
          bestAngle(ThrowEvent.shotPut, _senior(ThrowEvent.shotPut), r);
      expect(best.angleDeg,
          closeTo(optimalAngleDeg(13.5, releaseHeight: 2.1), 0.6));
    });

    test('no neighboring angle throws further', () {
      for (final event in ThrowEvent.values) {
        final range = eliteRanges[event]![EliteField.men]!;
        final r = Release(
            speed: range.typicalSpeed,
            angleDeg: range.typicalAngle,
            height: range.typicalHeight,
            attackDeg: range.attackDeg);
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
      final range = eliteRanges[event]![EliteField.men]!;
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
        final range = eliteRanges[r.event]![EliteField.men]!;
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

  test('every event has a men\'s and a women\'s final on its own implement',
      () {
    for (final event in ThrowEvent.values) {
      for (final field in EliteField.values) {
        final range = eliteRanges[event]![field]!;
        expect(range.field, field);
        expect(event.specFor(range.weightKg).weightKg, range.weightKg,
            reason: '${event.label} ${field.name}');
        // What the model makes of the typical release is somewhere near
        // what those finals throw.
        final d = flyThrow(
                event,
                event.specFor(range.weightKg),
                Release(
                    speed: range.typicalSpeed,
                    angleDeg: range.typicalAngle,
                    height: range.typicalHeight,
                    attackDeg: range.attackDeg))
            .distance;
        expect(d, inInclusiveRange(range.marks.$1 - 8, range.marks.$2 + 3),
            reason: '${event.label} ${field.name}');
      }
    }
  });

  group('ReleaseCalculatorScreen', () {
    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen));
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    // Scrolled to and then brought to the middle of the list, since the
    // edge a scroll stops at is where the floating result hangs.
    Future<void> reach(WidgetTester tester, Finder finder,
        [double delta = 200]) async {
      await tester.scrollUntilVisible(finder, delta);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
    }

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
      final measured = text(tester, 'whatIfDistance');
      // Far enough that the whole speed slider is on screen, not only its
      // label.
      await reach(tester, find.byType(Slider).first);
      expect(find.text('12.0 m/s'), findsOneWidget);
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pump();
      await reach(tester, find.text('Back to the measured throw'), -200);
      expect(text(tester, 'whatIfDistance'), isNot(measured));
      await tester.tap(find.text('Back to the measured throw'));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whatIfDistance')), -300);
      expect(text(tester, 'whatIfDistance'), measured);
    });

    testWidgets('says it is a guide before anything else', (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      final banner =
          tester.getRect(find.byKey(const ValueKey('whatIfDisclaimer')));
      final number =
          tester.getRect(find.byKey(const ValueKey('whatIfDistance')));
      expect(banner.bottom, lessThan(number.top));
      expect(find.textContaining('guide, not a reference'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SOURCES'), 600);
      await tester.scrollUntilVisible(
          find.textContaining('Linthorne, N. P.'), 200);
    });

    testWidgets('the speed-loss estimate says what research it rests on',
        (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      await tester.scrollUntilVisible(
          find.text('Speed lost per 10° steeper'), 300);
      expect(find.textContaining('Estimated from academic research'),
          findsOneWidget);
      expect(find.textContaining('Linthorne (2001) measured shot putters'),
          findsOneWidget);
      await tester.scrollUntilVisible(find.text('Hammer'), -2000);
      await tester.tap(find.text('Javelin'));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.text('Speed lost per 10° steeper'), 300);
      expect(
          find.textContaining('Red & Zogaib (1977) measured'), findsOneWidget);
    });

    testWidgets('the best angle can be tried, and goes in as the what-if',
        (tester) async {
      await pump(
          tester,
          const ReleaseCalculatorScreen(
            event: ThrowEvent.shotPut,
            implementKg: 7.26,
            measured: Release(speed: 12, angleDeg: 30, height: 2.0),
          ));
      final button = find.byKey(const ValueKey('tryBestAngle'));
      await reach(tester, button, 300);
      await tester.tap(button);
      await tester.pump();
      // Tried, it is at its best and asks no more.
      expect(button, findsNothing);
      expect(text(tester, 'bestAngle'), "At this thrower's best angle.");
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whatIfGap')), -600);
      expect(text(tester, 'whatIfGap'), startsWith('+'));
      expect(find.textContaining('YOUR MEASURED THROW'), findsNothing);
      // The angle carries its own speed, so the breakdown is the angle alone.
      expect(find.byKey(const ValueKey('gapShare-angle')), findsOneWidget);
      expect(find.byKey(const ValueKey('gapShare-speed')), findsNothing);
    });

    testWidgets('a dial steps by its unit and matches the other throw',
        (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      await tester.tap(find.byKey(const ValueKey('whatIfTry')));
      await tester.pump();
      final raise = find.byKey(const ValueKey('Raise-Speed'));
      await reach(tester, raise);
      for (var i = 0; i < 2; i++) {
        await tester.tap(raise);
        await tester.pumpAndSettle();
      }
      expect(find.text('+0.2 m/s'), findsOneWidget);
      // The difference is the way back level with the baseline.
      final match = find.byKey(const ValueKey('match-Speed'));
      await reach(tester, match, -100);
      await tester.tap(match);
      await tester.pump();
      expect(find.byKey(const ValueKey('match-Speed')), findsNothing);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whatIfGap')), -300);
      expect(text(tester, 'whatIfGap'), '0.00 m');
    });

    testWidgets('an elite thrower is laid over the baseline as the what-if',
        (tester) async {
      await pump(
          tester,
          const ReleaseCalculatorScreen(
            event: ThrowEvent.shotPut,
            implementKg: 4,
            measured: Release(speed: 11.4, angleDeg: 33.5, height: 1.95),
          ));
      final women = find.byKey(const ValueKey('elite-typical'));
      // Built is not on screen: bring it all the way in before tapping.
      await reach(tester, women, 300);
      await tester.tap(women);
      await tester.pump();

      // The what-if is the one on the sliders, with the baseline ticked on each
      // track and the difference beside the value.
      await tester.scrollUntilVisible(find.text('+2.1 m/s'), -300);
      expect(find.byKey(const ValueKey('other-Speed')), findsOneWidget);

      await tester.scrollUntilVisible(
          find.text('further than the baseline'), -300);
      expect(find.textContaining('Typical elite thrower'), findsWidgets);
      expect(text(tester, 'whatIfGap'), startsWith('+'));

      // Tapping it again puts it away.
      // Built is not on screen: bring it all the way in before tapping.
      await reach(tester, women, 300);
      await tester.tap(women);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('YOUR MEASURED THROW'), -300);
      expect(find.byKey(const ValueKey('whatIfGap')), findsNothing);
    });

    testWidgets('where the gap comes from adds up to the gap as printed',
        (tester) async {
      await pump(
          tester,
          const ReleaseCalculatorScreen(
            event: ThrowEvent.shotPut,
            implementKg: 4,
            measured: Release(speed: 11.4, angleDeg: 33.5, height: 1.95),
          ));
      final women = find.byKey(const ValueKey('elite-typical'));
      await reach(tester, women, 300);
      await tester.tap(women);
      await tester.pump();

      // Signed hundredths in meters, signed quarter inches in feet.
      int steps(String s, bool feet) {
        final sign = s.startsWith('−') ? -1 : 1;
        final body = s.replaceAll(RegExp(r'^[+−]'), '').replaceAll(' m', '');
        if (!feet) return sign * (double.parse(body) * 100).round();
        final [ft, inches] = body.split('-');
        return sign * (int.parse(ft) * 48 + (double.parse(inches) * 4).round());
      }

      Future<void> check(bool feet) async {
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('whatIfGap')), -300);
        final gap = steps(text(tester, 'whatIfGap'), feet);
        await tester.scrollUntilVisible(
            find.text('WHERE THE GAP COMES FROM'), 200);
        var sum = 0;
        for (final l in [Lever.speed, Lever.angle]) {
          sum += steps(text(tester, 'gapShare-${l.name}'), feet);
        }
        expect(sum, gap, reason: feet ? 'in feet' : 'in meters');
        // Height did not move, so it gets no row.
        expect(find.byKey(const ValueKey('gapShare-height')), findsNothing);
      }

      await check(false);
      await tester.scrollUntilVisible(find.text('ft'), -600);
      await tester.tap(find.text('ft'));
      await tester.pump();
      await check(true);

      // The shot trades speed for angle, and the angle's dial says so.
      await tester.scrollUntilVisible(
          find.textContaining('Speed moves with it'), 300);
      await tester.scrollUntilVisible(find.text('WHAT A NUDGE IS WORTH'), 300);
      expect(find.text('from the what if'), findsOneWidget);
    });

    testWidgets(
        'a what-if starts as a copy of the baseline and moves on its own',
        (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      await tester.scrollUntilVisible(find.text('Try a change'), 200);
      await tester.tap(find.text('Try a change'));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whatIfGap')), -300);
      expect(text(tester, 'whatIfGap'), '0.00 m');
      expect(text(tester, 'whatIfVerdict'), 'the same as the baseline');

      await reach(tester, find.byType(Slider).first);
      await tester.drag(find.byType(Slider).first, const Offset(-80, 0));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whatIfGap')), -300);
      expect(text(tester, 'whatIfGap'), startsWith('−'));
      expect(text(tester, 'whatIfVerdict'), 'shorter than the baseline');
    });

    testWidgets('reads in feet and miles an hour when switched',
        (tester) async {
      await pump(
          tester,
          const ReleaseCalculatorScreen(
            event: ThrowEvent.shotPut,
            implementKg: 7.26,
            measured: Release(speed: 12, angleDeg: 38, height: 2.0),
          ));
      final meters = text(tester, 'whatIfDistance');
      await tester.tap(find.text('ft'));
      await tester.pump();
      // The same throw, spelled the way a meet in feet writes it.
      final feet = text(tester, 'whatIfDistance');
      expect(feet, matches(RegExp(r'^\d+-\d')));
      expect(feet, isNot(meters));
      await tester.scrollUntilVisible(find.text('Angle'), 200);
      expect(find.text('26.8 mph'), findsOneWidget);
      // 2.00 m of release height, in feet and inches.
      await tester.scrollUntilVisible(find.text('6-06.50'), 100);
      await tester.scrollUntilVisible(find.text('+1 mph'), 200);
      expect(find.text('+4 in higher'), findsOneWidget);
    });

    testWidgets('a javelin\'s best angle is a thrower\'s, and the loss is set',
        (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      await tester.tap(find.text('Javelin'));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.text('Speed lost per 10° steeper'), 300);
      final before = text(tester, 'bestAngle');
      expect(
          before,
          anyOf(startsWith('Best angle for this thrower'),
              startsWith("At this thrower's best angle")));
      expect(
          find.textContaining('the flight alone is best at'), findsOneWidget);
      expect(find.text('1.0 m/s'), findsOneWidget);
      // Holding the speed turns it back into the flight's own answer.
      final lossDial = find.descendant(
          of: find
              .ancestor(
                  of: find.text('Speed lost per 10° steeper'),
                  matching: find.byType(Column))
              .first,
          matching: find.byType(Slider));
      await reach(tester, lossDial.first);
      await tester.drag(lossDial.first, const Offset(-600, 0));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('bestAngle')), -200);
      expect(find.text('0.0 m/s'), findsOneWidget);
      expect(text(tester, 'bestAngle'), isNot(before));
      expect(find.textContaining("not an athlete's"), findsOneWidget);

      // Another event opens on its own estimate, and says what it rests on.
      await tester.scrollUntilVisible(find.text('Discus'), -2000);
      await tester.tap(find.text('Discus'));
      await tester.pump();
      await tester.scrollUntilVisible(
          find.text('Speed lost per 10° steeper'), 300);
      expect(find.textContaining('elite discus throwers'), findsOneWidget);
    });

    testWidgets('an angle takes the speed that goes with it', (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      await tester.tap(find.text('Javelin'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('whatIfTry')));
      await tester.pump();
      final raise = find.byKey(const ValueKey('Raise-Angle'));
      await reach(tester, raise);
      // Two half-degree steps: a degree steeper, a tenth of a meter a
      // second slower at the javelin's estimate.
      for (var i = 0; i < 2; i++) {
        await tester.tap(raise);
        await tester.pumpAndSettle();
      }
      expect(find.text('+1.0°'), findsOneWidget);
      expect(find.text('−0.1 m/s'), findsOneWidget);
      expect(find.textContaining('Speed moves with it: −1.0 m/s per 10°'),
          findsOneWidget);

      // The discus's speed rides with its angle too, by its own estimate.
      await tester.scrollUntilVisible(find.text('Discus'), -2000);
      await tester.tap(find.text('Discus'));
      await tester.pumpAndSettle();
      await reach(tester, raise);
      expect(find.textContaining('Speed moves with it: −0.5 m/s per 10°'),
          findsOneWidget);
    });

    testWidgets('while the angle is in the hand the speed rides with it',
        (tester) async {
      // The shot: no dials in the air between the angle and its best.
      await pump(tester, const ReleaseCalculatorScreen());
      await reach(tester, find.byKey(const ValueKey('Raise-Angle')));
      final angle = find.descendant(
          of: find
              .ancestor(
                  of: find.byKey(const ValueKey('Raise-Angle')),
                  matching: find.byType(Row))
              .first,
          matching: find.byType(Slider));
      expect(find.byKey(const ValueKey('follows-Speed')), findsOneWidget);
      final before = text(tester, 'bestAngle');
      double speed() => tester
          .widget<Slider>(find.descendant(
              of: find
                  .ancestor(
                      of: find.byKey(const ValueKey('Raise-Speed')),
                      matching: find.byType(Row))
                  .first,
              matching: find.byType(Slider)))
          .value;
      final speedBefore = speed();

      final rect = tester.getRect(angle);
      final x = rect.left + 18 + (rect.width - 36) * 34.5 / 60;
      final finger = await tester.startGesture(Offset(x, rect.center.dy));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await finger.moveBy(const Offset(12, 0));
        await tester.pump();
      }
      // The speed has come down with the angle and says why; the best
      // angle is the one from before the finger went down, held over.
      expect(speed(), lessThan(speedBefore));
      expect(find.byKey(const ValueKey('following-Speed')), findsOneWidget);
      expect(text(tester, 'bestAngle'), before);

      await finger.up();
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('following-Speed')), findsNothing);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('bestAngle')), 300);
      expect(text(tester, 'bestAngle'), isNot(before));
    });

    testWidgets('the result floats over the dials once scrolled past',
        (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      final floating = find.byKey(const ValueKey('whatIfFloating'));
      expect(floating, findsNothing);
      await tester.scrollUntilVisible(find.text('Height'), 200);
      await tester.pumpAndSettle();
      expect(floating, findsOneWidget);
      // A tap goes back up to the card, and the copy goes away.
      await tester.tap(floating);
      await tester.pumpAndSettle();
      expect(floating, findsNothing);
      expect(find.byKey(const ValueKey('whatIfDistance')).hitTestable(),
          findsOneWidget);
    });

    testWidgets('elite throwers are offered by the implement they throw',
        (tester) async {
      await pump(
          tester,
          const ReleaseCalculatorScreen(
            event: ThrowEvent.shotPut,
            implementKg: 5.44,
            measured: Release(speed: 11.4, angleDeg: 33.5, height: 1.95),
          ));
      // A boys' 12 lb borrows the men's: the typical elite thrower and
      // Walsh, their releases flown with the 12 lb.
      final walsh = find.byKey(const ValueKey('elite-Tom Walsh'));
      await tester.scrollUntilVisible(walsh, 600);
      expect(find.byKey(const ValueKey('elite-typical')), findsOneWidget);
      expect(find.text("Men's 16 lb"), findsOneWidget);
      expect(find.textContaining('22.31 m with the 16 lb'), findsOneWidget);
      expect(find.textContaining("Elite men's releases, flown with the 12 lb"),
          findsOneWidget);
      await reach(tester, walsh);
      await tester.tap(walsh);
      await tester.pump();
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('whatIfGap')), -3000);
      expect(text(tester, 'whatIfGap'), startsWith('+'));

      // Nobody elite throws anything like a 3 kg, and the screen starts
      // over on it.
      await tester.scrollUntilVisible(find.text('Hammer'), -3000);
      await tester.tap(find.byKey(const ValueKey('whatIfImplement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 kg').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('whatIfGap')), findsNothing);
      expect(find.text('Back to the measured throw'), findsNothing);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('eliteNone')), 600);
      expect(find.byKey(const ValueKey('elite-typical')), findsNothing);
      expect(walsh, findsNothing);

      // And back to the 12 lb is the measured throw again.
      await tester.scrollUntilVisible(find.text('Hammer'), -3000);
      await tester.tap(find.byKey(const ValueKey('whatIfImplement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 lb').last);
      await tester.pumpAndSettle();
      expect(find.text('YOUR MEASURED THROW'), findsOneWidget);
    });

    test("a boys' implement borrows the men's elite throwers", () {
      expect(eliteWeightFor(ThrowEvent.shotPut, 5.44), 7.26);
      expect(eliteWeightFor(ThrowEvent.shotPut, 6), 7.26);
      expect(eliteWeightFor(ThrowEvent.discus, 1.6), 2);
      expect(eliteWeightFor(ThrowEvent.javelin, 0.7), 0.8);
      expect(eliteWeightFor(ThrowEvent.hammer, 5), 7.26);
      // The senior implements are their own.
      expect(eliteWeightFor(ThrowEvent.shotPut, 4), 4);
      expect(eliteWeightFor(ThrowEvent.discus, 2), 2);
      // Lighter than the women's has nobody.
      expect(eliteWeightFor(ThrowEvent.shotPut, 3), isNull);
      expect(eliteWeightFor(ThrowEvent.javelin, 0.5), isNull);
      expect(eliteReferencesFor(ThrowEvent.discus, 1.6), hasLength(3));
    });

    testWidgets('changing the implement starts over', (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      await tester.tap(find.byKey(const ValueKey('whatIfTry')));
      await tester.pump();
      expect(find.byKey(const ValueKey('whatIfGap')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('whatIfImplement')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 kg').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('whatIfGap')), findsNothing);
      expect(find.text('TYPICAL ELITE THROWER'), findsOneWidget);
    });

    testWidgets('switching event shows its own references', (tester) async {
      await pump(tester, const ReleaseCalculatorScreen());
      expect(find.text('Attack'), findsNothing);
      await tester.tap(find.text('Discus'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Attack'), 200);
      await tester.scrollUntilVisible(find.text('Daniel Ståhl'), 300);
      expect(find.text('Andrius Gudžius'), findsOneWidget);
    });
  });
}
