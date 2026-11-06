import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/screens/capture_screen.dart';
import 'package:throwlab/utils/capture_plan.dart';
import 'package:throwlab_camera/throwlab_camera.dart';

/// The app's own camera: which rate it opens on, which way up the preview
/// goes, and a take run by the countdown, the stop and the remote.
void main() {
  const hd120 =
      CameraMode(width: 1920, height: 1080, fps: 120, highSpeed: true);
  const hd240 =
      CameraMode(width: 1920, height: 1080, fps: 240, highSpeed: true);
  const hd60 = CameraMode(width: 1920, height: 1080, fps: 60, highSpeed: false);
  const sd240 = CameraMode(width: 1280, height: 720, fps: 240, highSpeed: true);
  const hd30 = CameraMode(width: 1920, height: 1080, fps: 30, highSpeed: false);

  group('mode', () {
    test('opens on 120 where the phone has it', () {
      expect(pickMode([hd30, hd60, hd120, hd240, sd240]), hd120);
    });

    test('keeps the rate it was last left on', () {
      expect(pickMode([hd30, hd120, hd240], preferredFps: 240), hd240);
      // Not offered any more: back to 120.
      expect(pickMode([hd30, hd120], preferredFps: 960), hd120);
    });

    test('without a high-speed session, the fastest there is', () {
      expect(pickMode([hd30, hd60]), hd60);
      expect(pickMode(const []), isNull);
    });

    test('the choice reads fastest first, sharper before smaller', () {
      expect(offeredModes([hd30, sd240, hd120, hd240, hd60]),
          [hd240, sd240, hd120, hd60, hd30]);
      expect(hd120.toString(), '1080p · 120 fps');
    });

    test('the preview is turned back by the sensor less the screen', () {
      // A phone upright, its sensor mounted a quarter turn round.
      expect(previewQuarterTurns(90, 0), 1);
      // Turned onto its left side, the screen turns with it.
      expect(previewQuarterTurns(90, 90), 0);
      expect(previewQuarterTurns(90, 270), 2);
    });
  });

  group('timings', () {
    test('each chip steps round its own values', () {
      var timings = const CaptureTimings();
      final countdowns = [
        for (var i = 0; i < CaptureTimings.countdowns.length + 1; i++)
          (timings = timings.nextCountdown()).countdown,
      ];
      expect(countdowns, [5, 10, 20, 0, 5]);
      expect(timings.stopAfter, 0);
      expect(const CaptureTimings().nextStop().stopAfter, 8);
    });
  });

  group('a take', () {
    late List<String> log;
    late CaptureRun run;
    setUp(() {
      log = [];
      run = CaptureRun(
        start: () async => log.add('start'),
        stop: () async => log.add('stop'),
        beep: (kind) => log.add(kind.name),
      );
    });

    test('counts down a beep a second, then rolls and says so', () {
      fakeAsync((clock) {
        run.press(const CaptureTimings(countdown: 3));
        expect(run.phase, CapturePhase.counting);
        expect(run.remaining, 3);
        clock.elapse(const Duration(seconds: 2));
        expect(run.remaining, 1);
        clock.elapse(const Duration(seconds: 1));
        clock.flushMicrotasks();
        expect(run.phase, CapturePhase.recording);
        expect(log, ['tick', 'tick', 'tick', 'start', 'go']);
      });
    });

    test('stops itself after the seconds it was set to', () {
      fakeAsync((clock) {
        run.press(const CaptureTimings(stopAfter: 8));
        clock.flushMicrotasks();
        expect(run.phase, CapturePhase.recording);
        clock.elapse(const Duration(milliseconds: 7900));
        expect(log, isNot(contains('stop')));
        clock.elapse(const Duration(milliseconds: 200));
        clock.flushMicrotasks();
        expect(log, ['start', 'go', 'stop', 'stop']);
        expect(run.phase, CapturePhase.idle);
      });
    });

    test('a press during the countdown calls it off', () {
      fakeAsync((clock) {
        run.press(const CaptureTimings(countdown: 5));
        clock.elapse(const Duration(seconds: 2));
        run.press(const CaptureTimings(countdown: 5));
        clock.elapse(const Duration(seconds: 10));
        expect(run.phase, CapturePhase.idle);
        expect(log, isNot(contains('start')));
      });
    });

    test('a press while recording stops it', () {
      fakeAsync((clock) {
        run.press(const CaptureTimings());
        clock.flushMicrotasks();
        run.press(const CaptureTimings());
        clock.flushMicrotasks();
        expect(log, ['start', 'go', 'stop', 'stop']);
      });
    });
  });

  group('screen', () {
    late Directory temp;
    late List<MethodCall> calls;
    Object? Function(MethodCall)? override;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('throwlab_capture');
      calls = [];
      override = null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ThrowCamera.channel, (call) async {
        calls.add(call);
        final custom = override?.call(call);
        if (custom != null) return custom;
        switch (call.method) {
          case 'modes':
            return {
              'modes': [
                hd30.toMap(),
                hd60.toMap(),
                hd120.toMap(),
                hd240.toMap()
              ],
              'sensorOrientation': 90,
            };
          case 'open':
            return {
              ...(call.arguments as Map),
              'textureId': 7,
              'sensorOrientation': 90
            };
          case 'stop':
            final file = File('${temp.path}/take.mp4')..writeAsStringSync('x');
            return file.path;
          case 'displayRotation':
            return 0;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path);
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ThrowCamera.channel, null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      temp.deleteSync(recursive: true);
    });

    Future<Object?> mount(WidgetTester tester) async {
      Object? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<Object>(
                  MaterialPageRoute(builder: (_) => const CaptureScreen()));
            },
            child: const Text('film'),
          ),
        ),
      ));
      await tester.tap(find.text('film'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets('opens on 120 fps and says so', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await mount(tester);
      final open = calls.firstWhere((c) => c.method == 'open');
      expect((open.arguments as Map)['fps'], 120);
      expect((open.arguments as Map)['highSpeed'], true);
      expect(find.text('120 fps'), findsOneWidget);
      expect(find.byType(Texture), findsOneWidget);
    });

    testWidgets('a volume press from a remote starts and stops a take',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      Object? popped;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<Object>(
                  MaterialPageRoute(builder: (_) => const CaptureScreen()));
            },
            child: const Text('film'),
          ),
        ),
      ));
      await tester.tap(find.text('film'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pump();
      expect(calls.map((c) => c.method), contains('start'));
      final start = calls.firstWhere((c) => c.method == 'start');
      expect((start.arguments as Map)['path'], endsWith('.mp4'));
      expect(find.text('Stop'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), contains('stop'));
      expect(popped, isA<FilmedClip>());
      expect((popped! as FilmedClip).fps, 120);
      expect(
          calls
              .where((c) => c.method == 'beep')
              .map((c) => (c.arguments as Map)['kind']),
          ['go', 'stop']);
    });

    testWidgets('the countdown and the stop are remembered', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('capture-countdown')));
      await tester.tap(find.byKey(const ValueKey('capture-countdown')));
      await tester.tap(find.byKey(const ValueKey('capture-stop')));
      await tester.pump();
      expect(find.text('10 s'), findsOneWidget);
      expect(find.text('8 s'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('throwlab.capture.countdown'), 10);
      expect(prefs.getInt('throwlab.capture.stopAfter'), 8);
    });

    testWidgets('without the camera, offers the phone\'s own', (tester) async {
      SharedPreferences.setMockInitialValues({});
      override = (call) => call.method == 'modes'
          ? throw PlatformException(code: 'permission')
          : null;
      await mount(tester);
      expect(find.textContaining('needs the camera'), findsOneWidget);
      expect(find.byKey(const ValueKey('capture-system')), findsOneWidget);
    });
  });
}
