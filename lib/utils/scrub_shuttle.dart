import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import 'frame_seeker.dart';
import 'scrub_frames.dart';

/// The smooth-scrub path, independent of the screen driving it: while a drag
/// is running the picture comes from pre-extracted stills instead of the
/// codec, and the finger only sets a *target* frame — a per-vsync shuttle
/// plays the shown frame toward it, so a fast scroll fast-forwards through
/// the frames instead of teleporting past them. When the finger lifts, the
/// last still is held until the real decoder has caught up, so the handover
/// back to live video is invisible.
///
/// Both the analysis screen and the comparison screen scrub through this, so
/// a drag feels the same wherever it happens. With no extracted stills for a
/// clip ([frames] null) every call falls back to seeking the player, which is
/// how scrubbing worked before the stills existed.
class ScrubShuttle extends ChangeNotifier {
  ScrubShuttle({
    required this.controller,
    required this.seeker,
    required this.fps,
    required TickerProvider vsync,
    ScrubFrames? frames,
  }) : _frames = frames {
    // Created eagerly: a lazy ticker on a screen left without scrubbing would
    // be created inside dispose(), when looking up the TickerMode is illegal.
    _ticker = vsync.createTicker(_onTick);
  }

  final VideoPlayerController controller;
  final FrameSeeker seeker;

  /// Playback frame rate of the clip, for sizing the handoff tolerance.
  final double fps;

  /// Pre-extracted stills for this clip, or null when it has none. Settable:
  /// the analysis screen extracts frames for older clips and swaps the set in
  /// once they are ready.
  ScrubFrames? get frames => _frames;
  ScrubFrames? _frames;
  set frames(ScrubFrames? value) {
    if (identical(value, _frames)) return;
    _frames = value;
    notifyListeners();
  }

  late final Ticker _ticker;

  /// A drag is actively scrubbing, and the brief hold afterwards while the
  /// real video catches up to the last frame.
  bool get scrubbing => _scrubbing;
  bool _scrubbing = false;

  /// The current touch has actually moved. Until it does no still is shown
  /// and the player is not seeked, so a tap leaves the frame alone.
  bool get moved => _moved;
  bool _moved = false;

  bool get handoff => _handoff;
  bool _handoff = false;

  /// Whether the still overlay should be covering the video right now.
  bool get overlayVisible => _frames != null && ((_scrubbing && _moved) || _handoff);

  /// Something scrub-related is still in flight; used to hold off work that
  /// would compete with it (re-extracting stills, tearing the set down).
  bool get busy => _scrubbing || _handoff || _ticker.isActive;

  Timer? _handoffTimer;
  VoidCallback? _handoffWatch;
  ScrubFrames? _handoffFrames;

  // The finger sets a target frame; a per-vsync follower advances the *shown*
  // frame toward it at a rate that scales with the gap.
  double _fingerIndex = 0;
  double _displayIndex = 0;
  int _lastShown = -1;
  Duration _lastTick = Duration.zero;

  /// Fraction of the finger→display gap closed per vsync (proportional catch-
  /// up: far gap plays fast, small gap tracks precisely).
  static const _catchUp = 0.3;

  /// Ceiling on how many frames/second the shuttle plays through, so a huge
  /// gap can't jump — it fast-forwards smoothly instead of skipping. At ~2x
  /// the clip's own rate it shows roughly every other frame during a fast
  /// spin, which reads as smooth speed-up rather than a stride.
  static const _maxCatchUpFramesPerSec = 120.0;

  /// Wall-clock spacing between decoder nudges while the shuttle is running.
  /// The extracted stills are what's on screen mid-scrub, so the player only
  /// has to stay roughly nearby for a quick handoff at the end. Seeking it on
  /// every shuttle frame meant a flick fired up to [_maxCatchUpFramesPerSec]
  /// platform seeks a second, each one flushing ExoPlayer's decode pipeline —
  /// which is what made a flick stutter and stall. ~10/s keeps the time/frame
  /// readout and the wheel live for a fraction of the work.
  static const _nudgeSpacing = Duration(milliseconds: 100);

  /// When the last decoder nudge was issued, and for which frame; null/-1
  /// until the first.
  DateTime? _lastNudge;
  int _lastNudgedIndex = -1;

  /// How long the still is held after the player reports it reached the
  /// target, covering the gap between a seek being accepted and its frame
  /// reaching the surface. Short enough not to feel like lag, long enough to
  /// cover a few frames of render latency.
  static const _renderSettle = Duration(milliseconds: 120);

  Duration get _frameStep =>
      Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());

  /// Shows the pre-extracted stills for the duration of a scrub drag. No-op
  /// when the clip has no extracted frames, so scrubbing then falls back to
  /// the seek path unchanged.
  void begin() {
    if (_frames == null) return;
    stopHandoff();
    controller.pause();
    if (!_ticker.isActive) {
      final start = _frames!.indexForPosition(seeker.position).toDouble();
      _fingerIndex = start;
      _displayIndex = start;
      _lastShown = -1;
      _lastNudge = null;
      _lastNudgedIndex = -1;
      _frames!.reset();
      // Decode the starting still now so it is ready the instant the finger
      // moves; nothing is shown until then.
      _frames!.showIndex(start.round());
      _moved = false;
    } else {
      // Grabbed again while the shuttle was still catching up: continue from
      // the frame currently on screen, already in the moved state.
      _fingerIndex = _displayIndex;
      _moved = true;
    }
    _scrubbing = true;
    _handoff = false;
    notifyListeners();
  }

  /// Advances the scrub by [frames] source frames — from a drag across the
  /// video or from the scrub wheel. With the stills active this moves the
  /// finger's target (the shuttle plays the shown frame toward it, stride-
  /// aware); otherwise it seeks the player directly.
  void by(int frames) {
    if (frames == 0) return;
    final atlas = _frames;
    if (_scrubbing && atlas != null) {
      _beginShuttle();
      _fingerIndex = (_fingerIndex + frames / atlas.stride)
          .clamp(0.0, (atlas.count - 1).toDouble());
    } else {
      controller.pause();
      seeker.seekBy(_frameStep * frames);
    }
  }

  /// Lets the shuttle finish playing to the finger's frame, then hands off to
  /// live video. The still overlay stays up across the handoff.
  void end() {
    if (!_scrubbing) return;
    // A touch that never moved changed nothing — no overlay was raised and
    // the player was never seeked, so there is nothing to hand back.
    if (!_moved) {
      _scrubbing = false;
      _handoff = false;
      notifyListeners();
      return;
    }
    _scrubbing = false;
    _handoff = _frames != null;
    notifyListeners();
    if (_frames == null) return;
    if (!_ticker.isActive) _startVideoHandoff(_displayIndex.round());
  }

  /// Starts the shuttle the first time a scrub actually moves. Touching the
  /// video is not a scrub: the stills only exist every [ScrubFrames.stride]
  /// frames, so covering the video with the nearest one — and seeking the
  /// player onto that grid — shifted the picture by up to a stride even
  /// though the finger never travelled. Nothing happens until it does.
  void _beginShuttle() {
    if (_moved) return;
    _moved = true;
    _lastTick = Duration.zero;
    _ticker.start();
    notifyListeners();
  }

  /// Per-vsync shuttle: eases the shown frame toward the finger's target so a
  /// fast scroll plays the frames through quickly (video speeds up to match)
  /// instead of jumping, and a slow scroll tracks frame for frame. Also nudges
  /// the hidden decoder along so the time/frame readout stays live and the
  /// eventual handoff is quick.
  void _onTick(Duration elapsed) {
    final frames = _frames;
    if (frames == null) {
      _ticker.stop();
      return;
    }
    final dt =
        ((elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, 0.05);
    _lastTick = elapsed;
    final gap = _fingerIndex - _displayIndex;
    if (gap.abs() < 0.5) {
      _displayIndex = _fingerIndex;
      // Caught up: seek for real, so the readout and any handoff are exact.
      _showAndSeek(_displayIndex.round(), force: true);
      if (!_scrubbing) {
        _ticker.stop();
        _startVideoHandoff(_displayIndex.round());
      }
      return;
    }
    final maxStep = _maxCatchUpFramesPerSec / frames.stride * dt;
    var step = gap * _catchUp;
    if (step > maxStep) step = maxStep;
    if (step < -maxStep) step = -maxStep;
    _displayIndex += step;
    _showAndSeek(_displayIndex.round());
  }

  /// Shows an extracted still, and occasionally nudges the hidden decoder
  /// toward it. [force] issues the seek regardless of spacing — used when the
  /// shuttle settles, so the player ends up exactly where the scrub stopped.
  void _showAndSeek(int imageIndex, {bool force = false}) {
    if (imageIndex != _lastShown) {
      _lastShown = imageIndex;
      _frames!.showIndex(imageIndex);
    }
    // Tracked separately from [_lastShown]: a throttled tick still advances
    // the shown still, so a later forced nudge for that same frame must not
    // be mistaken for one already sent to the decoder.
    if (imageIndex == _lastNudgedIndex) return;
    final now = DateTime.now();
    final last = _lastNudge;
    if (!force && last != null && now.difference(last) < _nudgeSpacing) return;
    _lastNudge = now;
    _lastNudgedIndex = imageIndex;
    seeker.seekTo(_positionForImage(imageIndex));
  }

  /// Where to seek so the video shows the still at [imageIndex]. ScrubFrames
  /// answers from the clip's own frame timestamps where it has them, and aims
  /// just short of the still's timestamp because the player renders the first
  /// frame at or after a seek — so the handoff lands on the frame the still
  /// was showing rather than the one after it.
  Duration _positionForImage(int imageIndex) =>
      _frames!.positionForIndex(imageIndex);

  /// Keeps the last still on screen when the finger lifts until the video
  /// decoder has actually seeked to that frame, so the handoff from stills
  /// back to live video is seamless instead of a visible jump.
  void _startVideoHandoff(int imageIndex) {
    stopHandoff();
    final frames = _frames;
    final target = _positionForImage(imageIndex);
    seeker.seekTo(target);
    // Under one frame: at 1.5 the still was dropped while the player was
    // still a whole frame away, so the picture stepped as the video took
    // over. A target sits a quarter frame short of the frame it names, so the
    // player reporting either the requested time or the frame's own timestamp
    // is within this.
    final toleranceUs = 0.6 * Duration.microsecondsPerSecond / fps;
    void watch() {
      // The still on screen has to be the one being handed back. A scrub ends
      // faster than 1440p JPEGs decode, so the overlay is often still showing
      // the neighbour that stood in for the frame the finger stopped on — and
      // swapping *that* for the video is itself the frame the picture appears
      // to skip. Waiting costs nothing: the still and the video then show the
      // same frame, so the switch is invisible.
      if (frames != null && frames.shownIndex != imageIndex) return;
      final delta =
          (controller.value.position.inMicroseconds - target.inMicroseconds)
              .abs();
      if (delta > toleranceUs) return;
      // Arrived — but only in the player's bookkeeping. The position is
      // reported when the seek is accepted, not when the decoded frame
      // reaches the surface, so dropping the still here uncovers whatever
      // frame the texture still holds: the picture steps to the old frame and
      // then snaps to the right one. Stop watching and give the texture a
      // moment to actually show the frame we asked for.
      stopHandoff();
      _handoffTimer = Timer(_renderSettle, _clearHandoff);
    }

    _handoffWatch = watch;
    controller.addListener(watch);
    // The decode that finally puts the right still on screen is the other
    // half of the condition above, and it arrives on its own notifier.
    _handoffFrames = frames;
    frames?.current.addListener(watch);
    // watch() may fire immediately below and replace this with the shorter
    // render-settle timer; this is the ceiling for the seek never landing.
    // Hold the (correct) still until the video actually arrives. seekTo can
    // take a second or more to render on some devices, so the fallback is
    // generous — showing the right frame a touch soft beats flashing the
    // wrong one and then jumping.
    _handoffTimer = Timer(const Duration(milliseconds: 2500), () {
      stopHandoff();
      _clearHandoff();
    });
    watch();
  }

  void _clearHandoff() {
    if (_disposed || !_handoff) return;
    _handoff = false;
    notifyListeners();
  }

  /// Drops the handoff watchers. Public so a screen swapping its still set
  /// out can make sure nothing is still listening to the old one.
  void stopHandoff() {
    if (_handoffWatch != null) {
      controller.removeListener(_handoffWatch!);
      // The instance the listener went on, not whatever [frames] is now: a
      // re-extraction can swap the set out between arming and stopping.
      _handoffFrames?.current.removeListener(_handoffWatch!);
      _handoffFrames = null;
      _handoffWatch = null;
    }
    _handoffTimer?.cancel();
    _handoffTimer = null;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    stopHandoff();
    _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }
}
