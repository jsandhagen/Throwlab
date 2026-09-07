import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/screens/meet_screen.dart';
import 'package:throwlab/screens/meets_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/throw_card.dart';

/// The season, read both ways: the meets one after another, and the months
/// they fall in.
void main() {
  late MeetLibrary meets;
  late VideoLibrary library;

  final now = DateTime.now();
  // Two days this month that no neighbouring month's days can be confused
  // with in the grid: it never runs further than the 14th of the month
  // after, or earlier than the 23rd of the month before.
  final champs = DateTime(now.year, now.month, 20);
  final open = DateTime(now.year, now.month, 8);

  Future<void> seed({bool calendar = false}) async {
    SharedPreferences.setMockInitialValues(
        calendar ? {'flutter.throwlab.meetsCalendar': true} : {});
    meets = MeetLibrary();
    await meets.load();
    library = VideoLibrary();
    await library.load();
    await meets.save(Meet(id: 'k1', name: 'County Champs', date: champs));
    await meets.save(Meet(id: 'k0', name: 'Spring Open', date: open));
    await meets.addEntry('k1',
        entry: MeetEntry(
          id: 'e1',
          athlete: 'Ana Diaz',
          event: ThrowEvent.discus,
          implementKg: 1,
        ));
  }

  setUp(() => seed());

  Future<void> mountMeets(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
      ],
      child: const MaterialApp(home: MeetsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openCalendar(WidgetTester tester) async {
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('holds every meet, newest first', (tester) async {
      await mountMeets(tester);
      expect(find.text('County Champs'), findsOneWidget);
      expect(find.text('Spring Open'), findsOneWidget);
    });

    testWidgets('a meet opens the events being contested at it',
        (tester) async {
      await mountMeets(tester);
      await tester.tap(find.text('County Champs'));
      await tester.pumpAndSettle();

      expect(find.byType(MeetScreen), findsOneWidget);
      expect(find.text('Discus · 1 kg'), findsOneWidget);
    });
  });

  group('the calendar', () {
    testWidgets('opens on the month the meets are in', (tester) async {
      await mountMeets(tester);
      await openCalendar(tester);

      // The month's days, and everything on in it.
      expect(find.text('20'), findsOneWidget);
      expect(find.text('County Champs'), findsOneWidget);
      expect(find.text('Spring Open'), findsOneWidget);
    });

    testWidgets('a day narrows it to what was on that day', (tester) async {
      await mountMeets(tester);
      await openCalendar(tester);
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();

      expect(find.text('County Champs'), findsOneWidget);
      expect(find.text('Spring Open'), findsNothing);
    });

    testWidgets('a day with nothing on offers to start one', (tester) async {
      await mountMeets(tester);
      await openCalendar(tester);
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing on this day.'), findsOneWidget);
      await tester.tap(find.text('Meet here'));
      await tester.pumpAndSettle();

      // The dialog opens already dated to the day that was tapped — which
      // is the whole point of starting one from a calendar.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching:
                  find.text(shortThrowDate(DateTime(now.year, now.month, 15)))),
          findsOneWidget);
    });

    testWidgets('the month can be stepped through', (tester) async {
      await mountMeets(tester);
      await openCalendar(tester);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();

      // Nothing is on next month, and the meets go with the month.
      expect(find.textContaining('Nothing on in'), findsOneWidget);
      expect(find.text('County Champs'), findsNothing);
    });

    testWidgets('is where the screen opens when it was left there',
        (tester) async {
      await seed(calendar: true);
      await mountMeets(tester);

      expect(find.text('20'), findsOneWidget);
    });
  });
}
