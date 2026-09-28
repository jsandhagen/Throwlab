import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/calculators_screen.dart';
import 'package:throwlab/screens/release_calculator_screen.dart';
import 'package:throwlab/screens/unit_converter_screen.dart';
import 'package:throwlab/widgets/distance_field.dart';

void main() {
  setUp(() => DistanceField.preferred = DistanceUnit.meters);

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('the calculators open both tools', (tester) async {
    await pump(tester, const CalculatorsScreen());
    await tester.tap(find.byKey(const ValueKey('tool-what-if')));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseCalculatorScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool-units')));
    await tester.pumpAndSettle();
    expect(find.byType(UnitConverterScreen), findsOneWidget);
  });

  group('UnitConverterScreen', () {
    testWidgets('a mark reads as a meet writes it in both units',
        (tester) async {
      await pump(tester, const UnitConverterScreen());
      await tester.enterText(find.byKey(const ValueKey('meters')), '21.53');
      await tester.pump();
      // Down to the quarter inch, the way a mark in feet is recorded.
      expect(find.text('70-07.50'), findsWidgets);
      expect(find.text('2153.0 cm'), findsOneWidget);
    });

    testWidgets('its unit switch leaves the app\'s own alone',
        (tester) async {
      await pump(tester, const UnitConverterScreen());
      await tester.tap(find.text('ft'));
      await tester.pump();
      expect(find.byKey(const ValueKey('feet')), findsOneWidget);
      expect(DistanceField.preferred, DistanceUnit.meters);
    });

    testWidgets('a weight in pounds names the implement it is',
        (tester) async {
      await pump(tester, const UnitConverterScreen());
      await tester.tap(find.text('Weight'));
      await tester.pump();
      await tester.tap(find.text('lb'));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('Weight-input')), '16');
      await tester.pump();
      expect(text(tester, 'Weight-kg'), '7.26 kg');
      expect(find.text('Shot Put · 16 lb'), findsOneWidget);
      expect(find.text('Hammer · 16 lb'), findsOneWidget);
    });

    testWidgets('switching unit converts what was typed', (tester) async {
      await pump(tester, const UnitConverterScreen());
      await tester.tap(find.text('Speed'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('Speed-input')), '14');
      await tester.pump();
      expect(text(tester, 'Speed-mph'), '31.3 mph');
      expect(text(tester, 'Speed-km/h'), '50.4 km/h');
      await tester.tap(find.text('mph'));
      await tester.pump();
      expect(find.text('31.3'), findsOneWidget);
      expect(text(tester, 'Speed-m/s'), '13.99 m/s');
    });
  });
}
