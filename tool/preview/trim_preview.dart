// Renders the trim screen to PNGs: the whole clip as it opens, and the same
// clip with both ends brought in and the release inside what is kept, upright
// and on its side. It asserts nothing.
//
//   flutter test --update-goldens tool/preview/trim_preview.dart
//
// The player is the widget tests' in-memory stand-in, so the frame is a flat
// blue rectangle; the strip under it is the sample library's stills, filed
// where a clip's scrub frames would be.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/trim_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../test/analysis_harness.dart';
import 'harness.dart';
import 'sample_library.dart';

const _out = '../../build/preview';

void main() {
  late Directory temp;
  late ThrowVideo video;
  late List<String> stills;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_trim');
    final frames = Directory('${temp.path}/frames')..createSync();
    final samples = sampleThumbnails();
    stills = [
      for (var i = 0; i < 12; i++)
        File(samples[i * samples.length ~/ 12])
            .copySync(
                '${frames.path}/f${(i + 1).toString().padLeft(5, '0')}.jpg')
            .path,
    ];
    // Five seconds at 30 fps, in twelve stills.
    video = testVideo(temp)
      ..scrubFramesDir = frames.path
      ..scrubFrameCount = 12
      ..scrubFrameStride = 13
      ..release = const Duration(milliseconds: 2992);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> mount(WidgetTester tester, Size screen, Size clip) async {
    await loadPreviewFonts();
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform(clip);
    // Decoded at the height the strip asks for, which is its own cache key.
    await tester.runAsync(() async {
      for (final path in stills) {
        final done = Completer<void>();
        final stream = ResizeImage(FileImage(File(path)), height: 96)
            .resolve(ImageConfiguration.empty);
        late final ImageStreamListener listener;
        listener = ImageStreamListener((_, __) {
          stream.removeListener(listener);
          if (!done.isCompleted) done.complete();
        }, onError: (_, __) {
          if (!done.isCompleted) done.complete();
        });
        stream.addListener(listener);
        await done.future;
      }
    });
    await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>.value(
      value: VideoLibrary(),
      child: MaterialApp(
        theme: ThrowLabApp.theme,
        home: TrimScreen(video: video),
      ),
    ));
    await pumpFrames(tester, 10);
  }

  Future<void> bringIn(WidgetTester tester) async {
    final bar = tester.getRect(find.byKey(const ValueKey('trim-bar')));
    final span = bar.width - 32;
    await tester.dragFrom(
        Offset(bar.left + 8, bar.center.dy), Offset(span * 0.3, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.dragFrom(
        Offset(bar.right - 8, bar.center.dy), Offset(-span * 0.25, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(Offset(bar.left + 16 + span * 0.55, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('portrait', (tester) async {
    await mount(tester, const Size(1179, 2556), const Size(1920, 1080));
    await _shoot(tester, 'trim_portrait');
    await bringIn(tester);
    await _shoot(tester, 'trim_portrait_cut');
    // The start dragged past the release, which is then said out loud.
    final bar = tester.getRect(find.byKey(const ValueKey('trim-bar')));
    await tester
        .tapAt(Offset(bar.left + 16 + (bar.width - 32) * 0.65, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('trim-start-here')));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, 'trim_portrait_release_cut');
  });

  testWidgets('landscape', (tester) async {
    await mount(tester, const Size(2556, 1179), const Size(1920, 1080));
    await bringIn(tester);
    await _shoot(tester, 'trim_landscape');
  });
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
  tester.takeException();
}
