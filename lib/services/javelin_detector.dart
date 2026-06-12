import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tip and tail of a detected javelin shaft, normalized to the video frame
/// (0..1 on both axes).
class JavelinDetection {
  const JavelinDetection({required this.tip, required this.tail});

  final ui.Offset tip;
  final ui.Offset tail;
}

/// Finds the javelin shaft in a single video frame: the longest straight
/// thin edge run near the user's tap (release frame) or matching the
/// previous frame's shaft (the +dt frame). Classical edge fitting — no ML —
/// so a confident-looking wrong answer is rare; ambiguous frames return
/// null and the measure flow falls back to manual taps.
class JavelinDetector {
  /// Detection runs on a copy downscaled to this width; endpoints come back
  /// at roughly tap precision, which the user can still fine-tune.
  static const _detectWidth = 1024;

  /// Looks for the shaft in the frame at [position] of [videoPath].
  ///
  /// All coordinates are normalized to the frame. Pass [nearPoint] (the
  /// user's tap, expected near the tip) on the release frame; pass
  /// [previousTip]/[previousTail] (that frame's confirmed markers) to
  /// re-find the shaft on the later frame. Returns null when nothing
  /// convincing is found.
  static Future<JavelinDetection?> detect({
    required String videoPath,
    required Duration position,
    ui.Offset? nearPoint,
    ui.Offset? previousTip,
    ui.Offset? previousTail,
  }) async {
    final image = await _grabFrame(videoPath, position);
    if (image == null) return null;
    final w = image.width;
    final h = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return null;

    final result = await compute(
      _findShaftInRgba,
      _ShaftJob(
        rgba: data.buffer.asUint8List(),
        width: w,
        height: h,
        nearX: nearPoint == null ? null : nearPoint.dx * w,
        nearY: nearPoint == null ? null : nearPoint.dy * h,
        prevTipX: previousTip == null ? null : previousTip.dx * w,
        prevTipY: previousTip == null ? null : previousTip.dy * h,
        prevTailX: previousTail == null ? null : previousTail.dx * w,
        prevTailY: previousTail == null ? null : previousTail.dy * h,
      ),
    );
    if (result == null) return null;
    return JavelinDetection(
      tip: ui.Offset(result[0] / w, result[1] / h),
      tail: ui.Offset(result[2] / w, result[3] / h),
    );
  }

  /// Extracts the frame at [position] as a downscaled image, or null.
  static Future<ui.Image?> _grabFrame(
      String videoPath, Duration position) async {
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/measure_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final seconds =
        position.inMicroseconds / Duration.microsecondsPerSecond;
    final session = await FFmpegKit.execute(
        '-y -ss ${seconds.toStringAsFixed(4)} -i "$videoPath" '
        '-frames:v 1 -q:v 3 "$outPath"');
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      File(outPath).delete().ignore();
      return null;
    }
    try {
      final bytes = await File(outPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: _detectWidth, allowUpscaling: false);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    } finally {
      File(outPath).delete().ignore();
    }
  }

  /// Core fit on a grayscale image. Coordinates are pixels of [luma];
  /// returns [tipX, tipY, tailX, tailY] or null. Parameters mirror
  /// [detect]: seed with [nearX]/[nearY] on the release frame, or with the
  /// previous shaft endpoints on the later frame.
  @visibleForTesting
  static List<double>? findShaft(
    Uint8List luma,
    int width,
    int height, {
    double? nearX,
    double? nearY,
    double? prevTipX,
    double? prevTipY,
    double? prevTailX,
    double? prevTailY,
  }) {
    // ---- Edge candidates: Sobel magnitude over an adaptive threshold ----
    final mags = Uint16List(width * height);
    var maxMag = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final gx = (luma[i - width + 1] +
                2 * luma[i + 1] +
                luma[i + width + 1]) -
            (luma[i - width - 1] + 2 * luma[i - 1] + luma[i + width - 1]);
        final gy = (luma[i + width - 1] +
                2 * luma[i + width] +
                luma[i + width + 1]) -
            (luma[i - width - 1] + 2 * luma[i - width] + luma[i - width + 1]);
        final mag = gx.abs() + gy.abs();
        mags[i] = mag;
        if (mag > maxMag) maxMag = mag;
      }
    }
    if (maxMag < 60) return null; // featureless frame

    // Keep roughly the strongest 3% of pixels, never below a noise floor.
    final hist = List<int>.filled(maxMag + 1, 0);
    for (final mag in mags) {
      hist[mag]++;
    }
    final target = (width * height * 0.03).round();
    var acc = 0;
    var thresh = maxMag;
    while (thresh > 60 && acc + hist[thresh] < target) {
      acc += hist[thresh];
      thresh--;
    }

    var xs = <double>[];
    var ys = <double>[];
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (mags[y * width + x] >= thresh) {
          xs.add(x.toDouble());
          ys.add(y.toDouble());
        }
      }
    }
    if (xs.length < 40) return null;
    if (xs.length > 12000) {
      final stride = (xs.length / 12000).ceil();
      final sx = <double>[], sy = <double>[];
      for (var i = 0; i < xs.length; i += stride) {
        sx.add(xs[i]);
        sy.add(ys[i]);
      }
      xs = sx;
      ys = sy;
    }
    final n = xs.length;

    // ---- Constraints from the seed ----
    double? dirX, dirY, prevLen, prevMidX, prevMidY;
    if (prevTipX != null &&
        prevTipY != null &&
        prevTailX != null &&
        prevTailY != null) {
      final ddx = prevTipX - prevTailX, ddy = prevTipY - prevTailY;
      prevLen = math.sqrt(ddx * ddx + ddy * ddy);
      if (prevLen < 20) return null;
      dirX = ddx / prevLen;
      dirY = ddy / prevLen;
      prevMidX = (prevTipX + prevTailX) / 2;
      prevMidY = (prevTipY + prevTailY) / 2;
    }
    List<int>? seedIdx;
    if (nearX != null && nearY != null) {
      seedIdx = <int>[];
      const r2 = 150.0 * 150.0;
      for (var i = 0; i < n; i++) {
        final dx = xs[i] - nearX, dy = ys[i] - nearY;
        if (dx * dx + dy * dy <= r2) seedIdx.add(i);
      }
      if (seedIdx.length < 10) return null;
    }

    // ---- RANSAC for the dominant line satisfying the constraints ----
    final rand = math.Random(0x5eed);
    const band = 2.5; // px from the line that counts as support
    const minCos = 0.94; // ~±20° around the previous shaft direction
    var bestScore = 0;
    var bnx = 0.0, bny = 0.0, bc = 0.0;
    for (var iter = 0; iter < 700; iter++) {
      final i = seedIdx == null
          ? rand.nextInt(n)
          : seedIdx[rand.nextInt(seedIdx.length)];
      final j = rand.nextInt(n);
      final dx = xs[j] - xs[i], dy = ys[j] - ys[i];
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 50) continue;
      if (dirX != null && dirY != null) {
        final cos = (dx * dirX + dy * dirY) / len;
        if (cos.abs() < minCos) continue;
      }
      final nx = -dy / len, ny = dx / len;
      final c = nx * xs[i] + ny * ys[i];
      if (nearX != null &&
          nearY != null &&
          (nx * nearX + ny * nearY - c).abs() > 14) {
        continue;
      }
      if (prevMidX != null &&
          prevMidY != null &&
          (nx * prevMidX + ny * prevMidY - c).abs() > prevLen!) {
        continue;
      }
      var score = 0;
      for (var k = 0; k < n; k++) {
        if ((nx * xs[k] + ny * ys[k] - c).abs() <= band) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bnx = nx;
        bny = ny;
        bc = c;
      }
    }
    if (bestScore < 30) return null;

    // ---- Refine direction with a total-least-squares fit on inliers ----
    final ix = <double>[], iy = <double>[];
    var sumX = 0.0, sumY = 0.0;
    for (var k = 0; k < n; k++) {
      if ((bnx * xs[k] + bny * ys[k] - bc).abs() <= band) {
        ix.add(xs[k]);
        iy.add(ys[k]);
        sumX += xs[k];
        sumY += ys[k];
      }
    }
    final m = ix.length;
    final mx = sumX / m, my = sumY / m;
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (var k = 0; k < m; k++) {
      final dx = ix[k] - mx, dy = iy[k] - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);
    final ux = math.cos(theta), uy = math.sin(theta);

    // ---- The shaft is the longest contiguous run of support along the
    // line (gaps over ~24 px split runs, tolerating hand occlusion). ----
    final ts = <double>[
      for (var k = 0; k < m; k++) (ix[k] - mx) * ux + (iy[k] - my) * uy,
    ]..sort();
    const maxGap = 24.0;
    var runStart = ts[0], last = ts[0];
    var bestStart = ts[0], bestEnd = ts[0];
    for (var k = 1; k < m; k++) {
      if (ts[k] - last > maxGap) {
        if (last - runStart > bestEnd - bestStart) {
          bestStart = runStart;
          bestEnd = last;
        }
        runStart = ts[k];
      }
      last = ts[k];
    }
    if (last - runStart > bestEnd - bestStart) {
      bestStart = runStart;
      bestEnd = last;
    }
    final runLen = bestEnd - bestStart;

    // ---- Sanity checks; failing any means "not convincing" → null ----
    if (runLen < 70) return null;
    if (prevLen != null &&
        (runLen < prevLen * 0.55 || runLen > prevLen * 1.8)) {
      return null;
    }
    var inRun = 0;
    for (final t in ts) {
      if (t >= bestStart && t <= bestEnd) inRun++;
    }
    if (inRun / runLen < 0.35) return null; // sparse: not a solid edge
    if (nearX != null && nearY != null) {
      final tNear = (nearX - mx) * ux + (nearY - my) * uy;
      if (tNear < bestStart - 40 || tNear > bestEnd + 40) return null;
    }
    if (prevMidX != null && prevMidY != null) {
      final cx = mx + ux * (bestStart + bestEnd) / 2;
      final cy = my + uy * (bestStart + bestEnd) / 2;
      final dx = cx - prevMidX, dy = cy - prevMidY;
      // Even a 40 m/s throw can't outrun this between the two frames.
      if (math.sqrt(dx * dx + dy * dy) > prevLen! * 3) return null;
    }

    final e1x = mx + ux * bestStart, e1y = my + uy * bestStart;
    final e2x = mx + ux * bestEnd, e2y = my + uy * bestEnd;

    // ---- Which end is the tip? Nearest the tap, or matching the
    // previous frame's tail→tip direction. ----
    bool e1IsTip;
    if (nearX != null && nearY != null) {
      double d2(double x, double y) =>
          (x - nearX) * (x - nearX) + (y - nearY) * (y - nearY);
      e1IsTip = d2(e1x, e1y) < d2(e2x, e2y);
    } else if (dirX != null && dirY != null) {
      e1IsTip = (e1x - e2x) * dirX + (e1y - e2y) * dirY > 0;
    } else {
      e1IsTip = true;
    }
    return e1IsTip
        ? [e1x, e1y, e2x, e2y]
        : [e2x, e2y, e1x, e1y];
  }
}

class _ShaftJob {
  const _ShaftJob({
    required this.rgba,
    required this.width,
    required this.height,
    this.nearX,
    this.nearY,
    this.prevTipX,
    this.prevTipY,
    this.prevTailX,
    this.prevTailY,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final double? nearX, nearY;
  final double? prevTipX, prevTipY, prevTailX, prevTailY;
}

List<double>? _findShaftInRgba(_ShaftJob job) {
  final luma = Uint8List(job.width * job.height);
  for (var i = 0; i < luma.length; i++) {
    final o = i * 4;
    luma[i] =
        (77 * job.rgba[o] + 150 * job.rgba[o + 1] + 29 * job.rgba[o + 2]) >>
            8;
  }
  return JavelinDetector.findShaft(
    luma,
    job.width,
    job.height,
    nearX: job.nearX,
    nearY: job.nearY,
    prevTipX: job.prevTipX,
    prevTipY: job.prevTipY,
    prevTailX: job.prevTailX,
    prevTailY: job.prevTailY,
  );
}
