// Renders the app's own camera: upright and on its side, ready, counting
// down, recording against a stop, and with the frame rates offered. It
// asserts nothing.
//
//   flutter test --update-goldens tool/preview/capture_preview.dart
//
// The camera is the plugin's channel answered in-process, so the preview is
// black where the picture would be: what is being looked at is the chrome
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
          };
        case 'open':
          return {
            ...(call.arguments as Map),
            'textureId': 1,
            'sensorOrientation': 90,
          };
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
      home: const CaptureScreen(),
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
  });

  testWidgets('on its side', (tester) async {
    await mount(tester, const Size(2556, 1179), countdown: 0, stop: 0);
    await _shoot(tester, 'capture_landscape');
  });
}

Future<void> _shoot(WidgetTester tester, String name) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
