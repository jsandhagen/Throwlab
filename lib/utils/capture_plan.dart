import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:throwlab_camera/throwlab_camera.dart';

/// The mode the camera opens on: the rate it was last left on where the
/// phone still offers it, else 120 at 1080p — the rate a phone's own slow
/// motion films at, and four times the frames of a stock video across a
/// release that lasts a few hundredths of a second. 240 is offered and not
/// the default, because it halves the light each frame gets and a cloudy
/// evening at a track turns it to grain.
///
/// The size is remembered with the rate, since 4K at 120 and 1080p at 120
/// are two choices a coach made differently.
CameraMode? pickMode(List<CameraMode> modes,
    {int? preferredFps, int? preferredHeight}) {
  if (modes.isEmpty) return null;
  int rank(CameraMode mode) {
    var score = 0;
    if (mode.fps == preferredFps) {
      score += 10000;
      if (_short(mode) == preferredHeight) score += 20000;
    }
    if (mode.fps == 120) score += 5000;
    // Otherwise the fastest, and of two the same speed the sharper.
    score += mode.fps * 10;
    if (_short(mode) == 1080) score += 5;
    return score;
  }

  return modes.reduce((a, b) => rank(b) > rank(a) ? b : a);
}

int _short(CameraMode mode) =>
    mode.height < mode.width ? mode.height : mode.width;

/// The modes as a coach chooses between them: fastest first, one per rate
/// and size.
///
/// Where the high-speed session and the ordinary one both offer a rate at a
/// size, the high-speed one is the one kept: it is the session built for
/// that rate, and the ordinary one is only listed for the sizes the
/// high-speed one doesn't reach.
List<CameraMode> offeredModes(List<CameraMode> modes) {
  final seen = <String>{};
  final sorted = [...modes]..sort((a, b) {
      if (b.fps != a.fps) return b.fps.compareTo(a.fps);
      final area = (b.width * b.height).compareTo(a.width * a.height);
      if (area != 0) return area;
      return (b.highSpeed ? 1 : 0).compareTo(a.highSpeed ? 1 : 0);
    });
  return [
    for (final mode in sorted)
      if (seen.add('${mode.fps}x${mode.width}x${mode.height}')) mode,
  ];
}

/// Quarter turns to stand the preview up. A camera hands its frames over the
/// way its sensor is mounted, a quarter turn from how the phone is held
/// upright, and nothing between it and the screen turns them back.
int previewQuarterTurns(int sensorOrientation, int displayDegrees) =>
    ((sensorOrientation - displayDegrees + 360) % 360) ~/ 90;

/// The two things that let somebody film themselves: a countdown before
/// the camera starts, so they can get to the ring, and a stop after so many
/// seconds, so they need not come back to it.
class CaptureTimings {
  const CaptureTimings({this.countdown = 0, this.stopAfter = 0});

  /// Seconds before recording starts; none, and it starts at once.
  final int countdown;

  /// Seconds recording runs before it stops itself; none, and it runs until
  /// it is stopped.
  final int stopAfter;

  static const countdowns = [0, 5, 10, 20];
  static const stops = [0, 8, 12, 20, 30];

  CaptureTimings nextCountdown() => CaptureTimings(
      countdown: _next(countdowns, countdown), stopAfter: stopAfter);

  CaptureTimings nextStop() =>
      CaptureTimings(countdown: countdown, stopAfter: _next(stops, stopAfter));

  static int _next(List<int> values, int value) {
    final at = values.indexOf(value);
    return values[(at + 1) % values.length];
  }
}

enum CapturePhase { idle, counting, recording, stopping }

/// One take, from the press to the file: the countdown, the recording and
/// the stop, each said out loud — a beep a second down to the start, a
/// longer one when it rolls and another when it stops — since the person it
/// is for is at the ring, not at the screen.
///
/// The camera itself is handed in as three calls, so a test drives the
/// timing on a fake clock with no camera at all.
class CaptureRun extends ChangeNotifier {
  CaptureRun({
    required this.start,
    required this.stop,
    required this.beep,
  });

  final Future<void> Function() start;
  final Future<void> Function() stop;
  final void Function(Beep) beep;

  CapturePhase _phase = CapturePhase.idle;
  CapturePhase get phase => _phase;

  /// Seconds left on the countdown while it runs.
  int get remaining => _remaining;
  int _remaining = 0;

  /// How long it has been recording.
  Duration get elapsed => _watch.elapsed;
  final Stopwatch _watch = Stopwatch();

  /// What recording was set to stop after, or none.
  int get stopAfter => _stopAfter;
  int _stopAfter = 0;

  Timer? _timer;
  Timer? _stopTimer;

  /// The one button, and the remote: starts, cancels a countdown, or stops.
  Future<void> press(CaptureTimings timings) async {
    switch (_phase) {
      case CapturePhase.idle:
        _stopAfter = timings.stopAfter;
        if (timings.countdown > 0) {
          _count(timings.countdown);
        } else {
          await _roll();
        }
      case CapturePhase.counting:
        _cancel();
      case CapturePhase.recording:
        await finish();
      case CapturePhase.stopping:
        break;
    }
  }

  void _count(int seconds) {
    _phase = CapturePhase.counting;
    _remaining = seconds;
    beep(Beep.tick);
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remaining--;
      if (_remaining <= 0) {
        timer.cancel();
        _roll();
        return;
      }
      beep(Beep.tick);
      notifyListeners();
    });
  }

  /// Calls a countdown off, if one is running.
  void cancel() {
    if (_phase == CapturePhase.counting) _cancel();
  }

  void _cancel() {
    _timer?.cancel();
    _phase = CapturePhase.idle;
    _remaining = 0;
    notifyListeners();
  }

  Future<void> _roll() async {
    _phase = CapturePhase.recording;
    _watch
      ..reset()
      ..start();
    notifyListeners();
    try {
      await start();
    } catch (_) {
      _watch.stop();
      _phase = CapturePhase.idle;
      notifyListeners();
      rethrow;
    }
    beep(Beep.go);
    // Ticked over every tenth so the clock on the screen runs; the stop is
    // a timer of its own rather than counted ticks, which drift.
    _timer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => notifyListeners());
    if (_stopAfter > 0) {
      _stopTimer = Timer(Duration(seconds: _stopAfter), finish);
    }
  }

  /// Stops recording, if it is.
  Future<void> finish() async {
    if (_phase != CapturePhase.recording) return;
    _timer?.cancel();
    _stopTimer?.cancel();
    _phase = CapturePhase.stopping;
    _watch.stop();
    notifyListeners();
    beep(Beep.stop);
    try {
      await stop();
    } finally {
      _phase = CapturePhase.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopTimer?.cancel();
    super.dispose();
  }
}
