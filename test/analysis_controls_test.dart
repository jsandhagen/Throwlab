import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/utils/time_format.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
import 'package:throwlab/widgets/drawing_rail.dart';
import 'package:throwlab/widgets/playback_controls.dart';

import 'analysis_harness.dart';

const _portraitPhone = Size(400, 800);
const _landscapePhone = Size(740, 360);

const _measure = 'Measure release — speed & angle (beta)';

void main() {
  group('the hand', () {
    late List<String> felt;
    late Duration now;
    late FrameHaptics haptics;

    setUp(() {
      felt = [];
      now = Duration.zero;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          felt.add((call.arguments as String).split('.').last);
        }
        return null;
      });
      haptics = FrameHaptics(clock: () => now)..lastFrame = 100;
    });

    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    test('a frame is a click, but never two inside the gap', () {
      haptics.step(10, 11);
      now += const Duration(milliseconds: 10);
      haptics.step(11, 12);
      now += FrameHaptics.minGap;
      haptics.step(12, 13);
      expect(felt, ['selectionClick', 'selectionClick']);
    });

    test('crossing the release is felt whatever the gap', () {
      haptics.releaseFrame = 20;
      haptics.step(18, 19);
      haptics.step(19, 21);
      haptics.step(21, 19);
      expect(felt, ['selectionClick', 'lightImpact', 'lightImpact']);
    });

    test('running into the end is felt once, and stops there', () {
      expect(haptics.step(100, 103), 100);
      expect(haptics.step(100, 101), 100);
      expect(felt, ['mediumImpact']);
      // Off the end and back into it is a second bump.
      now += FrameHaptics.minGap;
      haptics.step(100, 99);
      haptics.step(99, 100);
      haptics.step(100, 101);
      expect(felt, ['mediumImpact', 'selectionClick', 'mediumImpact']);
    });

    test('the start is an end too', () {
      expect(haptics.step(0, -4), 0);
      expect(felt, ['mediumImpact']);
    });
  });

  group('the scale', () {
    test('is numbered on whole frames, at the shortest round interval', () {
      // 240 fps at ~4 px a frame: a twentieth of a second is 12 frames.
      expect(ScalePainter.labelInterval(240, scrubPixelsPerFrame(240)),
          (seconds: 0.05, frames: 12));
      // 30 fps at ~33 px a frame: a twentieth would be a frame and a half,
      // which would put every other number between two ticks — so tenths.
      expect(ScalePainter.labelInterval(30, scrubPixelsPerFrame(30)),
          (seconds: 0.1, frames: 3));
      expect(ScalePainter.labelInterval(30, 4), (seconds: 0.5, frames: 15));
      // NTSC's 29.97 is near enough to divide into tenths.
      expect(ScalePainter.labelInterval(29.97, 33.4).frames, 3);
      // A rate no round interval divides is numbered by frames.
      expect(ScalePainter.labelInterval(12.34, 33).frames, 2);
    });

    test('counts from the release, signed, and names the release R', () {
      expect(ScalePainter.label(0, 0.05, relative: true), 'R');
      expect(ScalePainter.label(-0.1, 0.05, relative: true), '-0.10');
      expect(ScalePainter.label(0.15, 0.05, relative: true), '+0.15');
      expect(ScalePainter.label(2.4, 0.2, relative: false), '2.4');
    });

    test('the readout counts whole frames from the release', () {
      expect(formatSinceRelease(0, 240), '0.000');
      expect(formatSinceRelease(-3, 240), '-0.013');
      expect(formatSinceRelease(4, 30), '+0.133');
    });
  });

  test('a release survives being stored', () {
    final video = ThrowVideo(
      id: 'r',
      path: '/x.mp4',
      event: ThrowEvent.javelin,
      implementKg: 0.8,
      importedAt: DateTime(2026, 9, 1),
      release: const Duration(microseconds: 1234567),
    );
    expect(ThrowVideo.fromJson(video.toJson()).release,
        const Duration(microseconds: 1234567));
    final unmarked = video.toJson()..remove('releaseUs');
    expect(ThrowVideo.fromJson(unmarked).release, isNull);
  });

  group('the analysis screen', () {
    late Directory temp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('throwlab_test');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    DrawingRail rail(WidgetTester tester) =>
        tester.widget<DrawingRail>(find.byType(DrawingRail));

    testWidgets('upright, the header is the throw, the note and two actions',
        (tester) async {
      final video = testVideo(temp);
      await mountAnalysisScreen(tester,
          video: video,
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080));
      expect(find.byTooltip('Compare with another throw'), findsOneWidget);
      expect(find.byTooltip(_measure), findsOneWidget);
      expect(find.byTooltip('Tag athlete'), findsNothing);
      // Written while the throw is watched, so it is on the screen.
      expect(find.byTooltip('Add note'), findsOneWidget);
      expect(find.byIcon(Icons.shutter_speed), findsNothing);

      // What they did is on the sheet the title opens.
      await tester.tap(find.byKey(const ValueKey('throw-title')));
      await pumpFrames(tester, 30);
      expect(find.text('Set athlete'), findsOneWidget);
      expect(find.text('Add note'), findsOneWidget);
      expect(find.text('Frame rate · 30 fps'), findsOneWidget);
    });

    testWidgets('on its side the rail keeps everything', (tester) async {
      await mountAnalysisScreen(tester,
          video: testVideo(temp),
          screen: _landscapePhone,
          videoSize: const Size(1920, 1080));
      expect(find.byTooltip('Tag athlete'), findsOneWidget);
      expect(find.byTooltip('Add note'), findsOneWidget);
      expect(find.byIcon(Icons.shutter_speed), findsOneWidget);
    });

    testWidgets('a sideways clip held upright lays the tools under it',
        (tester) async {
      await mountAnalysisScreen(tester,
          video: testVideo(temp),
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080));
      expect(rail(tester).axis, Axis.horizontal);
    });

    testWidgets('an upright clip stands the tools up the edge', (tester) async {
      await mountAnalysisScreen(tester,
          video: testVideo(temp),
          screen: _portraitPhone,
          videoSize: const Size(1080, 1920));
      expect(rail(tester).axis, Axis.vertical);
      // Clear of the transport rather than over it.
      final tools = tester.getRect(find.byType(DrawingRail));
      final line = tester.getRect(find.byType(ClipLine));
      expect(tools.bottom, lessThanOrEqualTo(line.top));
    });

    testWidgets('the flag marks the release on the clip, and takes it off',
        (tester) async {
      final video = testVideo(temp);
      await mountAnalysisScreen(tester,
          video: video,
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080));
      await tester.drag(find.byType(ScrubWheel), const Offset(200, 0));
      await pumpFrames(tester, 20);

      await tester.tap(find.byKey(const ValueKey('release-flag')));
      await pumpFrames(tester);
      expect(video.release, isNotNull);
      expect(video.release, greaterThan(Duration.zero));
      expect(find.textContaining('R 0.000'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear the release'));
      await pumpFrames(tester);
      expect(video.release, isNull);
    });

    testWidgets('the offset from the release takes the clip back to it',
        (tester) async {
      final video = testVideo(temp)
        ..release = const Duration(milliseconds: 1000);
      final platform = FakeVideoPlayerPlatform(const Size(1920, 1080));
      await mountAnalysisScreen(tester,
          video: video,
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080),
          platform: platform);
      // Opened at the top of the clip, a second short of the release.
      expect(find.textContaining('R -1.000'), findsOneWidget);
      platform.seeks.clear();

      await tester.tap(find.byKey(const ValueKey('release-jump')));
      await pumpFrames(tester, 10);
      expect(platform.seeks.last.position.inMilliseconds, closeTo(1000, 34));
      expect(find.textContaining('R 0.000'), findsOneWidget);
    });

    testWidgets('the clock reads the frame under the wheel while it is turned',
        (tester) async {
      final video = testVideo(temp)
        ..release = const Duration(milliseconds: 1000);
      await mountAnalysisScreen(tester,
          video: video,
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080));
      expect(find.textContaining('R -1.000'), findsOneWidget);

      // Turned and still held: the offset has already moved with it, not a
      // seek later.
      final wheel = find.byKey(const ValueKey('scrub-wheel'));
      final gesture = await tester.startGesture(tester.getCenter(wheel));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      expect(find.textContaining('R -1.000'), findsNothing);
      final held = tester
          .widgetList<Text>(find.textContaining('R -'))
          .single
          .data;

      // And it is where the picture comes to rest once the wheel is let go.
      await gesture.up();
      await pumpFrames(tester, 40);
      expect(find.textContaining(held!), findsOneWidget);
    });

    testWidgets('a fling caught by a finger carries on from where it got to',
        (tester) async {
      final video = testVideo(temp)
        ..release = const Duration(milliseconds: 1000);
      await mountAnalysisScreen(tester,
          video: video,
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080));
      int frameShown() {
        final text = tester
            .widgetList<Text>(find.textContaining(' · f '))
            .single
            .data!;
        return int.parse(text.split('f ').last.trim());
      }

      final start = frameShown();
      final wheel = find.byKey(const ValueKey('scrub-wheel'));
      await tester.fling(wheel, const Offset(200, 0), 1500);
      await pumpFrames(tester, 6);
      final coasting = frameShown();
      expect(coasting, greaterThan(start));

      // Caught mid-coast and turned on a little further: it goes on from
      // the frame it had reached, never back toward where the flick began.
      final gesture = await tester.startGesture(tester.getCenter(wheel));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      expect(frameShown(), greaterThanOrEqualTo(coasting));
      await gesture.up();
      await pumpFrames(tester, 40);
    });

    testWidgets('the flag says what it marks', (tester) async {
      await mountAnalysisScreen(tester,
          video: testVideo(temp),
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080));
      expect(find.text('RELEASE'), findsOneWidget);
    });

    testWidgets('measuring starts on the release, and a tap can be undone',
        (tester) async {
      final video = testVideo(temp, event: ThrowEvent.shotPut)
        ..release = const Duration(milliseconds: 1000);
      final platform = FakeVideoPlayerPlatform(const Size(1920, 1080));
      await mountAnalysisScreen(tester,
          video: video,
          screen: _portraitPhone,
          videoSize: const Size(1920, 1080),
          platform: platform);
      platform.seeks.clear();

      await tester.tap(find.byTooltip(_measure));
      await pumpFrames(tester, 10);
      expect(platform.seeks.last.position.inMilliseconds, closeTo(1000, 34));
      expect(find.text('RELEASE FRAME · 1 / 4'), findsOneWidget);

      final canvas = tester.getRect(find.byType(DrawingCanvas));
      await tester.tapAt(canvas.center);
      await pumpFrames(tester);
      expect(find.text('RELEASE FRAME · 2 / 4'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('measure-undo')));
      await pumpFrames(tester);
      expect(find.text('RELEASE FRAME · 1 / 4'), findsOneWidget);
    });
  });
}
