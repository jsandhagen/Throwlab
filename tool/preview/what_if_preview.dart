// The what-if calculator: a shot put opened on its own; a measured high
// school put with each elite final laid over it; the discus and the hammer
// compared the same way; and the javelin read in feet, which is what the
// field's markers switch to. Each is shot at a phone's height, and the
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
    await tap(const ValueKey('elite-men'));
    await shoot('what_if_vs_men');
    await open(measured, height: 5600);
    await tap(const ValueKey('elite-women'));
    await shoot('what_if_vs_women_full');

    await open(const ReleaseCalculatorScreen(
      event: ThrowEvent.discus,
      implementKg: 1.6,
      measured: Release(speed: 19.5, angleDeg: 38, height: 1.5, attackDeg: 4),
    ));
    await tap(const ValueKey('elite-men'));
    await shoot('what_if_discus_vs_men');

    await open(const ReleaseCalculatorScreen(event: ThrowEvent.hammer));
    await tap(const ValueKey('elite-women'));
    await shoot('what_if_hammer_men_vs_women');

    await open(
      const ReleaseCalculatorScreen(
        event: ThrowEvent.javelin,
        implementKg: 0.8,
        measured: Release(speed: 22, angleDeg: 38, height: 1.8, attackDeg: 6),
      ),
      unit: DistanceUnit.feet,
    );
    await tap(const ValueKey('elite-men'));
    await shoot('what_if_javelin_feet');

    // The whole page in feet: mph on the sliders, heights in feet and
    // inches, and the worth tiles priced in a mile an hour and four inches.
    await open(measured, height: 7200, unit: DistanceUnit.feet);
    await tap(const ValueKey('elite-men'));
    await shoot('what_if_feet_full');
    DistanceField.preferred = DistanceUnit.meters;
  });
}
