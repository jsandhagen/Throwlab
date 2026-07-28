import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/utils/frame_timing.dart';
import 'package:throwlab/screens/comparison_screen.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
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

  group('the release loop', () {
    Duration lastSeek(int playerId) => platform.seeks
        .lastWhere((seek) => seek.playerId == playerId)
        .position;

    /// Scrubs each clip somewhere different and marks it as the release,
    /// which is what links the two.
    Future<({Duration a, Duration b})> markReleases(WidgetTester tester) async {
      await tester.drag(find.byType(ScrubWheel).first, const Offset(400, 0));
      await pumpFrames(tester, 20);
      final releaseA = lastSeek(1);
      await tester.tap(find.text('Set release').first);
      await pumpFrames(tester, 10);

      await tester.drag(find.byType(ScrubWheel).last, const Offset(250, 0));
      await pumpFrames(tester, 20);
      final releaseB = lastSeek(2);
      await tester.tap(find.text('Set release'));
      await pumpFrames(tester, 10);

      expect(releaseA, greaterThan(Duration.zero));
      expect(releaseB, greaterThan(Duration.zero));
      expect(releaseA, isNot(releaseB));
      return (a: releaseA, b: releaseB);
    }

    testWidgets('play starts both clips, the same run-up before each release',
        (tester) async {
      await mount(tester);
      final release = await markReleases(tester);

      platform.plays.clear();
      platform.seeks.clear();
      await tester.tap(find.byIcon(Icons.play_circle));
      await pumpFrames(tester, 10);

      // Both running — not just the one the transport is wired to.
      expect(platform.plays.toSet(), {1, 2});
      // And started at the same distance before their own release, which is
      // what makes the two comparable.
      expect(release.a - lastSeek(1), release.b - lastSeek(2));
    });

    testWidgets('it comes back round instead of running off the end',
        (tester) async {
      await mount(tester);
      final release = await markReleases(tester);
      await tester.tap(find.byIcon(Icons.play_circle));
      await pumpFrames(tester, 10);
      final startA = lastSeek(1);
      final startB = lastSeek(2);

      platform.seeks.clear();
      // The window is ~1.7 s of clip time, played at the default half speed.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(lastSeek(1), startA);
      expect(lastSeek(2), startB);
      // Still the same run-up on the way round.
      expect(release.a - lastSeek(1), release.b - lastSeek(2));
    });

    testWidgets('pause stops the loop where it is', (tester) async {
      await mount(tester);
      await markReleases(tester);
      await tester.tap(find.byIcon(Icons.play_circle));
      await pumpFrames(tester, 10);

      await tester.tap(find.byIcon(Icons.pause_circle));
      await pumpFrames(tester, 10);
      platform.seeks.clear();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(platform.seeks, isEmpty);
    });
  });

  group('drawing', () {
    /// The annotations painted over pane [index] (0 = A, 1 = B).
    List<T> paneAnnotations<T extends Annotation>(
        WidgetTester tester, int index) {
      final paint = tester.widget<CustomPaint>(find.descendant(
          of: find.byType(DrawingCanvas).at(index),
          matching: find.byType(CustomPaint)));
      return ((paint.painter as dynamic).annotations as List)
          .whereType<T>()
          .toList();
    }

    /// The rail starts collapsed here — the video area is already split
    /// between two clips.
    Future<void> openRail(WidgetTester tester) =>
        tapRail(tester, find.byKey(const ValueKey('rail-collapse')));

    /// A stroke across the middle of pane [index].
    Future<void> drawInPane(WidgetTester tester, int index) async {
      final pane = tester.getRect(find.byType(VideoPlayer).at(index));
      await drawAlong(tester, [
        pane.center - const Offset(40, 20),
        pane.center,
        pane.center + const Offset(40, 20),
      ]);
    }

    testWidgets('a stroke lands on the pane it was drawn in', (tester) async {
      await mount(tester);
      await openRail(tester);
      await selectTool(tester, Icons.draw);

      await drawInPane(tester, 0);
      expect(paneAnnotations<PenStroke>(tester, 0), hasLength(1));
      expect(paneAnnotations<PenStroke>(tester, 1), isEmpty);
    });

    testWidgets('the tool picked once arms both panes', (tester) async {
      await mount(tester);
      await openRail(tester);
      await selectTool(tester, Icons.draw);

      // Never drawn in B, and the tool was chosen while A was the active
      // pane — B still draws rather than reframing its crop.
      await drawInPane(tester, 1);
      expect(paneAnnotations<PenStroke>(tester, 1), hasLength(1));
      expect(paneAnnotations<PenStroke>(tester, 0), isEmpty);
    });

    testWidgets('undo takes back the mark from the pane it was made in',
        (tester) async {
      await mount(tester);
      await openRail(tester);
      await selectTool(tester, Icons.draw);
      await drawInPane(tester, 0);
      await drawInPane(tester, 1);

      await tapRail(tester, find.byIcon(Icons.undo));
      // B was drawn in last, so B is what undo acts on.
      expect(paneAnnotations<PenStroke>(tester, 1), isEmpty);
      expect(paneAnnotations<PenStroke>(tester, 0), hasLength(1));
    });

    testWidgets('with no tool selected a drag still reframes the crop',
        (tester) async {
      await mount(tester);
      final before = tester.getRect(find.byType(VideoPlayer).first);

      await drawInPane(tester, 0);

      expect(paneAnnotations<Annotation>(tester, 0), isEmpty);
      expect(tester.getRect(find.byType(VideoPlayer).first).left,
          isNot(closeTo(before.left, 1)));
    });
  });

  group('smooth scrubbing', () {
    /// How far a seek sits from the nearest frame boundary, in frames. The
    /// stills' targets aim [kSeekLead] of a frame short of the frame they
    /// name; a plain frame step lands on the boundary itself.
    double leadOf(Duration position, double fps) {
      final frames = position.inMicroseconds * fps / 1e6;
      return (frames - frames.roundToDouble()).abs();
    }

    testWidgets('a wheel drag runs through the shuttle, like the analysis '
        'screen', (tester) async {
      // The clip has stills extracted, so scrubbing plays them rather than
      // hammering the decoder with a seek per frame.
      videoA.scrubFramesDir = '${temp.path}/frames-a';
      videoA.scrubFrameCount = 300;
      videoA.scrubFrameStride = 1;
      await mount(tester);

      platform.seeks.clear();
      await tester.drag(find.byType(ScrubWheel).first, const Offset(120, 0));
      await pumpFrames(tester, 40);

      // The scrub starts at zero, where a still's lead is clamped away;
      // every seek past it comes off the extracted-frame grid.
      final moved =
          platform.seeks.where((seek) => seek.position > Duration.zero);
      expect(moved, isNotEmpty);
      for (final seek in moved) {
        expect(seek.playerId, 1);
        expect(leadOf(seek.position, videoA.fps), closeTo(kSeekLead, 0.02),
            reason: '${seek.position} is not a still-grid seek target');
      }
    });

    testWidgets('without stills it still scrubs, straight to the decoder',
        (tester) async {
      await mount(tester);

      platform.seeks.clear();
      await tester.drag(find.byType(ScrubWheel).first, const Offset(120, 0));
      await pumpFrames(tester, 40);

      expect(platform.seeks, isNotEmpty);
      // Frame steps off the player's own position land on the frame
      // boundary, without the stills' quarter-frame lead.
      expect(leadOf(platform.seeks.last.position, videoA.fps),
          closeTo(0, 0.02));
    });

    testWidgets('linked, both clips move by the same time even at different '
        'frame rates', (tester) async {
      videoB.fps = 60;
      videoB.captureFps = 60;
      await mount(tester);
      await tester.tap(find.byIcon(Icons.link_off)); // drive them together
      await pumpFrames(tester);

      platform.seeks.clear();
      await tester.drag(find.byType(ScrubWheel), const Offset(120, 0));
      await pumpFrames(tester, 40);

      Duration lastFor(int playerId) => platform.seeks
          .lastWhere((seek) => seek.playerId == playerId)
          .position;
      // B's clip runs at twice A's frame rate, so the same scrub is twice as
      // many frames of B — and the same amount of time.
      expect(lastFor(2).inMilliseconds,
          closeTo(lastFor(1).inMilliseconds, 1000 / videoB.fps));
    });
  });
}
