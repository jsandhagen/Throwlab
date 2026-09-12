import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
import 'package:throwlab/widgets/drawing_rail.dart';

/// How the rail fits itself to the room it is given: shrink a hair to stay
/// one run, break into two only where shrinking would leave a target a
/// thumb misses.
void main() {
  const controls = [
    'rail-place',
    'rail-pen',
    'rail-undo',
    'rail-redo',
    'rail-clear',
    'rail-collapse',
  ];

  Future<void> mountRail(WidgetTester tester,
      {required Axis axis, required Size box}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: Align(
              alignment: Alignment.bottomRight,
              child: DrawingRail(controller: DrawingController(), axis: axis),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  List<Rect> rectsOf(WidgetTester tester) =>
      [for (final key in controls) tester.getRect(find.byKey(ValueKey(key)))];

  /// Distinct positions across the rail — one per run.
  int runsAcross(List<Rect> rects, Axis axis) => rects
      .map((r) => (axis == Axis.vertical ? r.center.dx : r.center.dy).round())
      .toSet()
      .length;

  group('up an edge', () {
    testWidgets('takes one column where there is room', (tester) async {
      await mountRail(tester, axis: Axis.vertical, box: const Size(200, 400));
      final rects = rectsOf(tester);
      expect(runsAcross(rects, Axis.vertical), 1);
      // Nothing to shrink for, so the buttons are the size they are drawn.
      expect(rects.last.width, 40);
      expect(rects.last.height, 36);
    });

    testWidgets('shrinks a few pixels rather than breaking in two',
        (tester) async {
      // The 300 a landscape phone leaves above the transport, against the
      // 305 the tools want.
      await mountRail(tester, axis: Axis.vertical, box: const Size(200, 300));
      final rects = rectsOf(tester);
      expect(runsAcross(rects, Axis.vertical), 1);
      expect(rects.last.height, lessThan(36));
      // ...and by so little that nobody sees it.
      expect(rects.last.height, greaterThan(34));
    });

    testWidgets('breaks into two columns where shrinking would not save it',
        (tester) async {
      await mountRail(tester, axis: Axis.vertical, box: const Size(200, 200));
      final rects = rectsOf(tester);
      expect(runsAcross(rects, Axis.vertical), 2);
      // Two columns at full size beats one at a size a thumb misses.
      expect(rects.last.width, 40);
      expect(rects.last.height, 36);
      // The chevron is last, so it is still in the corner.
      expect(rects.last.right, greaterThanOrEqualTo(rects[0].right));
      expect(rects.last.bottom, greaterThanOrEqualTo(rects[0].bottom));
    });
  });

  group('along an edge', () {
    testWidgets('takes one row on the commonest Android width',
        (tester) async {
      // 360 logical across, less the 4 of inset each side.
      await mountRail(tester, axis: Axis.horizontal, box: const Size(352, 200));
      final rects = rectsOf(tester);
      expect(runsAcross(rects, Axis.horizontal), 1);
      expect(rects.last.width, 40);
    });

    testWidgets('breaks into two rows on something narrower than a phone',
        (tester) async {
      await mountRail(tester, axis: Axis.horizontal, box: const Size(240, 200));
      final rects = rectsOf(tester);
      expect(runsAcross(rects, Axis.horizontal), 2);
      expect(rects.last.width, 40);
    });
  });

  testWidgets('collapsed, it is one button whatever the room', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 120,
          height: 120,
          child: DrawingRail(
            controller: DrawingController(),
            initiallyOpen: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('rail-collapse')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-pen')), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('rail-collapse'))).width,
        40);
  });
}
