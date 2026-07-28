import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';

import 'analysis_harness.dart';

/// A landscape phone: ~360 logical pixels of height, which the drawing rail
/// used to run off the top of.
const _landscapePhone = Size(740, 360);
const _portraitPhone = Size(400, 800);

void main() {
  late Directory temp;
  late ThrowVideo video;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    video = testVideo(temp);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> mount(WidgetTester tester, Size screen) => mountAnalysisScreen(
        tester,
        video: video,
        screen: screen,
        videoSize: const Size(1920, 1080),
      );

  /// Every drawing tool, in rail order.
  const tools = [
    Icons.pan_tool_alt,
    Icons.draw,
    Icons.timeline,
    Icons.arrow_right_alt,
    Icons.turn_slight_right,
    Icons.square_foot,
  ];

  void expectOnScreen(WidgetTester tester, Finder finder, Size screen,
      {required String what}) {
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$what is off the top');
    expect(rect.bottom, lessThanOrEqualTo(screen.height),
        reason: '$what is off the bottom');
    expect(rect.left, greaterThanOrEqualTo(0), reason: '$what is off the left');
    expect(rect.right, lessThanOrEqualTo(screen.width),
        reason: '$what is off the right');
  }

  group('landscape', () {
    testWidgets('every drawing tool is reachable without scrolling the rail',
        (tester) async {
      await mount(tester, _landscapePhone);
      for (final tool in tools) {
        expectOnScreen(tester, find.byIcon(tool), _landscapePhone,
            what: '$tool');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the tools lie along a row, not a column', (tester) async {
      await mount(tester, _landscapePhone);
      final first = tester.getCenter(find.byIcon(tools.first));
      final last = tester.getCenter(find.byIcon(tools.last));
      expect(last.dx, greaterThan(first.dx));
      expect(last.dy, closeTo(first.dy, 1));
    });

    testWidgets('the header is a rail down the left, back arrow on top',
        (tester) async {
      await mount(tester, _landscapePhone);
      final back = tester.getRect(find.byIcon(Icons.arrow_back));
      final speed = tester.getRect(find.byIcon(Icons.speed));

      // Down the left edge...
      expect(back.left, lessThan(60));
      expect(speed.left, lessThan(60));
      // ...with back at the top of it.
      expect(back.top, lessThan(speed.top));
      // The header no longer spans the top of the frame.
      expect(speed.right, lessThan(_landscapePhone.width / 4));
    });

    testWidgets('the top of the frame is left to the video', (tester) async {
      await mount(tester, _landscapePhone);
      // Nothing but the back/glyph corner sits in the top strip: the
      // per-throw actions have moved down the rail.
      final compare = tester.getRect(find.byIcon(Icons.compare));
      expect(compare.top, greaterThan(60));
    });
  });

  group('portrait', () {
    testWidgets('keeps the header across the top and the rail on the right',
        (tester) async {
      await mount(tester, _portraitPhone);
      final back = tester.getRect(find.byIcon(Icons.arrow_back));
      final fps = tester.getRect(find.byIcon(Icons.shutter_speed));
      // One row along the top.
      expect(back.top, lessThan(80));
      expect(fps.top, closeTo(back.top, 1));
      expect(fps.left, greaterThan(_portraitPhone.width / 2));
      // Title has room here, unlike a 56px rail.
      expect(find.textContaining('Javelin'), findsOneWidget);

      // Tools stacked down the right edge.
      final pen = tester.getRect(find.byIcon(Icons.draw));
      final angle = tester.getRect(find.byIcon(Icons.square_foot));
      expect(pen.left, greaterThan(_portraitPhone.width / 2));
      expect(angle.top, greaterThan(pen.top));
      expect(tester.takeException(), isNull);
    });
  });
}
