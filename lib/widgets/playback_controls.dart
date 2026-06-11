import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/time_format.dart';

const kPlaybackSpeeds = [0.1, 0.25, 0.5, 0.75, 1.0];

/// Rounds [position] to the nearest frame boundary so seeks land on exact
/// frames instead of arbitrary milliseconds between them.
Duration snapToFrame(Duration position, double fps) {
  final frameUs = Duration.microsecondsPerSecond / fps;
  return Duration(
      microseconds: ((position.inMicroseconds / frameUs).round() * frameUs)
          .round());
}

/// Scrubber + transport controls for a single video: play/pause,
/// frame-by-frame stepping, and slow-motion speed selection.
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.controller,
    required this.fps,
    this.trailing,
  });

  final VideoPlayerController controller;
  final double fps;
  final Widget? trailing;

  Duration get _frameStep =>
      Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());

  void _stepBy(int frames) {
    controller.pause();
    final target = controller.value.position + _frameStep * frames;
    controller.seekTo(Duration(
      microseconds: target.inMicroseconds
          .clamp(0, controller.value.duration.inMicroseconds),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration.inMilliseconds;
        final position =
            value.position.inMilliseconds.clamp(0, duration).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: duration == 0 ? 0 : position,
              max: duration == 0 ? 1 : duration.toDouble(),
              onChanged: (ms) {
                controller.pause();
                controller.seekTo(
                    snapToFrame(Duration(milliseconds: ms.round()), fps));
              },
            ),
            Row(
              children: [
                const SizedBox(width: 12),
                Text(
                  '${formatPosition(value.position)}  ·  '
                  'frame ${frameAt(value.position, fps)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Back one frame',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => _stepBy(-1),
                ),
                IconButton(
                  iconSize: 36,
                  icon: Icon(value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle),
                  onPressed: () =>
                      value.isPlaying ? controller.pause() : controller.play(),
                ),
                IconButton(
                  tooltip: 'Forward one frame',
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => _stepBy(1),
                ),
                const Spacer(),
                SpeedMenuButton(
                  speed: value.playbackSpeed,
                  onChanged: controller.setPlaybackSpeed,
                ),
                if (trailing != null) trailing!,
                const SizedBox(width: 12),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SpeedMenuButton extends StatelessWidget {
  const SpeedMenuButton({
    super.key,
    required this.speed,
    required this.onChanged,
  });

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: speed,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final s in kPlaybackSpeeds)
          PopupMenuItem(value: s, child: Text('${s}x')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('${speed}x',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
