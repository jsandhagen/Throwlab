import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/screens/analysis_screen.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// In-memory video platform so the real analysis screen can be mounted in a
/// widget test: reports a fixed video size and nothing else.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  _FakeVideoPlayerPlatform(this.size);

  final Size size;
  final StreamController<VideoEvent> _events =
      StreamController<VideoEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // Only announce the video once someone is listening, otherwise the
    // broadcast stream drops the event before the controller subscribes.
    _events.onListen = () => scheduleMicrotask(() => _events.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 5),
          size: size,
          rotationCorrection: 0,
        )));
    return _events.stream;
  }

  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Widget buildView(int playerId) => const ColoredBox(color: Colors.blue);
}

void main() {
  late Directory temp;
  late ThrowVideo video;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('throwlab_test');
    final file = File('${temp.path}/clip.mp4')..writeAsBytesSync(<int>[0]);
    video = ThrowVideo(
      id: 'v1',
      path: file.path,
      event: ThrowEvent.javelin,
      gender: Gender.men,
      importedAt: DateTime(2026, 1, 1),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> pumpFrames(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Mounts the analysis screen on a [screen]-sized display with a video of
  /// [videoSize], and selects the pen.
  Future<void> mountWithPen(
    WidgetTester tester, {
    required Size screen,
    required Size videoSize,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(videoSize);
    await tester.pumpWidget(
      ChangeNotifierProvider<VideoLibrary>(
        create: (_) => VideoLibrary(),
        child: MaterialApp(home: AnalysisScreen(video: video)),
      ),
    );
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.draw)); // pen tool
    await pumpFrames(tester);
  }

  /// Where the annotation layer paints a stored (normalized) point.
  Offset inkFor(WidgetTester tester, Offset normalized) {
    final box = tester.renderObject<RenderBox>(find.byType(DrawingCanvas));
    return box.localToGlobal(Offset(
        normalized.dx * box.size.width, normalized.dy * box.size.height));
  }

  List<PenStroke> strokes(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(DrawingCanvas), matching: find.byType(CustomPaint)));
    return ((paint.painter as dynamic).annotations as List)
        .whereType<PenStroke>()
        .toList();
  }

  /// Drags a finger along [path] and returns where the last recorded point
  /// of the resulting stroke is painted.
  Future<Offset> drawAlong(WidgetTester tester, List<Offset> path) async {
    final gesture = await tester.startGesture(path.first);
    for (final point in path.skip(1)) {
      await gesture.moveTo(point);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await pumpFrames(tester);
    return inkFor(tester, strokes(tester).last.points.last);
  }

  Future<void> pinchOut(
      WidgetTester tester, Offset center, double finalSpread) async {
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      final spread = 20 + (finalSpread - 20) * i / 10;
      await a.moveTo(center - Offset(spread, 0));
      await b.moveTo(center + Offset(spread, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await pumpFrames(tester);
  }

  testWidgets('pen ink lands under the finger', (tester) async {
    // Portrait clip on a landscape screen: the video is pillarboxed, so a
    // mismapped touch shows up as a horizontal offset.
    await mountWithPen(tester,
        screen: const Size(800, 600), videoSize: const Size(1080, 1920));

    final ink = await drawAlong(tester, const [
      Offset(340, 200),
      Offset(360, 240),
      Offset(390, 300),
    ]);
    expect(ink, within(distance: 1, from: const Offset(390, 300)));
  });

  testWidgets('pen ink lands under the finger while zoomed', (tester) async {
    await mountWithPen(tester,
        screen: const Size(800, 600), videoSize: const Size(1080, 1920));
    await pinchOut(tester, const Offset(400, 300), 120);

    final ink = await drawAlong(tester, const [
      Offset(340, 200),
      Offset(360, 240),
      Offset(390, 300),
    ]);
    expect(ink, within(distance: 1, from: const Offset(390, 300)));
  });

  testWidgets('pen ink lands under the finger after the viewport changes',
      (tester) async {
    // Zoom and pan hard against the edge, then change the viewport (device
    // rotation, system bars): the pan the screen draws with gets re-clamped,
    // and the touch mapping has to follow it.
    await mountWithPen(tester,
        screen: const Size(800, 600), videoSize: const Size(1920, 1080));
    await pinchOut(tester, const Offset(720, 300), 220);

    tester.view.physicalSize = const Size(600, 400);
    await pumpFrames(tester);

    final ink = await drawAlong(tester, const [
      Offset(260, 150),
      Offset(280, 180),
      Offset(300, 200),
    ]);
    expect(ink, within(distance: 1, from: const Offset(300, 200)));
  });
}
