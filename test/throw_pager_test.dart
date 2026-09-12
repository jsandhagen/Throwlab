import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/widgets/throw_picker.dart';

import 'analysis_harness.dart';

const _landscapePhone = Size(740, 360);
const _portraitPhone = Size(400, 800);

/// Paging between the throws of a session without a trip back to the library.
void main() {
  late Directory temp;
  late List<ThrowVideo> session;

  setUp(() async {
    // A clean store each time: the strip remembers whether it was put away,
    // and one test putting it away would otherwise hide it for the rest.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
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

  /// Which throw the screen is on. Read off the screen rather than off its
  /// title, which names the throw and says nothing about the set — where it
  /// sits is answered by the strip of stills, and spending the title on it
  /// said nothing a coach needed.
  String openThrow(WidgetTester tester) =>
      tester.widget<AnalysisScreen>(find.byType(AnalysisScreen)).video.id;

  /// The stills of the set, in order.
  Finder stills() => find.byType(ThrowThumbnail);

  testWidgets('the title names the throw, not where it sits in the session',
      (tester) async {
    await mount(tester, video: throwNumber(2));
    // The header names the implement, which is what the analyzer measures
    // against — the harness throws an 800 g javelin.
    expect(find.text('Javelin · 800 g'), findsOneWidget);
    expect(find.textContaining('of 3'), findsNothing);
  });

  testWidgets('the set is ordered by when it was thrown, not by library order',
      (tester) async {
    // v1 comes last in the list handed over but was recorded first, so it is
    // the first still — otherwise the order would flip whenever the library
    // re-sorted.
    await mount(tester, video: throwNumber(1));
    expect(stills(), findsNWidgets(3));
    await tester.tap(stills().first);
    await pumpFrames(tester, 12);
    expect(openThrow(tester), 'v1');
  });

  testWidgets('a throw opened on its own has no pager', (tester) async {
    await mount(tester, video: throwNumber(2), siblings: const []);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('Javelin · 800 g'), findsOneWidget);
  });

  testWidgets('the set includes the open throw even when it is not passed in',
      (tester) async {
    await mount(tester, video: throwNumber(2), siblings: [throwNumber(3)]);
    expect(stills(), findsNWidgets(2));
  });

  testWidgets('tapping the title opens the throw itself', (tester) async {
    await mount(tester, video: throwNumber(2));
    await tester.tap(find.byKey(const ValueKey('throw-title')));
    await pumpFrames(tester, 30);
    // The library's own sheet: when it was taken, how far it went, what was
    // written down, and the edits for each.
    expect(find.text('Add distance'), findsOneWidget);
    expect(find.text('Add note'), findsOneWidget);
  });

  group('portrait', () {
    testWidgets('the session shows on top, and puts away on its handle',
        (tester) async {
      await mount(tester, video: throwNumber(2));
      // Shown to begin with: it is the first thing wanted on opening a
      // throw out of a session.
      expect(stills(), findsNWidgets(3));

      await tester.tap(find.byKey(const ValueKey('throw-strip-handle')));
      await pumpFrames(tester, 20);
      expect(stills(), findsNothing);
      // The handle stays, so there is something to pull it back down by.
      expect(find.byKey(const ValueKey('throw-strip-handle')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('throw-strip-handle')));
      await pumpFrames(tester, 20);
      expect(stills(), findsNWidgets(3));
    });

    testWidgets('a throw on its own has no strip and no handle',
        (tester) async {
      await mount(tester, video: throwNumber(2), siblings: const []);
      expect(stills(), findsNothing);
      expect(find.byKey(const ValueKey('throw-strip-handle')), findsNothing);
    });

    testWidgets('the strip hangs under the header, over the frame',
        (tester) async {
      await mount(tester, video: throwNumber(2));
      final back = tester.getRect(find.byIcon(Icons.arrow_back));
      final still = tester.getRect(stills().first);
      expect(still.top, greaterThan(back.bottom));
      expect(still.bottom, lessThan(_portraitPhone.height / 2));
    });

    testWidgets('put away, it stays away on the next throw', (tester) async {
      await mount(tester, video: throwNumber(2));
      await tester.tap(find.byKey(const ValueKey('throw-strip-handle')));
      await pumpFrames(tester, 20);
      expect(stills(), findsNothing);

      // Paging replaces the screen, so without remembering it the strip
      // would drop back down under the finger that just put it away.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await pumpFrames(tester, 30);
      expect(openThrow(tester), 'v3');
      expect(stills(), findsNothing);
    });

    testWidgets('tapping next moves on to the following throw', (tester) async {
      await mount(tester, video: throwNumber(2));
      await tester.tap(find.byIcon(Icons.chevron_right));
      await pumpFrames(tester, 12);
      expect(openThrow(tester), 'v3');
    });

    testWidgets('tapping a still in the strip opens that throw',
        (tester) async {
      await mount(tester, video: throwNumber(1));
      await tester.tap(stills().last);
      await pumpFrames(tester, 12);
      expect(openThrow(tester), 'v3');
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
      final rail = tester.getRect(find.byKey(const ValueKey('rail-undo')));
      expect(next.left, lessThan(_landscapePhone.width / 4),
          reason: 'the pager belongs on the left, with Back');
      expect(rail.left, greaterThan(_landscapePhone.width / 4),
          reason: 'the drawing bar starts clear of the header rail');
      expect(next.overlaps(rail), isFalse);
    });
  });
}
