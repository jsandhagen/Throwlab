// The what-if calculator: a shot put opened on its own, the same screen
// opened off a measured throw with an elite release tried, and the discus
// with its attack and wind dials. Each is shot at a phone's height and
// again at the full length of the page. See CLAUDE.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/screens/release_calculator_screen.dart';
import 'package:throwlab/utils/flight_model.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('what if', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> open(Widget screen, {double height = 2532}) async {
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

    await open(const ReleaseCalculatorScreen());
    await shoot('what_if_shot');
    await open(const ReleaseCalculatorScreen(), height: 5200);
    await shoot('what_if_shot_full');

    const measured = ReleaseCalculatorScreen(
      event: ThrowEvent.shotPut,
      implementKg: 5.44,
      measured: Release(speed: 11.4, angleDeg: 33.5, height: 1.95),
    );
    await open(measured);
    await shoot('what_if_measured');
    await open(measured, height: 5200);
    await tester.tap(find.byType(DropdownButton<ImplementSpec>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16 lb').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try'));
    await tester.pumpAndSettle();
    await shoot('what_if_elite_full');

    await open(const ReleaseCalculatorScreen(event: ThrowEvent.discus),
        height: 5600);
    await shoot('what_if_discus_full');
    await open(const ReleaseCalculatorScreen(event: ThrowEvent.javelin),
        height: 5600);
    await shoot('what_if_javelin_full');
  });
}
