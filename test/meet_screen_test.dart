import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_conditions.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/utils/meet_report.dart';
import 'package:throwlab/utils/pdf_text.dart';
import 'package:throwlab/screens/meet_event_screen.dart';
import 'package:throwlab/screens/meet_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/gold.dart';
import 'package:throwlab/widgets/sector_board.dart';

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

  Future<void> mount(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
      ],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
  }

  /// The discus, which is where the throwing happens: a meet is a day, and
  /// its events are what a coach actually stands at.
  ///
  /// The screen opens on the live card; most of what is tested here is the
  /// series behind it, so this lands there unless asked otherwise.
  Future<void> mountEvent(WidgetTester tester, {bool live = false}) async {
    await mount(
      tester,
      MeetEventScreen(
        meetId: 'k1',
        event: ThrowEvent.discus,
        implementKg: 1,
        filmAttempt: fakeFilm,
      ),
    );
    // An event nobody is in has no views to switch between.
    if (!live && find.text('Series').evaluate().isNotEmpty) {
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
    }
  }

  /// The meet itself: the events in it, and the settings.
  Future<void> mountMeet(WidgetTester tester) =>
      mount(tester, const MeetScreen(meetId: 'k1'));

  /// Opens the sheet on the round the athlete is about to throw. Ana leads
  /// the flight in these tests, so hers is the first card.
  Future<void> tapMark(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Write the next mark down').first);
    await tester.pumpAndSettle();
  }

  Future<void> tapFilm(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Film the next').first);
    await tester.pumpAndSettle();
  }

  Future<void> enterDistance(WidgetTester tester, String meters) async {
    await tester.enterText(find.byType(TextField).first, meters);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mark'));
    await tester.pumpAndSettle();
  }

  MeetEntry entry() => meets.byId('k1')!.entries.single;

  group('the card', () {
    testWidgets('shows who is entered, in what, with an empty series',
        (tester) async {
      await mountEvent(tester);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.text('Discus · 1 kg'), findsOneWidget);
      expect(find.text('County Champs'), findsOneWidget);
      // Six rounds, none of them thrown yet.
      expect(find.byKey(const ValueKey('round-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('round-5')), findsOneWidget);
      expect(find.textContaining('Best'), findsNothing);
    });

    testWidgets('an event nobody is in asks for the throwers first',
        (tester) async {
      await meets.removeEntry('k1', 'e1');
      await mountEvent(tester);
      expect(find.textContaining('Nobody in this event'), findsOneWidget);
    });
  });

  group('the meet', () {
    testWidgets('lists the events being contested at it', (tester) async {
      await meets.addEntry('k1',
          entry: MeetEntry(
            id: 'e2',
            athlete: 'Bea Cole',
            event: ThrowEvent.javelin,
            implementKg: 0.6,
            order: 1,
          ));
      await mountMeet(tester);

      expect(find.text('Discus · 1 kg'), findsOneWidget);
      expect(find.text('Javelin · 600 g'), findsOneWidget);
      expect(find.textContaining('2 events'), findsOneWidget);
      // The throwing is a screen down, not on the meet itself.
      expect(find.byTooltip('Write the next mark down'), findsNothing);
    });

    testWidgets('an event opens the competition it stands for', (tester) async {
      await mountMeet(tester);
      await tester.tap(find.text('Discus · 1 kg'));
      await tester.pumpAndSettle();

      expect(find.byType(MeetEventScreen), findsOneWidget);
      // On the live card, with the athlete in the circle under the board.
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.byTooltip('Write the next mark down'), findsOneWidget);
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.byTooltip('Write the next mark down'), findsOneWidget);
    });

    testWidgets('says how far through each event is', (tester) async {
      final meet = meets.byId('k1')!;
      meet.entries.single
        ..setAttempt(0, MeetAttempt.untracked(30))
        ..setAttempt(1, MeetAttempt.foul());
      await meets.save(meet);
      await mountMeet(tester);

      expect(find.textContaining('round 3 of 6'), findsOneWidget);
    });

    testWidgets('a meet nobody is entered in asks for the throwers first',
        (tester) async {
      await meets.removeEntry('k1', 'e1');
      await mountMeet(tester);
      expect(find.textContaining('Add the throwers'), findsOneWidget);
    });
  });

  group('writing a mark down', () {
    testWidgets('puts it in the series and in the record book', (tester) async {
      await mountEvent(tester);
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
      await mountEvent(tester);
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
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      // The medal says it; the row has no room for the word.
      expect(find.byType(FirstPlaceMedal), findsOneWidget);
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
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      expect(find.byType(FirstPlaceMedal), findsNothing);
      expect(find.textContaining('41.20 m'), findsOneWidget);
    });
  });

  group('the throws that do not count', () {
    testWidgets('a foul is an X and leaves nothing in the record book',
        (tester) async {
      await mountEvent(tester);
      await tapMark(tester);
      await tester.tap(find.text('Foul'));
      await tester.pumpAndSettle();

      expect(find.text('X'), findsOneWidget);
      expect(library.marks, isEmpty);
      expect(entry().attemptAt(0)?.kind, AttemptKind.foul);
    });

    testWidgets('a mark called back as a foul leaves the record book too',
        (tester) async {
      await mountEvent(tester);
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
      await mountEvent(tester);
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
      await mountEvent(tester);
      await tapFilm(tester);

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
      await mountEvent(tester);
      await tapFilm(tester);
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
      await mountEvent(tester);
      await tapFilm(tester);
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
      await mountEvent(tester);

      // Their card is the second one; the ruler next to their name.
      await tester.tap(find.byTooltip('Write the next mark down').last);
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
      await mountEvent(tester);
      // One camera, on the coach's own athlete; a ruler on both.
      expect(find.byTooltip('Film the next'), findsOneWidget);
      expect(find.byTooltip('Write the next mark down'), findsNWidgets(2));
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
      await mountEvent(tester);
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

    testWidgets('say what my athlete needs to make the final', (tester) async {
      // A final of two, and Ana is third.
      final meet = meets.byId('k1')!..advancing = 2;
      await meets.save(meet);
      await addRival('r1', 'M. Okoye', 44.90);
      await addRival('r2', 'J. Smith', 43.00, order: 6);
      await mountEvent(tester);
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
      await mountEvent(tester);
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
      await mountEvent(tester);
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
      await mountEvent(tester);
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
      await mountEvent(tester);

      // Ana is third of three with everyone's prelims thrown: rounds 4-6
      // are not hers to enter, and are grayed out to say so.
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
      expect(find.text('out'), findsOneWidget);
    });

    testWidgets('leaves them open while anyone still has a prelim to throw',
        (tester) async {
      await setUpThreeAndThree(ana: const [30.0, 31.0, 32.0], complete: false);
      await mountEvent(tester);

      // Fischer has thrown once. Nobody is out yet, so Ana can still be
      // entered for round 4.
      await tester.tap(find.byKey(const ValueKey('round-3')).first);
      await tester.pumpAndSettle();
      expect(find.text('Save mark'), findsOneWidget);
    });

    testWidgets('says the standings are the final once the cut is made',
        (tester) async {
      await setUpThreeAndThree(ana: const [30.0, 31.0, 32.0]);
      await mountEvent(tester);
      await tester.tap(find.text('Standings'));
      await tester.pumpAndSettle();

      expect(find.text('the final'), findsOneWidget);
      expect(find.text('the cut'), findsOneWidget);
      // Nothing left to need: the closed rounds say it.
      expect(find.textContaining('needs'), findsNothing);
    });
  });

  group('the meet format', () {
    /// Opens the meet's own settings, off the app bar.
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Meet settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers both a 3 + 3 and a straight six', (tester) async {
      await mountMeet(tester);
      await openSettings(tester);
      await tester.tap(find.byType(DropdownButtonFormField<(int, int)>));
      await tester.pumpAndSettle();

      // Two formats a coach reads off a program, each named in full.
      expect(find.text('3 + 3 · cut after 3'), findsWidgets);
      expect(find.text('6 throws · everyone'), findsWidgets);
      expect(find.text('4 throws · everyone'), findsWidgets);
    });

    testWidgets('a straight six has no cut and no final to ask about',
        (tester) async {
      await mountMeet(tester);
      await openSettings(tester);
      await tester.tap(find.byType(DropdownButtonFormField<(int, int)>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 throws · everyone').last);
      await tester.pumpAndSettle();

      // Nobody is cut, so there is nothing to advance to.
      expect(find.text('Final'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final meet = meets.byId('k1')!;
      expect(meet.rounds, 6);
      expect(meet.prelimRounds, 6);
      expect(meet.hasFinal, isFalse);
    });

    testWidgets('a 3 + 3 keeps the cut it was given', (tester) async {
      // Start from a meet with no cut, the way the straight six saves it.
      final meet = meets.byId('k1')!
        ..prelimRounds = 6
        ..advancing = 99;
      await meets.save(meet);
      await mountMeet(tester);
      await openSettings(tester);
      await tester.tap(find.byType(DropdownButtonFormField<(int, int)>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 + 3 · cut after 3').last);
      await tester.pumpAndSettle();

      // The final's own dropdown appears, defaulted rather than left on the
      // no-cut count it was stored with.
      expect(find.text('Top 8 advance'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = meets.byId('k1')!;
      expect(saved.prelimRounds, 3);
      expect(saved.rounds, 6);
      expect(saved.advancing, 8);
    });
  });

  group('the round in progress', () {
    Future<void> addRival(String id, String name, int order,
        {double? best}) async {
      final entry = MeetEntry(
        id: id,
        athlete: name,
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: order,
      );
      if (best != null) entry.setAttempt(0, MeetAttempt.untracked(best));
      await meets.addEntry('k1', entry: entry);
    }

    testWidgets('says which round it is and who is in the circle',
        (tester) async {
      await addRival('r1', 'M. Okoye', 1);
      await addRival('r2', 'J. Smith', 2);
      await mountEvent(tester);

      expect(find.text('ROUND 1 OF 6'), findsOneWidget);
      expect(find.text('0 of 3 thrown'), findsOneWidget);
      // Ana throws first, Okoye follows her. The three calls are said on
      // the bar; the cards mark only the athlete in the circle, and they
      // mark them by color rather than by taking a name's worth of width.
      expect(find.text('up'), findsOneWidget);
      expect(find.text('on deck'), findsOneWidget);
      expect(find.text('in the hole'), findsOneWidget);
      expect(find.text('Ana Diaz'), findsNWidgets(2));
      expect(find.text('M. Okoye'), findsNWidgets(2));
    });

    testWidgets('moves on as the round is written down', (tester) async {
      await addRival('r1', 'M. Okoye', 1);
      await addRival('r2', 'J. Smith', 2);
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');

      expect(find.text('1 of 3 thrown'), findsOneWidget);
      // Okoye is in the circle now. Ana is off the flight for this round —
      // she is only on the bar at all because her 41.20 leads it.
      expect(find.text('up'), findsOneWidget);
      expect(find.text('leading'), findsOneWidget);
      expect(find.text('M. Okoye'), findsNWidgets(2));
    });

    testWidgets('says nothing about a flight of one', (tester) async {
      await mountEvent(tester);
      // The whole flight is the one card underneath; naming the athlete
      // over it would be telling the coach what they are looking at.
      expect(find.text('ROUND 1 OF 6'), findsOneWidget);
      expect(find.text('up'), findsNothing);
      expect(find.text('Ana Diaz'), findsOneWidget);
    });

    testWidgets('names the leader once somebody is not already on the bar',
        (tester) async {
      await addRival('r1', 'M. Okoye', 1, best: 44.90);
      await addRival('r2', 'J. Smith', 2);
      await addRival('r3', 'K. Fox', 3);
      await mountEvent(tester);

      // Okoye has thrown and leads; Ana and Smith are the two on deck.
      expect(find.text('leading'), findsOneWidget);
      expect(find.text('44.90 m'), findsNWidgets(2));
    });

    testWidgets('says the competition is done when it is', (tester) async {
      final meet = meets.byId('k1')!..rounds = 2;
      meet.entries.single
        ..setAttempt(0, MeetAttempt.foul())
        ..setAttempt(1, MeetAttempt.foul());
      await meets.save(meet);
      await mountEvent(tester);

      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('all in'), findsOneWidget);
    });
  });

  group('a field thrown in flights', () {
    /// Somebody in the discus, in [flight], with whatever they have thrown.
    Future<void> add(String id, String name, int flight, int order,
        {bool tracked = false, List<double?> marks = const []}) async {
      final entry = MeetEntry(
        id: id,
        athlete: name,
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: tracked,
        order: order,
        flight: flight,
      );
      for (var round = 0; round < marks.length; round++) {
        entry.setAttempt(
            round,
            marks[round] == null
                ? MeetAttempt.foul()
                : MeetAttempt.untracked(marks[round]!));
      }
      await meets.addEntry('k1', entry: entry);
    }

    /// Ana in flight 1, two rivals behind her in flight 2.
    Future<void> twoFlights() async {
      await add('r1', 'M. Okoye', 1, 1);
      await add('r2', 'J. Smith', 2, 2);
      await add('r3', 'K. Fox', 2, 3);
    }

    testWidgets('calls nobody out of the flight that is throwing',
        (tester) async {
      await twoFlights();
      await mountEvent(tester, live: true);

      // Flight 2 is standing on the grass. Reading the round off the whole
      // field would put Smith in the circle behind Ana, an hour early.
      expect(find.text('FLIGHT 1 · ROUND 1'), findsOneWidget);
      expect(find.text('0 of 2 thrown'), findsOneWidget);
      expect(find.text('up'), findsOneWidget);
      expect(find.text('on deck'), findsOneWidget);
      expect(find.text('in the hole'), findsNothing);
    });

    testWidgets('hands the ring to the next flight when the first is through',
        (tester) async {
      final meet = meets.byId('k1')!..rounds = 1;
      await meets.save(meet);
      await twoFlights();
      // Ana and Okoye have had the only round their flight gets.
      final ana = meets.byId('k1')!.entries.first;
      ana.setAttempt(0, MeetAttempt.mark('nothing'));
      await meets.save(meets.byId('k1')!);
      await meets.setAttempt('k1', 'r1', 0, MeetAttempt.untracked(38.10));
      await mountEvent(tester, live: true);

      expect(find.text('FLIGHT 2 · ROUND 1'), findsOneWidget);
      expect(find.text('0 of 2 thrown'), findsOneWidget);
      expect(find.text('J. Smith'), findsNWidgets(2));
    });

    testWidgets('says when the coach\'s own athlete is up, in a flight that '
        'is not theirs', (tester) async {
      // Ana out of flight 1 and into the last one, so the ring in front of
      // the coach is somebody else's competition.
      final meet = meets.byId('k1')!;
      meet.entries.single.flight = 3;
      meet.entries.single.order = 9;
      await meets.save(meet);
      await twoFlights();
      await mountEvent(tester, live: true);

      expect(find.text('FLIGHT 1 · ROUND 1'), findsOneWidget);
      expect(find.text('Ana Diaz throws in flight 3'), findsOneWidget);
    });

    testWidgets('rules the field off where the flights are', (tester) async {
      await twoFlights();
      await mountEvent(tester);

      expect(find.text('FLIGHT 1 OF 2'), findsOneWidget);
      expect(find.text('FLIGHT 2 OF 2'), findsOneWidget);
      expect(find.text('to come'), findsOneWidget);
      expect(find.text('round 1 · 0 of 2 thrown'), findsOneWidget);
    });

    testWidgets('will not shuffle an athlete out of their own flight',
        (tester) async {
      await twoFlights();
      await mountEvent(tester);
      // Okoye throws last in flight 1. 'Throw later' would put him in
      // flight 2, which threw after him — so it does nothing.
      await tester.tap(find.byTooltip('Order and entry').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Throw later'));
      await tester.pumpAndSettle();

      final field = meets.byId('k1')!.entries;
      expect(field.firstWhere((e) => e.id == 'r1').flight, 1);
      expect(field.map((e) => e.athlete).toList(),
          ['Ana Diaz', 'M. Okoye', 'J. Smith', 'K. Fox']);
    });

    testWidgets('puts a late entry at the end of its own flight',
        (tester) async {
      await twoFlights();
      await mountEvent(tester);
      await tester.tap(find.text('Add athlete'));
      await tester.pumpAndSettle();

      // Asked for, and started on the flight in the ring — a late entry is
      // somebody the coach has just spotted, usually in the one being
      // called.
      expect(find.text('Flight 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'L. Fischer');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Behind Okoye and in front of flight 2, so the flights stay runs of
      // the order rather than names scattered through one.
      final field = meets.byId('k1')!.inOrder;
      expect(field.map((e) => e.athlete).toList(),
          ['Ana Diaz', 'M. Okoye', 'L. Fischer', 'J. Smith', 'K. Fox']);
      expect(field.map((e) => e.flight).toList(), [1, 1, 1, 2, 2]);
    });

    testWidgets('asks nothing about flights in a field thrown in one order',
        (tester) async {
      await add('r1', 'M. Okoye', 1, 1);
      await mountEvent(tester);
      await tester.tap(find.text('Add athlete'));
      await tester.pumpAndSettle();
      expect(find.text('Flight 1'), findsNothing);
    });

    testWidgets('reads them off the meet card as well', (tester) async {
      await twoFlights();
      await mountMeet(tester);
      expect(find.textContaining('4 in 2 flights'), findsOneWidget);
      expect(find.textContaining('flight 1 · round 1'), findsOneWidget);
    });

    testWidgets('drops the flights once the cut is made', (tester) async {
      final meet = meets.byId('k1')!
        ..rounds = 6
        ..prelimRounds = 1
        ..advancing = 2;
      meet.entries.single.setAttempt(0, MeetAttempt.foul());
      await meets.save(meet);
      await add('r1', 'M. Okoye', 1, 1, marks: [44.90]);
      await add('r2', 'J. Smith', 2, 2, marks: [38.10]);
      await add('r3', 'K. Fox', 2, 3, marks: [30.00]);
      await mountEvent(tester);

      // Everyone has had their prelim, so the qualifiers come back as one
      // group in one order — there is no flight left to rule off.
      expect(find.textContaining('FLIGHT'), findsNothing);
      expect(find.text('FINAL · ROUND 2'), findsOneWidget);
    });
  });

  group('the card', () {
    testWidgets('carries the camera, the ruler and the place', (tester) async {
      await meets.addEntry('k1',
          entry: MeetEntry(
            id: 'r1',
            athlete: 'M. Okoye',
            event: ThrowEvent.discus,
            implementKg: 1,
            tracked: false,
            order: 1,
          )..setAttempt(0, MeetAttempt.untracked(44.90)));
      await mountEvent(tester);

      // Filming is the half of this screen that can't wait: a mark can be
      // written down after the throw, and a throw nobody filmed is gone.
      expect(find.byTooltip('Film the next'), findsOneWidget);
      expect(find.byTooltip('Write the next mark down'), findsNWidgets(2));
      expect(find.text('1st'), findsOneWidget);
      // Ana has not thrown, so she has no place to be in yet.
      expect(find.text('2nd'), findsNothing);
    });

    testWidgets('keeps the order and entry menu', (tester) async {
      await mountEvent(tester);
      await tester.tap(find.byTooltip('Order and entry'));
      await tester.pumpAndSettle();
      expect(find.text('Throw later'), findsOneWidget);
    });

    testWidgets('has no buttons for an athlete the cut left behind',
        (tester) async {
      final meet = meets.byId('k1')!
        ..rounds = 6
        ..prelimRounds = 3
        ..advancing = 1;
      meet.entries.single
        ..setAttempt(0, MeetAttempt.untracked(30))
        ..setAttempt(1, MeetAttempt.foul())
        ..setAttempt(2, MeetAttempt.foul());
      await meets.save(meet);
      await meets.addEntry('k1',
          entry: MeetEntry(
            id: 'r1',
            athlete: 'M. Okoye',
            event: ThrowEvent.discus,
            implementKg: 1,
            tracked: false,
            order: 1,
          )
            ..setAttempt(0, MeetAttempt.untracked(44.90))
            ..setAttempt(1, MeetAttempt.untracked(44.00))
            ..setAttempt(2, MeetAttempt.untracked(43.00)));
      await mountEvent(tester);

      // There is no round left for a button to open, and the card says so
      // where the buttons were.
      expect(find.text('out'), findsOneWidget);
    });
  });

  group('the conditions', () {
    testWidgets('are asked for on a meet that has been thrown', (tester) async {
      await mountMeet(tester);
      expect(find.text('What was it like out there?'), findsOneWidget);
    });

    testWidgets('are not asked for about a day that has not happened',
        (tester) async {
      final meet = meets.byId('k1')!
        ..date = DateTime.now().add(const Duration(days: 20));
      await meets.save(meet);
      await mountMeet(tester);
      expect(find.text('What was it like out there?'), findsNothing);
    });

    testWidgets('go on the meet, and read back on it', (tester) async {
      await mountMeet(tester);
      await tester.tap(find.text('What was it like out there?'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Overcast'));
      await tester.tap(find.text('Headwind'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '54');
      await tester.tap(find.text('Save conditions'));
      await tester.pumpAndSettle();

      final conditions = meets.byId('k1')!.conditions;
      expect(conditions.sky, MeetSky.overcast);
      expect(conditions.wind, MeetWind.head);
      expect(conditions.temperature, 54);
      expect(find.text('Overcast · 54°F · Headwind'), findsOneWidget);
    });
  });

  group('the results sheet', () {
    /// Stands in for the file system: keeps what the button asked for.
    late List<(Meet, MeetCompetition?)> asked;
    late bool wrote;

    setUp(() {
      asked = [];
      wrote = true;
    });

    Future<String?> sharer(
        Meet meet, MeetCompetition? only, Iterable<ThrowResult> results) async {
      asked.add((meet, only));
      return wrote ? '/results/sheet.pdf' : null;
    }

    testWidgets('is offered for the whole day from the meet', (tester) async {
      await mount(tester, MeetScreen(meetId: 'k1', shareResults: sharer));
      await tester.tap(find.byTooltip('Results sheet'));
      await tester.pumpAndSettle();

      expect(asked, hasLength(1));
      // The whole meet: no one competition singled out.
      expect(asked.single.$2, isNull);
      expect(find.text('Results sheet saved.'), findsOneWidget);
    });

    testWidgets('is one event from inside one', (tester) async {
      await mount(
          tester,
          MeetEventScreen(
            meetId: 'k1',
            event: ThrowEvent.discus,
            implementKg: 1,
            shareResults: sharer,
          ));
      await tester.tap(find.byTooltip('Results sheet'));
      await tester.pumpAndSettle();

      expect(asked.single.$2?.event, ThrowEvent.discus);
      expect(asked.single.$2?.implementKg, 1);
    });

    testWidgets('says so when it could not be written', (tester) async {
      wrote = false;
      await mount(tester, MeetScreen(meetId: 'k1', shareResults: sharer));
      await tester.tap(find.byTooltip('Results sheet'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't write the results sheet."), findsOneWidget);
    });

    testWidgets('holds the series that were recorded on the screen',
        (tester) async {
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');

      final meet = meets.byId('k1')!;
      final text = pdfText(meetResultsPdf(meet, library.results))!;
      expect(text, contains('COUNTY CHAMPS'));
      expect(text, contains('Ana Diaz'));
      expect(text, contains('41.20'));
    });
  });

  group('the live card', () {
    Future<void> addRival(String id, String name, int order,
        {double? best}) async {
      final entry = MeetEntry(
        id: id,
        athlete: name,
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: order,
      );
      if (best != null) entry.setAttempt(0, MeetAttempt.untracked(best));
      await meets.addEntry('k1', entry: entry);
    }

    testWidgets('is what an event opens on', (tester) async {
      await mountEvent(tester, live: true);
      // The athlete in the circle, on the same card the series uses.
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.byTooltip('Write the next mark down'), findsOneWidget);
      expect(find.byKey(const ValueKey('round-0')), findsOneWidget);
    });

    testWidgets('calls the flight three deep', (tester) async {
      await addRival('r1', 'M. Okoye', 1);
      await addRival('r2', 'J. Smith', 2);
      await addRival('r3', 'K. Fox', 3);
      await mountEvent(tester, live: true);

      expect(find.text('up'), findsOneWidget);
      expect(find.text('on deck'), findsOneWidget);
      expect(find.text('in the hole'), findsOneWidget);
      // The fourth is a number in the order, not a call.
      expect(find.text('K. Fox'), findsNothing);
      // Ana is named once on the bar and once on the card under the board.
      expect(find.text('Ana Diaz'), findsNWidgets(2));
    });

    testWidgets('writes the mark for whoever is up', (tester) async {
      await mountEvent(tester, live: true);
      await tapMark(tester);

      expect(find.text('Ana Diaz · round 1'), findsOneWidget);
      await enterDistance(tester, '41.20');
      expect(entry().attemptAt(0)?.resultId, library.marks.single.id);
      // The mark is on the board and in the series under it.
      expect(find.text('41.20'), findsOneWidget);
      expect(find.textContaining('41.20 m'), findsWidgets);

      // And the next tap is the round after it.
      await tapMark(tester);
      expect(find.text('Ana Diaz · round 2'), findsOneWidget);
    });

    testWidgets('films from here too, for an athlete the coach keeps',
        (tester) async {
      await mountEvent(tester, live: true);
      await tapFilm(tester);
      expect(find.text('Ana Diaz · round 1'), findsOneWidget);
      expect(find.text('Filmed'), findsOneWidget);
    });

    testWidgets('points no camera at the rest of the field', (tester) async {
      await meets.removeEntry('k1', 'e1');
      await addRival('r1', 'M. Okoye', 0);
      await mountEvent(tester, live: true);
      expect(find.text('M. Okoye'), findsOneWidget);
      expect(find.byTooltip('Write the next mark down'), findsOneWidget);
      expect(find.byTooltip('Film the next'), findsNothing);
    });

    testWidgets('has no button for adding to the field on it', (tester) async {
      await mountEvent(tester, live: true);
      // The card ends in the mark about to be called out; a field is not
      // what a coach is adding to between attempts.
      expect(find.text('Add athlete'), findsNothing);

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.text('Add athlete'), findsOneWidget);
    });

    testWidgets('is where the event opens next time', (tester) async {
      await mountEvent(tester, live: true);
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('throwlab.meetView'), 'series');
    });
  });

  group('the sector board', () {
    Future<void> addRival(String id, String name, int order,
        {double? best}) async {
      final entry = MeetEntry(
        id: id,
        athlete: name,
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: order,
      );
      if (best != null) entry.setAttempt(0, MeetAttempt.untracked(best));
      await meets.addEntry('k1', entry: entry);
    }

    Future<void> openBoard(WidgetTester tester) async {
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
    }

    testWidgets('has nothing to draw until the first mark', (tester) async {
      await mountEvent(tester);
      await openBoard(tester);
      expect(find.byType(SectorBoard), findsNothing);
      expect(find.textContaining('Nothing on the board yet'), findsOneWidget);
    });

    testWidgets('draws the competition once somebody has thrown',
        (tester) async {
      await addRival('r1', 'M. Okoye', 1, best: 44.90);
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openBoard(tester);

      expect(find.byType(SectorBoard), findsOneWidget);
    });

    testWidgets('says what the next throw has to do', (tester) async {
      await addRival('r1', 'M. Okoye', 1, best: 44.90);
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openBoard(tester);

      // Ana is up again, a centimeter past the leader takes it.
      expect(find.text('44.91 m takes the lead'), findsOneWidget);
    });

    testWidgets('says what my athlete needs to make the final', (tester) async {
      final meet = meets.byId('k1')!..advancing = 1;
      await meets.save(meet);
      await addRival('r1', 'M. Okoye', 1, best: 44.90);
      await addRival('r2', 'J. Smith', 2, best: 30.00);
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openBoard(tester);

      expect(find.text('Ana Diaz needs 44.91 m to make the final'),
          findsOneWidget);
    });

    testWidgets('says who won once the competition is over', (tester) async {
      final meet = meets.byId('k1')!..rounds = 1;
      await meets.save(meet);
      await addRival('r1', 'M. Okoye', 1, best: 44.90);
      await mountEvent(tester);
      await tapMark(tester);
      await enterDistance(tester, '41.20');
      await openBoard(tester);

      expect(find.text('M. Okoye won it on 44.90 m'), findsOneWidget);
    });
  });
}
