// Writes the app's icons out of the same painter the app draws its mark
// with (`LogoMark`), so the launcher, the in-app mark and the results sheet
// are one drawing:
//
//   flutter test tool/generate_icon.dart
//
// assets/icon/logo.png            the mark alone, cropped to the flask, on
//                                 nothing — what the results sheet embeds
// assets/icon/icon.png            the launcher icon, on white
// assets/icon/icon_foreground.png the adaptive icon's foreground
//
// Then `dart run flutter_launcher_icons` (CI does this) turns them into the
// launcher's own sizes. It lives in tool/ so CI's `flutter test` never runs
// it: the icons are committed, not built.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/widgets/logo_mark.dart';

const _side = 1024;

/// Android crops an adaptive icon's foreground to a mask of the launcher's
/// choosing, and guarantees only a circle 66 dp across out of 108: the
/// flask is made as large as keeps every stroke of it inside that circle,
/// whatever shape the phone cuts it to — less a twentieth, because a
/// flask whose lip grazes the edge of a round icon looks jammed into it.
const _safeRadius = 66 / 108 / 2 * 0.95;

/// The legacy icon has no mask over it, only the white tile it is drawn on.
const _legacyHeight = 0.80;

void main() {
  testWidgets('write the icons', (tester) async {
    await tester.runAsync(() async {
      final logoWidth = (_side * logoAspect).round();
      await _write('assets/icon/logo.png', logoWidth, _side, (canvas) {
        const LogoPainter()
            .paint(canvas, Size(logoWidth.toDouble(), _side.toDouble()));
      });

      await _write('assets/icon/icon.png', _side, _side, (canvas) {
        canvas.drawRect(const Rect.fromLTWH(0, 0, _side * 1.0, _side * 1.0),
            Paint()..color = Colors.white);
        _centered(canvas, _legacyHeight * _side, 0.5);
      });

      final fit = await _safeFit();
      await _write('assets/icon/icon_foreground.png', _side, _side, (canvas) {
        _centered(canvas, fit.height * _side, fit.centerY);
      });
    });
  });
}

/// Paints the mark [height] pixels tall, its own box placed so that the
/// point [centerY] of the way down it sits in the middle of the canvas.
void _centered(Canvas canvas, double height, double centerY) {
  final width = height * logoAspect;
  canvas.save();
  canvas.translate((_side - width) / 2, _side / 2 - height * centerY);
  const LogoPainter().paint(canvas, Size(width, height));
  canvas.restore();
}

/// The largest the mark can be drawn inside the adaptive icon's safe
/// circle, and where down its own box that circle's center should sit — a
/// flask is wider at the base than the lip, so the middle of its box is not
/// the middle of the circle that holds it best.
Future<({double height, double centerY})> _safeFit() async {
  // Where the mark paints, found by painting it: every pixel it covers at a
  // working size, as a fraction of its box.
  const probe = 400;
  final width = (probe * logoAspect).round();
  final recorder = ui.PictureRecorder();
  const LogoPainter()
      .paint(Canvas(recorder), Size(width.toDouble(), probe.toDouble()));
  final image = await recorder.endRecording().toImage(width, probe);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  final points = <Offset>[];
  for (var y = 0; y < probe; y += 2) {
    for (var x = 0; x < width; x += 2) {
      if (bytes[(y * width + x) * 4 + 3] > 8) {
        points.add(Offset(x / probe, y / probe));
      }
    }
  }
  image.dispose();
  // ignore: avoid_print
  print('probed ${points.length} painted points');
  var best = (height: 0.0, centerY: 0.5);
  for (var c = 0.40; c <= 0.60; c += 0.005) {
    final middle = Offset(logoAspect / 2, c);
    final reach = points.map((p) => (p - middle).distance).reduce(math.max);
    final height = _safeRadius / reach;
    if (height > best.height) best = (height: height, centerY: c);
  }
  return best;
}

Future<void> _write(
    String path, int width, int height, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path ($width x $height)');
}
