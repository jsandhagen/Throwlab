import 'dart:async';
import 'dart:convert';
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

    if (!await _encodePlaybackCopy(srcPath, outPath, onProgress,
        totalMs: totalMs)) {
      File(outPath).delete().ignore();
      return srcPath;
    }
    return outPath;
  }

  /// The playback-copy recipe, shared by the import and by a later remake so
  /// the two can't drift apart. Returns whether the encode succeeded.
  static Future<bool> _encodePlaybackCopy(
    String srcPath,
    String outPath,
    ValueChanged<double?>? onProgress, {
    double? totalMs,
  }) async {
    if (totalMs == null) {
      try {
        final probe = await FFprobeKit.getMediaInformation(srcPath);
        final seconds =
            double.tryParse(probe.getMediaInformation()?.getDuration() ?? '');
        if (seconds != null && seconds > 0) totalMs = seconds * 1000;
      } catch (_) {
        // Progress stays indeterminate.
      }
    }
    final done = Completer<bool>();
    await FFmpegKit.executeAsync(
      // superfast (not ultrafast) keeps CABAC and the deblocking filter
      // on; lanczos keeps 4K downscales sharp; 1440p (not 1080) keeps
      // detail for pinch-zoom. g=6 over g=1: all-intra streams stuttered
      // during playback, while a 6-frame GOP plays like normal video and
      // an exact seek decodes at most 5 cheap P-frames. sc_threshold=0
      // stops scene-cut keyframes from disturbing the uniform grid; bf=0
      // keeps decode order = display order for clean frame stepping. The
      // leading scale=iw*sar bakes any non-square sample aspect into real
      // pixels and setsar=1 clears the tag, so the player can't stretch the
      // clip on playback — the extracted stills are square-pixel JPEGs and
      // couldn't follow it, which made the picture jump horizontally at the
      // scrub handoff. It also keeps on-screen measurements honest.
      //
      // The trailing crop takes both dimensions down to a multiple of 16, a
      // macroblock. H.264 codes anything else up to the next multiple and
      // marks the difference in a crop rectangle — and the texture the
      // player hands Flutter carries the *coded* frame, so the picture gets
      // squeezed into the part of the box that isn't padding. Measured on
      // the reported clip: an 8 px band of edge-replicated padding down the
      // right of every video frame, making the picture 0.74% narrower than
      // the square-pixel still drawn over it. Sized to the macroblock there
      // is no crop rectangle and nothing to disagree about. It costs up to
      // 15 px off the right and bottom — a crop, so nothing is distorted
      // and measurements stay honest.
      '-y -i "$srcPath" '
      '-vf scale=iw*sar:ih,setsar=1,scale=-2:min(1440\\,ih):flags=lanczos,'
      'crop=trunc(iw/16)*16:trunc(ih/16)*16:0:0,setsar=1 '
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
    return done.future;
  }

  /// Abandons the in-flight optimization; the import then keeps the
  /// original file.
  static Future<void> cancel() => FFmpegKit.cancel();

  /// Whether [path] is already shaped the way the current recipe produces:
  /// square pixels, and both dimensions on a macroblock so the coded frame
  /// is the displayed frame.
  ///
  /// Either miss means the file's stored pixels aren't the shape they are
  /// displayed at, and every consumer has to agree about who corrects for it
  /// — which is exactly what goes wrong between the player's texture and a
  /// square-pixel JPEG still. Unreadable files are left alone.
  @visibleForTesting
  static bool isPlaybackGeometryCurrent(
      {required double sampleAspect, required int width, required int height}) {
    if (sampleAspect != 1) return false;
    if (width <= 0 || height <= 0) return true;
    return width % 16 == 0 && height % 16 == 0;
  }

  static Future<bool> _playbackGeometryCurrent(String path) async {
    try {
      final info =
          (await FFprobeKit.getMediaInformation(path)).getMediaInformation();
      if (info == null) return true;
      for (final stream in info.getStreams()) {
        if (stream.getType() != 'video') continue;
        // "0:1" (unspecified) parses to 0 and means square, not degenerate.
        final ratio = parseRate(stream.getSampleAspectRatio());
        return isPlaybackGeometryCurrent(
          sampleAspect: (ratio == null || ratio <= 0) ? 1 : ratio,
          width: stream.getWidth()?.toInt() ?? 0,
          height: stream.getHeight()?.toInt() ?? 0,
        );
      }
    } catch (_) {
      // Unreadable → leave the clip alone.
    }
    return true;
  }

  /// Re-encodes [video]'s playback copy with the current recipe when it was
  /// made by an older one, and returns its path — unchanged when nothing
  /// needed doing.
  ///
  /// Only clips that are actually shaped wrong are re-encoded; the rest are
  /// just stamped, so bringing an existing library up to date costs one
  /// probe per clip instead of a full re-encode. The new copy is built beside
  /// the old one and renamed over it, so a failure or a cancel leaves the
  /// working file in place — and renaming under an open player is safe, since
  /// the already-open handle keeps serving the old content until the screen
  /// is reopened.
  static Future<String?> remakePlaybackCopy(
    String srcPath,
    String id, {
    ValueChanged<double?>? onProgress,
  }) async {
    if (await _playbackGeometryCurrent(srcPath)) return null;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/throws');
    await dir.create(recursive: true);
    final outPath = '${dir.path}/$id.mp4';
    final staging = '${dir.path}/$id.remake.mp4';
    File(staging).delete().ignore();
    final made = await _encodePlaybackCopy(srcPath, staging, onProgress);
    if (!made) {
      File(staging).delete().ignore();
      return null;
    }
    try {
      await File(staging).rename(outPath);
    } catch (_) {
      File(staging).delete().ignore();
      return null;
    }
    return outPath;
  }

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

  /// Current recipe for the playback copy. Bump whenever its *geometry*
  /// changes, so clips encoded by an older recipe are re-made on open.
  ///
  /// The stills have had this since [scrubFramesVersion] existed; the video
  /// they cover did not, and that asymmetry is a bug in its own right. A
  /// clip imported before the playback copy started baking a non-square
  /// sample aspect into pixels keeps that sample aspect live in the file,
  /// while its stills re-extract at the current recipe with the aspect baked
  /// in — so the still is wider than the video by exactly the sample aspect,
  /// and the picture jumps sideways at every scrub handoff.
  ///   1 — a non-square sample aspect is baked into real pixels, matching
  ///       the stills (see [scrubFramesVersion] 4).
  ///   2 — both dimensions are a multiple of 16, so the coded frame is the
  ///       displayed frame and there is no crop rectangle for the player's
  ///       texture to ignore. Measured on a real clip, the padding showed as
  ///       an 8 px replicated band down the right edge and left the video
  ///       0.74% narrower than the stills covering it.
  static const playbackVersion = 2;

  /// Current extraction recipe. Bump whenever the stills' resolution or
  /// geometry changes: clips carry the version that produced theirs, and any
  /// clip below this re-extracts when opened.
  ///   1 — 640px long side.
  ///   2 — [scrubFrameMax] long side.
  ///   3 — even dimensions, so the stills match the playback copy's width
  ///       rounding (a 1080x2340 clip yielded 665px-wide stills against a
  ///       664px-wide video, which the overlay stretched to cover).
  ///   4 — a non-square sample aspect is baked into real pixels, matching
  ///       what the player does with the video. Measured on a real clip,
  ///       skipping this left the stills 0.78% narrower than the video, so
  ///       the picture shifted sideways when a scrub ended.
  ///   5 — each still's real presentation time is recorded alongside it, so
  ///       a scrub ends on the frame the still was showing instead of a
  ///       neighbour on clips that aren't exactly constant-rate.
  static const scrubFramesVersion = 5;

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
    // scale=iw*sar,setsar=1 first: a non-square sample aspect has to become
    // real pixels here, because the player applies it to the video while a
    // JPEG has nowhere to carry it — leaving the stills a fraction narrower
    // than the video they cover. force_divisible_by=2 then matches the
    // playback copy's "-2" width rounding, so the two agree exactly rather
    // than differing by the odd pixel.
    final select = stride > 1 ? "select='not(mod(n\\,$stride))'," : '';
    final vf = '${select}scale=iw*sar:ih,setsar=1,'
        'scale=w=$scrubFrameMax:h=$scrubFrameMax:'
        'force_original_aspect_ratio=decrease:force_divisible_by=2';

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
    await _writeFrameTimes(videoPath, dir, stride, count);
    try {
      if (await finalDir.exists()) await finalDir.delete(recursive: true);
      await dir.rename(finalDir.path);
    } catch (_) {
      dir.delete(recursive: true).ignore();
      return null;
    }
    return (dir: finalDir.path, count: count, stride: stride);
  }

  /// File written beside the stills holding each one's presentation time in
  /// seconds, one per line. [ScrubFrames] uses it to map between a position
  /// and a still exactly.
  static const framesTimesFile = 'times.csv';

  /// Records when each extracted still is actually shown, straight from the
  /// clip's own timestamps.
  ///
  /// Deriving it as index*stride/fps instead assumes the clip is exactly
  /// constant-rate, starts at zero, and was probed with the exact rate.
  /// Phone slow-mo satisfies none of those dependably, and being wrong by a
  /// fraction of a frame is enough to land the video on the neighbouring
  /// frame when a scrub ends — consistently, in whichever direction the
  /// error runs. Best-effort: without this file ScrubFrames falls back to
  /// the arithmetic.
  static Future<void> _writeFrameTimes(
      String videoPath, Directory dir, int stride, int count) async {
    try {
      final session = await FFprobeKit.execute(
          '-v error -select_streams v:0 -show_entries frame=pts_time '
          '-of csv=p=0 "$videoPath"');
      if (!ReturnCode.isSuccess(await session.getReturnCode())) return;
      final output = await session.getOutput();
      if (output == null || output.isEmpty) return;
      final times = <double>[];
      for (final line in const LineSplitter().convert(output)) {
        final value = double.tryParse(line.trim().split(',').first);
        // A stream can report frames without a timestamp; a gap would
        // misalign every later still, so bail out rather than guess.
        if (value == null) continue;
        times.add(value);
      }
      final kept = <double>[
        for (var i = 0; i < times.length; i += stride) times[i],
      ];
      if (kept.length < count) return;
      await File('${dir.path}/$framesTimesFile')
          .writeAsString(kept.take(count).join('\n'));
    } catch (_) {
      // Falls back to the fps arithmetic.
    }
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
