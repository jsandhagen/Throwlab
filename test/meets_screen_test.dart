import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/screens/home_screen.dart';
import 'package:throwlab/screens/meet_event_screen.dart';
import 'package:throwlab/screens/meet_screen.dart';
import 'package:throwlab/screens/meets_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/notes_library.dart';
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
  // after, or earlier than the 23rd of the month before. Never today,
  // either — a meet on today's date is the live one, and the trophy walks
  // straight past the season to it, which is a different test below.
  final champs = DateTime(now.year, now.month, now.day == 20 ? 21 : 20);
  final open = DateTime(now.year, now.month, now.day == 8 ? 9 : 8);

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

  group('deleting a meet', () {
    testWidgets('a long press asks first, and a cancel keeps it',
        (tester) async {
      await mountMeets(tester);
      await tester.longPress(find.text('County Champs'));
      await tester.pumpAndSettle();

      expect(find.text('Delete County Champs?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(meets.byId('k1'), isNotNull);
      expect(find.text('County Champs'), findsOneWidget);
    });

    testWidgets('confirming takes it off the list and out of storage',
        (tester) async {
      await mountMeets(tester);
      await tester.longPress(find.text('County Champs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(meets.byId('k1'), isNull);
      expect(find.text('County Champs'), findsNothing);
      // The other meet is untouched.
      expect(find.text('Spring Open'), findsOneWidget);
    });

    testWidgets('the calendar deletes the same way', (tester) async {
      await mountMeets(tester);
      await openCalendar(tester);
      await tester.longPress(find.text('County Champs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(meets.byId('k1'), isNull);
      expect(find.text('County Champs'), findsNothing);
    });

    testWidgets('the last meet leaves the empty state behind', (tester) async {
      await meets.remove('k0');
      await mountMeets(tester);
      await tester.longPress(find.text('County Champs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('No meets yet'), findsOneWidget);
      // The bar stays: an empty season is still one to plan.
      expect(find.text('Calendar'), findsOneWidget);
    });
  });

  group('the season', () {
    /// A library of this test's own, so the headings depend on dates this
    /// test chose rather than on the shared fixture's.
    Future<void> seedSeason(List<Meet> season) async {
      SharedPreferences.setMockInitialValues({});
      meets = MeetLibrary();
      await meets.load();
      for (final meet in season) {
        await meets.save(meet);
      }
    }

    final now = DateTime.now();

    testWidgets('splits what is coming from what has been thrown',
        (tester) async {
      await seedSeason([
        Meet(
            id: 'p',
            name: 'Winter Open',
            date: now.subtract(const Duration(days: 21))),
        Meet(
            id: 'u',
            name: 'Spring Open',
            date: now.add(const Duration(days: 5))),
      ]);
      await mountMeets(tester);
      expect(find.text('UPCOMING'), findsOneWidget);
      expect(find.text('PAST'), findsOneWidget);
      // The next fixture reads above the season behind it.
      final upcoming = tester.getTopLeft(find.text('Spring Open')).dy;
      final past = tester.getTopLeft(find.text('Winter Open')).dy;
      expect(upcoming, lessThan(past));
    });

    testWidgets("today's meet gets a heading of its own", (tester) async {
      await seedSeason([
        Meet(id: 'now', name: 'County Champs', date: now),
        Meet(
            id: 'u',
            name: 'Spring Open',
            date: now.add(const Duration(days: 5))),
      ]);
      await mountMeets(tester);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('UPCOMING'), findsOneWidget);
      expect(find.text('PAST'), findsNothing);
    });

    testWidgets('says how far off a fixture is on its card', (tester) async {
      await seedSeason([
        Meet(
            id: 'u',
            name: 'Spring Open',
            date: now.add(const Duration(days: 1)),
            venue: 'Sportcity'),
      ]);
      await mountMeets(tester);
      expect(find.textContaining('tomorrow'), findsOneWidget);
      expect(find.textContaining('Sportcity'), findsOneWidget);
    });
  });

  group('the trophy', () {
    Future<void> mountHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<VideoLibrary>.value(value: library),
          ChangeNotifierProvider<MeetLibrary>.value(value: meets),
          ChangeNotifierProvider<NotesLibrary>(
              create: (_) => NotesLibrary()..load()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Meets'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the season when nothing is on today', (tester) async {
      await mountHome(tester);
      expect(find.byType(MeetsScreen), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
    });

    testWidgets('goes straight to the event when a meet is on today',
        (tester) async {
      // Today's meet, with one event in it.
      await meets.save(Meet(id: 'live', name: 'Open Meet', date: DateTime.now()));
      await meets.addEntry('live',
          entry: MeetEntry(
            id: 'e9',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1,
          ));
      await mountHome(tester);

      expect(find.byType(MeetEventScreen), findsOneWidget);
    });

    testWidgets("the season is still behind today's meet, to walk back to",
        (tester) async {
      await meets.save(Meet(id: 'live', name: 'Open Meet', date: DateTime.now()));
      await meets.addEntry('live',
          entry: MeetEntry(
            id: 'e9',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1,
          ));
      await mountHome(tester);

      // Back out of the event, then out of the meet: the calendar is there
      // rather than the library, which is what a coach came looking for.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MeetScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MeetsScreen), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
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
