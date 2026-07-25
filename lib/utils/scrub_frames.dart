import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Serves pre-extracted still frames for smooth scrubbing: given a scrub
/// position it decodes the matching JPEG to a [ui.Image] and publishes it on
/// [current], keeping a small LRU of decoded frames and prefetching ahead in
/// the scrub direction so the finger rarely outruns the decode. Because the
/// display samples cached stills instead of seeking the codec, scrubbing is
/// smooth at any speed and — unlike a live decoder — works in reverse too.
class ScrubFrames {
  ScrubFrames({
    required this.dir,
    required this.count,
    required this.stride,
    required this.fps,
  });

  final String dir;
  final int count;

  /// Source frames per extracted image (1 = every frame).
  final int stride;

  /// Playback frame rate of the video the frames were taken from.
  final double fps;

  /// The frame to show for the latest requested position — the exact one
  /// once decoded, otherwise the nearest already-decoded neighbour so the
  /// overlay never blanks mid-scrub.
  final ValueNotifier<ui.Image?> current = ValueNotifier<ui.Image?>(null);

  /// Byte budget for decoded frames held in memory. Sized in bytes rather
  /// than a frame count so the extraction resolution can change without
  /// re-tuning: 1440px stills are ~4.7 MB of RGBA each, so this holds ~20 of
  /// them — comfortably more than the prefetch window — while smaller frames
  /// simply cache deeper.
  static const _cacheBudgetBytes = 96 << 20;

  /// Never evict below this many frames, whatever their size: the prefetch
  /// window (12 ahead + 4 behind + the target) must stay resident or the
  /// cache would thrash against its own prefetching.
  static const _minCached = 18;

  /// Ceiling on simultaneous decodes so a fast fling can't spawn a decode
  /// storm; the window fills nearest-first as slots free up.
  static const _maxConcurrent = 6;

  final Map<int, ui.Image> _cache = {};
  final Set<int> _inFlight = {};
  int _target = 0;
  int _dir = 1;
  bool _disposed = false;

  /// Set at the start of a fresh drag: until the frame at (or beside) the
  /// target decodes, publish nothing so the overlay stays transparent and
  /// the correct live video shows through, rather than flashing a stale
  /// cached frame from a distant part of the clip.
  bool _freshStart = false;

  /// Presentation time (seconds) of each still, read from the clip itself;
  /// empty until [loadTimes] finishes or when the file is missing, in which
  /// case the fps arithmetic stands in.
  List<double> _times = const [];

  /// Reads the timestamps written alongside the stills. Safe to call once
  /// per instance; failures leave the arithmetic fallback in place.
  Future<void> loadTimes(String fileName) async {
    try {
      final file = File('$dir/$fileName');
      if (!await file.exists()) return;
      final times = <double>[];
      for (final line in const LineSplitter().convert(await file.readAsString())) {
        final value = double.tryParse(line.trim());
        if (value != null) times.add(value);
      }
      // A short or corrupt list would silently misalign every still past the
      // gap, which is worse than the arithmetic it replaces.
      if (times.length >= count && !_disposed) {
        _times = times;
      }
    } catch (_) {
      // Arithmetic fallback stands.
    }
  }

  /// Maps a scrub [position] to the extracted frame the video is showing at
  /// that instant — the one whose display window contains [position]. With
  /// real timestamps that is a search; without them it is a floor of the fps
  /// arithmetic (a round picked the *next* frame past the halfway point, so
  /// covering the video with a still could swap in its neighbour).
  int indexForPosition(Duration position) {
    if (count <= 0) return 0;
    final seconds = position.inMicroseconds / Duration.microsecondsPerSecond;
    if (_times.isNotEmpty) {
      // Last still whose time is at or before the position.
      var lo = 0, hi = _times.length - 1, best = 0;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        if (_times[mid] <= seconds + 1e-6) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return best.clamp(0, count - 1);
    }
    final frame = seconds * fps;
    final index = (frame / stride + 1e-6).floor();
    return index.clamp(0, count - 1);
  }

  /// Where to seek so the video lands on still [index]. Aims between this
  /// still's timestamp and the next so neither rounding to whole
  /// milliseconds nor an inexact rate can tip it into an adjacent frame.
  Duration positionForIndex(int index) {
    final k = index.clamp(0, count - 1);
    double seconds;
    if (_times.isNotEmpty) {
      final start = _times[k];
      final next = k + 1 < _times.length
          ? _times[k + 1]
          : start + stride / (fps > 0 ? fps : 30);
      seconds = start + (next - start) / 2;
    } else {
      seconds = (k * stride + 0.5) / (fps > 0 ? fps : 30);
    }
    return Duration(
        microseconds: (seconds * Duration.microsecondsPerSecond).round());
  }

  String _pathFor(int index) =>
      '$dir/f${(index + 1).toString().padLeft(5, '0')}.jpg';

  /// Begins a new drag: clears the shown frame so the overlay reveals live
  /// video until the target still is ready. Keeps the decoded cache so
  /// repeated drags over the same span stay instant.
  void reset() {
    if (_disposed) return;
    _freshStart = true;
    current.value = null;
  }

  /// Shows extracted-frame [index]: notes the scrub direction, makes sure a
  /// window of frames around it is decoding, and publishes the best frame
  /// available right now.
  void showIndex(int index) {
    if (_disposed) return;
    final clamped = index.clamp(0, count - 1);
    _dir = clamped >= _target ? 1 : -1;
    _target = clamped;
    _ensureWindow();
    _publishNearest();
  }

  void _ensureWindow() {
    // Bias the window the way the finger is moving — most of the reach ahead,
    // a little behind for a reversal — and fill it nearest-target first.
    final ahead = _dir > 0 ? 12 : 4;
    final behind = _dir > 0 ? 4 : 12;
    final reach = math.max(ahead, behind);
    for (var d = 0; d <= reach; d++) {
      for (final sign in const [1, -1]) {
        if (d == 0 && sign < 0) continue;
        if (sign > 0 && d > ahead) continue;
        if (sign < 0 && d > behind) continue;
        final index = _target + sign * d;
        if (index < 0 || index >= count) continue;
        if (_cache.containsKey(index) || _inFlight.contains(index)) continue;
        if (_inFlight.length >= _maxConcurrent) return;
        _decode(index);
      }
    }
  }

  Future<void> _decode(int index) async {
    _inFlight.add(index);
    try {
      final bytes = await File(_pathFor(index)).readAsBytes();
      if (_disposed) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _cache[index] = frame.image;
      _evict();
      _publishNearest();
      // A freed slot may let a still-missing nearer frame start decoding.
      _ensureWindow();
    } catch (_) {
      // Missing/corrupt frame: leave it out; neighbours still cover the scrub.
    } finally {
      _inFlight.remove(index);
    }
  }

  void _publishNearest() {
    final exact = _cache[_target];
    if (exact != null) {
      _freshStart = false;
      current.value = exact;
      return;
    }
    // At the start of a drag, only take over from live video once a frame
    // right at the target is available; a distant neighbour would be wrong.
    if (_freshStart) {
      for (final d in const [1, -1]) {
        final near = _cache[_target + d];
        if (near != null) {
          _freshStart = false;
          current.value = near;
          return;
        }
      }
      return;
    }
    // Mid-drag: any nearest decoded frame beats a gap, and prefetch keeps it
    // within a frame or two of the finger.
    ui.Image? best;
    var bestDist = 1 << 30;
    _cache.forEach((index, image) {
      final dist = (index - _target).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = image;
      }
    });
    if (best != null) current.value = best;
  }

  int _cacheBytes() {
    var bytes = 0;
    for (final image in _cache.values) {
      bytes += image.width * image.height * 4;
    }
    return bytes;
  }

  void _evict() {
    while (_cache.length > _minCached && _cacheBytes() > _cacheBudgetBytes) {
      int? farthest;
      var farDist = -1;
      _cache.forEach((index, _) {
        final dist = (index - _target).abs();
        if (dist > farDist) {
          farDist = dist;
          farthest = index;
        }
      });
      if (farthest == null) break;
      _cache.remove(farthest)?.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    current.dispose();
  }
}
