// Renders the comparison screen to PNGs so the chrome around the two panes
// can be reviewed without an emulator. It is not a test: it asserts
// nothing, it just paints.
//
//   flutter test --update-goldens tool/preview/comparison_preview.dart
//
// Images land in build/preview/ (gitignored). The player is the same
// in-memory stand-in the widget tests use, so each pane is a black box —
// what is being looked at here is the app bar, which now carries the
// mirror as well as the fit and the mode, and whether the title still has
// room on a narrow phone. A stroke is drawn on A before it is flipped,
// because ink is the only thing in a pane that a fake player paints: the
// mark crossing to the other side is the mirror showing itself.
//
// Living outside test/ keeps `flutter test` — and therefore CI — clear of
// it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/comparison_screen.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../test/analysis_harness.dart';
import 'harness.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

/// Two throws side by side is a landscape job, but the app bar has to
/// survive the narrow upright phone as well — 360 logical pixels across,
/// the common Android width, with the longest title the screen can hold.
const _landscape = Size(2280, 1080);
const _narrowPortrait = Size(1080, 2280);

void main() {
  late Directory temp;
  late ThrowVideo videoA;
  late ThrowVideo videoB;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_preview');
    videoA = testVideo(temp, id: 'a', athlete: 'Ana');
    videoB = testVideo(temp, id: 'b', athlete: 'Bea');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> mount(WidgetTester tester, Size screen) async {
    await loadPreviewFonts();
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    VideoPlayerPlatform.instance =
        FakeVideoPlayerPlatform(const Size(1920, 1080));
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: ComparisonScreen(videoA: videoA, videoB: videoB),
    ));
    await _pump(tester);
  }

  /// A stroke across the top half of pane [index], which is the half a
  /// flip is easiest to read in.
  Future<void> _markPane(WidgetTester tester, int index) async {
    final pane = tester.getRect(find.byType(DrawingCanvas).at(index));
    final y = pane.top + pane.height * 0.3;
    await _dragAlong(tester, [
      Offset(pane.left + pane.width * 0.15, y),
      Offset(pane.left + pane.width * 0.25, y - 20),
      Offset(pane.left + pane.width * 0.35, y),
    ]);
  }

  testWidgets('landscape', (tester) async {
    await mount(tester, _landscape);
    await _shoot(tester, 'comparison_landscape');

    // The mirror, offered as a tick against each clip rather than as two
    // more icons in a bar that already carries three controls.
    await tester.tap(find.byIcon(Icons.flip));
    await _pump(tester, 30);
    await _shoot(tester, 'comparison_mirror_menu');
    await tester.tapAt(const Offset(200, 400));
    await _pump(tester, 30);
  });

  testWidgets('narrow portrait', (tester) async {
    await mount(tester, _narrowPortrait);
    await _shoot(tester, 'comparison_portrait_narrow');

    // A mark on A, then A turned round: the stroke crosses with the
    // picture rather than staying where the finger left it.
    await tester.tap(find.byKey(const ValueKey('rail-collapse')));
    await _pump(tester, 30);
    await tester.tap(find.byIcon(Icons.draw));
    await _pump(tester, 30);
    await _markPane(tester, 0);
    await _shoot(tester, 'comparison_marked');

    await tester.tap(find.byIcon(Icons.flip));
    await _pump(tester, 30);
    await tester.tap(find.ancestor(
        of: find.text('Mirror A'),
        matching: find.byType(CheckedPopupMenuItem<bool>)));
    await _pump(tester, 30);
    await _shoot(tester, 'comparison_mirrored');
  });
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

/// Pumps, then swallows whatever the fake player threw on its way past:
/// this file is a renderer rather than a test, and an exception from a
/// stand-in decoder says nothing about the screen being painted.
Future<void> _pump(WidgetTester tester, [int frames = 20]) async {
  await pumpFrames(tester, frames);
  tester.takeException();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
  tester.takeException();
}
