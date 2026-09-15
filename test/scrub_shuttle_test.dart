import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/utils/frame_seeker.dart';
import 'package:throwlab/utils/scrub_frames.dart';
import 'package:throwlab/utils/scrub_shuttle.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'analysis_harness.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_shuttle');
    VideoPlayerPlatform.instance =
        FakeVideoPlayerPlatform(const Size(1920, 1080));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('release takes the still down so a video can play under it',
      (tester) async {
    final file = File('${temp.path}/clip.mp4')..writeAsBytesSync(<int>[0]);
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    final shuttle = ScrubShuttle(
      controller: controller,
      seeker: FrameSeeker(controller),
      fps: 30,
      vsync: const TestVSync(),
      frames: ScrubFrames(dir: temp.path, count: 120, stride: 1, fps: 30),
    );
    addTearDown(() {
      shuttle.dispose();
      controller.dispose();
    });

    shuttle.begin();
    shuttle.by(10);
    shuttle.end();
    // The still is held across the handoff, waiting for the decoder to catch
    // up — which is right after a scrub and wrong once the clip is running.
    expect(shuttle.overlayVisible, isTrue);

    shuttle.release();
    expect(shuttle.overlayVisible, isFalse);
    expect(shuttle.busy, isFalse);
  });

  testWidgets('release on an idle shuttle does nothing', (tester) async {
    final file = File('${temp.path}/clip.mp4')..writeAsBytesSync(<int>[0]);
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    final shuttle = ScrubShuttle(
      controller: controller,
      seeker: FrameSeeker(controller),
      fps: 30,
      vsync: const TestVSync(),
      frames: ScrubFrames(dir: temp.path, count: 120, stride: 1, fps: 30),
    );
    addTearDown(() {
      shuttle.dispose();
      controller.dispose();
    });

    var notified = 0;
    shuttle.addListener(() => notified++);
    shuttle.release();

    expect(notified, 0);
    expect(shuttle.overlayVisible, isFalse);
  });
}
