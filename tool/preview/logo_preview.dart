// The app's mark where it is actually shown: the launcher icon on its white
// tile at the sizes a home screen and a store draw it, the adaptive icon's
// foreground under the masks a launcher cuts it to, the app bar's 32 px on
// the dark theme, and the empty library's 140.
//
//   flutter test tool/generate_icon.dart            # the icon files first
//   flutter test --update-goldens tool/preview/logo_preview.dart
//
// The launcher rows are the committed PNGs, read back, so what is looked at
// is what ships; the in-app rows are the painter itself.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/widgets/logo_mark.dart';

import 'harness.dart';

const _out = '../../build/preview';
const _icon = 'assets/icon/icon.png';
const _foreground = 'assets/icon/icon_foreground.png';

void main() {
  testWidgets('the logo', (tester) async {
    await loadPreviewFonts();
    tester.view.physicalSize = const Size(1080, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await warmImages(tester, [_icon, _foreground]);
    final theme = ThrowLabApp.theme;

    Widget launcher(double size) => ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: Image.file(File(_icon), width: size, height: size),
        );

    // The adaptive foreground on its white background, cut the ways a
    // launcher cuts it. The canvas is 108 dp and a launcher shows the middle
    // 72 of it; a circle is the tightest mask, and the flask has to clear it.
    Widget adaptive(double size, ShapeBorder shape) => ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: Container(
            width: size,
            height: size,
            color: Colors.white,
            child: OverflowBox(
              maxWidth: size * 108 / 72,
              maxHeight: size * 108 / 72,
              child: Image.file(File(_foreground)),
            ),
          ),
        );

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(text, style: theme.textTheme.titleMedium),
        );

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              LogoMark(height: 32),
              SizedBox(width: 10),
              Text('ThrowLab',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Launcher icon'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final size in [150.0, 72.0, 48.0, 36.0]) ...[
                    launcher(size),
                    const SizedBox(width: 14),
                  ],
                ],
              ),
              label('Adaptive icon: circle, squircle, rounded square'),
              Row(
                children: [
                  for (final shape in <ShapeBorder>[
                    const CircleBorder(),
                    ContinuousRectangleBorder(
                        borderRadius: BorderRadius.circular(60)),
                    RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ]) ...[
                    adaptive(96, shape),
                    const SizedBox(width: 14),
                  ],
                ],
              ),
              label('Empty library'),
              const Center(child: LogoMark(height: 140)),
            ],
          ),
        ),
      ),
    ));
    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('$_out/logo.png'));
  });
}
