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
}
