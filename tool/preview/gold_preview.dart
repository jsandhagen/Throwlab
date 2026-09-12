// Renders the gold a personal best is marked in — the medal at every size
// the app pins it at, and the frame it shares its metal with — so drawn art
// can be reviewed without an emulator.
//
//   flutter test --update-goldens tool/preview/gold_preview.dart
//
// Images land in build/preview/ (gitignored). The medal is a badge before it
// is a picture: what matters is the 13-pixel one beside a mark, which is why
// they are painted together at the sizes actually in use rather than one big
// one on its own.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/widgets/gold.dart';

import 'harness.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

/// Every size a screen asks for: the placing beside a meet outing and the
/// mark on a series row, the picker's rows, a card's corner, a written-down
/// best, and the shelf for an athlete with nothing filmed.
const _sizes = [13.0, 14.0, 16.0, 20.0, 28.0, 34.0];

void main() {
  testWidgets('the gold', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 1640);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThrowLabApp.theme,
      home: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final size in _sizes) ...[
                        FirstPlaceMedal(size: size),
                        const SizedBox(width: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  // On a line of type, which is how it is nearly always seen.
                  Row(
                    children: [
                      const FirstPlaceMedal(size: 16),
                      const SizedBox(width: 6),
                      Text('58.44 m',
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: personalBestGold)),
                      const SizedBox(width: 16),
                      const FirstPlaceMedal(size: 13),
                      const SizedBox(width: 6),
                      Text('1st of 3', style: theme.textTheme.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // The frame beside it: one ramp, so the two have to read as
                  // the same piece of metal.
                  SizedBox(
                    width: 180,
                    height: 112,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        const Positioned.fill(
                          child: CustomPaint(painter: GoldEdgePainter()),
                        ),
                        const Positioned(
                          right: 8,
                          top: 6,
                          child: FirstPlaceMedal(size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Center(child: FirstPlaceMedal(size: 130)),
                ],
              ),
            ),
          );
        },
      ),
    ));
    await settle(tester);
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('$_out/gold.png'));
  });
}
