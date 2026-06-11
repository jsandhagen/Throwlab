import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Re-encodes an imported clip so every frame is a keyframe (`-g 1`).
/// Phone recordings keep keyframes seconds apart, so an exact seek has to
/// decode every frame since the previous keyframe; all-intra video makes
/// each seek decode exactly one frame, which is what lets frame-by-frame
/// scrubbing feel instant.
class VideoOptimizer {
  /// Returns the path of the optimized copy, or [srcPath] if encoding
  /// fails or is cancelled — the original still plays, scrubbing is just
  /// slower. [onProgress] gets 0..1 while encoding (null when the clip's
  /// duration is unknown).
  static Future<String> optimizeForScrubbing(
    String srcPath,
    String id, {
    ValueChanged<double?>? onProgress,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/throws');
    await dir.create(recursive: true);
    final outPath = '${dir.path}/$id.mp4';

    double? totalMs;
    try {
      final probe = await FFprobeKit.getMediaInformation(srcPath);
      final seconds =
          double.tryParse(probe.getMediaInformation()?.getDuration() ?? '');
      if (seconds != null && seconds > 0) totalMs = seconds * 1000;
    } catch (_) {
      // Progress stays indeterminate.
    }

    final done = Completer<bool>();
    await FFmpegKit.executeAsync(
      '-y -i "$srcPath" -vf scale=-2:min(1080\\,ih) -c:v libx264 '
      '-preset ultrafast -tune fastdecode -crf 21 -g 1 -bf 0 '
      '-pix_fmt yuv420p -c:a copy "$outPath"',
      (session) async {
        done.complete(ReturnCode.isSuccess(await session.getReturnCode()));
      },
      null,
      (statistics) {
        final total = totalMs;
        if (total == null) return;
        final ms = statistics.getTime().toDouble();
        onProgress?.call((ms / total).clamp(0.0, 1.0));
      },
    );
    if (!await done.future) {
      File(outPath).delete().ignore();
      return srcPath;
    }
    return outPath;
  }

  /// Abandons the in-flight optimization; the import then keeps the
  /// original file.
  static Future<void> cancel() => FFmpegKit.cancel();

  /// Extracts a still frame for the library list; null when it fails.
  static Future<String?> extractThumbnail(
      String videoPath, String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/throws');
    await dir.create(recursive: true);
    final outPath = '${dir.path}/$id.jpg';
    final session = await FFmpegKit.execute(
      '-y -ss 0.3 -i "$videoPath" -frames:v 1 -vf scale=480:-2 '
      '-q:v 4 "$outPath"',
    );
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      File(outPath).delete().ignore();
      return null;
    }
    return outPath;
  }
}
