import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/screens/analysis_screen.dart';
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

  Future<void> mountHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1000);
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
      await mountHome(tester);
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
      await mountHome(tester);
      await tester.tap(find.text('By event'));
      await pumpFrames(tester, 8);
      expect(find.text('Shot Put'), findsOneWidget);
      expect(find.text('Javelin'), findsOneWidget);
      expect(find.byType(ThrowCard), findsNWidgets(4));
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
      expect(find.text('By athlete'), findsNothing);
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
      await tester.tap(find.byIcon(Icons.close));
      await pumpFrames(tester, 8);
      expect(find.text('Ana Diaz'), findsOneWidget);
      expect(find.byType(ThrowCard), findsNWidgets(4));
    });
  });

  group('drilling in', () {
    testWidgets('the heading opens that group on its own', (tester) async {
      await mountHome(tester);
      await tester.tap(find.text('Ana Diaz'));
      await pumpFrames(tester, 12);
      expect(find.byType(GroupScreen), findsOneWidget);
      expect(find.byType(ThrowCard), findsNWidgets(2));
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
      expect(find.text('Set athlete'), findsOneWidget);
      expect(find.text('Add note'), findsOneWidget);
      expect(find.text('Delete throw'), findsOneWidget);
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
