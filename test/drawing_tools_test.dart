import 'dart:io';
import 'dart:math' as math;

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
      await selectTool(tester, Icons.draw);
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

      await selectWidth(tester, 'Thick');
      await drawAlong(tester, strokePath);
      expect(annotationsOf<PenStroke>(tester).last.width, kStrokeWidths.last);

      await selectWidth(tester, 'Thin');
      await drawAlong(tester, strokePath);
      expect(annotationsOf<PenStroke>(tester).last.width, kStrokeWidths.first);

      // The earlier strokes kept the pen they were drawn with.
      expect(annotationsOf<PenStroke>(tester).map((s) => s.width),
          [kStrokeWidths[1], kStrokeWidths.last, kStrokeWidths.first]);
    });

    testWidgets('each stroke paints at its own weight', (tester) async {
      await mountWithPen(tester);
      await selectWidth(tester, 'Thin');
      await drawAlong(tester, strokePath);
      await selectWidth(tester, 'Thick');
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
      await selectWidth(tester, 'Thick');

      await selectTool(tester, Icons.timeline);
      await drawAlong(tester, strokePath);
      expect(annotationsOf<LineAnnotation>(tester).single.width,
          kStrokeWidths.last);

      await selectTool(tester, Icons.square_foot);
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
      await selectTool(tester, Icons.arrow_right_alt);
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

    testWidgets('curved arrow traces the drag and heads where it lifts',
        (tester) async {
      await mountAnalysisScreen(tester,
          video: video,
          screen: const Size(800, 600),
          videoSize: const Size(1920, 1080));
      await selectTool(tester, Icons.turn_slight_right);

      // An arc, like the path of a pull.
      const path = [
        Offset(300, 420),
        Offset(320, 360),
        Offset(360, 310),
        Offset(410, 280),
        Offset(470, 270),
      ];
      await drawAlong(tester, path);

      final arrow = annotationsOf<CurvedArrowAnnotation>(tester).single;
      // Every sample is kept, so the stroke follows the finger's route
      // rather than the straight line between its ends.
      expect(arrow.points.length, greaterThanOrEqualTo(path.length - 1));
      expect(inkFor(tester, arrow.points.first),
          within(distance: 1, from: path.first));
      expect(inkFor(tester, arrow.points.last),
          within(distance: 1, from: path.last));
      expect(arrow.width, kStrokeWidths[1]);
      // A curved shaft that stops where the filled head starts — drawn to
      // the tip, the shaft's round cap bulges out past the point as a blob.
      expect(find.byType(DrawingCanvas), paints..path()..path());
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

  group('trimPathEnd', () {
    double lengthOf(List<Offset> points) {
      var total = 0.0;
      for (var i = 1; i < points.length; i++) {
        total += (points[i] - points[i - 1]).distance;
      }
      return total;
    }

    test('takes the asked-for distance off the end', () {
      const drawn = [Offset(0, 0), Offset(100, 0)];
      final trimmed = trimPathEnd(drawn, 30);
      expect(trimmed.last, within(distance: 0.01, from: const Offset(70, 0)));
      expect(lengthOf(trimmed), closeTo(70, 0.01));
    });

    test('cuts across whichever segment the distance lands in', () {
      const drawn = [Offset(0, 0), Offset(0, 40), Offset(60, 40)];
      // 30 back from the end is 30 along the second segment.
      final trimmed = trimPathEnd(drawn, 30);
      expect(trimmed.last, within(distance: 0.01, from: const Offset(30, 40)));
      // The corner it walked past is kept, so the curve still bends there.
      expect(trimmed, hasLength(3));
      expect(lengthOf(trimmed), closeTo(70, 0.01));
    });

    test('keeps the start when asked for more than the path has', () {
      const drawn = [Offset(0, 0), Offset(10, 0), Offset(20, 0)];
      expect(trimPathEnd(drawn, 500), [const Offset(0, 0)]);
    });

    test('walks past repeated samples instead of stalling on them', () {
      const drawn = [
        Offset(0, 0),
        Offset(50, 0),
        Offset(50, 0),
        Offset(50, 0),
      ];
      final trimmed = trimPathEnd(drawn, 20);
      expect(trimmed.last, within(distance: 0.01, from: const Offset(30, 0)));
    });

    test('trimming nothing leaves the path where it ended', () {
      const drawn = [Offset(0, 0), Offset(40, 30)];
      expect(trimPathEnd(drawn, 0).last,
          within(distance: 0.01, from: const Offset(40, 30)));
    });
  });

  group('smoothPath', () {
    List<Offset> pointsAlong(Path path, {int samples = 40}) {
      final metric = path.computeMetrics().single;
      return [
        for (var i = 0; i <= samples; i++)
          metric.getTangentForOffset(metric.length * i / samples)!.position,
      ];
    }

    test('keeps the ends the stroke was drawn with', () {
      const drawn = [Offset(10, 10), Offset(40, 60), Offset(90, 20)];
      final sampled = pointsAlong(smoothPath(drawn));
      expect(sampled.first, within(distance: 0.5, from: drawn.first));
      expect(sampled.last, within(distance: 0.5, from: drawn.last));
    });

    test('rounds the corner off a polyline without leaving its neighbourhood',
        () {
      const corner = [Offset(0, 0), Offset(50, 0), Offset(50, 50)];
      final sampled = pointsAlong(smoothPath(corner));
      // The curve cuts inside the sharp corner...
      final nearestToCorner = sampled
          .map((p) => (p - const Offset(50, 0)).distance)
          .reduce(math.min);
      expect(nearestToCorner, greaterThan(1));
      // ...but stays close to the route that was drawn.
      expect(nearestToCorner, lessThan(20));
    });

    test('a two-point stroke is just the segment', () {
      const line = [Offset(0, 0), Offset(30, 40)];
      final metric = smoothPath(line).computeMetrics().single;
      expect(metric.length, closeTo(50, 0.01));
    });

    test('an empty stroke paints nothing', () {
      expect(smoothPath(const []).computeMetrics().isEmpty, isTrue);
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
      await selectTool(tester, Icons.draw);
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
