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

  /// Opens the sheet on the round the athlete is about to throw.
  Future<void> tapMark(WidgetTester tester) async {
    await tester.tap(find.text('Mark'));
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
}
