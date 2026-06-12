import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/frame_seeker.dart';
import '../utils/time_format.dart';
import '../widgets/playback_controls.dart';

enum ComparisonMode { sideBySide, overlay }

/// Compares two throws. Scrub each video to its release frame and set the
/// sync point; after that, all transport controls drive both videos with the
/// release frames aligned.
class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key, required this.videoA, required this.videoB});

  final ThrowVideo videoA;
  final ThrowVideo videoB;

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  late final VideoPlayerController _controllerA;
  late final VideoPlayerController _controllerB;
  late final FrameSeeker _seekerA = FrameSeeker(_controllerA);
  late final FrameSeeker _seekerB = FrameSeeker(_controllerB);

  ComparisonMode _mode = ComparisonMode.sideBySide;
  double _overlayOpacity = 0.5;
  double _speed = 0.5;

  Duration _syncA = Duration.zero;
  Duration _syncB = Duration.zero;

  double get _fps => widget.videoA.fps;

  @override
  void initState() {
    super.initState();
    _controllerA = VideoPlayerController.file(File(widget.videoA.path))
      ..initialize().then((_) => mounted ? setState(() {}) : null)
          .catchError((Object _) => mounted ? setState(() {}) : null);
    _controllerB = VideoPlayerController.file(File(widget.videoB.path))
      ..initialize().then((_) => mounted ? setState(() {}) : null)
          .catchError((Object _) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _controllerA.dispose();
    _controllerB.dispose();
    super.dispose();
  }

  bool get _ready =>
      (_controllerA.value.isInitialized || _controllerA.value.hasError) &&
      (_controllerB.value.isInitialized || _controllerB.value.hasError);

  Duration _clampToDuration(Duration position, VideoPlayerController c) =>
      Duration(
        microseconds: position.inMicroseconds
            .clamp(0, c.value.duration.inMicroseconds),
      );

  /// Seeks B so both videos sit at the same offset from their sync points.
  void _followWithB() {
    final offset = _controllerA.value.position - _syncA;
    _controllerB.seekTo(_clampToDuration(_syncB + offset, _controllerB));
  }

  void _seekBoth(Duration positionA) {
    _controllerA.pause();
    _controllerB.pause();
    _seekerA.seekTo(positionA);
    _seekerB.seekTo(_syncB + (positionA - _syncA));
  }

  Future<void> _stepBoth(int frames) async {
    final step = Duration(
        microseconds: (Duration.microsecondsPerSecond / _fps).round());
    _seekBoth(await _seekerA.freshPosition() + step * frames);
  }

  void _togglePlay() {
    if (_controllerA.value.isPlaying) {
      _controllerA.pause();
      _controllerB.pause();
    } else {
      _controllerA.setPlaybackSpeed(_speed);
      _controllerB.setPlaybackSpeed(_speed);
      _followWithB();
      _controllerA.play();
      _controllerB.play();
    }
    setState(() {});
  }

  Widget _player(VideoPlayerController controller) {
    if (controller.value.hasError) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Couldn\'t open this video — the file may have '
              'been removed. Re-import the clip.'),
        ),
      );
    }
    return controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller))
        : const Center(child: CircularProgressIndicator());
  }

  Widget _syncRow(String label, FrameSeeker seeker, double fps,
      Duration sync, ValueChanged<Duration> onSet) {
    final controller = seeker.controller;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => Row(
        children: [
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Slider(
              value: value.position.inMilliseconds
                  .clamp(0, value.duration.inMilliseconds)
                  .toDouble(),
              max: value.duration.inMilliseconds == 0
                  ? 1
                  : value.duration.inMilliseconds.toDouble(),
              onChanged: (ms) {
                controller.pause();
                seeker.seekTo(
                    snapToFrame(Duration(milliseconds: ms.round()), fps));
              },
            ),
          ),
          TextButton.icon(
            icon: Icon(sync == Duration.zero
                ? Icons.flag_outlined
                : Icons.flag),
            label: Text(sync == Duration.zero
                ? 'Set release'
                : formatPosition(sync)),
            // freshPosition: the cached position can lag the displayed
            // frame right after pausing, mismarking the release.
            onPressed: () async => onSet(await seeker.freshPosition()),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.videoA.event.label}: compare throws'),
        actions: [
          SegmentedButton<ComparisonMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: ComparisonMode.sideBySide,
                  icon: Icon(Icons.splitscreen),
                  tooltip: 'Side by side'),
              ButtonSegment(
                  value: ComparisonMode.overlay,
                  icon: Icon(Icons.layers),
                  tooltip: 'Ghost overlay'),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: _mode == ComparisonMode.sideBySide
                          ? Column(
                              children: [
                                Expanded(child: _player(_controllerA)),
                                const Divider(height: 2),
                                Expanded(child: _player(_controllerB)),
                              ],
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                _player(_controllerA),
                                Opacity(
                                  opacity: _overlayOpacity,
                                  child: _player(_controllerB),
                                ),
                              ],
                            ),
                    ),
                  ),
                  if (_mode == ComparisonMode.overlay)
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        const Text('Ghost'),
                        Expanded(
                          child: Slider(
                            value: _overlayOpacity,
                            onChanged: (v) =>
                                setState(() => _overlayOpacity = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  _syncRow('A', _seekerA, widget.videoA.fps, _syncA,
                      (d) => setState(() => _syncA = d)),
                  _syncRow('B', _seekerB, widget.videoB.fps, _syncB,
                      (d) => setState(() => _syncB = d)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Both back one frame',
                        iconSize: 38,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () => _stepBoth(-1),
                      ),
                      IconButton(
                        iconSize: 56,
                        icon: Icon(_controllerA.value.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle),
                        onPressed: _togglePlay,
                      ),
                      IconButton(
                        tooltip: 'Both forward one frame',
                        iconSize: 38,
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => _stepBoth(1),
                      ),
                      const SizedBox(width: 16),
                      SpeedMenuButton(
                        speed: _speed,
                        onChanged: (s) {
                          setState(() => _speed = s);
                          _controllerA.setPlaybackSpeed(s);
                          _controllerB.setPlaybackSpeed(s);
                        },
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        icon: const Icon(Icons.flag_circle),
                        label: const Text('Go to release'),
                        onPressed: () => _seekBoth(_syncA),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}
