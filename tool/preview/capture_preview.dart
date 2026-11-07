// Renders the app's own camera: upright and on its side, ready, counting
// down, recording against a stop, and with the frame rates offered. It
// asserts nothing.
//
//   flutter test --update-goldens tool/preview/capture_preview.dart
//
// The camera is the plugin's channel answered in-process, so the preview is
// a flat panel where the picture would be: what is being looked at is the chrome
// over it, and whether it can be read from the ring.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/screens/capture_screen.dart';
import 'package:throwlab_camera/throwlab_camera.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  const modes = [
    CameraMode(width: 1920, height: 1080, fps: 30, highSpeed: false),
    CameraMode(width: 1920, height: 1080, fps: 60, highSpeed: false),
    CameraMode(width: 1920, height: 1080, fps: 120, highSpeed: true),
    CameraMode(width: 1920, height: 1080, fps: 240, highSpeed: true),
    CameraMode(width: 3840, height: 2160, fps: 60, highSpeed: false),
  ];

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('throwlab_capture');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ThrowCamera.channel, (call) async {
      switch (call.method) {
        case 'modes':
          return {
            'modes': [for (final m in modes) m.toMap()],
            'sensorOrientation': 90,
            // What a Galaxy Ultra reports to apps: high speed only at 1080p.
            'details': [
              'Back camera 0 · 6.3 mm',
              '  High speed: 1920x1080 at 120/240',
              '  Steady rates: 24/30/60',
              '  3840x2160: up to 60 fps',
              '  1920x1080: up to 60 fps',
              'Back camera 2 · 2.2 mm',
              '  High speed: none',
              '  Steady rates: 24/30',
              '  3840x2160: up to 30 fps',
              '  1920x1080: up to 30 fps',
            ],
          };
        case 'open':
          // Ready a moment after opening, as the phone says once its
          // preview is up.
          Future<void>.delayed(Duration.zero, () {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .handlePlatformMessage(
                    ThrowCamera.channel.name,
                    ThrowCamera.channel.codec
                        .encodeMethodCall(const MethodCall('ready')),
                    (_) {});
          });
          return {...(call.arguments as Map), 'sensorOrientation': 90};
        case 'displayRotation':
          return 0;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => temp.path);
  });

  Future<void> mount(WidgetTester tester, Size screen,
      {int countdown = 10, int stop = 12}) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.capture.countdown': countdown,
      'flutter.throwlab.capture.stopAfter': stop,
    });
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      // The platform view the phone shows can't be hosted here; a flat
      // panel marks where it goes and how much of the screen it takes.
      home: const CaptureScreen(preview: ColoredBox(color: Color(0xFF26323A))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('upright', (tester) async {
    await mount(tester, const Size(1179, 2556));
    await _shoot(tester, 'capture_ready');
    await tester.tap(find.byKey(const ValueKey('capture-shutter')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await _shoot(tester, 'capture_countdown');
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 4300));
    await _shoot(tester, 'capture_recording');
    await tester.tap(find.byKey(const ValueKey('capture-shutter')));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the rates on offer', (tester) async {
    await mount(tester, const Size(1179, 2556));
    await tester.tap(find.byKey(const ValueKey('capture-mode')));
    await tester.pumpAndSettle();
    await _shoot(tester, 'capture_modes');
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('camera-details')), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('camera-details')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('  1920x1080: up to 30 fps'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await _shoot(tester, 'capture_camera_details');
  });

  testWidgets('on its side', (tester) async {
    await mount(tester, const Size(2556, 1179), countdown: 0, stop: 0);
    await _shoot(tester, 'capture_landscape');
  });
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
