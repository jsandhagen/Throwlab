// The calculators: the screen the library's calculator opens, and the unit
// converter on each of its tabs with something typed in — a mark, a weight
// in pounds that names its implement, and a release speed. See CLAUDE.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/calculators_screen.dart';
import 'package:throwlab/screens/unit_converter_screen.dart';
import 'package:throwlab/widgets/distance_field.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('calculators', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    DistanceField.preferred = DistanceUnit.meters;
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

    await open(const CalculatorsScreen());
    await shoot('calculators');

    await open(const UnitConverterScreen());
    await tester.enterText(find.byKey(const ValueKey('meters')), '21.53');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shoot('convert_distance');

    await open(const UnitConverterScreen(), height: 6400);
    await tester.tap(find.text('Weight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('Weight-input')), '12');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shoot('convert_weight_full');

    await open(const UnitConverterScreen());
    await tester.tap(find.text('Speed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('Speed-input')), '14');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shoot('convert_speed');
  });
}
