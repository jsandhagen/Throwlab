import 'package:flutter/material.dart';

import '../utils/zoom_detail.dart';

/// The sharp still [detail] holds, laid over the video box it was cut from.
/// Sits in the same stack as the video, inside the zoom transform, so it is
/// placed in the frame's own coordinates and pans and pinches with the
/// picture rather than having to be told about either. Draws nothing while
/// there is no still, so it can stay in the stack for good.
class DetailStill extends StatelessWidget {
  const DetailStill({super.key, required this.detail});

  final ZoomDetail detail;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: detail,
        builder: (context, _) {
          final image = detail.image;
          final job = detail.shown;
          if (image == null || job == null) return const SizedBox.shrink();
          return LayoutBuilder(builder: (context, constraints) {
            final crop = job.crop.normalized;
            final size = constraints.biggest;
            return Stack(children: [
              Positioned(
                left: crop.left * size.width,
                top: crop.top * size.height,
                width: crop.width * size.width,
                height: crop.height * size.height,
                // Faded in rather than switched: the frame under it is the
                // same picture, softer, so the swap reads as the picture
                // coming into focus instead of as something being replaced.
                child: TweenAnimationBuilder<double>(
                  key: ObjectKey(image),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 140),
                  builder: (context, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
                  // Drawn at about one of its pixels to one of the
                  // screen's, so the filter here only has the snap to whole
                  // pixels to smooth over.
                  child: RawImage(
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ]);
          });
        },
      ),
    );
  }
}
