import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/utils/scrub_frames.dart';

void main() {
  group('ScrubFrames.indexForPosition', () {
    test('every frame extracted (stride 1) maps position to frame number', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      expect(frames.indexForPosition(Duration.zero), 0);
      expect(frames.indexForPosition(const Duration(seconds: 1)), 60);
      expect(
          frames.indexForPosition(const Duration(milliseconds: 500)), 30);
    });

    test('strided extraction divides the source frame by the stride', () {
      // 120 source frames at 60 fps kept as 40 images (every 3rd).
      final frames =
          ScrubFrames(dir: '/none', count: 40, stride: 3, fps: 60);
      // 0.5 s = source frame 30 -> image 10.
      expect(
          frames.indexForPosition(const Duration(milliseconds: 500)), 10);
      expect(frames.indexForPosition(Duration.zero), 0);
    });

    test('clamps within the available frames', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      // 2 s would be frame 120, but only 0..119 exist.
      expect(frames.indexForPosition(const Duration(seconds: 2)), 119);
      expect(
          frames.indexForPosition(const Duration(seconds: -1)), 0);
    });

    test('picks the still whose timestamp the position is nearest', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 60);
      // Frame 1 is stamped 16.67 ms and frame 2 at 33.33 ms, so the still
      // changes over halfway between them. Seeks aim a quarter frame
      // *before* a stamp (see positionForIndex), so a floor of the display
      // window would cover the video with the still before the one the
      // player just landed on.
      expect(frames.indexForPosition(const Duration(milliseconds: 13)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 17)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 24)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 26)), 2);
      expect(frames.indexForPosition(const Duration(milliseconds: 33)), 2);
    });

    test('an exact frame boundary is that frame', () {
      final frames =
          ScrubFrames(dir: '/none', count: 120, stride: 1, fps: 50);
      // 20 ms per frame.
      expect(frames.indexForPosition(const Duration(milliseconds: 20)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 40)), 2);
      expect(frames.indexForPosition(const Duration(milliseconds: 100)), 5);
    });

    test('seek targets map back to the still they aimed at', () {
      // The round trip that decides whether a scrub hands back the frame it
      // ended on: the position built for a still must name that still again.
      for (final stride in [1, 2, 5]) {
        final frames = ScrubFrames(
            dir: '/none', count: 500, stride: stride, fps: 60);
        for (final index in [0, 1, 7, 42, 99]) {
          expect(
              frames.indexForPosition(frames.positionForIndex(index)), index,
              reason: 'stride $stride, index $index');
        }
      }
    });

    test('a seek target sits just before the still it names', () {
      // The player renders the first frame at or after the seek position, so
      // a target inside the still's own display window lands on the *next*
      // frame — the one-frame skip at the end of every scrub.
      final frames =
          ScrubFrames(dir: '/none', count: 100, stride: 1, fps: 30);
      const frameUs = Duration.microsecondsPerSecond / 30;
      for (final index in [1, 5, 60]) {
        final us = frames.positionForIndex(index).inMicroseconds;
        expect(us, lessThan(index * frameUs), reason: 'still $index');
        expect(us, greaterThan((index - 1) * frameUs), reason: 'still $index');
      }
      // Frame 0 has nothing before it to lead from.
      expect(frames.positionForIndex(0), Duration.zero);
    });
  });

  group('ScrubFrames with real frame timestamps', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('scrubframes');
    });
    tearDown(() async => dir.delete(recursive: true));

    Future<ScrubFrames> framesWithTimes(
        List<double> times, {int stride = 1, double fps = 30}) async {
      await File('${dir.path}/times.csv').writeAsString(times.join('\n'));
      final frames = ScrubFrames(
          dir: dir.path, count: times.length, stride: stride, fps: fps);
      await frames.loadTimes('times.csv');
      return frames;
    }

    test('a clip that does not start at zero maps without a frame of lag',
        () async {
      // Every frame sits one frame-duration later than index/fps implies.
      // The fps arithmetic would name the still before the right one - the
      // "always one frame behind" handoff.
      const step = 1 / 30;
      final times = [for (var i = 0; i < 10; i++) step + i * step];
      final frames = await framesWithTimes(times);
      for (var i = 0; i < 10; i++) {
        final at = Duration(microseconds: (times[i] * 1e6).round());
        expect(frames.indexForPosition(at), i, reason: 'still $i');
      }
    });

    test('positionForIndex lands just short of the frame it names', () async {
      const step = 1 / 30;
      final times = [for (var i = 0; i < 10; i++) 0.5 + i * step];
      final frames = await framesWithTimes(times);
      for (var i = 0; i < 10; i++) {
        final seconds = frames.positionForIndex(i).inMicroseconds / 1e6;
        // Before its own frame, so the player renders that frame; after the
        // one before it, so it doesn't render that one instead.
        expect(seconds, lessThan(times[i]));
        if (i > 0) expect(seconds, greaterThan(times[i - 1]));
        expect(frames.indexForPosition(frames.positionForIndex(i)), i);
      }
    });

    test('uneven (variable rate) spacing still maps exactly', () async {
      final times = [0.0, 0.031, 0.070, 0.099, 0.140, 0.171];
      final frames = await framesWithTimes(times);
      for (var i = 0; i < times.length; i++) {
        final at = Duration(microseconds: (times[i] * 1e6).round());
        expect(frames.indexForPosition(at), i);
        expect(frames.indexForPosition(frames.positionForIndex(i)), i);
        final seconds = frames.positionForIndex(i).inMicroseconds / 1e6;
        expect(seconds, lessThanOrEqualTo(times[i]));
        if (i > 0) expect(seconds, greaterThan(times[i - 1]));
      }
      expect(frames.indexForPosition(const Duration(milliseconds: 200)), 5);
    });

    test(
        'a short, out-of-order or missing times file falls back to the '
        'arithmetic', () async {
      await File('${dir.path}/times.csv').writeAsString('0.0\n0.033');
      final short =
          ScrubFrames(dir: dir.path, count: 10, stride: 1, fps: 30);
      await short.loadTimes('times.csv');
      // Fallback: 25 ms at 30 fps is the seek target for frame 1.
      expect(short.indexForPosition(const Duration(milliseconds: 25)), 1);
      expect(short.indexForPosition(const Duration(milliseconds: 10)), 0);

      // Times in decode rather than presentation order: the searches assume
      // the list climbs, so one that doesn't is refused outright instead of
      // misaligning the stills it covers.
      await File('${dir.path}/times.csv')
          .writeAsString('0.0\n0.066\n0.033\n0.099');
      final jumbled =
          ScrubFrames(dir: dir.path, count: 4, stride: 1, fps: 30);
      await jumbled.loadTimes('times.csv');
      expect(jumbled.indexForPosition(const Duration(milliseconds: 66)), 2);

      final none = ScrubFrames(dir: dir.path, count: 10, stride: 1, fps: 30);
      await none.loadTimes('absent.csv');
      expect(none.indexForPosition(const Duration(milliseconds: 33)), 1);
    });

    test('strided stills use their own recorded times', () async {
      // Every 3rd frame of a 30 fps clip.
      final times = [for (var i = 0; i < 8; i++) i * 3 / 30];
      final frames = await framesWithTimes(times, stride: 3);
      expect(frames.indexForPosition(const Duration(milliseconds: 100)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 149)), 1);
      expect(frames.indexForPosition(const Duration(milliseconds: 200)), 2);
      for (var i = 0; i < times.length; i++) {
        expect(frames.indexForPosition(frames.positionForIndex(i)), i);
      }
    });

    test('extra times beyond the stills that exist are dropped', () async {
      const step = 1 / 30;
      await File('${dir.path}/times.csv')
          .writeAsString([for (var i = 0; i < 10; i++) i * step].join('\n'));
      final frames =
          ScrubFrames(dir: dir.path, count: 4, stride: 1, fps: 30);
      await frames.loadTimes('times.csv');
      // Only stills 0..3 exist; a position past them clamps to the last.
      expect(frames.indexForPosition(const Duration(milliseconds: 300)), 3);
    });
  });
}
