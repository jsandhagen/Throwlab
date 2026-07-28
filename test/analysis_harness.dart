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

/// Mounting the real analysis screen in a widget test: an in-memory video
/// platform plus the gestures the drawing tools are driven with.

/// Stands in for the real player: reports a fixed video size and nothing
/// else.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  FakeVideoPlayerPlatform(this.size);

  final Size size;

  /// One stream per player: the comparison screen runs two at once, and a
  /// shared broadcast stream would announce the video to whichever
  /// controller subscribed first and leave the other waiting forever.
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _nextPlayerId++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // Only announce the video once someone is listening, otherwise the
    // stream drops the event before the controller subscribes.
    final events = _events.putIfAbsent(
        playerId, () => StreamController<VideoEvent>.broadcast());
    events.onListen = () => scheduleMicrotask(() => events.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 5),
          size: size,
          rotationCorrection: 0,
        )));
    return events.stream;
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

/// A throw backed by a real (empty) file, since the screen checks that the
/// clip still exists before opening it.
ThrowVideo testVideo(
  Directory directory, {
  String id = 'v1',
  ThrowEvent event = ThrowEvent.javelin,
  String athlete = '',
}) {
  final file = File('${directory.path}/$id.mp4')..writeAsBytesSync(<int>[0]);
  return ThrowVideo(
    id: id,
    path: file.path,
    event: event,
    gender: Gender.men,
    importedAt: DateTime(2026, 1, 1),
    athlete: athlete,
  );
}

Future<void> pumpFrames(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Mounts the analysis screen on a [screen]-sized display, playing a clip of
/// [videoSize], with the drawing rail open.
Future<void> mountAnalysisScreen(
  WidgetTester tester, {
  required ThrowVideo video,
  required Size screen,
  required Size videoSize,
  VideoLibrary? library,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  VideoPlayerPlatform.instance = FakeVideoPlayerPlatform(videoSize);
  await tester.pumpWidget(
    ChangeNotifierProvider<VideoLibrary>.value(
      value: library ?? VideoLibrary(),
      child: MaterialApp(home: AnalysisScreen(video: video)),
    ),
  );
  await pumpFrames(tester);
}

/// Taps a drawing-rail control (tool icon, thickness swatch, …).
Future<void> tapRail(WidgetTester tester, Finder control) async {
  await tester.tap(control);
  await pumpFrames(tester);
}

List<T> annotationsOf<T extends Annotation>(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(DrawingCanvas), matching: find.byType(CustomPaint)));
  return ((paint.painter as dynamic).annotations as List).whereType<T>().toList();
}

/// Where the annotation layer paints a stored (normalized) point.
Offset inkFor(WidgetTester tester, Offset normalized) {
  final box = tester.renderObject<RenderBox>(find.byType(DrawingCanvas));
  return box.localToGlobal(Offset(
      normalized.dx * box.size.width, normalized.dy * box.size.height));
}

/// Drags a finger along [path] — a stroke with whichever tool is selected.
Future<void> drawAlong(WidgetTester tester, List<Offset> path) async {
  final gesture = await tester.startGesture(path.first);
  for (final point in path.skip(1)) {
    await gesture.moveTo(point);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await pumpFrames(tester);
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
