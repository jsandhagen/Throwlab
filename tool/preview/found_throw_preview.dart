// Renders the question a long clip is asked on its way in — the throw the
// finder picked out of it, and whether to keep only that — over a library,
// on a phone. It asserts nothing.
//
//   flutter test --update-goldens tool/preview/found_throw_preview.dart
//
// The stills are the sample library's thumbnails standing in for the three
// frames cut out of the clip.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/utils/throw_finder.dart';
import 'package:throwlab/widgets/found_throw.dart';

import 'harness.dart';
import 'sample_library.dart';

const _out = '../../build/preview';

void main() {
  Future<void> open(WidgetTester tester, {required bool keepsOriginal}) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final samples = sampleThumbnails();
    final stills = [samples[0], samples[1], samples[2]];
    await warmImages(tester, stills);
    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('ThrowLab')),
          body: Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                useSafeArea: true,
                isScrollControlled: true,
                builder: (_) => FoundThrowSheet(
                  window: const ThrowWindow(
                      start: 70.2, end: 79.6, peak: 74.4, duration: 123.4),
                  stills: stills,
                  keepsOriginal: keepsOriginal,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('filmed', (tester) async {
    await open(tester, keepsOriginal: false);
    await _shoot(tester, 'found_throw_filmed');
  });

  testWidgets('imported', (tester) async {
    await open(tester, keepsOriginal: true);
    await _shoot(tester, 'found_throw_imported');
  });
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
