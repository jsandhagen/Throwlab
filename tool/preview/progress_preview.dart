// Renders the two waits that know how far along they are — optimizing an
// imported clip, and downloading an update — with the mark filling as their
// gauge.
//
//   flutter test --update-goldens tool/preview/progress_preview.dart
//
// The import's dialog before its first reading, part way through the
// re-encode, on the frames, and nearly done; and the library with the
// update banner down to 55%. Its motion is in motion_preview.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/screens/home_screen.dart';
import 'package:throwlab/services/app_updater.dart';

import 'harness.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('an import optimizing', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final progress = ValueNotifier<double?>(null);
    final stage = ValueNotifier<String>(
        'Re-encoding for instant frame-by-frame scrubbing. Long or '
        'high-fps clips take a few minutes.');
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Scaffold(
          body: OptimizingDialog(progress: progress, stage: stage)),
    ));
    await tester.pump();
    await _shoot(tester, 'import_starting');
    for (final (name, value, text) in [
      ('import_encoding', 0.3, null),
      ('import_frames', 0.8, 'Extracting frames for smooth scrubbing…'),
      ('import_nearly', 0.97, null),
    ]) {
      progress.value = value;
      if (text != null) stage.value = text;
      await _run(tester);
      await _shoot(tester, name);
    }
  });

  testWidgets('an update coming down', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // The banner itself: the library only puts it up once a real check has
    // found a newer build, which a debug build never makes.
    final status = ValueNotifier(const UpdateStatus(
        stage: UpdateStage.downloading, build: 214, progress: 0.2));
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('ThrowLab')),
        body: Column(children: [
          ValueListenableBuilder(
            valueListenable: status,
            builder: (context, value, _) => UpdateBanner(
                status: value, onUpdate: () {}, onInstall: () {}, onLater: () {}),
          ),
          const Expanded(child: SizedBox()),
        ]),
      ),
    ));
    await tester.pump();
    status.value = const UpdateStatus(
        stage: UpdateStage.downloading, build: 214, progress: 0.55);
    await _run(tester);
    await _shoot(tester, 'update_downloading');
  });
}

/// Lets the flask ease onto its reading. It is driven by a ticker, and a
/// single long pump is a single frame.
Future<void> _run(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
