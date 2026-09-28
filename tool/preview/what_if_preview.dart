// The what-if calculator: a shot put opened on its own; a measured high
// school 12 lb put against the men's elite throwers, whose release carries
// across to a boys' implement; a measured 4 kg put with the
// typical elite thrower laid over it; the discus, the hammer and the
// javelin compared the same way, the javelin read in feet, which is what
// the field's markers switch to. Each is shot at a phone's height, and the
// busiest again at the full length of the page. See CLAUDE.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/release_calculator_screen.dart';
import 'package:throwlab/utils/flight_model.dart';
import 'package:throwlab/widgets/distance_field.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('what if', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> open(Widget screen,
        {double height = 2532, DistanceUnit unit = DistanceUnit.meters}) async {
      DistanceField.preferred = unit;
      tester.view.physicalSize = Size(1170, height);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        theme: ThrowLabApp.theme,
        debugShowCheckedModeBanner: false,
        home: screen,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> shoot(String name) => expectLater(
        find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));

    // The elite cards sit under the sliders: tap one where it is, then go
    // back to the top, which is what a coach looks at after tapping it.
    Future<void> tap(Key key) async {
      await tester.scrollUntilVisible(find.byKey(key), 300);
      await tester.pumpAndSettle();
      // To the middle: the top edge is where the floating result hangs.
      await Scrollable.ensureVisible(tester.element(find.byKey(key)),
          alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      // Back to the top. A jump lands on an estimate of the rows above that
      // were never built, so it is repeated until the list says it is
      // really there.
      final position = tester
          .state<ScrollableState>(find.descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable)))
          .position;
      for (var i = 0; i < 5 && position.pixels != 0; i++) {
        position.jumpTo(0);
        await tester.pumpAndSettle();
      }
    }

    await open(const ReleaseCalculatorScreen());
    await shoot('what_if_shot');
    await open(const ReleaseCalculatorScreen(), height: 7200);
    await shoot('what_if_shot_full');

    const measured = ReleaseCalculatorScreen(
      event: ThrowEvent.shotPut,
      implementKg: 5.44,
      measured: Release(speed: 11.4, angleDeg: 33.5, height: 1.95),
    );
    await open(measured);
    await shoot('what_if_measured');
    // The best angle, tried: it goes in as the what-if over the measured
    // throw, so the headline is what the angle alone is worth.
    await tap(const ValueKey('tryBestAngle'));
    await shoot('what_if_best_angle');
    await open(measured, height: 7200);
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_boys_full');

    // A women's 4 kg put against the typical elite thrower with the 4 kg.
    const women = ReleaseCalculatorScreen(
      event: ThrowEvent.shotPut,
      implementKg: 4,
      measured: Release(speed: 11.4, angleDeg: 33.5, height: 1.95),
    );
    await open(women);
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_vs_elite');
    // Down among the dials, with the result hanging over them: the number,
    // the two flights and what the gap is made of, while a slider moves.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('Raise-Height')), 300);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('Raise-Height'))),
        alignment: 0.6);
    await tester.pumpAndSettle();
    await shoot('what_if_floating');
    // And an angle raised from there: the speed comes down with it.
    await tester.tap(find.byKey(const ValueKey('Raise-Angle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Raise-Angle')));
    await tester.pumpAndSettle();
    await shoot('what_if_floating_angle');
    await open(women, height: 5600);
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_vs_elite_full');

    // The 16 lb, with Walsh measured by name beside the typical thrower.
    await open(const ReleaseCalculatorScreen(), height: 7200);
    await tap(const ValueKey('elite-Tom Walsh'));
    await shoot('what_if_vs_walsh_full');

    await open(const ReleaseCalculatorScreen(
      event: ThrowEvent.discus,
      implementKg: 1.6,
      measured: Release(speed: 19.5, angleDeg: 38, height: 1.5, attackDeg: 4),
    ));
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_discus_vs_elite');

    await open(const ReleaseCalculatorScreen(
      event: ThrowEvent.hammer,
      implementKg: 4,
      measured: Release(speed: 23, angleDeg: 38, height: 1.4),
    ));
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_hammer_vs_elite');

    // The whole hammer screen: its best angle is a thrower's now, with the
    // speed it gives up going higher on the card under it.
    await open(
      const ReleaseCalculatorScreen(
        event: ThrowEvent.hammer,
        implementKg: 7.26,
        measured: Release(speed: 26, angleDeg: 41, height: 1.5),
      ),
      height: 7200,
    );
    await shoot('what_if_hammer_full');

    await open(
      const ReleaseCalculatorScreen(
        event: ThrowEvent.javelin,
        implementKg: 0.8,
        measured: Release(speed: 22, angleDeg: 38, height: 1.8, attackDeg: 6),
      ),
      unit: DistanceUnit.feet,
    );
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_javelin_feet');

    // The javelin's own dial: the pitch rate it leaves the hand turning at,
    // under the attack, and nothing like it on any other event.
    await open(
      const ReleaseCalculatorScreen(
        event: ThrowEvent.javelin,
        implementKg: 0.8,
        measured: Release(
            speed: 27, angleDeg: 34, height: 1.8, attackDeg: 4, pitchRate: -8),
      ),
      height: 7200,
    );
    await shoot('what_if_javelin_full');

    // The whole page in feet: mph on the sliders, heights in feet and
    // inches, and the worth tiles priced in a mile an hour and four inches.
    await open(women, height: 7200, unit: DistanceUnit.feet);
    await tap(const ValueKey('elite-typical'));
    await shoot('what_if_feet_full');
    DistanceField.preferred = DistanceUnit.meters;
  });
}
