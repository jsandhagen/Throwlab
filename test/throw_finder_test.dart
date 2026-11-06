import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/services/video_optimizer.dart';
import 'package:throwlab/utils/throw_finder.dart';
import 'package:throwlab/widgets/found_throw.dart';

/// Finding the throw in a clip an athlete filmed of themselves: the motion
/// read off the frames, the walk at each end set aside, and the window kept
/// around the burst between them.
void main() {
  const rate = motionSampleRate;

  /// A clip's motion as runs of (seconds, how much of the frame moved), at
  /// the scan's own rate.
  List<double> clip(List<(double, double)> runs, {double slowdown = 1}) => [
        for (final (seconds, level) in runs)
          for (var i = 0; i < (seconds * slowdown * rate).round(); i++) level,
      ];

  /// The clip this is for: record, walk away (filling the frame, then less
  /// of it), stand in the ring, throw, fetch the implement, stand, and walk
  /// back up to the camera to stop it.
  final selfFilmed = clip([
    (2, 0.30),
    (3, 0.08),
    (6, 0.002),
    (1.2, 0.05),
    (0.4, 0.004),
    (1.0, 0.06),
    (6, 0.012),
    (20, 0.002),
    (4, 0.15),
    (2, 0.40),
  ]);
  // The throw's own motion runs from 11 s to 13.6 s, and is strongest from
  // 12.6 s.

  group('motion', () {
    Uint8List frames(int count, int Function(int frame, int x, int y) gray,
        {int side = 8}) {
      final bytes = Uint8List(count * side * side);
      for (var f = 0; f < count; f++) {
        for (var y = 0; y < side; y++) {
          for (var x = 0; x < side; x++) {
            bytes[f * side * side + y * side + x] = gray(f, x, y);
          }
        }
      }
      return bytes;
    }

    test('a still picture has not moved', () {
      final still =
          motionActivity(frames(4, (_, x, y) => 100 + x + y), side: 8);
      expect(still, everyElement(0));
    });

    test('counts the part of the frame that changed', () {
      // A two-by-two block crossing a flat field a column at a time: each
      // step it leaves two pixels and takes two more.
      final moving = motionActivity(
          frames(4, (f, x, y) => (x == f || x == f + 1) && y < 2 ? 220 : 90),
          side: 8);
      expect(moving.length, 4);
      expect(moving[1], closeTo(4 / 64, 1e-9));
      // The first sample has nothing before it and reads as the next.
      expect(moving[0], moving[1]);
    });

    test('a phone walking its exposure is not motion', () {
      final darkening =
          motionActivity(frames(4, (f, x, y) => 160 - 30 * f), side: 8);
      expect(darkening, everyElement(0));
    });

    test('is read off a gray postage stamp of the clip', () {
      final command = VideoOptimizer.motionCommand('/in.mp4', '/out.gray');
      expect(command, contains('-skip_loop_filter all'));
      expect(command, contains('fps=15'));
      expect(command, contains('scale=$motionSide:$motionSide'));
      expect(command, contains('format=gray'));
      expect(command, endsWith('-f rawvideo "/out.gray"'));
    });
  });

  group('finding the throw', () {
    test('keeps the throw and not the walk either side of it', () {
      final found =
          findThrow(selfFilmed, rate: rate, event: ThrowEvent.shotPut)!;
      expect(found.duration, closeTo(45.6, 0.1));
      expect(found.peak, inInclusiveRange(12.6, 13.6));
      // The whole of the throw's motion, and a second either side of it.
      expect(found.start, lessThanOrEqualTo(10.5));
      expect(found.end, greaterThanOrEqualTo(14.4));
      // Not the walk away, and not the fetch and the walk back.
      expect(found.start, greaterThan(5));
      expect(found.end, lessThan(19));
      expect(found.length, lessThan(found.duration / 3));
    });

    test('leads in further for an event with a longer run-up', () {
      final shot =
          findThrow(selfFilmed, rate: rate, event: ThrowEvent.shotPut)!;
      final javelin =
          findThrow(selfFilmed, rate: rate, event: ThrowEvent.javelin)!;
      expect(javelin.start, lessThan(shot.start));
      expect(javelin.peak - javelin.start, greaterThanOrEqualTo(5 - 1e-9));
    });

    test('stops short of the walk out to fetch the implement', () {
      final found =
          findThrow(selfFilmed, rate: rate, event: ThrowEvent.discus)!;
      final timing = throwTiming(ThrowEvent.discus);
      expect(found.end - found.peak,
          lessThanOrEqualTo(timing.maxFollow + 1 + 1 / rate));
    });

    test('finds a throw in a clip that starts already still', () {
      // Started with a remote, or by somebody who stepped straight out of
      // shot: nothing at the start to set aside.
      final remote = clip([
        (8, 0.002),
        (1.5, 0.05),
        (12, 0.002),
        (3, 0.3),
      ]);
      final found = findThrow(remote, rate: rate, event: ThrowEvent.shotPut)!;
      expect(found.peak, inInclusiveRange(8, 9.5));
    });

    test('says nothing about a camera held in a hand', () {
      // The picture never settles, so nothing in it can be told from the
      // walk at either end — and a clip somebody was holding is one they
      // stopped themselves.
      final handheld = clip([(10, 0.2), (2, 0.5), (20, 0.25)]);
      expect(findThrow(handheld, rate: rate, event: ThrowEvent.discus), isNull);
    });

    test('says nothing when nobody threw', () {
      final empty = clip([(2, 0.3), (30, 0.002), (2, 0.3)]);
      expect(findThrow(empty, rate: rate, event: ThrowEvent.shotPut), isNull);
    });

    test('leaves a clip somebody already stopped by hand alone', () {
      final short = clip([(2, 0.002), (1, 0.06), (4, 0.002)]);
      expect(findThrow(short, rate: rate, event: ThrowEvent.shotPut), isNull);
    });

    test('measures a throw in real seconds in a slow-motion clip', () {
      // 240 fps stored to play at 30: every real second is eight of file.
      final slow = clip([
        (2, 0.30),
        (6, 0.002),
        (1.0, 0.06),
        (8, 0.002),
        (2, 0.30),
      ], slowdown: 8);
      final found =
          findThrow(slow, rate: rate, event: ThrowEvent.shotPut, slowdown: 8)!;
      expect(found.peak, inInclusiveRange(8 * 8, 9 * 8));
      // The shot's two and a half seconds of lead-in, eight times over.
      expect(found.peak - found.start, greaterThanOrEqualTo(2.5 * 8 - 0.1));
      expect(found.length, lessThan(found.duration / 2));
    });

    test('lands on whole frames of the clip', () {
      final found =
          findThrow(selfFilmed, rate: rate, event: ThrowEvent.shotPut)!;
      final range = found.toRange(const Duration(milliseconds: 45600), 30);
      expect(range.frameCount, 1368);
      expect(range.first, (found.start * 30).floor());
      expect(range.end.inMicroseconds / 1e6, closeTo(found.end, 1 / 30 + 1e-6));
      expect(range.isWhole, isFalse);
    });
  });

  testWidgets('asks before cutting, over the frame it picked', (tester) async {
    const window =
        ThrowWindow(start: 70.2, end: 79.6, peak: 74.4, duration: 123.4);
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                answer = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const FoundThrowSheet(
                    window: window,
                    stills: [null, null, null],
                    keepsOriginal: false,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Found the throw'), findsOneWidget);
    expect(find.text('At 1:14 — keeps 9.4 s of 2:03.'), findsOneWidget);
    expect(find.text('The throw'), findsOneWidget);
    expect(find.text('The rest of the recording is not kept.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('found-cut')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('found-keep-whole')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
