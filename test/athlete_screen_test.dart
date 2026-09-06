import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/screens/athlete_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/throw_card.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

/// An athlete's profile: the marks they hold, and the medal that says which
/// clip each one came out of.
void main() {
  late Directory temp;
  late VideoLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VideoPlayerPlatform.instance =
        FakeVideoPlayerPlatform(const Size(1920, 1080));
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    library = VideoLibrary();
    await library.load();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> fill(List<ThrowVideo> videos) async {
    for (final video in videos) {
      await library.add(video);
    }
  }

  Future<void> mountProfile(WidgetTester tester,
      {String name = 'Ana Diaz'}) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>.value(
      value: library,
      child: MaterialApp(
        home: AthleteScreen(
            name: name, titleFor: (video) => video.event.label),
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
    expect(cards.map((card) => card.isPersonalBest),
        [true, false, false]);
    // The medal is the card's; the bests section is all marks already.
    expect(find.byIcon(Icons.military_tech), findsOneWidget);
  });

  testWidgets('says how to start tracking bests when nothing is measured',
      (tester) async {
    await fill([testVideo(temp, id: 'v1', athlete: 'Ana Diaz')]);
    await mountProfile(tester);

    expect(find.textContaining('No distances recorded yet'), findsOneWidget);
    expect(find.byIcon(Icons.military_tech), findsNothing);
    expect(find.byType(ThrowCard), findsOneWidget);
  });

  testWidgets('sums up the season under the name', (tester) async {
    await fill([
      testVideo(temp,
          id: 'jav',
          athlete: 'Ana Diaz',
          importedAt: DateTime(2026, 3, 4)),
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

  testWidgets('an athlete with nothing left says so', (tester) async {
    await mountProfile(tester, name: 'Nobody');
    expect(find.textContaining('Nothing here any more'), findsOneWidget);
    expect(find.byType(ThrowCard), findsNothing);
  });
}
