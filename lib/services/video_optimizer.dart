import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Re-encodes an imported clip with a keyframe every few frames.
/// Phone recordings keep keyframes seconds apart, so an exact seek has to
/// decode every frame since the previous keyframe; a tiny GOP caps that
/// work at a handful of frames, which is what lets frame-by-frame
/// scrubbing feel instant. (All-intra would cap it at one frame, but its
/// ~100+ Mbps bitrate makes continuous playback stutter.)
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
      // superfast (not ultrafast) keeps CABAC and the deblocking filter
      // on; lanczos keeps 4K downscales sharp; 1440p (not 1080) keeps
      // detail for pinch-zoom. g=6 over g=1: all-intra streams stuttered
      // during playback, while a 6-frame GOP plays like normal video and
      // an exact seek decodes at most 5 cheap P-frames. sc_threshold=0
      // stops scene-cut keyframes from disturbing the uniform grid; bf=0
      // keeps decode order = display order for clean frame stepping.
      '-y -i "$srcPath" -vf scale=-2:min(1440\\,ih):flags=lanczos '
      '-c:v libx264 -preset superfast -crf 17 -g 6 -bf 0 -sc_threshold 0 '
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

  /// Largest number of frames to pre-extract per clip. Beyond this the
  /// extraction strides over source frames so a long or very high-fps clip
  /// can't blow up disk use — scrubbing stays smooth on the extracted grid
  /// and exact frame steps still fall back to seeking.
  static const _maxScrubFrames = 720;

  /// Longest-side cap for the extracted scrub frames. Matches the 1440p
  /// playback copy exactly, so the stills shown while scrubbing are
  /// indistinguishable from the video they stand in for — the earlier 640
  /// cap was a visible resolution drop the moment the finger moved. The
  /// cost is disk: on detailed outdoor footage this is ~200 MB at the
  /// [_maxScrubFrames] cap versus ~50 MB at 640, which is why deleting a
  /// clip now reclaims its frame directory (see VideoLibrary.remove).
  /// Bounding the long side (not the width) keeps portrait and landscape
  /// clips at the same per-frame memory; ScrubFrames budgets its decoded
  /// cache in bytes, so this can grow without exhausting RAM. Clips
  /// extracted at an older, smaller cap are re-extracted on open (see
  /// AnalysisScreen), which is why the value is public.
  static const scrubFrameMax = 1440;

  /// Pre-extracts frames as JPEGs so scrubbing can show cached stills at
  /// display rate instead of waiting on the decoder to seek. Returns the
  /// directory, the number of frames written, and the stride (1 = every
  /// frame), or null if extraction failed or was cancelled — the caller then
  /// keeps the seek-based scrub path. [onProgress] gets 0..1 while running.
  static Future<({String dir, int count, int stride})?> extractScrubFrames(
    String videoPath,
    String id,
    double fps, {
    ValueChanged<double?>? onProgress,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    // Extract beside the live directory and swap in only when complete, so
    // a re-extraction (resolution upgrade) can't destroy a working set of
    // frames if it fails or is cancelled partway.
    final finalDir = Directory('${docs.path}/throws/frames/$id');
    final dir = Directory('${docs.path}/throws/frames/$id.tmp');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    double? seconds;
    try {
      final probe = await FFprobeKit.getMediaInformation(videoPath);
      seconds =
          double.tryParse(probe.getMediaInformation()?.getDuration() ?? '');
    } catch (_) {
      // Total unknown → assume no striding is needed.
    }
    final total = (seconds != null && fps > 0) ? (seconds * fps).round() : 0;
    final stride = total > _maxScrubFrames ? (total / _maxScrubFrames).ceil() : 1;

    // select drops all but every Nth frame; -vsync 0 stops ffmpeg from
    // re-timing (duplicating/dropping) what select left, so output image k
    // maps cleanly to source frame k*stride. The scale fits each frame inside
    // a square box, preserving aspect and only ever shrinking.
    final select = stride > 1 ? "select='not(mod(n\\,$stride))'," : '';
    final vf = '${select}scale=w=$scrubFrameMax:h=$scrubFrameMax:'
        'force_original_aspect_ratio=decrease';

    final done = Completer<bool>();
    final totalMs = (seconds ?? 0) * 1000;
    await FFmpegKit.executeAsync(
      // q:v 5 at this resolution is already well past what the eye resolves
      // mid-scrub; q:v 4 costs ~13% more disk for no visible gain.
      '-y -i "$videoPath" -vf "$vf" -vsync 0 -q:v 5 "${dir.path}/f%05d.jpg"',
      (session) async {
        done.complete(ReturnCode.isSuccess(await session.getReturnCode()));
      },
      null,
      (statistics) {
        if (totalMs <= 0) return;
        onProgress?.call((statistics.getTime() / totalMs).clamp(0.0, 1.0));
      },
    );
    if (!await done.future) {
      dir.delete(recursive: true).ignore();
      return null;
    }
    final count = dir
        .listSync()
        .where((e) => e.path.endsWith('.jpg'))
        .length;
    if (count == 0) {
      dir.delete(recursive: true).ignore();
      return null;
    }
    try {
      if (await finalDir.exists()) await finalDir.delete(recursive: true);
      await dir.rename(finalDir.path);
    } catch (_) {
      dir.delete(recursive: true).ignore();
      return null;
    }
    return (dir: finalDir.path, count: count, stride: stride);
  }

  /// Frame rates and recording time probed from the clip's metadata.
  /// [playback] is the container rate that frame stepping must use;
  /// [capture] is the real recorded rate — slow-mo clips often play at
  /// 30 fps while each frame represents 1/240 s of real time, advertised
  /// by Android via the com.android.capture.fps tag. [recordedAt] is the
  /// camera's creation_time tag (UTC), null when absent.
  static Future<
      ({
        double playback,
        double capture,
        DateTime? recordedAt,
      })?> probeFrameRates(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return null;
      double? playback;
      double? capture;
      DateTime? recordedAt =
          DateTime.tryParse('${info.getTags()?['creation_time'] ?? ''}');
      for (final stream in info.getStreams()) {
        if (stream.getType() != 'video') continue;
        playback ??= parseRate(stream.getAverageFrameRate()) ??
            parseRate(stream.getRealFrameRate());
        capture ??= parseRate(
            '${stream.getTags()?['com.android.capture.fps'] ?? ''}');
        recordedAt ??= DateTime.tryParse(
            '${stream.getTags()?['creation_time'] ?? ''}');
      }
      capture ??=
          parseRate('${info.getTags()?['com.android.capture.fps'] ?? ''}');
      if (playback == null) return null;
      return (
        playback: playback,
        capture: math.max(capture ?? playback, playback),
        recordedAt: recordedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses ffprobe rate strings: "240", "240.000000", or "30000/1001".
  @visibleForTesting
  static double? parseRate(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('/');
    final numerator = double.tryParse(parts[0]);
    if (numerator == null || numerator <= 0) return null;
    if (parts.length == 1) return numerator;
    final denominator = double.tryParse(parts[1]);
    if (denominator == null || denominator <= 0) return null;
    return numerator / denominator;
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
