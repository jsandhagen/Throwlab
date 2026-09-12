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
    test('keeps centimeters, including trailing zeros', () {
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
      expect(formatDistance(58.42, DistanceUnit.meters), '58.42 m');
      // 58.42 m is 191 feet 8 inches, and that is how a meet writes it —
      // not as 191.67, which is a number no throws sheet has ever printed.
      expect(formatDistance(58.42, DistanceUnit.feet), '191-08');
      // To the lesser quarter inch, which is the rule a mark is recorded
      // under: 12.19 m is a hair under forty feet, so it is 39-11.75 and
      // not a 40 flat.
      expect(formatDistance(12.19, DistanceUnit.feet), '39-11.75');
      // The quarter is written where there is one, and left off where
      // there isn't.
      expect(formatDistance((44 + 6 / 12) * 0.3048, DistanceUnit.feet),
          '44-06');
      expect(formatDistance((44 + 6.25 / 12) * 0.3048, DistanceUnit.feet),
          '44-06.25');
      // And a tape between two quarters is written as the lesser one, not
      // rounded to the nearer.
      expect(formatDistance((44 + 6.4 / 12) * 0.3048, DistanceUnit.feet),
          '44-06.25');
    });

    test('writes a mark a meet could read back off the page', () {
      // The round trip the app is actually asked for: a mark typed off a
      // sheet comes back spelled the way the sheet spelled it.
      for (final written in ['191-08', '44-06.25', '200-02', '58-11.75']) {
        final meters = parseFeet(written)! * 0.3048;
        expect(formatDistance(meters, DistanceUnit.feet), written);
      }
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
      double? meters;
      DistanceUnit? unit;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DistanceField(
            meters: null,
            unit: DistanceUnit.meters,
            onChanged: (value, entered) {
              meters = value;
              unit = entered;
            },
          ),
        ),
      ));

      final metersBox = find.byType(TextField).first;
      final feetBox = find.byType(TextField).last;

      await tester.enterText(metersBox, '58.42');
      await tester.pump();
      expect(meters, closeTo(58.42, 1e-9));
      expect(unit, DistanceUnit.meters);
      expect(tester.widget<TextField>(feetBox).controller!.text, '191-08');

      await tester.enterText(feetBox, '150-06');
      await tester.pump();
      expect(unit, DistanceUnit.feet);
      expect(meters, closeTo(150.5 * 0.3048, 1e-9));
      expect(tester.widget<TextField>(metersBox).controller!.text, '45.87');

      // Clearing a box clears the throw's distance, and the other box.
      await tester.enterText(feetBox, '');
      await tester.pump();
      expect(meters, isNull);
      expect(tester.widget<TextField>(metersBox).controller!.text, '');
    });

    testWidgets('opens on the distance a throw already has', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DistanceField(
            meters: 58.42,
            unit: DistanceUnit.feet,
            onChanged: (_, __) {},
          ),
        ),
      ));
      // By the controllers, not by find.text: the meters box hints with
      // an example distance, which is a "58.42" of its own.
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.first.controller!.text, '58.42');
      expect(fields.last.controller!.text, '191-08');
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

    testWidgets('offers the library\'s athletes as a dropdown', (tester) async {
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
          known: ['Riley'], value: 'Riley', onChanged: (name) => picked = name);
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
      await pump(tester, known: ['Riley'], value: 'Ana', onChanged: (_) {});
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
    });
  });
}
