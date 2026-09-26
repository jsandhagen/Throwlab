import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_video.dart';
import '../services/video_library.dart';
import '../services/video_optimizer.dart';
import '../utils/clip_trim.dart';
import '../utils/frame_seeker.dart';
import '../widgets/playback_controls.dart';
import '../widgets/trim_bar.dart';
import 'home_screen.dart' show OptimizingDialog;

/// How much of a trim's gauge the encode takes, the stills taking the rest
/// — the same split an import makes, for the same wait.
const _encodeShare = 0.75;

/// Cuts a throw down to the part worth keeping.
///
/// A phone left running at the ring films the walk in, the setting up and
/// the walk out, and the throw is two seconds of it: every scrub through
/// that clip is a scrub past the rest, and every still of it is disk. So
/// the ends are picked here — roughly on the strip of stills, then to the
/// frame on the scale under it — and the clip is cut once, for good, to
/// what lies between. Pops with true when the throw's file was replaced.
///
/// Played, the kept part loops, so what is about to be kept is watched
/// before it is saved.
class TrimScreen extends StatefulWidget {
  const TrimScreen({super.key, required this.video});

  final ThrowVideo video;

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  late final VideoPlayerController _controller;
  late final FrameSeeker _seeker;
  TrimRange? _range;

  /// The frame the scale is holding while it is in the hand, which the
  /// player only reaches a seek later.
  int? _held;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      File(widget.video.path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _seeker = FrameSeeker(_controller);
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _range =
          TrimRange.whole(_controller.value.duration, widget.video.fps));
    }).catchError((Object _) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  /// Keeps playback inside the kept part: past its end it goes round again
  /// from its start.
  void _onTick() {
    final range = _range;
    if (range == null) return;
    final value = _controller.value;
    if (value.isPlaying && value.position >= range.end) {
      _controller.seekTo(range.seekTarget(range.first));
    }
    if (mounted) setState(() {});
  }

  int get _frame {
    final range = _range!;
    return _held ?? range.frameAt(_seeker.position);
  }

  void _seek(int frame) {
    _controller.pause();
    _seeker.seekTo(_range!.seekTarget(frame));
    setState(() {});
  }

  /// Moving an end shows the frame it is on, since that frame is what is
  /// being decided about.
  void _setFirst(int frame) {
    final next = _range!.withFirst(frame);
    setState(() => _range = next);
    _seek(next.first);
  }

  void _setLast(int frame) {
    final next = _range!.withLast(frame);
    setState(() => _range = next);
    _seek(next.last);
  }

  Future<void> _togglePlay() async {
    final range = _range!;
    if (_controller.value.isPlaying) {
      await _controller.pause();
      return;
    }
    final frame = _frame;
    if (frame < range.first || frame >= range.last) {
      await _controller.seekTo(range.seekTarget(range.first));
    }
    await _controller.play();
  }

  /// Stills evenly across the clip, out of the ones already cut for
  /// scrubbing; none when it has none yet.
  List<String> _stills(int count) {
    final video = widget.video;
    final dir = video.scrubFramesDir;
    final range = _range;
    if (dir == null || video.scrubFrameCount <= 0 || range == null) {
      return const [];
    }
    return [
      for (var i = 0; i < count; i++)
        () {
          final frame = ((i + 0.5) / count * range.frameCount).floor();
          final still = (frame / video.scrubFrameStride)
              .floor()
              .clamp(0, video.scrubFrameCount - 1);
          return '$dir/f${(still + 1).toString().padLeft(5, '0')}.jpg';
        }(),
    ];
  }

  Future<void> _save() async {
    final range = _range;
    if (range == null || range.isWhole || _saving) return;
    final video = widget.video;
    final library = context.read<VideoLibrary>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await _controller.pause();
    if (!mounted) return;
    setState(() => _saving = true);

    final progress = ValueNotifier<double?>(null);
    final stage = ValueNotifier<String>('Cutting the clip to '
        '${_seconds(range.length)}.');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OptimizingDialog(
        progress: progress,
        stage: stage,
        title: 'Trimming clip',
        action: 'Cancel',
      ),
    );

    final path = await VideoOptimizer.trimClip(
      video.path,
      video.id,
      range,
      onProgress: (p) => progress.value = p == null ? null : p * _encodeShare,
    );
    if (path == null) {
      navigator.pop();
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Trim stopped — the clip is as it was')));
      return;
    }
    applyTrim(video, range);
    video
      ..path = path
      ..playbackVersion = VideoOptimizer.playbackVersion
      ..optimizePending = false;
    // Saved before the stills are cut: the file is already replaced, and a
    // throw pointing at stills of the old clip would scrub the wrong frames.
    await library.update(video);

    stage.value = 'Extracting frames for smooth scrubbing…';
    progress.value = _encodeShare;
    final frames = await VideoOptimizer.extractScrubFrames(
      path,
      video.id,
      video.fps,
      onProgress: (p) => progress.value =
          p == null ? _encodeShare : _encodeShare + p * (1 - _encodeShare),
    );
    if (frames != null) {
      video
        ..scrubFramesDir = frames.dir
        ..scrubFrameCount = frames.count
        ..scrubFrameStride = frames.stride
        ..scrubFrameLongSide = VideoOptimizer.scrubFrameMax
        ..scrubFramesVersion = VideoOptimizer.scrubFramesVersion;
    }
    final thumbnail = await VideoOptimizer.extractThumbnail(path, video.id);
    if (thumbnail != null) {
      // Written over the old one's path, so the card would go on showing
      // the old still out of the image cache.
      await FileImage(File(thumbnail)).evict();
      video.thumbnailPath = thumbnail;
    }
    await library.update(video);
    navigator
      ..pop()
      ..pop(true);
  }

  static String _seconds(Duration d) =>
      '${(d.inMicroseconds / 1e6).toStringAsFixed(2)} s';

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Trim clip'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              key: const ValueKey('trim-save'),
              onPressed:
                  range == null || range.isWhole || _saving ? null : _save,
              child: const Text('Trim'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: range == null
            ? Center(
                child: _controller.value.hasError
                    ? const Text('This clip could not be opened.')
                    : const CircularProgressIndicator(),
              )
            : LayoutBuilder(builder: (context, constraints) {
                final picture = GestureDetector(
                  onTap: _togglePlay,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                );
                final controls = _controls(context, range);
                if (constraints.maxWidth > constraints.maxHeight) {
                  return Row(
                    children: [
                      Expanded(child: picture),
                      SizedBox(
                        width: 360,
                        child: SingleChildScrollView(child: controls),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [Expanded(child: picture), controls],
                );
              }),
      ),
    );
  }

  Widget _controls(BuildContext context, TrimRange range) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final release = widget.video.release;
    final frame = _frame;
    final cutsRelease = release != null && range.releaseAfter(release) == null;
    final label = theme.textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 1);
    final value = theme.textTheme.titleMedium
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    Widget readout(String name, String text, {TextAlign? align}) => Column(
          crossAxisAlignment: align == TextAlign.end
              ? CrossAxisAlignment.end
              : align == TextAlign.center
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
          children: [
            Text(name, style: label),
            Text(text, style: value),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(child: readout('START', _seconds(range.start))),
                Expanded(
                  child: readout(
                    'KEEP',
                    '${_seconds(range.length)} of '
                        '${_seconds(range.at(range.frameCount))}',
                    align: TextAlign.center,
                  ),
                ),
                Expanded(
                  child:
                      readout('END', _seconds(range.end), align: TextAlign.end),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => TrimBar(
              range: range,
              frame: frame,
              release: release == null ? null : range.frameAt(release),
              stills: _stills(((constraints.maxWidth - 2 * TrimBar.handle) / 40)
                  .floor()
                  .clamp(1, 16)),
              onFirst: _setFirst,
              onLast: _setLast,
              onSeek: _seek,
            ),
          ),
          ScrubWheel(
            controller: _controller,
            fps: widget.video.fps,
            captureFps: widget.video.captureFps,
            release: release,
            onHold: (held) => setState(() => _held = held),
          ),
          if (cutsRelease)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The release is outside what is kept — it will be cleared.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('trim-start-here'),
                  onPressed: () => _setFirst(frame),
                  icon: const Icon(Icons.first_page),
                  label: const Text('Start here'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip:
                    _controller.value.isPlaying ? 'Pause' : 'Play kept part',
                onPressed: _togglePlay,
                icon: Icon(_controller.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('trim-end-here'),
                  onPressed: () => _setLast(frame),
                  icon: const Icon(Icons.last_page),
                  label: const Text('End here'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
