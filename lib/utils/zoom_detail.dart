import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'frame_timing.dart';

/// A zoomed-in frame drawn sharp once it stops moving.
///
/// Zooming blows the frame up on the GPU, which filters it bilinearly: fine
/// at 1:1, soft by 2x, and mush by 8x, which is exactly how far in a coach
/// goes to look at a hand at release. So when the picture settles, ffmpeg
/// cuts the part of the frame that is on screen out of the clip and scales
/// it to the screen's own pixels with lanczos, and that is laid over the
/// soft one where it belongs.
///
/// It is a better drawing of the pixels the clip has, never new ones: the
/// playback copy is all there is (the camera's file is not kept), and a
/// model that invented detail would be inventing the one thing on the frame
/// somebody is measuring off.

/// Below this many screen pixels per pixel of the clip, the GPU's own
/// scaling is as good as anything ffmpeg would hand back. Not much above
/// one: a portrait clip's playback copy is 810 wide, so a 1080-wide phone
/// shows it at 1.33x before anybody has pinched, and at that size lanczos
/// draws the frame all but the same as the GPU does — a render for every
/// paused frame, and a swap that changes nothing but the grain. The still
/// is for a frame somebody has zoomed into.
const double kDetailMinMagnification = 2;

/// Ceiling on the rendered still, in pixels. What is on screen is at most a
/// phone's own resolution; this is headroom for the snap to whole pixels and
/// a tablet, and it keeps a decoded still to ~16 MB whatever is asked for.
const int kDetailMaxPixels = 4 << 20;

/// The part of the canvas that is on screen, in the canvas's own logical
/// coordinates — the space the annotations are drawn in. [canvas] is the
/// letterboxed video box, centered in the [viewport], and the whole stage is
/// scaled by [zoom] about the viewport's corner and moved by [offset], which
/// is how the analysis screen lays it out. Null when none of it is.
Rect? visibleCanvasRect({
  required Size viewport,
  required Size canvas,
  required double zoom,
  required Offset offset,
}) {
  if (viewport.isEmpty || canvas.isEmpty || zoom <= 0) return null;
  final stage = Rect.fromLTWH(
    -offset.dx / zoom,
    -offset.dy / zoom,
    viewport.width / zoom,
    viewport.height / zoom,
  );
  final origin = Offset(
    (viewport.width - canvas.width) / 2,
    (viewport.height - canvas.height) / 2,
  );
  final visible = stage.shift(-origin).intersect(Offset.zero & canvas);
  if (visible.width <= 0 || visible.height <= 0) return null;
  return visible;
}

/// A rectangle of the clip's own pixels, and the size to draw it at.
@immutable
class DetailCrop {
  const DetailCrop({
    required this.frameWidth,
    required this.frameHeight,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.outWidth,
    required this.outHeight,
  });

  /// The clip's frame, which the crop is measured in.
  final int frameWidth, frameHeight;

  final int x, y, width, height;

  /// What ffmpeg scales the crop to.
  final int outWidth, outHeight;

  /// Where the crop sits on the frame, as fractions of it — what the still
  /// is positioned by, so it lands on the canvas whatever size that is.
  Rect get normalized => Rect.fromLTWH(
        x / frameWidth,
        y / frameHeight,
        width / frameWidth,
        height / frameHeight,
      );

  @override
  bool operator ==(Object other) =>
      other is DetailCrop &&
      other.frameWidth == frameWidth &&
      other.frameHeight == frameHeight &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.outWidth == outWidth &&
      other.outHeight == outHeight;

  @override
  int get hashCode => Object.hash(
      frameWidth, frameHeight, x, y, width, height, outWidth, outHeight);

  @override
  String toString() => 'DetailCrop(${width}x$height+$x+$y of '
      '${frameWidth}x$frameHeight -> ${outWidth}x$outHeight)';
}

/// What to cut out of a [frameWidth] x [frameHeight] clip when [visible] —
/// a fraction of the frame — covers [magnification] screen pixels per pixel
/// of the clip. Null when there is nothing to gain.
///
/// The crop is widened outwards to whole pixels, and to even ones: the clip
/// is 4:2:0, and a crop starting on an odd row would move the color half a
/// pixel off the light. The still is positioned by the crop it was actually
/// cut to rather than by what was asked for, so the widening costs a pixel
/// of margin off screen and never a pixel of misplacement on it.
DetailCrop? detailCropFor({
  required int frameWidth,
  required int frameHeight,
  required Rect visible,
  required double magnification,
}) {
  if (frameWidth <= 0 || frameHeight <= 0) return null;
  if (!(magnification >= kDetailMinMagnification)) return null;
  int down(double v) => (v / 2).floor() * 2;
  int up(double v) => (v / 2).ceil() * 2;
  // A hair's tolerance, so an edge that is a whole pixel in all but its
  // floating point doesn't widen by two.
  const eps = 1e-6;
  final x0 = down(visible.left * frameWidth + eps).clamp(0, frameWidth);
  final y0 = down(visible.top * frameHeight + eps).clamp(0, frameHeight);
  final x1 = up(visible.right * frameWidth - eps).clamp(0, frameWidth);
  final y1 = up(visible.bottom * frameHeight - eps).clamp(0, frameHeight);
  final w = x1 - x0, h = y1 - y0;
  if (w <= 0 || h <= 0) return null;
  var scale = magnification;
  final pixels = w * h * scale * scale;
  if (pixels > kDetailMaxPixels) scale *= math.sqrt(kDetailMaxPixels / pixels);
  // Capped that far down, it may no longer be worth doing.
  if (scale < kDetailMinMagnification) return null;
  return DetailCrop(
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    x: x0,
    y: y0,
    width: w,
    height: h,
    outWidth: math.max(1, (w * scale).round()),
    outHeight: math.max(1, (h * scale).round()),
  );
}

/// The position a detail still is rendered at, for a player paused at
/// [position] — and whether the player has to be moved there first.
///
/// ffmpeg, handed a position, draws the first frame at or after it, which
/// is the rule the player follows after a seek (see frame_timing.dart). So a
/// position the player was *seeked* to — [lastSeek], or the frame's own
/// timestamp, which some players report instead, a [kSeekLead] later — is
/// handed to ffmpeg as it is, and the two draw the same frame.
///
/// A player paused out of playback is another matter: it stopped somewhere
/// inside a frame and shows the one it had reached, the last at or *before*
/// the position. That frame's seek target is where ffmpeg has to go, and the
/// player is sent there too ([seek]): it is the frame already on screen, so
/// nothing moves, and afterwards the two are agreeing about a seek rather
/// than about arithmetic on a frame rate a slow-motion clip does not keep
/// exactly.
({Duration at, bool seek}) detailTarget({
  required Duration position,
  required Duration? lastSeek,
  required double fps,
}) {
  final rate = fps > 0 ? fps : 30;
  final frameUs = Duration.microsecondsPerSecond / rate;
  final last = lastSeek;
  if (last != null) {
    final ahead = position.inMicroseconds - last.inMicroseconds;
    // A couple of milliseconds either side: a player reports whole ones.
    if (ahead >= -2000 && ahead <= kSeekLead * frameUs + 2000) {
      return (at: last, seek: false);
    }
  }
  final frame = (position.inMicroseconds / frameUs + 1e-6).floor();
  final target = seekTargetSeconds(frame / rate, 1 / rate);
  return (
    at: Duration(
        microseconds: (target * Duration.microsecondsPerSecond).round()),
    seek: true,
  );
}

/// One still to render: which moment of the clip, and which part of it.
@immutable
class DetailJob {
  const DetailJob({required this.at, required this.crop});

  final Duration at;
  final DetailCrop crop;

  @override
  bool operator ==(Object other) =>
      other is DetailJob && other.at == at && other.crop == crop;

  @override
  int get hashCode => Object.hash(at, crop);

  @override
  String toString() => 'DetailJob($at, $crop)';
}

typedef DetailRenderer = Future<ui.Image?> Function(DetailJob job);

/// Holds the sharp still over a zoomed frame and runs the renders for it.
///
/// One render at a time, and only the latest request waits behind it: a
/// pinch that ends and is adjusted twice more is three requests, and the two
/// in the middle are nobody's business. A still that arrives for the frame
/// still on screen is shown even if a newer request for another part of it
/// is queued — it is drawn where it belongs, so panning past its edge shows
/// the soft frame beyond it and nothing that is wrong. [clear] is the one
/// thing that makes a render in flight worthless, because it is what is
/// called when the frame itself changes.
class ZoomDetail extends ChangeNotifier {
  ZoomDetail(this._render);

  final DetailRenderer _render;

  /// The still on screen, or null.
  ui.Image? get image => _image;
  ui.Image? _image;

  /// What [image] was rendered for.
  DetailJob? get shown => _shown;
  DetailJob? _shown;

  DetailJob? _running;
  DetailJob? _queued;

  /// Bumped by [clear]: a render started under an older one is for a frame
  /// that has gone.
  int _epoch = 0;
  bool _disposed = false;

  void request(DetailJob job) {
    if (_disposed) return;
    if (_running != null) {
      _queued = job == _running ? null : job;
      return;
    }
    if (job == _shown) return;
    _run(job);
  }

  Future<void> _run(DetailJob job) async {
    _running = job;
    final epoch = _epoch;
    ui.Image? result;
    try {
      result = await _render(job);
    } catch (_) {
      // No still; the soft frame stays, which is what there was before.
    }
    _running = null;
    if (_disposed) {
      result?.dispose();
      return;
    }
    if (epoch == _epoch && result != null) {
      _image?.dispose();
      _image = result;
      _shown = job;
      notifyListeners();
    } else {
      result?.dispose();
    }
    final next = _queued;
    _queued = null;
    if (next != null && next != _shown) _run(next);
  }

  /// Takes the still down: the frame under it has changed, or is playing.
  void clear() {
    if (_disposed) return;
    _epoch++;
    _queued = null;
    if (_image == null && _shown == null) return;
    _image?.dispose();
    _image = null;
    _shown = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}
