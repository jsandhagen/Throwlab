import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/widgets/athlete_picker.dart';
import 'package:throwlab/widgets/distance_field.dart';
import 'package:throwlab/widgets/throw_card.dart';

/// The two things a throw is tagged with by hand: how far it went, and who
/// threw it.
void main() {
  group('distance', () {
    test('keeps centimetres, including trailing zeros', () {
      expect(formatDistance(58.42), '58.42 m');
      expect(formatDistance(58.4), '58.40 m');
      expect(formatDistance(9), '9.00 m');
    });

    test('parses what a phone keyboard hands over', () {
      expect(parseDistance('58.42'), 58.42);
      // A comma decimal mark, as most of Europe types it.
      expect(parseDistance('58,42'), 58.42);
      expect(parseDistance(' 58.42 '), 58.42);
      expect(parseDistance('0'), 0);
    });

    test('rejects what is not a distance', () {
      expect(parseDistance(''), isNull);
      expect(parseDistance('sixty'), isNull);
      // A throw can be zero-length, never less.
      expect(parseDistance('-1'), isNull);
    });

    test('reads back in the unit it was measured in', () {
      expect(formatDistance(58.42, DistanceUnit.metres), '58.42 m');
      // 58.42 m is 191 feet 8 inches, which is 191.67 ft.
      expect(formatDistance(58.42, DistanceUnit.feet), '191.67 ft');
      expect(formatDistance(12.19, DistanceUnit.feet), '39.99 ft');
    });

    test('takes feet as a meet writes them', () {
      expect(parseFeet('191.67'), closeTo(191.67, 1e-9));
      // Feet and inches: 191-08, 191' 8", 191 8.
      expect(parseFeet('191-08'), closeTo(191 + 8 / 12, 1e-9));
      expect(parseFeet("191' 8\""), closeTo(191 + 8 / 12, 1e-9));
      expect(parseFeet('191 8'), closeTo(191 + 8 / 12, 1e-9));
      // Twelve inches is another foot, not a reading.
      expect(parseFeet('191-12'), isNull);
      expect(parseFeet('feet'), isNull);
    });
  });

  group('DistanceField', () {
    testWidgets('fills in the conversion as you type, either way',
        (tester) async {
      double? metres;
      DistanceUnit? unit;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DistanceField(
            metres: null,
            unit: DistanceUnit.metres,
            onChanged: (value, entered) {
              metres = value;
              unit = entered;
            },
          ),
        ),
      ));

      final metresBox = find.byType(TextField).first;
      final feetBox = find.byType(TextField).last;

      await tester.enterText(metresBox, '58.42');
      await tester.pump();
      expect(metres, closeTo(58.42, 1e-9));
      expect(unit, DistanceUnit.metres);
      expect(tester.widget<TextField>(feetBox).controller!.text, '191.67');

      await tester.enterText(feetBox, '150-06');
      await tester.pump();
      expect(unit, DistanceUnit.feet);
      expect(metres, closeTo(150.5 * 0.3048, 1e-9));
      expect(tester.widget<TextField>(metresBox).controller!.text, '45.87');

      // Clearing a box clears the throw's distance, and the other box.
      await tester.enterText(feetBox, '');
      await tester.pump();
      expect(metres, isNull);
      expect(tester.widget<TextField>(metresBox).controller!.text, '');
    });

    testWidgets('opens on the distance a throw already has', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DistanceField(
            metres: 58.42,
            unit: DistanceUnit.feet,
            onChanged: (_, __) {},
          ),
        ),
      ));
      // By the controllers, not by find.text: the metres box hints with
      // an example distance, which is a "58.42" of its own.
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.first.controller!.text, '58.42');
      expect(fields.last.controller!.text, '191.67');
    });
  });

  group('AthletePicker', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<String> known,
      String value = '',
      required ValueChanged<String> onChanged,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AthletePicker(
            known: known,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ));
    }

    testWidgets('offers the library\'s athletes as a dropdown',
        (tester) async {
      var picked = '';
      await pump(tester,
          known: ['Riley', 'Sam'], onChanged: (name) => picked = name);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Unassigned'), findsWidgets);
      expect(find.text('Sam'), findsWidgets);

      await tester.tap(find.text('Riley').last);
      await tester.pumpAndSettle();
      expect(picked, 'Riley');
    });

    testWidgets('"Someone new" swaps the list for a field', (tester) async {
      var picked = 'Riley';
      await pump(tester,
          known: ['Riley'],
          value: 'Riley',
          onChanged: (name) => picked = name);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Someone new…').last);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ana');
      expect(picked, 'Ana');
    });

    testWidgets('is a plain field while the library has no athletes',
        (tester) async {
      var picked = '';
      await pump(tester, known: const [], onChanged: (name) => picked = name);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(find.byType(TextField), 'Ana');
      expect(picked, 'Ana');
    });

    testWidgets('starts on the field for a name not in the library',
        (tester) async {
      await pump(tester,
          known: ['Riley'], value: 'Ana', onChanged: (_) {});
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });
  });
}
