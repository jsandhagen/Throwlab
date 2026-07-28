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
    shot = testVideo(temp, id: 'shot', event: ThrowEvent.shotPut, athlete: 'Cy');
    library = VideoLibrary();
    for (final video in [javelinA, javelinB, shot]) {
      await library.add(video);
    }
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> openPicker(WidgetTester tester) async {
    await mountAnalysisScreen(tester,
        video: javelinA,
        screen: const Size(800, 600),
        videoSize: const Size(1920, 1080),
        library: library);
    await tester.tap(find.byIcon(Icons.compare));
    await pumpFrames(tester, 8);
  }

  testWidgets('the video offers a comparison without going back to the library',
      (tester) async {
    await openPicker(tester);
    expect(find.text('Compare with'), findsOneWidget);
  });

  testWidgets('opens on throws of the same event', (tester) async {
    await openPicker(tester);

    expect(find.textContaining('Bea'), findsOneWidget); // other javelin
    expect(find.textContaining('Cy'), findsNothing); // shot put, filtered out
    expect(find.textContaining('Ana'), findsNothing); // this throw itself
  });

  testWidgets('All events widens the list', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('All events'));
    await pumpFrames(tester);

    expect(find.textContaining('Bea'), findsOneWidget);
    expect(find.textContaining('Cy'), findsOneWidget);
  });

  testWidgets('every candidate carries its still frame', (tester) async {
    await openPicker(tester);
    expect(find.byType(ThrowThumbnail), findsOneWidget);

    await tester.tap(find.text('All events'));
    await pumpFrames(tester);
    expect(find.byType(ThrowThumbnail), findsNWidgets(2));
  });

  testWidgets('picking one opens the two throws side by side', (tester) async {
    await openPicker(tester);
    await tester.tap(find.textContaining('Bea'));
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
    await pumpFrames(tester, 8);

    // No other javelin exists, so the sheet shows what there is rather than
    // an empty list behind a filter chip.
    expect(find.textContaining('Cy'), findsOneWidget);
  });

  group('library picker', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>.value(
        value: library,
        child: const MaterialApp(home: HomeScreen()),
      ));
      await pumpFrames(tester, 8);
      await tester.tap(find.byIcon(Icons.compare));
      await pumpFrames(tester, 8);
    }

    testWidgets('lists every throw with its still frame', (tester) async {
      await openDialog(tester);
      expect(find.text('Pick two throws'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ThrowThumbnail)),
          findsNWidgets(3));
    });

    testWidgets('narrows to the first pick\'s event', (tester) async {
      await openDialog(tester);
      await tester.tap(find.descendant(
          of: find.byType(CheckboxListTile),
          matching: find.textContaining('Ana')));
      await pumpFrames(tester);

      expect(find.text('Pick another javelin throw'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(CheckboxListTile),
              matching: find.textContaining('Bea')),
          findsOneWidget);
      // The shot put is gone: it can't be compared with a javelin.
      expect(
          find.descendant(
              of: find.byType(CheckboxListTile),
              matching: find.textContaining('Cy')),
          findsNothing);
    });
  });
}
