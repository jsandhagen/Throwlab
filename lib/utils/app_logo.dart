import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'pdf_writer.dart';

/// The app's own mark, decoded once, ready to go in the corner of a sheet.
///
/// Struck by the engine rather than drawn again, which is the rule the
/// personal-best medal is already served under: every number in a mark
/// somebody designed is measured off a reference, and one re-drawn out of
/// PDF operators until it looked about right would be nearly the logo.
///
/// Decoded at [size] rather than at the 1024 the asset holds — a sheet
/// draws it a few dozen points across, and the engine resamples better
/// than a PDF viewer scaling a megapixel down to a postage stamp.
///
/// Null when it cannot be had: no asset bundle behind the caller, or a
/// decode that failed. A results sheet without its logo is a results sheet,
/// and it is never the thing a coach is waiting on.
Future<PdfImage?> sheetLogo({int size = 192}) async {
  if (_tried) return _held;
  _tried = true;
  try {
    final asset = await rootBundle.load('assets/icon/logo.png');
    final codec = await ui.instantiateImageCodec(
      asset.buffer.asUint8List(),
      targetWidth: size,
      targetHeight: size,
    );
    final frame = await codec.getNextFrame();
    try {
      // Straight rather than premultiplied: a PDF keeps the color and the
      // alpha in two images and composites them itself, so color already
      // multiplied by its own alpha would draw the logo's antialiased
      // edges over again and leave a dark fringe around every stroke.
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (data == null) return null;
      _held = PdfImage(
        width: frame.image.width,
        height: frame.image.height,
        rgba: data.buffer.asUint8List(),
      );
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  } catch (_) {
    // No bundle, or an asset that would not decode. Nothing is owed.
  }
  return _held;
}

/// Decoded once for the life of the process: it is the same few kilobytes
/// on every sheet, and a coach writing one up at a ring should not pay for
/// it twice.
PdfImage? _held;
bool _tried = false;
