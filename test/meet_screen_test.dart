import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/meet_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/gold.dart';

/// Recording a competition from the infield: film the throw, write the mark
/// down, and get both into the athlete's record book without leaving the
/// screen.
void main() {
  late MeetLibrary meets;
  late VideoLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    meets = MeetLibrary();
    await meets.load();
    library = VideoLibrary();
    await library.load();
    await meets.save(Meet(
      id: 'k1',
      name: 'County Champs',
      date: DateTime(2026, 6, 13),
      rounds: 6,
    ));
    await meets.addEntry('k1',
        entry: MeetEntry(
          id: 'e1',
          athlete: 'Ana Diaz',
          event: ThrowEvent.discus,
          implementKg: 1,
        ));
  });

  /// The clip a filmed attempt turns into, without a camera in the way.
  Future<ThrowVideo?> fakeFilm(MeetEntry entry, String meetName) async {
    final video = ThrowVideo(
      id: 'v1',
      path: '/v1.mp4',
      event: entry.event,
      implementKg: entry.implementKg,
      importedAt: DateTime(2026, 6, 13),
      recordedAt: DateTime(2026, 6, 13),
      athlete: entry.athlete,
      note: meetName,
      optimizePending: true,
    );
    await library.add(video);
    return video;
  }

  Future<void> mountMeet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
      ],
      child: MaterialApp(
        home: MeetScreen(meetId: 'k1', filmAttempt: fakeFilm),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Opens the sheet on the round the athlete is about to throw. Ana leads
  /// the flight in these tests, so hers is the first card.
  Future<void> tapMark(WidgetTester tester) async {
    await tester.tap(find.text('Mark').first);
    await tester.pumpAndSettle();
  }

  Future<void> enterDistance(WidgetTester tester, String metres) async {
    await tester.enterText(find.byType(TextField).first, metres);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mark'));
    await tester.pumpAndSettle();
  }

  MeetEntry entry() => meets.byId('k1')!.entries.single;

  group('the card', () {
    testWidgets('shows who is entered, in what, with an empty series',
        (tester) async {
      await mountMeet(tester);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.text('Discus · 1 kg'), findsOneWidget);
      expect(find.text('County Champs'), findsOneWidget);
      // Six rounds, none of them thrown yet.
      expect(find.byKey(const ValueKey('round-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('round-5')), findsOneWidget);
      expect(find.textContaining('Best'), findsNothing);
    });

    testWidgets('an empty meet asks for the throwers first', (tester) async {
      await meets.removeEntry('k1', 'e1');
      await mountMeet(tester);
      expect(find.textContaining('Add the throwers'), findsOneWidget);
    });
  });

  group('writing a mark down', () {
    testWidgets('puts it in the series and in the record book',
        (tester) async {
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');

      expect(find.text('41.20'), findsOneWidget);
      expect(find.textContaining('41.20 m'), findsOneWidget); // the best
      final mark = library.marks.single;
      expect(mark.athlete, 'Ana Diaz');
      expect(mark.event, ThrowEvent.discus);
      expect(mark.implementKg, 1);
      expect(mark.distance, 41.20);
      // Dated and labelled by the meet, so the record book knows where it
      // came from without the coach typing it again.
      expect(mark.achievedOn, DateTime(2026, 6, 13));
      expect(mark.note, 'County Champs');
      expect(entry().attemptAt(0)?.resultId, mark.id);
    });

    testWidgets('the next mark goes in the next round', (tester) async {
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await tapMark(tester);
      await enterDistance(tester, '43.06');

      expect(library.marks.length, 2);
      expect(entry().taken, 2);
      expect(entry().attemptAt(1), isNotNull);
      // The further of the two leads the card.
      expect(find.textContaining('43.06 m'), findsOneWidget);
    });

    testWidgets('a personal best is called one on the spot', (tester) async {
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      expect(find.byType(FirstPlaceMedal), findsOneWidget);
      expect(find.text('PB'), findsOneWidget);
    });

    testWidgets('a mark short of an older one is not a best', (tester) async {
      await library.addMark(ThrowMark(
        id: 'm-old',
        athlete: 'Ana Diaz',
        event: ThrowEvent.discus,
        implementKg: 1,
        distance: 45,
        achievedOn: DateTime(2026, 5, 1),
      ));
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      expect(find.byType(FirstPlaceMedal), findsNothing);
      expect(find.text('Best'), findsOneWidget);
    });
  });

  group('the throws that do not count', () {
    testWidgets('a foul is an X and leaves nothing in the record book',
        (tester) async {
      await mountMeet(tester);
      await tapMark(tester);
      await tester.tap(find.text('Foul'));
      await tester.pumpAndSettle();

      expect(find.text('X'), findsOneWidget);
      expect(library.marks, isEmpty);
      expect(entry().attemptAt(0)?.kind, AttemptKind.foul);
    });

    testWidgets('a mark called back as a foul leaves the record book too',
        (tester) async {
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      expect(library.marks, hasLength(1));

      // Back into the round that was just recorded.
      await tester.tap(find.byKey(const ValueKey('round-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foul'));
      await tester.pumpAndSettle();

      expect(library.marks, isEmpty);
      expect(entry().attemptAt(0)?.kind, AttemptKind.foul);
    });

    testWidgets('clearing a round takes the mark with it', (tester) async {
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');

      await tester.tap(find.byKey(const ValueKey('round-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(library.marks, isEmpty);
      expect(entry().taken, 0);
    });
  });

  group('filming', () {
    testWidgets('hangs the clip on the round and asks for the distance',
        (tester) async {
      await mountMeet(tester);
      await tester.tap(find.text('Film'));
      await tester.pumpAndSettle();

      // The sheet opens on the round just filmed, already knowing it was.
      expect(find.text('Ana Diaz · round 1'), findsOneWidget);
      expect(find.text('Filmed'), findsOneWidget);
      await enterDistance(tester, '44.11');

      // The distance goes on the clip: one attempt, one record of it.
      final clip = library.videos.single;
      expect(clip.distance, 44.11);
      expect(clip.athlete, 'Ana Diaz');
      expect(clip.note, 'County Champs');
      expect(library.marks, isEmpty);
      expect(entry().attemptAt(0)?.resultId, clip.id);
      expect(find.text('44.11'), findsOneWidget);
    });

    testWidgets('a clip stays in the library when the round is cleared',
        (tester) async {
      await mountMeet(tester);
      await tester.tap(find.text('Film'));
      await tester.pumpAndSettle();
      await enterDistance(tester, '44.11');

      await tester.tap(find.byKey(const ValueKey('round-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      // The footage is of a real throw; only the round was taken back.
      expect(library.videos, hasLength(1));
      expect(library.videos.single.distance, isNull);
      expect(entry().taken, 0);
    });

    testWidgets('a filmed throw called a foul keeps the clip, loses the mark',
        (tester) async {
      await mountMeet(tester);
      await tester.tap(find.text('Film'));
      await tester.pumpAndSettle();
      await enterDistance(tester, '44.11');

      await tester.tap(find.byKey(const ValueKey('round-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foul'));
      await tester.pumpAndSettle();

      expect(library.videos.single.distance, isNull);
      expect(entry().attemptAt(0)?.kind, AttemptKind.foul);
      expect(entry().attemptAt(0)?.resultId, 'v1');
      expect(find.text('X'), findsOneWidget);
    });
  });

  group('the rest of the field', () {
    /// Adds a rival to the meet: someone the library must never hear about.
    Future<void> addRival(String name, {double? best}) async {
      final entry = MeetEntry(
        id: 'r-$name',
        athlete: name,
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: 5,
      );
      if (best != null) entry.setAttempt(0, MeetAttempt.untracked(best));
      await meets.addEntry('k1', entry: entry);
    }

    testWidgets('their mark is recorded without touching the library',
        (tester) async {
      await addRival('M. Okoye');
      await mountMeet(tester);

      // Their card is the second one; the Mark button next to their name.
      await tester.tap(find.text('Mark').last);
      await tester.pumpAndSettle();
      await enterDistance(tester, '44.90');

      final rival = meets.byId('k1')!.entries.last;
      expect(rival.attemptAt(0)?.distance, 44.90);
      expect(rival.attemptAt(0)?.resultId, isNull);
      // The record book never hears about it.
      expect(library.marks, isEmpty);
      expect(library.videos, isEmpty);
      expect(library.knownAthletes, isNot(contains('M. Okoye')));
    });

    testWidgets('there is no camera pointed at them', (tester) async {
      await addRival('M. Okoye');
      await mountMeet(tester);
      // One Film button, on the coach's own athlete.
      expect(find.text('Film'), findsOneWidget);
      expect(find.text('Mark'), findsNWidgets(2));
    });
  });

  group('standings', () {
    Future<void> openStandings(WidgetTester tester) async {
      await tester.tap(find.text('Standings'));
      await tester.pumpAndSettle();
    }

    Future<void> addRival(String id, String name, double best,
        {int order = 5}) async {
      await meets.addEntry('k1',
          entry: MeetEntry(
            id: id,
            athlete: name,
            event: ThrowEvent.discus,
            implementKg: 1,
            tracked: false,
            order: order,
          )..setAttempt(0, MeetAttempt.untracked(best)));
    }

    testWidgets('rank the field, mine among them', (tester) async {
      await addRival('r1', 'M. Okoye', 44.90);
      await addRival('r2', 'J. Smith', 38.44, order: 6);
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openStandings(tester);

      final okoye = tester.getRect(find.text('M. Okoye')).top;
      final ana = tester.getRect(find.text('Ana Diaz')).top;
      final smith = tester.getRect(find.text('J. Smith')).top;
      expect(okoye, lessThan(ana));
      expect(ana, lessThan(smith));
      expect(find.text('44.90 m'), findsOneWidget);
    });

    testWidgets('say what my athlete needs to make the final',
        (tester) async {
      // A final of two, and Ana is third.
      final meet = meets.byId('k1')!..advancing = 2;
      await meets.save(meet);
      await addRival('r1', 'M. Okoye', 44.90);
      await addRival('r2', 'J. Smith', 43.00, order: 6);
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openStandings(tester);

      expect(find.text('the cut'), findsOneWidget);
      expect(find.textContaining('needs 43.01 m'), findsOneWidget);
    });

    testWidgets('say nothing about what the rest of the field needs',
        (tester) async {
      final meet = meets.byId('k1')!..advancing = 1;
      await meets.save(meet);
      await addRival('r1', 'M. Okoye', 44.90);
      await addRival('r2', 'J. Smith', 20.00, order: 6);
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openStandings(tester);

      // Ana is out of the final and told so; Smith is out of it and not.
      expect(find.textContaining('needs'), findsOneWidget);
    });

    testWidgets('order the final worst-placed first', (tester) async {
      final meet = meets.byId('k1')!..advancing = 2;
      await meets.save(meet);
      await addRival('r1', 'M. Okoye', 44.90);
      await addRival('r2', 'J. Smith', 20.00, order: 6);
      await mountMeet(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openStandings(tester);
      await tester.tap(find.text('Order the final'));
      await tester.pumpAndSettle();

      // Ana (41.20) throws before Okoye (44.90); Smith missed the cut and
      // is left behind them.
      expect(meets.byId('k1')!.inOrder.map((e) => e.athlete),
          ['Ana Diaz', 'M. Okoye', 'J. Smith']);
    });
  });

  group('the throwing order', () {
    testWidgets('an athlete can be moved down the flight', (tester) async {
      await meets.addEntry('k1',
          entry: MeetEntry(
            id: 'e2',
            athlete: 'Bea Cole',
            event: ThrowEvent.discus,
            implementKg: 1,
            order: 1,
          ));
      await mountMeet(tester);
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Throw later'));
      await tester.pumpAndSettle();

      expect(meets.byId('k1')!.inOrder.map((e) => e.athlete),
          ['Bea Cole', 'Ana Diaz']);
    });
  });

  group('a 3 + 3', () {
    /// Ana plus two rivals in a 3 + 3 where only two go through.
    Future<void> setUpThreeAndThree(
        {List<double> ana = const [], bool complete = true}) async {
      final meet = meets.byId('k1')!
        ..rounds = 6
        ..prelimRounds = 3
        ..advancing = 2;
      final entry = meet.entries.single;
      for (var round = 0; round < ana.length; round++) {
        entry.setAttempt(round, MeetAttempt.untracked(ana[round]));
      }
      // Ana is the coach's, but her marks are stubbed straight onto the
      // series here so the test is about the cut, not about entering them.
      entry.tracked = false;
      for (final rival in [
        ('r1', 'M. Okoye', [44.90, 44.10, 45.00]),
        ('r2', 'L. Fischer', complete ? [43.20, 42.00, 43.50] : [43.20]),
      ]) {
        final other = MeetEntry(
          id: rival.$1,
          athlete: rival.$2,
          event: ThrowEvent.discus,
          implementKg: 1,
          tracked: false,
          order: 5,
        );
        for (var round = 0; round < rival.$3.length; round++) {
          other.setAttempt(round, MeetAttempt.untracked(rival.$3[round]));
        }
        meet.entries.add(other);
      }
      await meets.save(meet);
    }

    testWidgets('closes the last rounds for an athlete who missed the cut',
        (tester) async {
      await setUpThreeAndThree(ana: const [30.0, 31.0, 32.0]);
      await mountMeet(tester);

      // Ana is third of three with everyone's prelims thrown: rounds 4-6
      // are not hers to enter, and are greyed out to say so.
      final closed = tester.widget<Opacity>(find.descendant(
          of: find.byKey(const ValueKey('round-3')).first,
          matching: find.byType(Opacity)));
      expect(closed.opacity, lessThan(1));
      // Round 3 was hers, and still reads at full strength.
      final open = tester.widget<Opacity>(find.descendant(
          of: find.byKey(const ValueKey('round-2')).first,
          matching: find.byType(Opacity)));
      expect(open.opacity, 1);

      // Tapping a closed round does nothing — no sheet opens.
      await tester.tap(find.byKey(const ValueKey('round-3')).first);
      await tester.pumpAndSettle();
      expect(find.text('Save mark'), findsNothing);

      // And the card says so where its buttons were: there is no round
      // left for them to open.
      expect(find.text('out of the final'), findsOneWidget);
    });

    testWidgets('leaves them open while anyone still has a prelim to throw',
        (tester) async {
      await setUpThreeAndThree(
          ana: const [30.0, 31.0, 32.0], complete: false);
      await mountMeet(tester);

      // Fischer has thrown once. Nobody is out yet, so Ana can still be
      // entered for round 4.
      await tester.tap(find.byKey(const ValueKey('round-3')).first);
      await tester.pumpAndSettle();
      expect(find.text('Save mark'), findsOneWidget);
    });

    testWidgets('says the standings are the final once the cut is made',
        (tester) async {
      await setUpThreeAndThree(ana: const [30.0, 31.0, 32.0]);
      await mountMeet(tester);
      await tester.tap(find.text('Standings'));
      await tester.pumpAndSettle();

      expect(find.text('the final'), findsOneWidget);
      expect(find.text('the cut'), findsOneWidget);
      // Nothing left to need: the closed rounds say it.
      expect(find.textContaining('needs'), findsNothing);
    });
  });
}
