import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';

import 'analysis_harness.dart';

void main() {
  late Directory temp;
  late ThrowVideo video;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    video = testVideo(temp);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> mountWithPen(
    WidgetTester tester, {
    required Size screen,
    required Size videoSize,
  }) async {
    await mountAnalysisScreen(tester,
        video: video, screen: screen, videoSize: videoSize);
    await tapRail(tester, find.byIcon(Icons.draw)); // pen tool
  }

  /// Where the last point of the stroke just drawn is painted.
  Future<Offset> inkAtEndOf(WidgetTester tester, List<Offset> path) async {
    await drawAlong(tester, path);
    return inkFor(tester, annotationsOf<PenStroke>(tester).last.points.last);
  }

  testWidgets('pen ink lands under the finger', (tester) async {
    // Portrait clip on a landscape screen: the video is pillarboxed, so a
    // mismapped touch shows up as a horizontal offset.
    await mountWithPen(tester,
        screen: const Size(800, 600), videoSize: const Size(1080, 1920));

    final ink = await inkAtEndOf(tester, const [
      Offset(340, 200),
      Offset(360, 240),
      Offset(390, 300),
    ]);
    expect(ink, within(distance: 1, from: const Offset(390, 300)));
  });

  testWidgets('pen ink lands under the finger while zoomed', (tester) async {
    await mountWithPen(tester,
        screen: const Size(800, 600), videoSize: const Size(1080, 1920));
    await pinchOut(tester, const Offset(400, 300), 120);

    final ink = await inkAtEndOf(tester, const [
      Offset(340, 200),
      Offset(360, 240),
      Offset(390, 300),
    ]);
    expect(ink, within(distance: 1, from: const Offset(390, 300)));
  });

  testWidgets('pen ink lands under the finger after the viewport changes',
      (tester) async {
    // Zoom and pan hard against the edge, then change the viewport (device
    // rotation, system bars): the pan the screen draws with gets re-clamped,
    // and the touch mapping has to follow it.
    await mountWithPen(tester,
        screen: const Size(800, 600), videoSize: const Size(1920, 1080));
    await pinchOut(tester, const Offset(720, 300), 220);

    tester.view.physicalSize = const Size(600, 400);
    await pumpFrames(tester);

    final ink = await inkAtEndOf(tester, const [
      Offset(260, 150),
      Offset(280, 180),
      Offset(300, 200),
    ]);
    expect(ink, within(distance: 1, from: const Offset(300, 200)));
  });
}
