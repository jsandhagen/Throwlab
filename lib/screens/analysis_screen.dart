import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/video_library.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/playback_controls.dart';

const kAnnotationColors = [
  Colors.orangeAccent,
  Colors.lightGreenAccent,
  Colors.cyanAccent,
  Colors.pinkAccent,
  Colors.white,
];

/// Single-throw breakdown: slow motion, frame stepping, and drawing.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.video});

  final ThrowVideo video;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final VideoPlayerController _controller;
  final DrawingController _drawing = DrawingController();

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.video.path))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _drawing.dispose();
    super.dispose();
  }

  /// Steps the video by [frames] while dragging across it in scrub mode.
  void _jogFrames(int frames) {
    _controller.pause();
    final frameUs =
        (Duration.microsecondsPerSecond / widget.video.fps).round();
    final target =
        _controller.value.position.inMicroseconds + frameUs * frames;
    _controller.seekTo(Duration(
      microseconds:
          target.clamp(0, _controller.value.duration.inMicroseconds),
    ));
  }

  Future<void> _editFps() async {
    final fieldController =
        TextEditingController(text: widget.video.fps.toStringAsFixed(0));
    final fps = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recorded frame rate'),
        content: TextField(
          controller: fieldController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'fps',
            helperText: 'Slow-motion clips are usually 120 or 240 fps',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
                context, double.tryParse(fieldController.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (fps != null && fps > 0) {
      widget.video.fps = fps;
      if (mounted) {
        await context.read<VideoLibrary>().update(widget.video);
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.video.implementSpec;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.video.event.label} · ${widget.video.gender.label}'),
        actions: [
          IconButton(
            tooltip: 'Set frame rate (${widget.video.fps.toStringAsFixed(0)} fps)',
            icon: const Icon(Icons.shutter_speed),
            onPressed: _editFps,
          ),
          IconButton(
            tooltip: 'Clear drawings',
            icon: const Icon(Icons.layers_clear),
            onPressed: _drawing.clear,
          ),
        ],
      ),
      // top: false — the AppBar already handles the status bar; the bottom
      // inset keeps controls above the Android gesture/taskbar area.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: _controller.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoPlayer(_controller),
                            DrawingCanvas(
                              controller: _drawing,
                              onJogFrames: _jogFrames,
                            ),
                          ],
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
            _DrawingToolbar(controller: _drawing),
            PlaybackControls(
              controller: _controller,
              fps: widget.video.fps,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Calibration reference: ${spec.referenceLabel.toLowerCase()} '
                '${(spec.nominalSize * 100).toStringAsFixed(1)} cm (nominal) '
                '· drag video to scrub frames',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingToolbar extends StatelessWidget {
  const _DrawingToolbar({required this.controller});

  final DrawingController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SegmentedButton<DrawTool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: DrawTool.none,
                  icon: Icon(Icons.pan_tool_alt),
                  tooltip: 'Scrub only'),
              ButtonSegment(
                  value: DrawTool.pen,
                  icon: Icon(Icons.draw),
                  tooltip: 'Freehand pen'),
              ButtonSegment(
                  value: DrawTool.line,
                  icon: Icon(Icons.timeline),
                  tooltip: 'Straight line'),
              ButtonSegment(
                  value: DrawTool.angle,
                  icon: Icon(Icons.square_foot),
                  tooltip: 'Angle (tap 3 points, vertex second)'),
            ],
            selected: {controller.tool},
            onSelectionChanged: (selection) =>
                controller.tool = selection.first,
          ),
          const SizedBox(width: 12),
          for (final color in kAnnotationColors)
            GestureDetector(
              onTap: () => controller.color = color,
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: controller.color == color
                        ? Colors.white
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: controller.undo,
          ),
        ],
      ),
    );
  }
}
