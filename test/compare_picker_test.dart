import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/comparison_screen.dart';
import 'package:throwlab/screens/home_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/throw_picker.dart';

import 'analysis_harness.dart';

void main() {
  late Directory temp;
  late ThrowVideo javelinA;
  late ThrowVideo javelinB;
  late ThrowVideo shot;
  late VideoLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    javelinA = testVideo(temp, id: 'jav-a', athlete: 'Ana');
    javelinB = testVideo(temp, id: 'jav-b', athlete: 'Bea');
    shot =
        testVideo(temp, id: 'shot', event: ThrowEvent.shotPut, athlete: 'Cy');
    library = VideoLibrary();
    for (final video in [javelinA, javelinB, shot]) {
      await library.add(video);
    }
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// The sheet's own widgets, so the screen behind it — which has a search
  /// box and stills of its own — can't answer a finder meant for the picker.
  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(BottomSheet), matching: matching);

  /// The candidate list, which is the half of the sheet that gets tapped.
  Finder inList(Finder matching) =>
      find.descendant(of: inSheet(find.byType(ListView)), matching: matching);

  Future<void> openPicker(WidgetTester tester) async {
    await mountAnalysisScreen(tester,
        video: javelinA,
        screen: const Size(800, 600),
        videoSize: const Size(1920, 1080),
        library: library);
    await tester.tap(find.byIcon(Icons.compare));
    // Long enough for the sheet to finish sliding up: a tap that lands
    // while it is still animating hits the barrier under it.
    await pumpFrames(tester, 30);
  }

  testWidgets('the video offers a comparison without going back to the library',
      (tester) async {
    await openPicker(tester);
    expect(find.text('Compare with'), findsOneWidget);
  });

  testWidgets('says which throw is being compared, as slot A', (tester) async {
    await openPicker(tester);

    // The throw the sheet was opened from is on it: a picker that only
    // showed the candidates left "compare with what?" unanswered.
    expect(inSheet(find.text('A')), findsOneWidget);
    expect(inSheet(find.text('Ana · Javelin · 800 g')), findsOneWidget);
    expect(inList(find.textContaining('Ana')), findsNothing);
  });

  testWidgets('opens on throws of the same event', (tester) async {
    await openPicker(tester);

    expect(inList(find.textContaining('Bea')), findsOneWidget);
    expect(inList(find.textContaining('Cy')), findsNothing); // shot put
  });

  testWidgets('dropping the event chip widens the list', (tester) async {
    await openPicker(tester);
    await tester.tap(inSheet(find.text('Javelin')));
    await pumpFrames(tester);

    expect(inList(find.textContaining('Bea')), findsOneWidget);
    expect(inList(find.textContaining('Cy')), findsOneWidget);
  });

  testWidgets('the athlete chip narrows to whoever threw it', (tester) async {
    await openPicker(tester);
    await tester.tap(inSheet(find.text('Javelin'))); // all events
    await pumpFrames(tester);
    await tester.tap(inSheet(find.text('Ana')));
    await pumpFrames(tester);

    // Nobody else's throw is Ana's, so the list empties and says which
    // filter emptied it.
    expect(inList(find.textContaining('Bea')), findsNothing);
    expect(find.text('No other throws by Ana.'), findsOneWidget);

    await tester.tap(find.text('Show everyone'));
    await pumpFrames(tester);
    expect(inList(find.textContaining('Bea')), findsOneWidget);
  });

  testWidgets('search finds a throw by who threw it', (tester) async {
    await openPicker(tester);
    await tester.tap(inSheet(find.text('Javelin'))); // all events
    await pumpFrames(tester);

    await tester.enterText(inSheet(find.byType(TextField)), 'cy');
    await pumpFrames(tester);
    expect(inList(find.textContaining('Cy')), findsOneWidget);
    expect(inList(find.textContaining('Bea')), findsNothing);

    await tester.enterText(inSheet(find.byType(TextField)), 'nobody');
    await pumpFrames(tester);
    expect(find.text('Nothing matches "nobody".'), findsOneWidget);
  });

  testWidgets('every candidate carries its still frame', (tester) async {
    await openPicker(tester);
    expect(inList(find.byType(ThrowThumbnail)), findsOneWidget);

    await tester.tap(inSheet(find.text('Javelin')));
    await pumpFrames(tester);
    expect(inList(find.byType(ThrowThumbnail)), findsNWidgets(2));
  });

  testWidgets('picking one opens the two throws side by side', (tester) async {
    await openPicker(tester);
    await tester.tap(inList(find.textContaining('Bea')));
    await pumpFrames(tester, 8);

    final comparison =
        tester.widget<ComparisonScreen>(find.byType(ComparisonScreen));
    expect(comparison.videoA.id, javelinA.id);
    expect(comparison.videoB.id, javelinB.id);
  });

  testWidgets('a lone event opens on the whole library instead of nothing',
      (tester) async {
    final soleLibrary = VideoLibrary();
    await soleLibrary.add(javelinA);
    await soleLibrary.add(shot);
    await mountAnalysisScreen(tester,
        video: javelinA,
        screen: const Size(800, 600),
        videoSize: const Size(1920, 1080),
        library: soleLibrary);
    await tester.tap(find.byIcon(Icons.compare));
    await pumpFrames(tester, 30);

    // No other javelin exists, so the sheet shows what there is rather than
    // an empty list behind a filter chip.
    expect(inList(find.textContaining('Cy')), findsOneWidget);
  });

  group('from the library', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>.value(
        value: library,
        child: const MaterialApp(home: HomeScreen()),
      ));
      await pumpFrames(tester, 8);
      await tester.tap(find.byIcon(Icons.compare));
      await pumpFrames(tester, 30);
    }

    testWidgets('lists every throw with its still frame', (tester) async {
      await openSheet(tester);
      expect(find.text('Pick two throws'), findsOneWidget);
      expect(inList(find.byType(ThrowThumbnail)), findsNWidgets(3));
    });

    testWidgets('both slots stand empty until they are filled',
        (tester) async {
      await openSheet(tester);
      expect(inSheet(find.text('Tap a throw below')), findsOneWidget);
      expect(inSheet(find.text('Then a second one')), findsOneWidget);
      // Nothing to open yet, and the button says what is missing rather
      // than sitting there greyed and mute.
      expect(find.text('Pick two throws to compare'), findsOneWidget);
      // Every row offers A, since A is the side the first tap fills.
      expect(inList(find.text('A')), findsNWidgets(3));
    });

    testWidgets('the first pick fills A and narrows to its event',
        (tester) async {
      await openSheet(tester);
      await tester.tap(inList(find.textContaining('Ana')));
      await pumpFrames(tester);

      expect(find.text('Pick one more throw'), findsOneWidget);
      expect(inList(find.textContaining('Bea')), findsOneWidget);
      // The shot put is behind the event chip now, which is on and says so.
      expect(inList(find.textContaining('Cy')), findsNothing);
      final chip = tester.widget<FilterChip>(
          find.ancestor(of: find.text('Javelin'), matching: find.byType(FilterChip)));
      expect(chip.selected, isTrue);
    });

    testWidgets('picking two and comparing opens them in slot order',
        (tester) async {
      await openSheet(tester);
      await tester.tap(inList(find.textContaining('Ana')));
      await pumpFrames(tester);
      await tester.tap(inList(find.textContaining('Bea')));
      await pumpFrames(tester);
      await tester.tap(find.text('Compare'));
      await pumpFrames(tester, 8);

      final comparison =
          tester.widget<ComparisonScreen>(find.byType(ComparisonScreen));
      expect(comparison.videoA.id, javelinA.id);
      expect(comparison.videoB.id, javelinB.id);
    });

    testWidgets('swapping trades the two sides over', (tester) async {
      await openSheet(tester);
      await tester.tap(inList(find.textContaining('Ana')));
      await pumpFrames(tester);
      await tester.tap(inList(find.textContaining('Bea')));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Swap A and B'));
      await pumpFrames(tester);
      await tester.tap(find.text('Compare'));
      await pumpFrames(tester, 8);

      final comparison =
          tester.widget<ComparisonScreen>(find.byType(ComparisonScreen));
      expect(comparison.videoA.id, javelinB.id);
      expect(comparison.videoB.id, javelinA.id);
    });

    testWidgets('a third pick takes B rather than being swallowed',
        (tester) async {
      await openSheet(tester);
      await tester.tap(inList(find.textContaining('Ana')));
      await pumpFrames(tester);
      await tester.tap(inList(find.textContaining('Bea')));
      await pumpFrames(tester);
      // Off the event filter, so there is a third row to tap.
      await tester.tap(inSheet(find.text('Javelin')));
      await pumpFrames(tester);
      await tester.tap(inList(find.textContaining('Cy')));
      await pumpFrames(tester);
      await tester.tap(find.text('Compare'));
      await pumpFrames(tester, 8);

      final comparison =
          tester.widget<ComparisonScreen>(find.byType(ComparisonScreen));
      expect(comparison.videoA.id, javelinA.id);
      expect(comparison.videoB.id, shot.id);
    });

    testWidgets('clearing a slot puts it back to a question', (tester) async {
      await openSheet(tester);
      await tester.tap(inList(find.textContaining('Ana')));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip('Clear A'));
      await pumpFrames(tester);

      expect(inSheet(find.text('Tap a throw below')), findsOneWidget);
      expect(inSheet(find.text('Then a second one')), findsOneWidget);
      // With no throw to narrow against, the whole library is back.
      expect(inList(find.textContaining('Cy')), findsOneWidget);
    });
  });
}
