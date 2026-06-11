import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Re-encodes an imported clip so every frame is a keyframe (`-g 1`).
/// Phone recordings keep keyframes seconds apart, so an exact seek has to
/// decode every frame since the previous keyframe; all-intra video makes
/// each seek decode exactly one frame, which is what lets frame-by-frame
/// scrubbing feel instant.
class VideoOptimizer {
  /// Returns the path of the optimized copy, or [srcPath] if encoding
  /// fails — the original still plays, scrubbing is just slower.
  static Future<String> optimizeForScrubbing(
      String srcPath, String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/throws');
    await dir.create(recursive: true);
    final outPath = '${dir.path}/$id.mp4';
    final session = await FFmpegKit.execute(
      '-y -i "$srcPath" -c:v libx264 -preset veryfast -crf 20 '
      '-g 1 -bf 0 -pix_fmt yuv420p -c:a copy "$outPath"',
    );
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      File(outPath).delete().ignore();
      return srcPath;
    }
    return outPath;
  }

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
