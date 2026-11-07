import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab_camera/throwlab_camera.dart';

import '../utils/capture_plan.dart';

/// A clip just filmed: the file, and the rate it was filmed at where the
/// app's own camera knows it (the phone's camera app is probed like an
/// import).
class FilmedClip {
  const FilmedClip(this.path, {this.fps, this.deliveredFps});
  final String path;
  final int? fps;

  /// The rate the camera really delivered, counted while it filmed.
  final double? deliveredFps;

  /// Whether the camera fell short of the rate it was asked for: below nine
  /// tenths of it, which is more than a stray frame at either end.
  bool get shortOfRate {
    final asked = fps;
    final got = deliveredFps;
    return asked != null && got != null && got < asked * 0.9;
  }
}

/// Films a throw — in the app's own camera, which reaches the 120 and 240
/// fps the phone's camera app does, or in the phone's camera app where this
/// one cannot open. Null when nothing was filmed.
Future<FilmedClip?> filmThrow(BuildContext context) async {
  final result = await Navigator.of(context).push<Object>(
    MaterialPageRoute(builder: (_) => const CaptureScreen()),
  );
  if (result is FilmedClip) {
    // Said rather than buried: a clip filmed at 120 that came in at 70 is
    // the difference between seeing the release and guessing at it, and
    // nothing in the file tells the two apart once its gaps are filled.
    if (result.shortOfRate && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('The camera delivered '
            '${result.deliveredFps!.round()} of ${result.fps} fps on that '
            'take. Try a slower rate, or more light.'),
      ));
    }
    return result;
  }
  if (result != CaptureScreen.useSystemCamera) return null;
  final picked = await ImagePicker().pickVideo(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
  );
  return picked == null ? null : FilmedClip(picked.path);
}

/// The app's own camera.
///
/// Built for the athlete filming themselves as much as for the coach: the
/// phone on a bag at the side of the ring, a countdown long enough to walk
/// out to it, a stop after so many seconds so nobody walks back to end it,
/// a beep for each, and the volume button — which is also what a Bluetooth
/// selfie remote presses — as the shutter.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.preview});

  /// What the viewfinder is drawn with: the camera's own [CameraPreview],
  /// unless a test hands in a stand-in for the platform view it cannot
  /// host.
  final Widget? preview;

  /// What the screen pops with when the camera would not open and the
  /// phone's own should be used instead.
  static const useSystemCamera = 'system';

  static const _fpsKey = 'throwlab.capture.fps';
  static const _heightKey = 'throwlab.capture.height';
  static const _countdownKey = 'throwlab.capture.countdown';
  static const _stopKey = 'throwlab.capture.stopAfter';

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  List<CameraMode> _modes = const [];
  List<String> _details = const [];
  CameraMode? _mode;
  OpenCamera? _camera;
  int _display = 0;
  String? _error;
  CaptureTimings _timings = const CaptureTimings();
  String? _path;
  late final CaptureRun _run = CaptureRun(
    start: _startRecording,
    stop: _stopRecording,
    beep: (kind) => ThrowCamera.beep(kind).catchError((_) {}),
  )..addListener(_changed);

  /// Whether the camera has its session up on the preview and can record.
  bool _ready = false;

  void _onReady() {
    if (mounted) setState(() => _ready = ThrowCamera.ready.value);
  }

  void _onFailure() {
    final why = ThrowCamera.failure.value;
    if (why != null && mounted) setState(() => _error = why);
  }

  @override
  void initState() {
    super.initState();
    ThrowCamera.ready.addListener(_onReady);
    ThrowCamera.failure.addListener(_onFailure);
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _boot();
  }

  @override
  void dispose() {
    ThrowCamera.ready.removeListener(_onReady);
    ThrowCamera.failure.removeListener(_onFailure);
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _run.dispose();
    ThrowCamera.close().catchError((_) {});
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    int? preferredFps;
    int? preferredHeight;
    try {
      final prefs = await SharedPreferences.getInstance();
      preferredFps = prefs.getInt(CaptureScreen._fpsKey);
      preferredHeight = prefs.getInt(CaptureScreen._heightKey);
      _timings = CaptureTimings(
        countdown: prefs.getInt(CaptureScreen._countdownKey) ?? 0,
        stopAfter: prefs.getInt(CaptureScreen._stopKey) ?? 0,
      );
    } catch (_) {
      // Opens on the defaults.
    }
    try {
      final offered = await ThrowCamera.modes();
      _modes = offeredModes(offered.modes);
      _details = offered.details;
      final mode = pickMode(_modes,
          preferredFps: preferredFps, preferredHeight: preferredHeight);
      if (mode == null) throw StateError('no modes');
      await _open(mode);
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  static String _describe(Object e) {
    if (e is PlatformException && e.code == 'permission') {
      return 'ThrowLab needs the camera to film. It can be allowed in the '
          "phone's settings.";
    }
    if (e is MissingPluginException) {
      return "This phone's camera couldn't be opened.";
    }
    return "The camera couldn't be opened.";
  }

  Future<void> _open(CameraMode mode) async {
    final camera = await ThrowCamera.open(mode);
    final display = await ThrowCamera.displayRotation();
    if (!mounted) return;
    setState(() {
      _camera = camera;
      _mode = camera.mode;
      _display = display;
      _error = null;
    });
  }

  @override
  void didChangeMetrics() {
    // Turned: the preview is turned against the screen, so it is asked again.
    ThrowCamera.displayRotation().then((display) {
      if (mounted && display != _display) setState(() => _display = display);
    }).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Leaving the app takes the camera from it. A take in progress is
      // kept as far as it got rather than lost.
      _run.cancel();
      if (_run.phase == CapturePhase.recording) {
        _run.finish();
      } else if (_camera != null) {
        ThrowCamera.close().catchError((_) {});
        setState(() => _camera = null);
      }
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        _mode != null &&
        _path == null) {
      _open(_mode!).catchError((Object e) {
        if (mounted) setState(() => _error = _describe(e));
      });
    }
  }

  /// The volume buttons, and what a Bluetooth shutter remote sends, are the
  /// shutter while the camera is up — a press from twenty meters away.
  static final _shutters = {
    LogicalKeyboardKey.audioVolumeUp,
    LogicalKeyboardKey.audioVolumeDown,
    LogicalKeyboardKey.camera,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.mediaPlayPause,
  };

  bool _onKey(KeyEvent event) {
    if (!_shutters.contains(event.logicalKey)) return false;
    if (event is KeyDownEvent && _camera != null && _ready) _press();
    return true;
  }

  Future<void> _press() async {
    try {
      await _run.press(_timings);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("The camera wouldn't start recording.")));
      }
    }
  }

  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/throwlab_capture_${DateTime.now().millisecondsSinceEpoch}.mp4';
    await ThrowCamera.start(path);
    _path = path;
  }

  Future<void> _stopRecording() async {
    RecordedTake? take;
    try {
      take = await ThrowCamera.stop();
    } catch (_) {
      take = null;
    }
    _path = null;
    if (!mounted) return;
    if (take == null || !File(take.path).existsSync()) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing was recorded.')));
      return;
    }
    Navigator.of(context).pop(FilmedClip(take.path,
        fps: _mode?.fps, deliveredFps: take.deliveredFps));
  }

  Future<void> _remember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(CaptureScreen._countdownKey, _timings.countdown);
      await prefs.setInt(CaptureScreen._stopKey, _timings.stopAfter);
      final mode = _mode;
      if (mode != null) {
        await prefs.setInt(CaptureScreen._fpsKey, mode.fps);
        await prefs.setInt(CaptureScreen._heightKey,
            mode.height < mode.width ? mode.height : mode.width);
      }
    } catch (_) {}
  }

  Future<void> _pickMode() async {
    final picked = await showModalBottomSheet<CameraMode>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      // A phone that films at every rate at every size lists more than half
      // a screen of them.
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding:
              EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in _modes)
                ListTile(
                  key: ValueKey('mode-${mode.fps}-${mode.height}'),
                  leading: Icon(mode == _mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  title: Text('${mode.resolution} · ${mode.fps} fps'),
                  subtitle: Text(_modeNote(mode)),
                  onTap: () => Navigator.pop(context, mode),
                ),
              // Said here because it is the first thing looked for: the
              // phone's own camera films 4K at 120, and most phones keep
              // that to themselves.
              if (!_modes.any((m) => m.resolution == '4K' && m.fps >= 120))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    "This phone doesn't let other apps film 4K at 120 fps. "
                    "For that, film in the phone's own camera and import "
                    'the clip.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              // The camera's own word on what it gives apps, folded away:
              // the question of what a phone can film is settled by this and
              // nothing else, and it is a screenshot to send.
              if (_details.isNotEmpty)
                ExpansionTile(
                  key: const ValueKey('camera-details'),
                  title: Text('What this camera gives apps',
                      style: Theme.of(context).textTheme.bodyMedium),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  expandedAlignment: Alignment.centerLeft,
                  children: [
                    for (final line in _details)
                      Text(line,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == _mode || !mounted) return;
    setState(() => _camera = null);
    try {
      await _open(picked);
      await _remember();
    } catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  static String _modeNote(CameraMode mode) {
    if (mode.fps == 120 && mode.resolution == '1080p') {
      return 'Recommended. Four times the frames of normal video, '
          'sharp and bright enough for most days.';
    }
    final speed = switch (mode.fps) {
      >= 240 => 'Most frames, darkest picture. For a bright day.',
      >= 120 => 'Four times the frames of normal video.',
      >= 60 => 'Twice the frames of normal video.',
      _ => 'Normal video.',
    };
    // The library keeps a clip at 1440p for scrubbing, so 4K buys the
    // sharpest copy there is rather than four times the detail.
    return mode.resolution == '4K'
        ? '$speed Sharpest copy, biggest files.'
        : speed;
  }

  @override
  Widget build(BuildContext context) {
    // Back doesn't walk away from a take: it is stopped with the shutter,
    // which keeps what was filmed.
    return PopScope(
      canPop: _run.phase == CapturePhase.idle,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null ? _failed(context) : _viewfinder(context),
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('capture-system'),
              onPressed: () =>
                  Navigator.pop(context, CaptureScreen.useSystemCamera),
              child: const Text("Use the phone's camera"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewfinder(BuildContext context) {
    final camera = _camera;
    final turns = camera == null
        ? 0
        : previewQuarterTurns(camera.sensorOrientation, _display);
    final mode = camera?.mode;
    // The system stands the picture up; the view only has to be the shape
    // the picture is on this screen, which is the mode's turned whenever
    // the sensor and the screen are a quarter turn apart.
    final preview = camera == null || mode == null
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: AspectRatio(
              aspectRatio: turns.isOdd
                  ? mode.height / mode.width
                  : mode.width / mode.height,
              child: widget.preview ?? const CameraPreview(),
            ),
          );
    return OrientationBuilder(builder: (context, orientation) {
      final side = orientation == Orientation.landscape;
      final controls = _Controls(
        run: _run,
        timings: _timings,
        mode: _mode,
        vertical: side,
        ready: camera != null && _ready,
        onPress: _press,
        onMode: _modes.length > 1 ? _pickMode : null,
        onCountdown: () {
          setState(() => _timings = _timings.nextCountdown());
          _remember();
        },
        onStop: () {
          setState(() => _timings = _timings.nextStop());
          _remember();
        },
      );
      final busy = _run.phase != CapturePhase.idle;
      return Stack(
        fit: StackFit.expand,
        children: [
          preview,
          if (_run.phase == CapturePhase.counting)
            Center(child: _Countdown(seconds: _run.remaining)),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton.filledTonal(
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                if (_run.phase == CapturePhase.recording ||
                    _run.phase == CapturePhase.stopping)
                  Positioned(
                    top: 14,
                    left: 0,
                    right: 0,
                    child: Center(child: _RecordingClock(run: _run)),
                  ),
                if (side)
                  Positioned(top: 0, bottom: 0, right: 12, child: controls)
                else
                  Positioned(left: 0, right: 0, bottom: 12, child: controls),
              ],
            ),
          ),
        ],
      );
    });
  }
}

/// The shutter and what is set around it.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.run,
    required this.timings,
    required this.mode,
    required this.vertical,
    required this.ready,
    required this.onPress,
    required this.onMode,
    required this.onCountdown,
    required this.onStop,
  });

  final CaptureRun run;
  final CaptureTimings timings;
  final CameraMode? mode;
  final bool vertical;
  final bool ready;
  final VoidCallback onPress;
  final VoidCallback? onMode;
  final VoidCallback onCountdown;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final idle = run.phase == CapturePhase.idle;
    final chips = [
      _Chip(
        key: const ValueKey('capture-mode'),
        icon: Icons.slow_motion_video,
        label: mode == null
            ? '…'
            : mode!.resolution == '4K'
                ? '4K ${mode!.fps}'
                : '${mode!.fps} fps',
        onTap: idle ? onMode : null,
      ),
      _Chip(
        key: const ValueKey('capture-countdown'),
        icon: Icons.timer_outlined,
        label: timings.countdown == 0 ? 'Now' : '${timings.countdown} s',
        caption: 'Start',
        onTap: idle ? onCountdown : null,
      ),
      _Chip(
        key: const ValueKey('capture-stop'),
        icon: Icons.stop_circle_outlined,
        label: timings.stopAfter == 0 ? 'By hand' : '${timings.stopAfter} s',
        caption: 'Stop',
        onTap: idle ? onStop : null,
      ),
    ];
    final shutter = _Shutter(run: run, enabled: ready, onPress: onPress);
    final hint = Text(
      'Volume button or a Bluetooth remote works too',
      textAlign: TextAlign.center,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: Colors.white70),
    );
    if (vertical) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final chip in chips) ...[chip, const SizedBox(height: 8)],
          const SizedBox(height: 8),
          shutter,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
        const SizedBox(height: 16),
        shutter,
        const SizedBox(height: 10),
        hint,
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.icon,
    required this.label,
    this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.black54,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              if (caption != null) ...[
                Text(caption!,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The record button: a red disc to start, a red square to stop, and the
/// seconds left in it while a countdown runs.
class _Shutter extends StatelessWidget {
  const _Shutter(
      {required this.run, required this.enabled, required this.onPress});

  final CaptureRun run;
  final bool enabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final phase = run.phase;
    final recording =
        phase == CapturePhase.recording || phase == CapturePhase.stopping;
    final label = switch (phase) {
      CapturePhase.idle => 'Record',
      CapturePhase.counting => 'Cancel countdown',
      _ => 'Stop',
    };
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey('capture-shutter'),
        onTap: enabled ? onPress : null,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: recording ? 30 : 60,
            height: recording ? 30 : 60,
            decoration: BoxDecoration(
              color: enabled ? Colors.red : Colors.white24,
              borderRadius: BorderRadius.circular(recording ? 6 : 30),
            ),
            alignment: Alignment.center,
            child: phase == CapturePhase.counting
                ? Text('${run.remaining}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700))
                : null,
          ),
        ),
      ),
    );
  }
}

/// The countdown as big as the screen will take it: it is read from the
/// ring, where the phone is a small thing on a bag.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Text(
          '$seconds',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: 180,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: const [Shadow(blurRadius: 16, color: Colors.black)],
          ),
        ),
      );
}

class _RecordingClock extends StatelessWidget {
  const _RecordingClock({required this.run});
  final CaptureRun run;

  @override
  Widget build(BuildContext context) {
    final seconds = run.elapsed.inMilliseconds / 1000;
    final stop = run.stopAfter;
    final text = stop > 0
        ? '${seconds.toStringAsFixed(1)} / $stop s'
        : '${seconds.toStringAsFixed(1)} s';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
