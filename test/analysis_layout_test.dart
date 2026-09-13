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
  /// placed-marks menu, the pen (one button up a column, two along a bar),
  /// undo, redo, clear, and the collapse chevron.
  List<Finder> railControlsFor(Axis axis) => [
        find.byIcon(Icons.pan_tool_alt),
        find.byIcon(Icons.draw),
        find.byKey(const ValueKey('rail-place')),
        if (axis == Axis.vertical)
          find.byKey(const ValueKey('rail-pen'))
        else ...[
          find.byKey(const ValueKey('rail-width')),
          find.byKey(const ValueKey('rail-color')),
        ],
        find.byKey(const ValueKey('rail-undo')),
        find.byKey(const ValueKey('rail-redo')),
        find.byKey(const ValueKey('rail-clear')),
        find.byKey(const ValueKey('rail-collapse')),
      ];
  final railControls = railControlsFor(Axis.vertical);
  final barControls = railControlsFor(Axis.horizontal);

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
      // One column, reading down. Centers, since a finder on an icon
      // measures the glyph and one on a button measures the slot around it.
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].center.dx, closeTo(rects.first.center.dx, 1));
        expect(rects[i].center.dy, greaterThan(rects[i - 1].center.dy));
      }
      // Hard against the right edge, chevron last and so in the corner.
      expect(rects.last.right, greaterThan(_landscapePhone.width * 0.9));
      expect(rects.last.bottom, greaterThan(_landscapePhone.height * 0.75));
      for (final control in railControls) {
        expectOnScreen(tester, control, _landscapePhone, what: '$control');
      }
    });

    testWidgets('shrinks the last few pixels rather than breaking in two',
        (tester) async {
      await mount(tester, _landscapePhone);
      // 305 of tools into 300 of usable height: a scale nobody sees, and
      // one column rather than two.
      final undo = tester.getRect(find.byKey(const ValueKey('rail-undo')));
      expect(undo.width, closeTo(40, 2));
      expect(undo.height, closeTo(36, 2));
    });

    testWidgets('the tools keep to the right edge of the frame',
        (tester) async {
      await mount(tester, _landscapePhone);
      // Whatever height the column takes, it never leaves the last sliver
      // of the frame: the throw is everywhere left of it.
      for (final control in railControls) {
        expect(tester.getRect(control).left,
            greaterThan(_landscapePhone.width * 0.85),
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

      // Tools in a row along the bottom, in the letterbox under the frame.
      final pen = tester.getRect(find.byIcon(Icons.draw));
      final clear = tester.getRect(find.byKey(const ValueKey('rail-clear')));
      expect(clear.center.dy, closeTo(pen.center.dy, 1));
      expect(clear.center.dx, greaterThan(pen.center.dx));
      final video = tester.getRect(find.byType(DrawingCanvas));
      expect(pen.top, greaterThan(video.bottom),
          reason: 'the tools are over the frame');
      // Upright there is width for a button each, which is a tap closer to
      // whichever half of the pen is being changed.
      expect(find.byKey(const ValueKey('rail-width')), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-color')), findsOneWidget);
      expect(find.byKey(const ValueKey('rail-pen')), findsNothing);
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
    testWidgets('still holds the tools in one row', (tester) async {
      await mount(tester, _narrowPhone);
      final rects = [for (final c in barControls) tester.getRect(c)];
      final row = rects.first.center.dy;
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].center.dy, closeTo(row, 1));
        expect(rects[i].center.dx, greaterThan(rects[i - 1].center.dx));
      }
      // 377 of tools into 352: a shrink of a few percent, not a second row.
      expect(tester.getRect(find.byKey(const ValueKey('rail-undo'))).width,
          closeTo(40, 3));
      expect(rects.last.right, greaterThan(_narrowPhone.width - 12));
      for (final control in barControls) {
        expectOnScreen(tester, control, _narrowPhone, what: '$control');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row sits between the frame and the scrubber',
        (tester) async {
      await mount(tester, _narrowPhone);
      final video = tester.getRect(find.byType(DrawingCanvas));
      final slider = tester.getRect(find.byType(Slider));
      for (final control in barControls) {
        final rect = tester.getRect(control);
        expect(rect.top, greaterThan(video.bottom),
            reason: '$control is over the frame');
        expect(rect.bottom, lessThanOrEqualTo(slider.top),
            reason: '$control is over the scrubber');
      }
      // Hard against the scrubber rather than floating at a guessed inset.
      final bar = barControls
          .map((c) => tester.getRect(c).bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(slider.top - bar, lessThan(24));
    });
  });
}
