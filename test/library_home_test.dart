import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/screens/athlete_screen.dart';
import 'package:throwlab/screens/group_screen.dart';
import 'package:throwlab/screens/home_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/throw_card.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

/// Getting around the library: shelves per heading, search across the lot,
/// and a drill-down into one heading.
void main() {
  late Directory temp;
  late VideoLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VideoPlayerPlatform.instance =
        FakeVideoPlayerPlatform(const Size(1920, 1080));
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    library = VideoLibrary();
    // add() alone leaves the library "not loaded", which renders as the
    // startup spinner rather than the shelves.
    await library.load();
    // Bea threw most recently; Ana is alphabetically first. One clip is
    // left untagged.
    for (final video in [
      testVideo(temp,
          id: 'ana-1', athlete: 'Ana Diaz', importedAt: DateTime(2026, 1, 4)),
      testVideo(temp,
          id: 'ana-2', athlete: 'Ana Diaz', importedAt: DateTime(2026, 1, 5)),
      testVideo(temp,
          id: 'bea-1',
          athlete: 'Bea Cole',
          event: ThrowEvent.shotPut,
          importedAt: DateTime(2026, 2, 1)),
      testVideo(temp, id: 'loose', importedAt: DateTime(2026, 1, 1)),
    ]) {
      await library.add(video);
    }
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// [width] widens the phone-sized default for the tests that count every
  /// card: a shelf only builds the cards it can show, and one card is now
  /// 264 wide, so three of them don't exist at 400.
  Future<void> mountHome(WidgetTester tester, {double width = 400}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>.value(
      value: library,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await pumpFrames(tester, 8);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await pumpFrames(tester, 8);
  }

  group('shelves', () {
    testWidgets('one heading per athlete, with a card per throw',
        (tester) async {
      await mountHome(tester, width: 1000);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.text('Bea Cole'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.byType(ThrowCard), findsNWidgets(4));
    });

    testWidgets('the heading says how many throws and how recent',
        (tester) async {
      await mountHome(tester);
      expect(find.textContaining('2 throws'), findsOneWidget); // Ana
      expect(find.textContaining('1 throw ·'), findsNWidgets(2));
    });

    testWidgets('the most recent athlete leads and Unassigned waits at the end',
        (tester) async {
      await mountHome(tester);
      final bea = tester.getRect(find.text('Bea Cole')).top;
      final ana = tester.getRect(find.text('Ana Diaz')).top;
      final loose = tester.getRect(find.text('Unassigned')).top;
      // Bea threw in February, Ana in January — alphabetical order would
      // have put Ana on top and buried the newest session.
      expect(bea, lessThan(ana));
      expect(ana, lessThan(loose));
    });

    testWidgets('grouping by event re-headings the same throws',
        (tester) async {
      await mountHome(tester, width: 1000);
      await tester.tap(find.text('Event'));
      await pumpFrames(tester, 8);
      expect(find.text('Shot Put'), findsOneWidget);
      expect(find.text('Javelin'), findsOneWidget);
      expect(find.byType(ThrowCard), findsNWidgets(4));
    });

    testWidgets('grouping by date heads each day the library was filmed',
        (tester) async {
      await mountHome(tester, width: 1000);
      await tester.tap(find.text('Date'));
      await pumpFrames(tester, 8);
      // Four throws on four days: 1, 4 and 5 January, and 1 February. Each
      // date reads twice — once as the heading, once on the card under it.
      for (final day in ['1 Feb', '5 Jan', '4 Jan', '1 Jan']) {
        expect(find.text(day), findsNWidgets(2));
      }
      expect(find.byType(ThrowCard), findsNWidgets(4));
      // Newest day leads, and a card names who threw rather than repeating
      // the event grouping's wording.
      expect(tester.getRect(find.text('1 Feb').first).top,
          lessThan(tester.getRect(find.text('1 Jan').first).top));
      expect(find.textContaining('Bea Cole ·'), findsOneWidget);
    });
  });

  group('personal bests', () {
    /// Ana's two throws, oldest first.
    List<ThrowVideo> anas() => library.videos.reversed
        .where((video) => video.athlete == 'Ana Diaz')
        .toList();

    testWidgets('the furthest throw wears the medal on the shelf',
        (tester) async {
      final ana = anas();
      ana[0].distance = 58.90;
      await library.update(ana[0]);
      ana[1].distance = 61.44;
      await library.update(ana[1]);
      await mountHome(tester, width: 1000);

      expect(find.byIcon(Icons.military_tech), findsOneWidget);
      final gold = tester
          .widgetList<ThrowCard>(find.byType(ThrowCard))
          .where((card) => card.isPersonalBest);
      expect(gold.single.video.id, ana[1].id);
    });

    testWidgets('an untagged throw is never a best, however far it went',
        (tester) async {
      final loose = library.videos.firstWhere((video) => video.id == 'loose');
      loose.distance = 99.99;
      await library.update(loose);
      await mountHome(tester, width: 1000);

      expect(find.byIcon(Icons.military_tech), findsNothing);
      expect(find.text('99.99 m'), findsOneWidget);
    });

    testWidgets('a search result carries the medal too', (tester) async {
      final ana = anas();
      ana[1].distance = 61.44;
      await library.update(ana[1]);
      await mountHome(tester);
      await search(tester, 'Ana');

      expect(find.byIcon(Icons.military_tech), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('narrows to matching throws and drops the headings',
        (tester) async {
      await mountHome(tester);
      await search(tester, 'Bea');
      expect(find.byType(ThrowCard), findsOneWidget);
      // Headings and the grouping switch are gone: a search crosses them.
      expect(find.text('Ana Diaz'), findsNothing);
      expect(find.text('Athlete'), findsNothing);
    });

    testWidgets('matches on the event as well as the name', (tester) async {
      await mountHome(tester);
      await search(tester, 'shot');
      expect(find.byType(ThrowCard), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await mountHome(tester);
      await search(tester, 'nobody');
      expect(find.byType(ThrowCard), findsNothing);
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('clearing brings the shelves back', (tester) async {
      await mountHome(tester);
      await search(tester, 'Bea');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await pumpFrames(tester, 8);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.byType(ThrowCard), findsNWidgets(4));
    });
  });

  group('drilling in', () {
    testWidgets('an athlete heading opens their profile', (tester) async {
      await mountHome(tester);
      await tester.tap(find.text('Ana Diaz'));
      await pumpFrames(tester, 25);
      expect(find.byType(AthleteScreen), findsOneWidget);
      // Scoped to the new screen: the library underneath is still mounted
      // while the push transition runs, and its cards would count too.
      expect(
        find.descendant(
            of: find.byType(AthleteScreen), matching: find.byType(ThrowCard)),
        findsNWidgets(2),
      );
    });

    testWidgets('a heading nobody is behind opens the plain grid',
        (tester) async {
      await mountHome(tester);
      // Unassigned is not a person, so there is no profile to open.
      await tester.tap(find.text('Unassigned'));
      await pumpFrames(tester, 25);
      expect(find.byType(GroupScreen), findsOneWidget);
      expect(find.byType(AthleteScreen), findsNothing);
    });

    testWidgets('an event heading opens the plain grid', (tester) async {
      await mountHome(tester);
      await tester.tap(find.text('Event'));
      await pumpFrames(tester, 8);
      await tester.tap(find.text('Shot Put'));
      await pumpFrames(tester, 25);
      expect(find.byType(GroupScreen), findsOneWidget);
      expect(find.byType(AthleteScreen), findsNothing);
    });

    testWidgets('a card opens the throw itself', (tester) async {
      await mountHome(tester);
      await tester.tap(find.byType(ThrowCard).first);
      await pumpFrames(tester, 12);
      expect(find.byType(AnalysisScreen), findsOneWidget);
    });

    testWidgets('a long press offers the per-throw edits', (tester) async {
      await mountHome(tester);
      await tester.longPress(find.byType(ThrowCard).first);
      await pumpFrames(tester, 30);
      // Bea is already tagged, so the sheet offers to change her, not to
      // name someone.
      expect(find.text('Change athlete'), findsOneWidget);
      expect(find.text('Add note'), findsOneWidget);
      expect(find.text('Delete throw'), findsOneWidget);
    });

    testWidgets('an untagged throw is offered a name, not a change',
        (tester) async {
      await mountHome(tester);
      // Unassigned is pinned last, so its throw is the last card.
      await tester.longPress(find.byType(ThrowCard).last);
      await pumpFrames(tester, 30);
      expect(find.text('Set athlete'), findsOneWidget);
      expect(find.text('Change athlete'), findsNothing);
    });

    testWidgets('deleting from the sheet takes the throw out of the library',
        (tester) async {
      await mountHome(tester);
      await tester.longPress(find.byType(ThrowCard).first);
      await pumpFrames(tester, 30);
      await tester.tap(find.text('Delete throw'));
      await pumpFrames(tester, 30);
      expect(library.videos, hasLength(3));
      expect(find.byType(ThrowCard), findsNWidgets(3));
    });
  });
}
