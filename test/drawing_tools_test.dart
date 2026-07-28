import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';

import 'analysis_harness.dart';

void main() {
  group('DrawingController', () {
    test('starts on the middle thickness', () {
      expect(DrawingController().strokeWidth, kStrokeWidths[1]);
    });

    test('notifies listeners when the thickness changes', () {
      final controller = DrawingController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.strokeWidth = kStrokeWidths.last;
      expect(controller.strokeWidth, kStrokeWidths.last);
      expect(notifications, 1);
    });
  });

  group('thickness picker', () {
    late Directory temp;
    late ThrowVideo video;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('throwlab_test');
      video = testVideo(temp);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    Future<void> mountWithPen(WidgetTester tester) async {
      await mountAnalysisScreen(tester,
          video: video,
          screen: const Size(800, 600),
          videoSize: const Size(1920, 1080));
      await tapRail(tester, find.byIcon(Icons.draw));
    }

    const strokePath = [
      Offset(340, 200),
      Offset(360, 240),
      Offset(390, 300),
    ];

    testWidgets('sets the weight of new strokes, leaving drawn ones alone',
        (tester) async {
      await mountWithPen(tester);

      await drawAlong(tester, strokePath);
      expect(annotationsOf<PenStroke>(tester).last.width, kStrokeWidths[1]);

      await tapRail(tester, find.byTooltip('Thick line'));
      await drawAlong(tester, strokePath);
      expect(annotationsOf<PenStroke>(tester).last.width, kStrokeWidths.last);

      await tapRail(tester, find.byTooltip('Thin line'));
      await drawAlong(tester, strokePath);
      expect(annotationsOf<PenStroke>(tester).last.width, kStrokeWidths.first);

      // The earlier strokes kept the pen they were drawn with.
      expect(annotationsOf<PenStroke>(tester).map((s) => s.width),
          [kStrokeWidths[1], kStrokeWidths.last, kStrokeWidths.first]);
    });

    testWidgets('each stroke paints at its own weight', (tester) async {
      await mountWithPen(tester);
      await tapRail(tester, find.byTooltip('Thin line'));
      await drawAlong(tester, strokePath);
      await tapRail(tester, find.byTooltip('Thick line'));
      await drawAlong(tester, strokePath);

      expect(
        find.byType(DrawingCanvas),
        paints
          ..path(strokeWidth: kStrokeWidths.first)
          ..path(strokeWidth: kStrokeWidths.last),
      );
    });

    testWidgets('straight lines and angles use the selected weight',
        (tester) async {
      await mountWithPen(tester);
      await tapRail(tester, find.byTooltip('Thick line'));

      await tapRail(tester, find.byIcon(Icons.timeline)); // line tool
      await drawAlong(tester, strokePath);
      expect(annotationsOf<LineAnnotation>(tester).single.width,
          kStrokeWidths.last);

      await tapRail(tester, find.byIcon(Icons.square_foot)); // angle tool
      await tester.tapAt(const Offset(300, 200));
      await pumpFrames(tester);
      expect(annotationsOf<AngleAnnotation>(tester).single.width,
          kStrokeWidths.last);
    });
  });

  group('arrow tool', () {
    late Directory temp;
    late ThrowVideo video;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('throwlab_test');
      video = testVideo(temp);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    Future<void> mountWithArrow(WidgetTester tester) async {
      await mountAnalysisScreen(tester,
          video: video,
          screen: const Size(800, 600),
          videoSize: const Size(1920, 1080));
      await tapRail(tester, find.byIcon(Icons.arrow_right_alt));
    }

    testWidgets('drags tail to head', (tester) async {
      await mountWithArrow(tester);
      await drawAlong(tester, const [
        Offset(300, 400),
        Offset(360, 300),
        Offset(420, 200),
      ]);

      final arrow = annotationsOf<ArrowAnnotation>(tester).single;
      expect(inkFor(tester, arrow.start),
          within(distance: 1, from: const Offset(300, 400)));
      expect(inkFor(tester, arrow.end),
          within(distance: 1, from: const Offset(420, 200)));
      expect(arrow.width, kStrokeWidths[1]);
      // A shaft plus a filled head.
      expect(find.byType(DrawingCanvas), paints..line()..path());
    });

    testWidgets('undo removes the whole arrow', (tester) async {
      await mountWithArrow(tester);
      await drawAlong(
          tester, const [Offset(300, 400), Offset(360, 300), Offset(420, 200)]);
      expect(annotationsOf<ArrowAnnotation>(tester), hasLength(1));

      await tapRail(tester, find.byIcon(Icons.undo));
      expect(annotationsOf<ArrowAnnotation>(tester), isEmpty);
    });
  });

  group('ink under zoom', () {
    late Directory temp;
    late ThrowVideo video;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('throwlab_test');
      video = testVideo(temp);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('damps rather than tracks the zoom', () {
      expect(inkScaleFor(1), 1);
      // Ink grows, but slower than the picture: 4x zoom, 2x the weight.
      expect(inkScaleFor(4), 2);
      expect(inkScaleFor(9), 3);
      // Never thinner than it was drawn.
      expect(inkScaleFor(0.5), 1);
    });

    testWidgets('a zoomed stroke paints thinner in canvas space',
        (tester) async {
      await mountAnalysisScreen(tester,
          video: video,
          screen: const Size(800, 600),
          videoSize: const Size(1920, 1080));
      await tapRail(tester, find.byIcon(Icons.draw));
      await drawAlong(tester, const [
        Offset(340, 200),
        Offset(360, 240),
        Offset(390, 300),
      ]);
      // Unzoomed: painted at the weight it was drawn with.
      expect(find.byType(DrawingCanvas),
          paints..path(strokeWidth: kStrokeWidths[1]));

      await pinchOut(tester, const Offset(400, 300), 80);
      final zoom = tester
          .widget<DrawingCanvas>(find.byType(DrawingCanvas))
          .zoomScale;
      expect(zoom, greaterThan(1.5));
      // The canvas is drawn inside the zoom transform, so the damping shows
      // up as a *thinner* canvas-space stroke: width x sqrt(z) / z.
      final damped = kStrokeWidths[1] * inkScaleFor(zoom) / zoom;
      // Thinner in canvas space than it was drawn...
      expect(damped, lessThan(kStrokeWidths[1]));
      // ...but still fatter on screen than unzoomed, just not by the full
      // zoom: it scales somewhat, which is the whole point.
      expect(damped * zoom, greaterThan(kStrokeWidths[1]));
      expect(damped * zoom, lessThan(kStrokeWidths[1] * zoom));
      expect(
        find.byType(DrawingCanvas),
        paints
          ..something((symbol, arguments) =>
              symbol == #drawPath &&
              ((arguments.last as Paint).strokeWidth - damped).abs() < 0.01),
      );
    });
  });
}
