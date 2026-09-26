// The distance a mark is typed into, in the round-entry sheet: meters and
// feet, empty and filled in. See CLAUDE.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/widgets/attempt_entry.dart';
import 'package:throwlab/widgets/distance_field.dart';
import 'package:throwlab/models/throw_video.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('distance entry', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> open(String unit) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({'throwlab.distanceUnit': unit});
      DistanceField.preferred = DistanceUnit.values.byName(unit);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        theme: ThrowLabApp.theme,
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAttemptSheet(context,
                    athlete: 'Anna Sofia', round: 2, filmed: false),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> shoot(String name) async {
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
    }

    await open('meters');
    await shoot('distance_meters_empty');
    await tester.enterText(find.byKey(const ValueKey('meters')), '43.06');
    await shoot('distance_meters');

    await open('feet');
    await shoot('distance_feet_empty');
    await tester.enterText(find.byKey(const ValueKey('feet')), '141');
    await tester.enterText(find.byKey(const ValueKey('inches')), '3.25');
    await shoot('distance_feet');
  });
}
