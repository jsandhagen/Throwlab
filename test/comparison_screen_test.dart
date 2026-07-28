import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/comparison_screen.dart';
import 'package:throwlab/widgets/playback_controls.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

void main() {
  late Directory temp;
  late ThrowVideo videoA;
  late ThrowVideo videoB;
  late FakeVideoPlayerPlatform platform;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    videoA = testVideo(temp, id: 'a', athlete: 'Ana');
    videoB = testVideo(temp, id: 'b', athlete: 'Bea');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Mounts the comparison screen with a landscape clip in a portrait
  /// window, so each pane is much wider than the clip is tall — the shape
  /// that used to shrink a throw to a stamp.
  Future<void> mount(
    WidgetTester tester, {
    Size screen = const Size(400, 800),
    Size videoSize = const Size(1920, 1080),
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    platform = FakeVideoPlayerPlatform(videoSize);
    VideoPlayerPlatform.instance = platform;
    await tester.pumpWidget(
      MaterialApp(home: ComparisonScreen(videoA: videoA, videoB: videoB)),
    );
    await pumpFrames(tester, 8);
  }

  Size paneOf(WidgetTester tester, int index) =>
      tester.getSize(find.byType(ClipRect).at(index));

  Size videoSizeOf(WidgetTester tester, int index) =>
      tester.getSize(find.byType(VideoPlayer).at(index));

  group('framing', () {
    testWidgets('fills the pane instead of letterboxing it', (tester) async {
      await mount(tester);

      final pane = paneOf(tester, 0);
      final video = videoSizeOf(tester, 0);
      // Covers the pane on both axes...
      expect(video.width, greaterThanOrEqualTo(pane.width - 0.5));
      expect(video.height, greaterThanOrEqualTo(pane.height - 0.5));
      // ...at the clip's own aspect ratio, never stretched to fit.
      expect(video.width / video.height, closeTo(1920 / 1080, 0.01));
    });

    testWidgets('the toggle shows the whole frame again', (tester) async {
      await mount(tester);
      await tester.tap(find.byIcon(Icons.fit_screen));
      await pumpFrames(tester);

      final pane = paneOf(tester, 0);
      final video = videoSizeOf(tester, 0);
      expect(video.width, lessThanOrEqualTo(pane.width + 0.5));
      expect(video.height, lessThanOrEqualTo(pane.height + 0.5));
      expect(video.width / video.height, closeTo(1920 / 1080, 0.01));
    });

    testWidgets('a drag reframes the crop, and cannot open a gap',
        (tester) async {
      await mount(tester);
      final pane = tester.getRect(find.byType(ClipRect).first);
      final before = tester.getRect(find.byType(VideoPlayer).first);

      await tester.drag(find.byType(VideoPlayer).first, const Offset(-200, 0));
      await pumpFrames(tester);
      final after = tester.getRect(find.byType(VideoPlayer).first);

      // The clip moved under the finger...
      expect(after.left, lessThan(before.left));
      // ...but never far enough to show through beside it.
      expect(after.left, lessThanOrEqualTo(pane.left + 0.5));
      expect(after.right, greaterThanOrEqualTo(pane.right - 0.5));
    });

    testWidgets('double tap recentres', (tester) async {
      await mount(tester);
      final centred = tester.getRect(find.byType(VideoPlayer).first);
      await tester.drag(find.byType(VideoPlayer).first, const Offset(-150, 0));
      await pumpFrames(tester);
      expect(tester.getRect(find.byType(VideoPlayer).first).left,
          isNot(closeTo(centred.left, 1)));

      await tester.tap(find.byType(VideoPlayer).first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(VideoPlayer).first);
      await pumpFrames(tester);

      expect(tester.getRect(find.byType(VideoPlayer).first).left,
          closeTo(centred.left, 1));
    });
  });

  group('scrub wheel', () {
    testWidgets('each clip gets one while they are unlinked', (tester) async {
      await mount(tester);
      expect(find.byType(ScrubWheel), findsNWidgets(2));
    });

    testWidgets('one wheel drives both once they are linked', (tester) async {
      await mount(tester);
      await tester.tap(find.byIcon(Icons.link_off)); // drive them together
      await pumpFrames(tester);

      expect(find.byType(ScrubWheel), findsOneWidget);

      platform.seeks.clear();
      await tester.drag(find.byType(ScrubWheel), const Offset(-120, 0));
      await pumpFrames(tester);

      // Both players moved, not just the one the wheel is attached to.
      expect(platform.seeks.map((seek) => seek.playerId).toSet(), {1, 2});
    });

    testWidgets('an unlinked wheel moves only its own clip', (tester) async {
      await mount(tester);
      platform.seeks.clear();
      await tester.drag(find.byType(ScrubWheel).first, const Offset(-120, 0));
      await pumpFrames(tester);

      expect(platform.seeks.map((seek) => seek.playerId).toSet(), {1});
    });
  });
}
