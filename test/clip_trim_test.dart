import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/trim_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/services/video_optimizer.dart';
import 'package:throwlab/utils/clip_trim.dart';
import 'package:throwlab/widgets/throw_actions.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

/// Cutting a clip down to the throw: which frames are kept, what happens to
/// the release, and the ffmpeg that does the cutting.
void main() {
  TrimRange range(int first, int last, {int count = 150, double fps = 30}) =>
      TrimRange(first: first, last: last, frameCount: count, fps: fps);

  group('range', () {
    test('opens on the whole clip, which cuts nothing', () {
      final whole = TrimRange.whole(const Duration(seconds: 5), 30);
      expect(whole.first, 0);
      expect(whole.last, 149);
      expect(whole.isWhole, isTrue);
      expect(whole.length, const Duration(seconds: 5));
    });

    test('keeps both of its end frames', () {
      final kept = range(30, 59);
      expect(kept.keptFrames, 30);
      expect(kept.start, const Duration(seconds: 1));
      // The end of the last frame, so thirty frames last a second.
      expect(kept.end, const Duration(seconds: 2));
      expect(kept.length, const Duration(seconds: 1));
      expect(kept.isWhole, isFalse);
    });

    test('never lets the ends cross or close up past the minimum', () {
      final kept = range(30, 90);
      // A fifth of a second at 30 fps is six frames.
      expect(kept.minFrames, 6);
      expect(kept.withFirst(200).first, 85);
      expect(kept.withLast(0).last, 35);
      expect(kept.withFirst(-4).first, 0);
      expect(kept.withLast(400).last, 149);
    });

    test('reads a seek target back as the frame it was aimed at', () {
      final kept = range(0, 149);
      for (final frame in [0, 1, 29, 30, 149]) {
        expect(kept.frameAt(kept.seekTarget(frame)), frame);
      }
    });
  });

  group('release', () {
    test('moves with the clip, counted from the new start', () {
      final kept = range(30, 89);
      final release = range(0, 149).seekTarget(60);
      final after = kept.releaseAfter(release)!;
      // The same frame, thirty frames earlier in a clip that starts a
      // second later.
      expect(range(0, 59, count: 60).frameAt(after), 30);
    });

    test('survives on either end frame', () {
      final whole = range(0, 149);
      final kept = range(30, 89);
      expect(kept.releaseAfter(whole.seekTarget(30)), Duration.zero);
      expect(kept.releaseAfter(whole.seekTarget(89)), isNotNull);
    });

    test('goes with the part that was cut off', () {
      final whole = range(0, 149);
      final kept = range(30, 89);
      expect(kept.releaseAfter(whole.seekTarget(29)), isNull);
      expect(kept.releaseAfter(whole.seekTarget(90)), isNull);
      expect(kept.releaseAfter(null), isNull);
    });

    test('a trimmed throw is owed new stills', () {
      final video = ThrowVideo(
        id: 'v',
        path: '/v.mp4',
        event: ThrowEvent.discus,
        implementKg: 2,
        importedAt: DateTime(2026),
        scrubFramesDir: '/frames/v',
        scrubFrameCount: 150,
        scrubFramesVersion: VideoOptimizer.scrubFramesVersion,
        release: range(0, 149).seekTarget(100),
      );
      applyTrim(video, range(0, 59));
      expect(video.release, isNull);
      expect(video.scrubFrameCount, 0);
      expect(video.scrubFramesVersion, 0);
      // Kept, so a delete still finds the directory to reclaim.
      expect(video.scrubFramesDir, '/frames/v');
    });
  });

  group('ffmpeg', () {
    test('cuts half a frame outside the kept frames', () {
      final cut = VideoOptimizer.trimFilters(range(30, 59));
      expect(cut.seek, '0.000000');
      expect(cut.video, 'trim=start=0.983333:end=1.983333,setpts=PTS-STARTPTS');
      expect(
          cut.audio, 'atrim=start=0.983333:end=1.983333,asetpts=PTS-STARTPTS');
    });

    test('never cuts before the start of the clip', () {
      final cut = VideoOptimizer.trimFilters(range(0, 59));
      expect(cut.video, startsWith('trim=start=0.000000:'));
    });

    test('seeks to short of a late cut and measures from there', () {
      // Frame 300 at 30 fps is ten seconds in; the seek stops two short,
      // on a whole second, and the filter counts from it.
      final cut = VideoOptimizer.trimFilters(range(300, 359, count: 600));
      expect(cut.seek, '7.000000');
      expect(cut.video, 'trim=start=2.983333:end=4.983333,setpts=PTS-STARTPTS');
    });
  });

  group('screen', () {
    late Directory directory;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      directory = Directory.systemTemp.createTempSync('trim');
    });
    tearDown(() => directory.deleteSync(recursive: true));

    Future<void> mount(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      VideoPlayerPlatform.instance =
          FakeVideoPlayerPlatform(const Size(1080, 1920));
      await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>.value(
        value: VideoLibrary(),
        child: MaterialApp(home: home),
      ));
      await pumpFrames(tester);
    }

    testWidgets('is offered on the throw sheet', (tester) async {
      final video = testVideo(directory);
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showThrowActions(context, video),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await pumpFrames(tester, 30);
      await tester.tap(find.text('Trim clip'));
      await pumpFrames(tester, 30);
      expect(find.byType(TrimScreen), findsOneWidget);
    });

    testWidgets('trims nothing until an end is moved', (tester) async {
      final video = testVideo(directory);
      await mount(tester, TrimScreen(video: video));
      FilledButton save() =>
          tester.widget<FilledButton>(find.byKey(const ValueKey('trim-save')));
      expect(save().onPressed, isNull);
      expect(find.text('5.00 s of 5.00 s'), findsOneWidget);

      // Tap a second into the clip, and start there.
      final bar = tester.getRect(find.byKey(const ValueKey('trim-bar')));
      await tester.tapAt(
          Offset(bar.left + 16 + (bar.width - 32) * 0.2 + 1, bar.center.dy));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('trim-start-here')));
      await pumpFrames(tester);
      expect(find.text('1.00 s'), findsOneWidget);
      expect(find.text('4.00 s of 5.00 s'), findsOneWidget);
      expect(save().onPressed, isNotNull);
    });

    testWidgets('a handle dragged in moves that end', (tester) async {
      final video = testVideo(directory);
      await mount(tester, TrimScreen(video: video));
      final bar = tester.getRect(find.byKey(const ValueKey('trim-bar')));
      // The right-hand handle stands just outside the end of the strip.
      final grip = Offset(bar.right - 8, bar.center.dy);
      await tester.dragFrom(grip, Offset(-(bar.width - 32) / 2, 0));
      // Long enough for the seeks the drag sent to settle.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('of 5.00 s'), findsOneWidget);
      expect(find.text('5.00 s of 5.00 s'), findsNothing);
    });

    testWidgets('says when a cut would take the release', (tester) async {
      final video = testVideo(directory)
        ..release = range(0, 149).seekTarget(15);
      await mount(tester, TrimScreen(video: video));
      expect(find.textContaining('will be cleared'), findsNothing);
      final bar = tester.getRect(find.byKey(const ValueKey('trim-bar')));
      await tester
          .tapAt(Offset(bar.left + 16 + (bar.width - 32) * 0.5, bar.center.dy));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('trim-start-here')));
      await pumpFrames(tester);
      expect(find.textContaining('will be cleared'), findsOneWidget);
    });
  });
}
