// Renders the event glyphs at every size a screen pins them at, and once
// large enough to see what was drawn.
//
//   flutter test --update-goldens tool/preview/glyph_preview.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/widgets/event_glyph.dart';

import 'harness.dart';

const _out = '../../build/preview';

const _sizes = [16.0, 18.0, 20.0, 26.0, 34.0];

void main() {
  testWidgets('the glyphs', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final event in ThrowEvent.values) ...[
                // Each row on its own, so the icon sizes can be shot at the
                // pixels a phone paints them at rather than shrunk to fit.
                RepaintBoundary(
                  key: ValueKey(event),
                  child: ColoredBox(
                    color: ThrowLabApp.theme.colorScheme.surface,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final size in _sizes) ...[
                          EventGlyph(event, size: size),
                          const SizedBox(width: 14),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // One big enough to see what was drawn.
              const EventGlyph(ThrowEvent.javelin, size: 300),
            ],
          ),
        ),
      ),
    ));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('$_out/glyphs.png'));
    for (final event in ThrowEvent.values) {
      await expectLater(find.byKey(ValueKey(event)),
          matchesGoldenFile('$_out/glyphs_${event.name}.png'));
    }
  });
}
