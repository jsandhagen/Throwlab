import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/services/javelin_detector.dart';

/// Gray frame with a horizon-like bright band and a 3 px thick bright
/// "javelin" from [tail] to [tip].
Uint8List _frame(
  int w,
  int h, {
  required List<double> tail,
  required List<double> tip,
}) {
  final luma = Uint8List(w * h)..fillRange(0, w * h, 40);
  for (var x = 0; x < w; x++) {
    for (var y = 520; y < 524; y++) {
      luma[y * w + x] = 180;
    }
  }
  final dx = tip[0] - tail[0], dy = tip[1] - tail[1];
  final steps = (math.sqrt(dx * dx + dy * dy) * 2).ceil();
  for (var s = 0; s <= steps; s++) {
    final x = tail[0] + dx * s / steps;
    final y = tail[1] + dy * s / steps;
    for (var ox = -1; ox <= 1; ox++) {
      for (var oy = -1; oy <= 1; oy++) {
        final xi = (x + ox).round(), yi = (y + oy).round();
        if (xi >= 0 && xi < w && yi >= 0 && yi < h) {
          luma[yi * w + xi] = 230;
        }
      }
    }
  }
  return luma;
}

void main() {
  const w = 1024, h = 576;
  // ~32° shaft, well separated from the horizontal clutter band.
  const tail = [250.0, 450.0];
  const tip = [650.0, 200.0];

  group('JavelinDetector.findShaft', () {
    test('finds tip and tail seeded by a tap near the tip', () {
      final luma = _frame(w, h, tail: tail, tip: tip);
      final r = JavelinDetector.findShaft(luma, w, h,
          nearX: 660, nearY: 210);
      expect(r, isNotNull);
      expect(r![0], closeTo(tip[0], 10));
      expect(r[1], closeTo(tip[1], 10));
      expect(r[2], closeTo(tail[0], 10));
      expect(r[3], closeTo(tail[1], 10));
    });

    test('assigns tip to the end nearest the tap', () {
      final luma = _frame(w, h, tail: tail, tip: tip);
      // Tap near the other end: that end becomes the "tip".
      final r = JavelinDetector.findShaft(luma, w, h,
          nearX: 260, nearY: 445);
      expect(r, isNotNull);
      expect(r![0], closeTo(tail[0], 10));
      expect(r[1], closeTo(tail[1], 10));
    });

    test('re-finds a moved shaft from the previous frame markers', () {
      // Shaft moved (180, -100) px with the same attitude.
      const tail2 = [430.0, 350.0];
      const tip2 = [830.0, 100.0];
      final luma = _frame(w, h, tail: tail2, tip: tip2);
      final r = JavelinDetector.findShaft(
        luma,
        w,
        h,
        prevTipX: tip[0],
        prevTipY: tip[1],
        prevTailX: tail[0],
        prevTailY: tail[1],
      );
      expect(r, isNotNull);
      // Direction match keeps tip/tail assignment consistent.
      expect(r![0], closeTo(tip2[0], 10));
      expect(r[1], closeTo(tip2[1], 10));
      expect(r[2], closeTo(tail2[0], 10));
      expect(r[3], closeTo(tail2[1], 10));
    });

    test('returns null rather than guessing on an empty frame', () {
      final luma = Uint8List(w * h)..fillRange(0, w * h, 40);
      expect(
          JavelinDetector.findShaft(luma, w, h, nearX: 500, nearY: 300),
          isNull);
    });

    test('returns null when the tap is nowhere near the shaft', () {
      final luma = _frame(w, h, tail: tail, tip: tip);
      expect(
          JavelinDetector.findShaft(luma, w, h, nearX: 60, nearY: 60),
          isNull);
    });
  });
}
