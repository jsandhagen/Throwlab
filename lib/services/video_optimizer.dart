import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/zoom_detail.dart';

/// Re-encodes an imported clip with a keyframe every few frames.
/// Phone recordings keep keyframes seconds apart, so an exact seek has to
/// decode every frame since the previous keyframe; a tiny GOP caps that
/// work at a handful of frames, which is what lets frame-by-frame
/// scrubbing feel instant. (All-intra would cap it at one frame, but its
/// ~100+ Mbps bitrate makes continuous playback stutter.)
class VideoOptimizer {
  /// Returns the path of the optimized copy, or [srcPath] if encoding
  /// fails or is canceled — the original still plays, scrubbing is just
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
      final probe = await _probe(srcPath);
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

  /// Takes a just-filmed clip into the app's own storage as it was shot, and
  /// returns its path — no re-encode, so it costs a file copy rather than
  /// the minutes [optimizeForScrubbing] takes.
  ///
  /// This is what filming at a meet needs: the camera hands back a file in a
  /// cache the OS will clear, and the next athlete is up. The clip lands
  /// where a re-encoded one would, so the encode can be done later in place
  /// (see ThrowVideo.optimizePending). Returns null if the copy fails, which
  /// leaves the caller with nothing worth storing.
  static Future<String?> stashCapture(String srcPath, String id) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/throws');
      await dir.create(recursive: true);
      final outPath = '${dir.path}/$id.mp4';
      await File(srcPath).copy(outPath);
      return outPath;
    } catch (_) {
      return null;
    }
  }

  /// The playback-copy recipe, shared by the import and by a later remake so
  /// the two can't drift apart. Returns whether the encode succeeded.
  static Future<bool> _encodePlaybackCopy(
    String srcPath,
    String outPath,
    ValueChanged<double?>? onProgress, {
    double? totalMs,
  }) async {
    // Probed for two things: how long the clip is, so progress has a
    // denominator, and what color it is in — see [colorTagsFor].
    var colorTags = '';
    try {
      final probe = await _probe(srcPath);
      final info = probe.getMediaInformation();
      if (totalMs == null) {
        final seconds = double.tryParse(info?.getDuration() ?? '');
        if (seconds != null && seconds > 0) totalMs = seconds * 1000;
      }
      for (final stream in info?.getStreams() ?? []) {
        if (stream.getType() != 'video') continue;
        colorTags = colorTagsFor(
          colorSpace: '${stream.getAllProperties()?['color_space'] ?? ''}',
          height: stream.getHeight(),
        );
        break;
      }
    } catch (_) {
      // Progress stays indeterminate, and the copy keeps whatever color
      // metadata the source had.
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
      '-pix_fmt yuv420p$colorTags -c:a copy "$outPath"',
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
      final info = (await _probe(path)).getMediaInformation();
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
  ///
  /// [force] encodes whatever the geometry says, for a clip that was never
  /// encoded at all: a meet capture is the camera's own file, and its fault
  /// is the seconds between keyframes rather than the shape of its pixels.
  static Future<String?> remakePlaybackCopy(
    String srcPath,
    String id, {
    ValueChanged<double?>? onProgress,
    bool force = false,
  }) async {
    if (!force && await _playbackGeometryCurrent(srcPath)) return null;
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
  ///   6 — both ends of the JPEG's color conversion are named (see
  ///       [jpegColorFilter]). Measured on a real clip, the stills held
  ///       Rec. 709 numbers that Flutter then read as Rec. 601, which cost
  ///       the red track ~9 levels of red for as long as a finger was down.
  static const scrubFramesVersion = 6;

  /// Pre-extracts frames as JPEGs so scrubbing can show cached stills at
  /// display rate instead of waiting on the decoder to seek. Returns the
  /// directory, the number of frames written, and the stride (1 = every
  /// frame), or null if extraction failed or was canceled — the caller then
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
    // frames if it fails or is canceled partway.
    final finalDir = Directory('${docs.path}/throws/frames/$id');
    final dir = Directory('${docs.path}/throws/frames/$id.tmp');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    double? seconds;
    try {
      final probe = await _probe(videoPath);
      seconds =
          double.tryParse(probe.getMediaInformation()?.getDuration() ?? '');
    } catch (_) {
      // Total unknown → assume no striding is needed.
    }
    // What color the clip is in, so the stills are written out of it rather
    // than out of a guess — see [jpegColorFilter].
    final color = await _jpegColorFilterFor(videoPath);
    final total = (seconds != null && fps > 0) ? (seconds * fps).round() : 0;
    final stride =
        total > _maxScrubFrames ? (total / _maxScrubFrames).ceil() : 1;

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
    // The color conversion rides on the same scale, which is the only place
    // the pixels are touched.
    final select = stride > 1 ? "select='not(mod(n\\,$stride))'," : '';
    final vf = '${select}scale=iw*sar:ih,setsar=1,'
        'scale=w=$scrubFrameMax:h=$scrubFrameMax:'
        'force_original_aspect_ratio=decrease:force_divisible_by=2:$color';

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
    final count = dir.listSync().where((e) => e.path.endsWith('.jpg')).length;
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

  /// What ffprobe knows about [path], asked for with its logging switched
  /// off.
  ///
  /// ffmpeg-kit reads the answer out of *everything* the run printed, log
  /// lines included, and parses the lot as one JSON document. Its own
  /// [FFprobeKit.getMediaInformation] asks at `-v error`, so a file ffmpeg
  /// has a single complaint about — and a Samsung clip carries enough of its
  /// own metadata to draw one — comes back as no information at all: no
  /// duration, no color, and a frame rate that fell back to 30. Quiet, the
  /// output is the JSON and nothing else.
  static Future<MediaInformationSession> _probe(String path) =>
      FFprobeKit.getMediaInformationFromCommandArguments([
        '-v',
        'quiet',
        '-hide_banner',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        '-i',
        path,
      ]);

  /// Frame rates and recording time probed from the clip's metadata.
  /// [playback] is the container rate that frame stepping must use;
  /// [capture] is the real recorded rate — slow-mo clips often play at
  /// 30 fps while each frame represents 1/240 s of real time, advertised
  /// by Android via the com.android.capture.fps tag. [recordedAt] is the
  /// camera's creation_time tag (UTC), null when absent.
  ///
  /// Read as plain `key=value` lines rather than through ffmpeg-kit's JSON,
  /// for the reason [_probe] gives: this is the one number every frame step,
  /// every timer and every measured speed is built on, and when the JSON
  /// failed to parse it failed silently, to 30.
  static Future<
      ({
        double playback,
        double capture,
        DateTime? recordedAt,
      })?> probeFrameRates(String path) async {
    try {
      final session = await FFprobeKit.executeWithArguments([
        '-v',
        'quiet',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=avg_frame_rate,r_frame_rate,nb_frames,duration'
            ':stream_tags=com.android.capture.fps,creation_time'
            ':format_tags=com.android.capture.fps,creation_time',
        '-of',
        'default=noprint_wrappers=1',
        path,
      ]);
      return readFrameRates(await session.getOutput() ?? '');
    } catch (_) {
      return null;
    }
  }

  /// The rates out of [probeFrameRates]' output: the stream's own lines
  /// first, then the container's tags. The playback rate is the stream's
  /// average; where that is missing or nonsense (`0/0`, or a timescale
  /// passed off as a rate) it is the frames counted over the duration, and
  /// only then the guessed `r_frame_rate`.
  @visibleForTesting
  static ({double playback, double capture, DateTime? recordedAt})?
      readFrameRates(String output) {
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final split = line.indexOf('=');
      if (split <= 0) continue;
      // The first of each wins: the stream is printed before the container.
      values.putIfAbsent(line.substring(0, split).trim(),
          () => line.substring(split + 1).trim());
    }
    double? sane(double? rate) =>
        rate != null && rate >= 1 && rate <= 1000 ? rate : null;
    final frames = double.tryParse(values['nb_frames'] ?? '');
    final seconds = double.tryParse(values['duration'] ?? '');
    final counted = frames != null && seconds != null && seconds > 0
        ? frames / seconds
        : null;
    final playback = sane(parseRate(values['avg_frame_rate'])) ??
        sane(counted) ??
        sane(parseRate(values['r_frame_rate']));
    if (playback == null) return null;
    final capture = sane(parseRate(values['TAG:com.android.capture.fps']));
    return (
      playback: playback,
      capture: math.max(capture ?? playback, playback),
      recordedAt: DateTime.tryParse(values['TAG:creation_time'] ?? ''),
    );
  }

  /// The color tags to write onto the playback copy, or empty to leave the
  /// source's own metadata alone.
  ///
  /// A clip that says nothing about its color leaves everything that reads
  /// it to guess, and the two things this app points at one throw guess
  /// differently: a video player treats untagged HD as Rec. 709, which is
  /// what a phone actually shoots, while ffmpeg's scaler falls back to the
  /// older Rec. 601 whatever the size. That is one and the same picture
  /// converted two ways — and it is visible, because the smooth-scrub
  /// stills come from ffmpeg and the frame they hand back to at the end of
  /// a drag comes from the player. Saying which it is stops the guessing at
  /// the source. It is only half of it, though: a tag settles what the
  /// pixels mean, and [jpegColorFilter] is what makes the stills written out
  /// of them mean the same thing.
  ///
  /// Only for HD, and only when nobody has said: standard-definition
  /// footage really is Rec. 601, and a clip that declares its color is
  /// already unambiguous to both of them.
  @visibleForTesting
  static String colorTagsFor({String? colorSpace, int? height}) {
    final declared = (colorSpace ?? '').trim().toLowerCase();
    final known =
        declared.isNotEmpty && declared != 'unknown' && declared != 'n/a';
    if (known || (height ?? 0) < 720) return '';
    return ' -colorspace bt709 -color_primaries bt709 -color_trc bt709';
  }

  /// The matrix ffmpeg has to read a clip's YCbCr with, named the way
  /// swscale names them: whatever the clip declares, and failing that the
  /// same guess a player makes — Rec. 709 for HD, Rec. 601 for standard
  /// definition. Deliberately the same rule [colorTagsFor] writes, so the
  /// two ends of a clip can't come to different conclusions about an
  /// untagged one. 'auto' for a clip that was not measured at all: leaving
  /// ffmpeg to its own default beats inventing a matrix for it.
  @visibleForTesting
  static String readMatrixFor({String? colorSpace, int? height}) {
    switch ((colorSpace ?? '').trim().toLowerCase()) {
      case 'bt709':
        return 'bt709';
      case 'bt601':
      case 'bt470bg':
      case 'smpte170m':
        return 'bt601';
      case 'smpte240m':
        return 'smpte240m';
      case 'fcc':
        return 'fcc';
      case 'bt2020nc':
      case 'bt2020_ncl':
        return 'bt2020';
    }
    if ((height ?? 0) <= 0) return 'auto';
    return height! >= 720 ? 'bt709' : 'bt601';
  }

  /// The color half of the scale every JPEG this class writes goes through.
  ///
  /// A JPEG has nowhere to say what its numbers mean: the format *is*
  /// full-range Rec. 601, and every decoder — Flutter's included — reads one
  /// that way. Handed a Rec. 709 clip, ffmpeg writes the JPEG by stretching
  /// the range and leaving the coefficients where they were, so the file
  /// ends up holding 709 numbers that are then read as 601. Naming both ends
  /// of the conversion is what stops it: read the clip with the matrix it is
  /// actually in, write the matrix a JPEG is actually read with.
  ///
  /// This is the other half of the shift [colorTagsFor] went after, and the
  /// bigger half — a tag on the clip settles what the video means, and this
  /// settles what the still standing in for it means. It is not a rounding
  /// difference: it desaturates and swings the hue of anything strongly
  /// colored, measured at ~9 levels of red on a red track, for exactly as
  /// long as a finger is down on a scrub.
  ///
  /// Returned as scale options rather than a filter of its own, so it rides
  /// on the scale that is already resizing the frame instead of costing a
  /// second pass over it.
  @visibleForTesting
  static String jpegColorFilter({String? colorSpace, int? height}) =>
      'in_color_matrix=${readMatrixFor(colorSpace: colorSpace, height: height)}'
      ':out_color_matrix=bt601:out_range=pc';

  /// [jpegColorFilter] for the clip at [path], read off the clip itself. A
  /// file that won't probe falls back to what ffmpeg would have read it as,
  /// which is no worse than before it was asked.
  static Future<String> _jpegColorFilterFor(String path) async {
    try {
      final info = (await _probe(path)).getMediaInformation();
      for (final stream in info?.getStreams() ?? []) {
        if (stream.getType() != 'video') continue;
        return jpegColorFilter(
          colorSpace: '${stream.getAllProperties()?['color_space'] ?? ''}',
          height: stream.getHeight(),
        );
      }
    } catch (_) {
      // Unmeasured → 'auto' below.
    }
    return jpegColorFilter();
  }

  /// The filter a zoom detail still is drawn through: [crop] cut out of the
  /// frame at [at] and scaled up to the screen's pixels. See zoom_detail.dart
  /// for why, and [renderDetail] for where it runs.
  ///
  /// The frame is first brought to the size the player reports it at, the
  /// way the stills are — square pixels, then the player's own dimensions,
  /// which for the playback copy is already exactly what it is and costs
  /// nothing. That is the size the crop was measured in, so whatever the
  /// file turns out to be, the piece cut from it is the piece that was on
  /// screen. `exact` stops the crop being rounded to the chroma grid behind
  /// the crop's back; the crop is already on it.
  ///
  /// Scaled with lanczos, and then clamped. Lanczos makes an edge steep by
  /// overshooting it: left alone it drew a dark rim round a white block and a
  /// bright fringe down every edge between two colors, and pushed the most
  /// saturated color on the frame past anything the clip holds. So nothing
  /// leaves the range of the clip's own pixels around it: `erosion` and
  /// `dilation` take each pixel's darkest and brightest 3x3 neighbor, plane
  /// by plane, at the clip's resolution, those two bounds are scaled up
  /// bilinearly beside the picture, and `maskedclamp` holds the picture
  /// between them. An edge keeps its steepness, which is what reads as sharp,
  /// and none of its overshoot — and because the chroma planes are clamped
  /// the same way, no color comes out stronger than the colors it sits among.
  /// On a frame of hard edges, saturated patches, thin lines and grass the
  /// color peaks at 101, exactly as the bilinear zoom's does, against the
  /// clip's own 103.
  ///
  /// No sharpening on top, though it was tried. An unsharp mask lifts
  /// whatever is finest in the picture, and in a phone's footage of a field
  /// that is the compression — grain in the grass, blocks in the trees. The
  /// clamp can't catch it, because noise stays inside the range of its
  /// neighbors. Measured on a real throw, the fine-grain energy in the trees
  /// rose 42% over the bilinear zoom with an unsharp of 0.6 and 16% without,
  /// and at 4x it drew the codec's blocks as a checkerboard.
  ///
  /// The color is written the way every other JPEG here is
  /// ([jpegColorFilter]), and after the clamp, so the bounds and the picture
  /// are compared in the clip's own numbers. Otherwise the sharp still would
  /// be a shade off the soft frame it lands on — the scrub shift again, at
  /// 8x.
  @visibleForTesting
  static String detailCommand({
    required String videoPath,
    required String outPath,
    required Duration at,
    required DetailCrop crop,
    required String color,
  }) {
    final seconds =
        (at.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(6);
    final size = '${crop.outWidth}:${crop.outHeight}';
    final vf = 'scale=iw*sar:ih,setsar=1,'
        'scale=${crop.frameWidth}:${crop.frameHeight},'
        'crop=${crop.width}:${crop.height}:${crop.x}:${crop.y}:exact=1,'
        'split=3[pic][lo][hi];'
        '[pic]scale=$size:flags=lanczos[sharp];'
        '[lo]erosion,scale=$size:flags=bilinear[floor];'
        '[hi]dilation,scale=$size:flags=bilinear[ceiling];'
        '[sharp][floor][ceiling]maskedclamp=undershoot=0:overshoot=0,'
        'scale=$size:$color';
    // -ss ahead of -i seeks the input and then decodes forward, discarding
    // every frame before the position: the first frame at or after it, which
    // is the rule the player keeps after a seek. q:v 2 because this is the
    // one JPEG here that is looked at closely.
    return '-y -ss $seconds -i "$videoPath" -frames:v 1 -vf "$vf" '
        '-q:v 2 "$outPath"';
  }

  /// [_jpegColorFilterFor], asked once per clip: the detail still is
  /// rendered every time a zoomed frame settles, and the answer can't change
  /// under an open clip.
  static final Map<String, String> _detailColor = {};

  static int _detailSerial = 0;

  /// Renders [crop] of the frame at [at] — see [detailCommand] — and returns
  /// the JPEG's bytes, or null if ffmpeg could not. The file is only the way
  /// ffmpeg hands them over and is gone before this returns: a still is for
  /// one pinch on one frame, and never worth the disk.
  static Future<Uint8List?> renderDetail(
    String videoPath, {
    required Duration at,
    required DetailCrop crop,
  }) async {
    final temp = await getTemporaryDirectory();
    final out = File('${temp.path}/detail_${_detailSerial++}.jpg');
    final color =
        _detailColor[videoPath] ??= await _jpegColorFilterFor(videoPath);
    try {
      final session = await FFmpegKit.execute(detailCommand(
        videoPath: videoPath,
        outPath: out.path,
        at: at,
        crop: crop,
        color: color,
      ));
      if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
      return await out.readAsBytes();
    } catch (_) {
      return null;
    } finally {
      out.delete().ignore();
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
  static Future<String?> extractThumbnail(String videoPath, String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/throws');
    await dir.create(recursive: true);
    final outPath = '${dir.path}/$id.jpg';
    // Same JPEG, same conversion: a card whose thumbnail is a shade off the
    // clip it opens is the scrub shift again, standing still.
    final color = await _jpegColorFilterFor(videoPath);
    final session = await FFmpegKit.execute(
      '-y -ss 0.3 -i "$videoPath" -frames:v 1 -vf scale=480:-2:$color '
      '-q:v 4 "$outPath"',
    );
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      File(outPath).delete().ignore();
      return null;
    }
    return outPath;
  }
}
