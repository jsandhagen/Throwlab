import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:throwlab/utils/frame_seeker.dart';

/// Records seeks instead of talking to a platform player. Completing a
/// seek updates [value.position] the same way the real controller does.
class _FakeController extends VideoPlayerController {
  _FakeController() : super.file(File('missing.mp4')) {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 10),
      isInitialized: true,
    );
  }

  final seeks = <Duration>[];
  int platformPositionCalls = 0;

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<Duration?> get position async {
    platformPositionCalls++;
    return value.position;
  }
}

/// One frame at 30 fps, matching FrameSeeker's rounding.
const frame = Duration(microseconds: 33333);

extension on _FakeController {
  /// Seeks are spaced ~50 ms apart; waits until no new seek lands.
  Future<void> settle() async {
    var count = -1;
    while (count != seeks.length) {
      count = seeks.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
}

void main() {
  test('seekBy lands a small step directly', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller, fps: 30);
    await seeker.seekBy(frame);
    await controller.settle();
    expect(controller.seeks, [frame]);
  });

  test('seekTo jumps straight to the target', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller, fps: 30);
    seeker.seekTo(const Duration(seconds: 5));
    await controller.settle();
    expect(controller.seeks, [const Duration(seconds: 5)]);
  });

  test('a large scrub delta chases through intermediate frames', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller, fps: 30);
    await seeker.seekBy(frame * 30);
    await controller.settle();

    // Ends exactly on the requested frame...
    expect(controller.seeks.last, frame * 30);
    // ...renders more than one step on the way there...
    expect(controller.seeks.length, greaterThan(3));
    // ...never advances more than 3 frames per seek once chasing...
    var previous = controller.seeks.first;
    for (final seek in controller.seeks.skip(1)) {
      expect((seek - previous).inMicroseconds,
          lessThanOrEqualTo(frame.inMicroseconds * 3));
      previous = seek;
    }
    // ...and the first seek honours the lag clamp (24 frames behind the
    // 30-frame goal is 6 frames in).
    expect(controller.seeks.first, frame * 6);
  });

  test('chasing works backwards too', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller, fps: 30);
    seeker.seekTo(frame * 40);
    await controller.settle();
    controller.seeks.clear();

    await seeker.seekBy(-frame * 10);
    await controller.settle();
    expect(controller.seeks.last, frame * 30);
    var previous = frame * 40;
    for (final seek in controller.seeks) {
      expect((previous - seek).inMicroseconds,
          lessThanOrEqualTo(frame.inMicroseconds * 3));
      expect(previous - seek, isNot(Duration.zero));
      previous = seek;
    }
  });

  test('without a known fps every seek jumps directly', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller);
    await seeker.seekBy(frame * 30);
    await controller.settle();
    expect(controller.seeks, [frame * 30]);
  });

  test('freshPosition skips the platform once a seek has landed', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller, fps: 30);
    await seeker.seekBy(frame);
    await controller.settle();
    final callsAfterScrub = controller.platformPositionCalls;

    expect(await seeker.freshPosition(), frame);
    // Later relative steps chain off the cached target with no fetch.
    await seeker.seekBy(frame);
    await controller.settle();
    expect(controller.platformPositionCalls, callsAfterScrub);
    expect(controller.seeks.last, frame * 2);
  });

  test('seeks clamp to the clip', () async {
    final controller = _FakeController();
    final seeker = FrameSeeker(controller, fps: 30);
    await seeker.seekBy(-frame * 5);
    await controller.settle();
    expect(controller.seeks, [Duration.zero]);
  });
}
