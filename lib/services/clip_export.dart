import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../models/throw_video.dart';
import '../widgets/drawing_canvas.dart';
import 'video_optimizer.dart';

/// The drawings on a throw as they stood when somebody asked to share it:
/// the marks, the size of the frame they were laid out on, and where the
/// clip was — which is what a timer reads from and which frame a still is.
class ThrowDrawing {
  const ThrowDrawing({
    required this.annotations,
    required this.layout,
    required this.position,
    required this.labelStyle,
  });

  final List<Annotation> annotations;

  /// The frame's size on screen, in logical pixels. Marks are stored
  /// normalized, but their ink and their labels are sized in pixels of the
  /// screen they were drawn on, so the export lays them out at that size and
  /// scales the lot up to the clip's — a stroke as thick against the
  /// athlete as it was on the phone.
  final Size layout;
  final Duration position;
  final TextStyle labelStyle;

  bool get isEmpty => annotations.isEmpty;

  /// A timer reads the clip's own clock, so a clip carrying one has to be
  /// drawn frame by frame; everything else is one picture laid over all of
  /// it.
  bool get moves => annotations.any((a) => a is TimerMarker);
}

/// A throw made into something that can leave the app: the clip with its
/// drawings burned in, or the frame on screen as a picture.
///
/// The drawings are painted by the app's own painter — the same ink, the
/// same type for an angle's degrees and a timer's clock — onto a
/// transparent frame the size of the clip, and ffmpeg lays that over the
/// video. A drawing with a timer in it is painted once per frame, since the
/// timer counts; one without is painted once.
class ClipExport {
  /// Writes [video] with [drawing] over it to a new file in the temporary
  /// directory and returns its path, or null when it failed or was
  /// canceled. [pixels] is the clip's frame size. [onProgress] runs 0..1.
  static Future<String?> clip(
    ThrowVideo video, {
    required ThrowDrawing drawing,
    required Size pixels,
    required Duration duration,
    required String name,
    bool Function()? canceled,
    ValueChanged<double?>? onProgress,
  }) async {
    final dir = await _workDir();
    final out = '${dir.path}/$name.mp4';
    final frames = Directory('${dir.path}/overlay')..createSync();
    String command;
    double? encodeFrom;
    if (!drawing.moves) {
      final png = '${frames.path}/overlay.png';
      await File(png).writeAsBytes(await overlayPng(drawing, pixels));
      command = stillOverlayCommand(video.path, png, out);
      encodeFrom = 0;
    } else {
      // Painted per frame of the clip, numbered from one so ffmpeg's image
      // sequence reads them in order, at the clip's own rate.
      final count = (duration.inMicroseconds * video.fps / 1e6).ceil();
      for (var i = 0; i < count; i++) {
        if (canceled?.call() ?? false) {
          await frames.delete(recursive: true);
          return null;
        }
        final frame = Duration(microseconds: (i * 1e6 / video.fps).round());
        final bytes = await overlayPng(drawing, pixels, at: frame);
        await File('${frames.path}/${overlayFrame(i + 1)}').writeAsBytes(bytes);
        onProgress?.call(0.5 * (i + 1) / count);
      }
      command = movingOverlayCommand(
          video.path, '${frames.path}/o%05d.png', video.fps, out);
      encodeFrom = 0.5;
    }
    final ok = await _run(command, duration, (p) {
      onProgress?.call(encodeFrom! + (1 - encodeFrom) * p);
    });
    await frames.delete(recursive: true);
    if (!ok) {
      File(out).delete().ignore();
      return null;
    }
    return out;
  }

  /// The frame the clip is on, with [drawing] over it, as a JPEG in the
  /// temporary directory — or null when it failed.
  static Future<String?> frame(
    ThrowVideo video, {
    required ThrowDrawing drawing,
    required Size pixels,
    required String name,
  }) async {
    final dir = await _workDir();
    final png = '${dir.path}/overlay.png';
    await File(png).writeAsBytes(await overlayPng(drawing, pixels));
    final out = '${dir.path}/$name.jpg';
    final color = await VideoOptimizer.jpegColorFilterFor(video.path);
    final ok = await _run(
        frameCommand(video.path, png, out,
            seconds: drawing.position.inMicroseconds / 1e6, color: color),
        null,
        null);
    File(png).delete().ignore();
    if (!ok) {
      File(out).delete().ignore();
      return null;
    }
    return out;
  }

  /// [drawing] painted over nothing at [pixels], as a PNG — at the clip
  /// position [at], or where it was drawn.
  static Future<Uint8List> overlayPng(ThrowDrawing drawing, Size pixels,
      {Duration? at}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Laid out at the screen's width and the clip's shape, then scaled up,
    // so ink and labels keep the proportion they had to the frame.
    final scale = pixels.width / drawing.layout.width;
    canvas.scale(scale);
    paintAnnotations(
      canvas,
      Size(drawing.layout.width, pixels.height / scale),
      drawing.annotations,
      position: at ?? drawing.position,
      labelStyle: drawing.labelStyle,
    );
    final picture = recorder.endRecording();
    final image =
        await picture.toImage(pixels.width.round(), pixels.height.round());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  @visibleForTesting
  static String overlayFrame(int n) => 'o${n.toString().padLeft(5, '0')}.png';

  /// The overlay is scaled to the video rather than trusted to be its size
  /// (`scale2ref`): a capture still carrying a rotation flag is turned
  /// upright by ffmpeg on the way in, and its frame is the other way round
  /// to the one the player reported.
  static const _lay = '[1:v][0:v]scale2ref[ov][base];'
      '[base][ov]overlay=0:0:format=auto';

  /// The recipe for a clip that is going to be watched on somebody else's
  /// phone rather than scrubbed on this one: the usual keyframe spacing,
  /// and the index up front so it starts playing before it has finished
  /// downloading.
  static const _encode = '-c:v libx264 -preset veryfast -crf 20 '
      '-pix_fmt yuv420p -c:a copy -movflags +faststart';

  @visibleForTesting
  static String stillOverlayCommand(String src, String png, String out) =>
      '-y -i "$src" -i "$png" -filter_complex "$_lay,format=yuv420p" '
      '$_encode "$out"';

  @visibleForTesting
  static String movingOverlayCommand(
          String src, String pattern, double fps, String out) =>
      '-y -i "$src" -framerate ${fps.toStringAsFixed(6)} -i "$pattern" '
      '-filter_complex "$_lay:eof_action=repeat,format=yuv420p" '
      '$_encode "$out"';

  @visibleForTesting
  static String frameCommand(String src, String png, String out,
          {required double seconds, required String color}) =>
      '-y -ss ${seconds.toStringAsFixed(6)} -i "$src" -i "$png" '
      '-filter_complex "$_lay,scale=iw:ih:$color" '
      '-frames:v 1 -q:v 2 "$out"';

  static Future<Directory> _workDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/share');
    // One export at a time is kept: the share sheet hands the file to
    // another app that may still be reading it after the sheet closes, so
    // it goes when the next one is made rather than straight away.
    if (await dir.exists()) await dir.delete(recursive: true);
    return dir.create(recursive: true);
  }

  static Future<bool> _run(
      String command, Duration? duration, ValueChanged<double>? onProgress) {
    final done = Completer<bool>();
    FFmpegKit.executeAsync(
      command,
      (session) async =>
          done.complete(ReturnCode.isSuccess(await session.getReturnCode())),
      null,
      (statistics) {
        final total = duration?.inMilliseconds;
        if (total == null || total <= 0) return;
        onProgress?.call((statistics.getTime() / total).clamp(0.0, 1.0));
      },
    );
    return done.future;
  }
}
