import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/widgets/throw_picker.dart';

import 'analysis_harness.dart';

const _landscapePhone = Size(740, 360);
const _portraitPhone = Size(400, 800);

/// Paging between the throws of a session without a trip back to the library.
void main() {
  late Directory temp;
  late List<ThrowVideo> session;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    // Deliberately built newest-first, the order the library holds them in:
    // the screen is expected to re-order the set into throwing order.
    session = [
      for (var i = 3; i >= 1; i--)
        testVideo(temp, id: 'v$i', importedAt: DateTime(2026, 1, i)),
    ];
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> mount(
    WidgetTester tester, {
    required ThrowVideo video,
    Size screen = _portraitPhone,
    List<ThrowVideo>? siblings,
  }) =>
      mountAnalysisScreen(
        tester,
        video: video,
        screen: screen,
        videoSize: const Size(1920, 1080),
        siblings: siblings ?? session,
      );

  ThrowVideo throwNumber(int n) => session.firstWhere((v) => v.id == 'v$n');

  IconButton pager(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon).first);

  testWidgets('the title says where the throw sits in the session',
      (tester) async {
    await mount(tester, video: throwNumber(2));
    expect(find.textContaining('2 of 3'), findsOneWidget);
  });

  testWidgets('the set is ordered by when it was thrown, not by library order',
      (tester) async {
    // v1 comes last in the list handed over but was recorded first, so it is
    // throw 1 — otherwise the numbering would flip whenever the library
    // re-sorted.
    await mount(tester, video: throwNumber(1));
    expect(find.textContaining('1 of 3'), findsOneWidget);
  });

  testWidgets('a throw opened on its own has no pager', (tester) async {
    await mount(tester, video: throwNumber(2), siblings: const []);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    // The header names the implement, which is what the analyzer measures
    // against — the harness throws an 800 g javelin.
    expect(find.text('Javelin · 800 g'), findsOneWidget);
  });

  testWidgets('the set includes the open throw even when it is not passed in',
      (tester) async {
    await mount(tester, video: throwNumber(2), siblings: [throwNumber(3)]);
    expect(find.textContaining('1 of 2'), findsOneWidget);
  });

  group('portrait', () {
    testWidgets('the filmstrip shows a still per throw', (tester) async {
      await mount(tester, video: throwNumber(2));
      expect(find.byType(ThrowThumbnail), findsNWidgets(3));
    });

    testWidgets('tapping next moves on to the following throw',
        (tester) async {
      await mount(tester, video: throwNumber(2));
      await tester.tap(find.byIcon(Icons.chevron_right));
      await pumpFrames(tester, 12);
      expect(find.textContaining('3 of 3'), findsOneWidget);
    });

    testWidgets('tapping a still in the strip opens that throw',
        (tester) async {
      await mount(tester, video: throwNumber(1));
      await tester.tap(find.byType(ThrowThumbnail).last);
      await pumpFrames(tester, 12);
      expect(find.textContaining('3 of 3'), findsOneWidget);
    });

    testWidgets('the first throw has nowhere earlier to go', (tester) async {
      await mount(tester, video: throwNumber(1));
      expect(pager(tester, Icons.chevron_left).onPressed, isNull);
      expect(pager(tester, Icons.chevron_right).onPressed, isNotNull);
    });

    testWidgets('the last throw does not wrap back to the first',
        (tester) async {
      await mount(tester, video: throwNumber(3));
      expect(pager(tester, Icons.chevron_left).onPressed, isNotNull);
      expect(pager(tester, Icons.chevron_right).onPressed, isNull);
    });
  });

  group('landscape', () {
    testWidgets('pages from the header rail, with no filmstrip',
        (tester) async {
      await mount(tester, video: throwNumber(2), screen: _landscapePhone);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      // A strip would cost height the frame needs.
      expect(find.byType(ThrowThumbnail), findsNothing);
    });

    testWidgets('the pager keeps clear of the drawing rail', (tester) async {
      await mount(tester, video: throwNumber(2), screen: _landscapePhone);
      final next = tester.getRect(find.byIcon(Icons.chevron_right));
      final rail = tester.getRect(find.byIcon(Icons.undo));
      expect(next.left, lessThan(_landscapePhone.width / 4),
          reason: 'the pager belongs on the left, with Back');
      expect(rail.left, greaterThan(_landscapePhone.width * 0.8),
          reason: 'the drawing rail still owns the right edge');
      expect(next.overlaps(rail), isFalse);
    });
  });
}
