import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_conditions.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/models/training_note.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/screens/athlete_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/notes_library.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/gold.dart';
import 'package:throwlab/widgets/throw_card.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

/// An athlete's profile: the marks they hold, and the medal that says which
/// clip each one came out of.
void main() {
  late Directory temp;
  late VideoLibrary library;
  late NotesLibrary notes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VideoPlayerPlatform.instance =
        FakeVideoPlayerPlatform(const Size(1920, 1080));
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    library = VideoLibrary();
    await library.load();
    notes = NotesLibrary();
    await notes.load();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> fill(List<ThrowVideo> videos) async {
    for (final video in videos) {
      await library.add(video);
    }
  }

  Future<void> mountProfile(WidgetTester tester,
      {String name = 'Ana Diaz', MeetLibrary? meets}) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<NotesLibrary>.value(value: notes),
        // A profile paints with no meets in scope at all — that is what
        // every other test here mounts — so they only go in when the meets
        // are the thing under test.
        if (meets != null)
          ChangeNotifierProvider<MeetLibrary>.value(value: meets),
      ],
      child: MaterialApp(
        home: AthleteScreen(name: name, titleFor: (video) => video.event.label),
      ),
    ));
    await pumpFrames(tester, 8);
  }

  testWidgets('leads with a best per event and weight', (tester) async {
    await fill([
      testVideo(temp,
          id: 'shot-far',
          athlete: 'Ana Diaz',
          event: ThrowEvent.shotPut,
          implementKg: 4,
          distance: 15.02),
      testVideo(temp,
          id: 'shot-near',
          athlete: 'Ana Diaz',
          event: ThrowEvent.shotPut,
          implementKg: 4,
          distance: 14.10),
      testVideo(temp,
          id: 'shot-light',
          athlete: 'Ana Diaz',
          event: ThrowEvent.shotPut,
          implementKg: 3,
          distance: 16.44),
    ]);
    await mountProfile(tester);

    expect(find.text('Personal bests'.toUpperCase()), findsOneWidget);
    // A weight holds its own mark, so the 3 kg is listed beside the 4 kg
    // rather than swallowed by the further throw.
    expect(find.text('4 kg Shot Put'), findsOneWidget);
    expect(find.text('3 kg Shot Put'), findsOneWidget);
    expect(find.text('15.02 m'), findsWidgets);
    expect(find.text('16.44 m'), findsWidgets);
    // 14.10 lost the 4 kg mark, so it appears on its card and nowhere else.
    expect(find.textContaining('best of 2'), findsOneWidget);
    expect(find.textContaining('first mark'), findsOneWidget);
  });

  testWidgets('the medal goes on the record holder alone', (tester) async {
    await fill([
      testVideo(temp,
          id: 'far',
          athlete: 'Ana Diaz',
          distance: 61.44,
          importedAt: DateTime(2026, 5, 3)),
      testVideo(temp,
          id: 'near',
          athlete: 'Ana Diaz',
          distance: 58.90,
          importedAt: DateTime(2026, 4, 2)),
      testVideo(temp,
          id: 'unmeasured',
          athlete: 'Ana Diaz',
          importedAt: DateTime(2026, 3, 1)),
    ]);
    await mountProfile(tester);

    final cards = tester.widgetList<ThrowCard>(find.byType(ThrowCard));
    expect(cards.map((card) => card.video.id), ['far', 'near', 'unmeasured']);
    expect(cards.map((card) => card.isPersonalBest), [true, false, false]);
    // The medal is the card's; the bests section is all marks already.
    expect(find.byType(FirstPlaceMedal), findsOneWidget);
  });

  testWidgets('says how to start tracking bests when nothing is measured',
      (tester) async {
    await fill([testVideo(temp, id: 'v1', athlete: 'Ana Diaz')]);
    await mountProfile(tester);

    expect(find.textContaining('No distances yet'), findsOneWidget);
    expect(find.byType(FirstPlaceMedal), findsNothing);
    expect(find.byType(ThrowCard), findsOneWidget);
  });

  testWidgets('sums up the season under the name', (tester) async {
    await fill([
      testVideo(temp,
          id: 'jav', athlete: 'Ana Diaz', importedAt: DateTime(2026, 3, 4)),
      testVideo(temp,
          id: 'shot',
          athlete: 'Ana Diaz',
          event: ThrowEvent.shotPut,
          importedAt: DateTime(2026, 5, 9)),
    ]);
    await mountProfile(tester);

    expect(find.text('Ana Diaz'), findsOneWidget);
    expect(find.text('2 throws · 2 events · since 4 Mar'), findsOneWidget);
  });

  testWidgets('a mark opens the throw it came out of', (tester) async {
    await fill([
      testVideo(temp, id: 'far', athlete: 'Ana Diaz', distance: 61.44),
    ]);
    await mountProfile(tester);

    await tester.tap(find.text('800 g Javelin'));
    await pumpFrames(tester, 25);
    expect(find.byType(AnalysisScreen), findsOneWidget);
  });

  group('marks', () {
    ThrowMark mark({
      String id = 'm1',
      String athlete = 'Ana Diaz',
      double distance = 15.02,
      DateTime? on,
      String note = '',
    }) =>
        ThrowMark(
          id: id,
          athlete: athlete,
          event: ThrowEvent.shotPut,
          implementKg: 4,
          distance: distance,
          achievedOn: on ?? DateTime(2026, 5, 4),
          note: note,
        );

    testWidgets('a throw nobody filmed can hold the best', (tester) async {
      await fill([
        testVideo(temp,
            id: 'filmed',
            athlete: 'Ana Diaz',
            event: ThrowEvent.shotPut,
            implementKg: 4,
            distance: 14.10),
      ]);
      await library.addMark(mark(distance: 15.02, note: 'County Champs'));
      await mountProfile(tester);

      expect(find.text('15.02 m'), findsWidgets);
      expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
      // The clip lost the medal to a throw that actually went further.
      final card = tester.widget<ThrowCard>(find.byType(ThrowCard));
      expect(card.isPersonalBest, isFalse);
      // Its own section lists it, meet and all.
      expect(find.text('Marks'.toUpperCase()), findsOneWidget);
      expect(find.textContaining('County Champs'), findsOneWidget);
    });

    testWidgets('an athlete with no clips still has a profile', (tester) async {
      await library.addMark(mark(distance: 15.02));
      await library.addMark(mark(id: 'm2', distance: 14.10));
      await mountProfile(tester);

      expect(find.text('2 throws · 1 event · since 4 May'), findsOneWidget);
      // Once as the best, once per mark in the list under it.
      expect(find.text('4 kg Shot Put'), findsNWidgets(3));
      expect(find.textContaining('Nothing filmed yet'), findsOneWidget);
      expect(find.byType(ThrowCard), findsNothing);
    });

    testWidgets('records one from the profile', (tester) async {
      await fill([testVideo(temp, id: 'v1', athlete: 'Ana Diaz')]);
      await mountProfile(tester);

      await tester.tap(find.byIcon(Icons.emoji_events_outlined).first);
      await pumpFrames(tester, 20);
      expect(find.widgetWithText(AlertDialog, 'Record a mark'), findsOneWidget);
      // The name is already known, so the sheet doesn't ask for it again.
      expect(find.text('Athlete'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Meters'), '17.55');
      await pumpFrames(tester, 4);
      await tester.tap(find.text('Save'));
      await pumpFrames(tester, 20);

      expect(library.marks.single.distance, 17.55);
      expect(library.marks.single.athlete, 'Ana Diaz');
      expect(find.text('17.55 m'), findsWidgets);
    });

    testWidgets('deleting one asks first', (tester) async {
      await library.addMark(mark(distance: 15.02));
      await mountProfile(tester);

      await tester.longPress(find.text('15.02 m').last);
      await pumpFrames(tester, 20);
      expect(find.text('Delete this mark?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await pumpFrames(tester, 20);
      expect(library.marks, isEmpty);
    });
  });

  testWidgets('a note can be deleted from the profile, after asking',
      (tester) async {
    await fill([
      testVideo(temp,
          id: 'a', athlete: 'Ana Diaz', importedAt: DateTime(2026, 5, 3)),
    ]);
    await notes.save(TrainingNote(
      id: 'n1',
      athlete: 'Ana Diaz',
      title: 'Throws day',
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    ));
    await mountProfile(tester);

    await tester.scrollUntilVisible(find.text('Throws day'), 200,
        scrollable: find.byType(Scrollable).first);
    await pumpFrames(tester, 4);
    await tester.longPress(find.text('Throws day'));
    await pumpFrames(tester, 20);
    expect(find.text('Delete this note?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, 20);

    expect(notes.notes, isEmpty);
  });

  testWidgets('an athlete with nothing left says so', (tester) async {
    await mountProfile(tester, name: 'Nobody');
    expect(find.textContaining('Nothing here any more'), findsOneWidget);
    expect(find.byType(ThrowCard), findsNothing);
  });

  group('their meets', () {
    /// A meet Ana threw a series at, with one rival in the field.
    Future<MeetLibrary> season({
      List<double> series = const [41.20, 43.06],
      double rival = 40.00,
      MeetConditions conditions = const MeetConditions(),
    }) async {
      for (var round = 0; round < series.length; round++) {
        await library.addMark(ThrowMark(
          id: 'm$round',
          athlete: 'Ana Diaz',
          event: ThrowEvent.discus,
          implementKg: 1,
          distance: series[round],
          achievedOn: DateTime(2026, 6, 13),
          note: 'County Champs',
        ));
      }
      final meets = MeetLibrary();
      await meets.load();
      final meet = Meet(
        id: 'k1',
        name: 'County Champs',
        date: DateTime(2026, 6, 13),
        venue: 'Sportcity',
        rounds: 6,
        conditions: conditions,
      );
      final mine = MeetEntry(
          id: 'e1',
          athlete: 'Ana Diaz',
          event: ThrowEvent.discus,
          implementKg: 1);
      for (var round = 0; round < series.length; round++) {
        mine.setAttempt(round, MeetAttempt.mark('m$round'));
      }
      meet.entries.add(mine);
      meet.entries.add(MeetEntry(
        id: 'e2',
        athlete: 'B. Rival',
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: 1,
      )..setAttempt(0, MeetAttempt.untracked(rival)));
      await meets.save(meet);
      return meets;
    }

    testWidgets('show the meet, where it placed, and the series',
        (tester) async {
      await mountProfile(tester, meets: await season());

      expect(find.text('County Champs'), findsOneWidget);
      expect(find.text('1st of 2'), findsOneWidget);
      expect(find.textContaining('13 Jun · Discus · 1 kg · Sportcity'),
          findsOneWidget);
      // The series, round by round, with the one that counted picked out.
      expect(find.text('41.20'), findsOneWidget);
      expect(find.text('43.06'), findsOneWidget);
    });

    testWidgets('count the wins in the heading', (tester) async {
      await mountProfile(tester, meets: await season());
      // One meet, won off a field of two.
      expect(find.text('1 · 1 win'), findsOneWidget);
    });

    testWidgets('carry what the day was like', (tester) async {
      await mountProfile(
        tester,
        meets: await season(
          conditions: const MeetConditions(
              sky: MeetSky.overcast, wind: MeetWind.head, note: 'wet ring'),
        ),
      );
      expect(find.text('Overcast · Headwind · wet ring'), findsOneWidget);
    });

    testWidgets('are nothing at all when there are no meets in scope',
        (tester) async {
      await fill([
        testVideo(temp,
            id: 'v1',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1,
            distance: 41.20),
      ]);
      await mountProfile(tester);
      expect(find.text('MEETS'), findsNothing);
    });

    testWidgets('a season of one throw draws no line', (tester) async {
      await mountProfile(tester, meets: await season(series: [41.20]));
      // One mark is a measurement, not a direction.
      expect(find.textContaining('measured'), findsNothing);
    });

    testWidgets('a season of two says which way it went', (tester) async {
      await mountProfile(tester, meets: await season());
      expect(find.textContaining('+1.86 m since 13 Jun · 2 measured'),
          findsOneWidget);
    });
  });

  group('their averages', () {
    /// One meet, thrown as [series] — a null round is a foul, the way it
    /// is called out. Every legal round goes into the record book, which
    /// is what the meet itself would have done.
    Future<MeetLibrary> competed(
      List<double?> series, {
      String id = 'k1',
      DateTime? on,
    }) async {
      final day = on ?? DateTime(2026, 6, 13);
      final meets = MeetLibrary();
      await meets.load();
      final meet =
          Meet(id: id, name: 'County Champs', date: day, rounds: series.length);
      final mine = MeetEntry(
          id: '$id-e1',
          athlete: 'Ana Diaz',
          event: ThrowEvent.discus,
          implementKg: 1);
      for (var round = 0; round < series.length; round++) {
        final mark = series[round];
        if (mark == null) {
          mine.setAttempt(round, MeetAttempt.foul());
          continue;
        }
        await library.addMark(ThrowMark(
          id: '$id-m$round',
          athlete: 'Ana Diaz',
          event: ThrowEvent.discus,
          implementKg: 1,
          distance: mark,
          achievedOn: day,
        ));
        mine.setAttempt(round, MeetAttempt.mark('$id-m$round'));
      }
      meet.entries.add(mine);
      await meets.save(meet);
      return meets;
    }

    testWidgets('say what the competition averaged and what it fouled away',
        (tester) async {
      // 69, F, 67, 80, F, 66 — an afternoon with a big one in it and two
      // thrown away.
      await mountProfile(tester,
          meets: await competed([69, null, 67, 80, null, 66]));

      expect(find.text('AVERAGES'), findsOneWidget);
      // The level competed at is the best; the middle of the series is
      // what the rest of it came to.
      expect(find.text('80.00 m'), findsWidgets);
      expect(find.text('70.50 m'), findsOneWidget);
      expect(find.text('2 of 6'), findsOneWidget);
      expect(find.text('33% of attempts'), findsOneWidget);
      // And on the meet itself, under the series it came out of.
      expect(find.text('averaged 70.50 m from 4 · 2 fouls'), findsOneWidget);
    });

    testWidgets('widen to the record book when there is training in it',
        (tester) async {
      final meets = await competed([61, 63]);
      await library.addMark(ThrowMark(
        id: 't1',
        athlete: 'Ana Diaz',
        event: ThrowEvent.discus,
        implementKg: 1,
        distance: 56.00,
        achievedOn: DateTime(2026, 5, 2),
      ));
      await mountProfile(tester, meets: meets);

      expect(find.text('IN COMPETITION'), findsOneWidget);
      expect(find.text('62.00 m'), findsOneWidget);
      expect(find.text('WITH TRAINING'), findsOneWidget);
      expect(find.text('60.00 m'), findsOneWidget);
    });

    testWidgets('a meet average on its own is not a second figure',
        (tester) async {
      await mountProfile(tester, meets: await competed([60, 64]));
      // Everything measured was measured at the meet, so widening to the
      // record book would print the same number twice.
      expect(find.text('WITH TRAINING'), findsNothing);
      expect(find.text('EVERY MARK'), findsNothing);
    });

    testWidgets('an athlete who only trains still has an average',
        (tester) async {
      await fill([
        testVideo(temp,
            id: 'v1',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1,
            distance: 41.20),
        testVideo(temp,
            id: 'v2',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1,
            distance: 43.20),
      ]);
      await mountProfile(tester);
      expect(find.text('EVERY MARK'), findsOneWidget);
      expect(find.text('42.20 m'), findsOneWidget);
      expect(find.text('MEET BEST'), findsNothing);
      expect(find.text('FOULS'), findsNothing);
    });

    testWidgets('one mark is not an average of anything', (tester) async {
      await mountProfile(tester, meets: await competed([60, null]));
      // The series above it already says 60.00 and X; saying it again as a
      // mean of one would be the same line twice.
      expect(find.textContaining('averaged'), findsNothing);
      expect(find.text('AVERAGES'), findsNothing);
    });

    testWidgets('the meet average is drawn across the season', (tester) async {
      final meets = await competed([60, 62]);
      final june = await competed([64, 68],
          id: 'k2', on: DateTime(2026, 6, 27));
      for (final meet in june.meets) {
        await meets.save(meet);
      }
      await mountProfile(tester, meets: meets);
      // 61 in June, 66 a fortnight later.
      expect(
          find.textContaining('+5.00 m since 13 Jun · 2 meets averaged'),
          findsOneWidget);
    });
  });
}
