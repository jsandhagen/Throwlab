import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';

import 'analysis_harness.dart';

/// A landscape phone: ~360 logical pixels of height, which the drawing rail
/// used to run off the top of.
const _landscapePhone = Size(740, 360);
const _portraitPhone = Size(400, 800);

/// A narrow phone held upright — 360 logical pixels across, which is the
/// common Android width and is too little for the tools in one row.
const _narrowPhone = Size(360, 760);

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

  /// Everything the rail shows at rest, in order along it: scrub, pen, the
  /// shape menu, width, color, undo, redo, clear, and the collapse chevron.
  final railControls = <Finder>[
    find.byIcon(Icons.pan_tool_alt),
    find.byIcon(Icons.draw),
    find.byKey(const ValueKey('rail-shapes')),
    find.byKey(const ValueKey('rail-width')),
    find.byKey(const ValueKey('rail-color')),
    find.byKey(const ValueKey('rail-undo')),
    find.byKey(const ValueKey('rail-redo')),
    find.byKey(const ValueKey('rail-clear')),
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
      expect(find.byKey(const ValueKey('rail-undo')), findsNothing);
      expect(find.byKey(const ValueKey('rail-clear')), findsNothing);
      expect(collapse, findsOneWidget);
      expectOnScreen(tester, collapse, _landscapePhone, what: 'collapsed rail');

      await tester.tap(collapse);
      await tester.pump();
      for (final control in railControls) {
        expect(control, findsOneWidget);
      }
    });

    testWidgets('the tools run up the right edge, not across the bottom',
        (tester) async {
      await mount(tester, _landscapePhone);
      final rects = [for (final c in railControls) tester.getRect(c)];
      // Two columns — 341 of tools into 300 of usable height — so the pen
      // reads down the first and the drawing's own controls down the
      // second. Centers, since a finder on an icon measures the glyph and
      // one on a button measures the slot around it.
      final columns = rects.map((r) => r.center.dx).toSet();
      expect(columns, hasLength(2));
      final pen = rects.take(5).toList();
      for (var i = 1; i < pen.length; i++) {
        expect(pen[i].center.dx, closeTo(pen.first.center.dx, 1));
        expect(pen[i].center.dy, greaterThan(pen[i - 1].center.dy));
      }
      // Full-size buttons: growing a second column is what that is for.
      expect(tester.getSize(find.byKey(const ValueKey('rail-clear'))),
          const Size(40, 36));
      // Hard against the right edge, with the chevron last and so in the
      // corner.
      final collapse = rects.last;
      expect(collapse.right, greaterThan(_landscapePhone.width * 0.9));
      expect(collapse.center.dx, greaterThan(pen.first.center.dx));
      expect(collapse.bottom, greaterThan(_landscapePhone.height * 0.75));
      for (final control in railControls) {
        expectOnScreen(tester, control, _landscapePhone, what: '$control');
      }
    });

    testWidgets('the tools keep to the corner, not the length of the edge',
        (tester) async {
      await mount(tester, _landscapePhone);
      // Two short columns rather than one long one: the top half of the
      // frame — and everything left of the last 12% of it — is the video's.
      for (final control in railControls) {
        final rect = tester.getRect(control);
        expect(rect.top, greaterThan(_landscapePhone.height * 0.25),
            reason: '$control is up in the frame');
        expect(rect.left, greaterThan(_landscapePhone.width * 0.85),
            reason: '$control is out in the frame');
      }
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
    testWidgets('keeps the header across the top and the tools along the '
        'bottom', (tester) async {
      await mount(tester, _portraitPhone);
      final back = tester.getRect(find.byIcon(Icons.arrow_back));
      final fps = tester.getRect(find.byIcon(Icons.shutter_speed));
      // One row along the top.
      expect(back.top, lessThan(80));
      expect(fps.top, closeTo(back.top, 1));
      expect(fps.left, greaterThan(_portraitPhone.width / 2));
      // Title has room here, unlike a 56px rail.
      expect(find.textContaining('Javelin'), findsOneWidget);

      // Tools in a row along the bottom. Upright, a widescreen clip is
      // letterboxed into a band of black under it, and the bar sits in the
      // band rather than over any of the frame.
      final pen = tester.getRect(find.byIcon(Icons.draw));
      final clear = tester.getRect(find.byKey(const ValueKey('rail-clear')));
      expect(clear.center.dy, closeTo(pen.center.dy, 1));
      expect(clear.center.dx, greaterThan(pen.center.dx));
      final video = tester.getRect(find.byType(DrawingCanvas));
      expect(pen.top, greaterThan(video.bottom),
          reason: 'the tools are over the frame');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the frame carries no caption under it', (tester) async {
      await mount(tester, _portraitPhone);
      // The calibration reference is stated on the measure sheet and on the
      // card in the library; under the frame it only cost the band the
      // tools sit in.
      expect(find.textContaining('drag video to scrub'), findsNothing);
      expect(find.textContaining('Ref:'), findsNothing);
    });
  });

  group('a narrow phone', () {
    testWidgets('grows the tools a second row rather than shrinking them',
        (tester) async {
      await mount(tester, _narrowPhone);
      final rects = [for (final c in railControls) tester.getRect(c)];
      final rows = rects.map((r) => r.center.dy).toSet();
      expect(rows, hasLength(2), reason: 'the tools should be on two rows');

      // Split where the bar is already grouped: what a tool is picked with
      // above, what is done to the drawing below.
      final top = rects.first.center.dy;
      expect(rects.take(5).every((r) => r.center.dy == top), isTrue);
      expect(rects.skip(5).every((r) => r.center.dy != top), isTrue);

      // Full-size buttons, not a squeezed row: what the second row is for.
      for (final key in ['rail-undo', 'rail-redo', 'rail-clear']) {
        expect(tester.getSize(find.byKey(ValueKey(key))),
            const Size(40, 36), reason: key);
      }
      // The chevron is still last, and so still in the corner.
      final collapse = tester.getRect(railControls.last);
      expect(collapse.center.dy, greaterThan(top));
      expect(collapse.right, greaterThan(_narrowPhone.width - 12));
      for (final control in railControls) {
        expectOnScreen(tester, control, _narrowPhone, what: '$control');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the two rows still clear the frame', (tester) async {
      await mount(tester, _narrowPhone);
      final video = tester.getRect(find.byType(DrawingCanvas));
      for (final control in railControls) {
        expect(tester.getRect(control).top, greaterThan(video.bottom),
            reason: '$control is over the frame');
      }
    });
  });
}
