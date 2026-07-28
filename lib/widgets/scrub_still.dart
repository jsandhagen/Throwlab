import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/scrub_shuttle.dart';

/// The pre-extracted still that covers the video while [shuttle] is
/// scrubbing, and across the brief handoff back to live video afterwards.
/// Draws nothing at any other time, so it can sit permanently in the stack
/// over a video player.
class ScrubStill extends StatelessWidget {
  const ScrubStill({super.key, required this.shuttle});

  final ScrubShuttle shuttle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shuttle,
      builder: (context, _) {
        final frames = shuttle.frames;
        if (frames == null || !shuttle.overlayVisible) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<ui.Image?>(
          valueListenable: frames.current,
          builder: (_, image, __) => image == null
              ? const SizedBox.shrink()
              // contain, not fill: the stills carry the video's exact aspect,
              // and preserving their own geometry means any future mismatch
              // letterboxes by a pixel instead of stretching the picture
              // mid-scrub.
              : RawImage(image: image, fit: BoxFit.contain),
        );
      },
    );
  }
}
