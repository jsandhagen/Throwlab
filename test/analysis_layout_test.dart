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

  /// Everything the rail shows at rest, top to bottom: scrub, pen, the
  /// shape menu, width, colour, undo, more, and the collapse chevron.
  final railControls = <Finder>[
    find.byIcon(Icons.pan_tool_alt),
    find.byIcon(Icons.draw),
    find.byKey(const ValueKey('rail-shapes')),
    find.byKey(const ValueKey('rail-width')),
    find.byKey(const ValueKey('rail-colour')),
    find.byIcon(Icons.undo),
    find.byKey(const ValueKey('rail-more')),
    find.byKey(const ValueKey('rail-collapse')),
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
    testWidgets('the whole rail is on screen, not scrolled off the top',
        (tester) async {
      await mount(tester, _landscapePhone);
      for (final control in railControls) {
        expectOnScreen(tester, control, _landscapePhone, what: '$control');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the collapse button hides the tools and brings them back',
        (tester) async {
      await mount(tester, _landscapePhone);
      final collapse = find.byKey(const ValueKey('rail-collapse'));

      await tester.tap(collapse);
      await tester.pump();
      // Only the collapse button is left, still in the bottom-right corner.
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byKey(const ValueKey('rail-more')), findsNothing);
      expect(collapse, findsOneWidget);
      expectOnScreen(tester, collapse, _landscapePhone, what: 'collapsed rail');

      await tester.tap(collapse);
      await tester.pump();
      for (final control in railControls) {
        expect(control, findsOneWidget);
      }
    });

    testWidgets('the rail stays a column down the right edge', (tester) async {
      await mount(tester, _landscapePhone);
      final first = tester.getRect(railControls.first);
      final last = tester.getRect(railControls.last);
      expect(last.top, greaterThan(first.top));
      expect(first.left, greaterThan(_landscapePhone.width * 0.8));
      expect(last.left, greaterThan(_landscapePhone.width * 0.8));
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
      final more = tester.getRect(find.byKey(const ValueKey('rail-more')));
      expect(pen.left, greaterThan(_portraitPhone.width / 2));
      expect(more.top, greaterThan(pen.top));
      expect(tester.takeException(), isNull);
    });
  });
}
