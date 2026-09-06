import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/widgets/athlete_picker.dart';
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
