// Renders what leaves the app when a throw is shared or the library is
// backed up: the share sheet off a throw with drawings on it, the
// library's menu and the backup's question, and — the part worth looking
// at — the drawings themselves painted onto a frame the way the export
// burns them in, at a clip's own pixels, with a timer counting. It asserts
// nothing.
//
//   flutter test --update-goldens tool/preview/export_preview.dart
//
// The export's overlay goes over a sample still in a plain Stack here; on
// the phone ffmpeg lays the same PNG over the video.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/clip_export.dart';
import 'package:throwlab/services/video_library.dart';
import 'package:throwlab/widgets/drawing_canvas.dart';
import 'package:throwlab/widgets/share_throw.dart';

import 'harness.dart';
import 'sample_library.dart';

const _out = '../../build/preview';

void main() {
  final marks = <Annotation>[
    CircleAnnotation(const Color(0xFFFFEB3B), 3, const Offset(0.42, 0.55),
        const Offset(0.47, 0.55)),
    ArrowAnnotation(const Color(0xFFFF5252), 3, const Offset(0.2, 0.8),
        const Offset(0.38, 0.6)),
    AngleAnnotation(const Color(0xFF4FC3F7), 3)
      ..points.addAll(const [
        Offset(0.55, 0.35),
        Offset(0.62, 0.55),
        Offset(0.75, 0.5),
      ]),
    TimerMarker(const Color(0xFFFFFFFF), 3, const Offset(0.8, 0.15),
        const Duration(milliseconds: 200)),
  ];

  testWidgets('drawings burned onto a frame', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final still = sampleThumbnails().first;
    final overlay = '${Directory.systemTemp.path}/throwlab_overlay.png';
    await tester.runAsync(() async {
      final png = await ClipExport.overlayPng(
        ThrowDrawing(
          annotations: marks,
          layout: const Size(390, 219),
          position: const Duration(milliseconds: 1370),
          labelStyle: ThrowLabApp.theme.textTheme.bodyMedium!,
        ),
        const Size(1920, 1080),
      );
      await File(overlay).writeAsBytes(png);
    });
    await warmImages(tester, [still, overlay]);
    await tester.pumpWidget(MaterialApp(
      home: Stack(fit: StackFit.expand, children: [
        Image.file(File(still), fit: BoxFit.fill),
        Image.file(File(overlay), fit: BoxFit.fill),
      ]),
    ));
    await tester.pump();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/export_frame.png'));
  });

  testWidgets('the share sheet and the library menu', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final video = ThrowVideo(
      id: 'v',
      path: '/v.mp4',
      event: ThrowEvent.discus,
      implementKg: 1,
      importedAt: DateTime(2026, 11, 4),
    );
    await tester.pumpWidget(ChangeNotifierProvider<VideoLibrary>(
      create: (_) => VideoLibrary(),
      child: MaterialApp(
        theme: ThrowLabApp.theme,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Discus · 1 kg')),
            body: Center(
              child: TextButton(
                onPressed: () => shareThrow(context, video,
                    drawing: ThrowDrawing(
                      annotations: marks,
                      layout: const Size(390, 219),
                      position: Duration.zero,
                      labelStyle: const TextStyle(),
                    ),
                    pixels: const Size(1920, 1080),
                    duration: const Duration(seconds: 6)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/export_share_sheet.png'));
  });
}
