// Renders the analysis screen to PNGs so the drawing tools and the chrome
// over the video can be reviewed without an emulator. It is not a test: it
// asserts nothing, it just paints.
//
//   flutter test --update-goldens tool/preview/analysis_preview.dart
//
// Images land in build/preview/ (gitignored). The player is the same
// in-memory stand-in the widget tests use, so the "video" is a flat blue
// rectangle — which is the point: what is being looked at here is where the
// tools sit over the frame, and how much of it they cost.
//
// Living outside test/ keeps `flutter test` — and therefore CI — clear of it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/services/video_optimizer.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../test/analysis_harness.dart';
import 'harness.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

/// A landscape phone in logical pixels — how a throw is filmed, and so how
/// this screen is nearly always read.
const _landscape = Size(2280, 1080);
const _portrait = Size(1080, 2280);

void main() {
  late Directory temp;
  late ThrowVideo video;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_preview');
    // Stamped as already prepared, so the screen doesn't reach for ffmpeg
    // and path_provider — neither of which is behind a widget test — and
    // the frame is painted without the 'preparing smooth scrubbing' hint
    // over it.
    video = testVideo(temp)
      ..scrubFramesDir = temp.path
      ..scrubFrameCount = 1
      ..scrubFrameStride = 1
      ..scrubFrameLongSide = VideoOptimizer.scrubFrameMax
      ..scrubFramesVersion = VideoOptimizer.scrubFramesVersion
      ..playbackVersion = VideoOptimizer.playbackVersion;
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> mount(WidgetTester tester, Size screen) async {
    await loadPreviewFonts();
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    VideoPlayerPlatform.instance =
        FakeVideoPlayerPlatform(const Size(1920, 1080));
    await tester.pumpWidget(
      ChangeNotifierProvider<VideoLibrary>.value(
        value: VideoLibrary(),
        child: MaterialApp(
          theme: ThrowLabApp.theme,
          home: AnalysisScreen(video: video),
        ),
      ),
    );
    await _pump(tester);
  }

  testWidgets('landscape', (tester) async {
    await mount(tester, _landscape);
    await _shoot(tester, 'analysis_landscape');

    // A ring round where the implement is, then an arrow off it: the two
    // marks a coach actually makes, both built on one drag.
    await _pickShape(tester, Icons.circle_outlined);
    await _dragAlong(tester, const [
      Offset(430, 150),
      Offset(450, 150),
      Offset(468, 150),
    ]);
    await _pickShape(tester, Icons.arrow_right_alt);
    await _dragAlong(tester, const [
      Offset(470, 140),
      Offset(530, 110),
      Offset(600, 80),
    ]);
    await _shoot(tester, 'analysis_landscape_drawn');

    // The shapes a drag builds, all behind the one button.
    await tester.tap(find.byKey(const ValueKey('rail-shapes')));
    await _pump(tester, 30);
    await _shoot(tester, 'analysis_shapes');
    await tester.tapAt(const Offset(120, 120));
    await _pump(tester, 30);

    // Folded away, one fixed target at the end of the bar.
    await tester.tap(find.byKey(const ValueKey('rail-collapse')));
    await _pump(tester, 10);
    await _shoot(tester, 'analysis_landscape_folded');
  });

  testWidgets('portrait', (tester) async {
    await mount(tester, _portrait);
    await _shoot(tester, 'analysis_portrait');
  });
}

/// Chooses one of the shapes out of the rail's shape menu.
Future<void> _pickShape(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byKey(const ValueKey('rail-shapes')));
  await _pump(tester, 30);
  await tester.tap(find.byIcon(icon).last);
  await _pump(tester, 30);
}

/// Draws with whichever tool is armed, the way a finger would.
Future<void> _dragAlong(WidgetTester tester, List<Offset> path) async {
  final gesture = await tester.startGesture(path.first);
  for (final point in path.skip(1)) {
    await gesture.moveTo(point);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await _pump(tester, 10);
}

/// Pumps, then swallows whatever the scrub-frame prep threw on its way
/// past: there is no ffmpeg behind the in-memory player, and this file is a
/// renderer rather than a test — an exception here says nothing about the
/// screen being painted.
Future<void> _pump(WidgetTester tester, [int frames = 20]) async {
  await pumpFrames(tester, frames);
  tester.takeException();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
  tester.takeException();
}
