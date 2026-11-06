import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../screens/home_screen.dart' show OptimizingDialog;
import '../services/clip_export.dart';
import '../services/video_optimizer.dart';
import 'throw_card.dart' show formatDistance;
import 'throw_picker.dart';

enum _Share { clipDrawn, frame, clip }

/// Sends a throw to somebody — the athlete, mostly, who wants to see what
/// the coach saw.
///
/// From the analysis screen, [drawing] is what is on the frame, and the
/// choice is the clip with it burned in, the frame on screen as a picture,
/// or the clip as filmed. From anywhere else there is nothing drawn and
/// nothing on screen, so it is the clip, straight to the share sheet.
/// [pixels] and [duration] are the clip's, as the player reported them.
Future<void> shareThrow(
  BuildContext context,
  ThrowVideo video, {
  ThrowDrawing? drawing,
  Size? pixels,
  Duration? duration,
}) async {
  final drawn = drawing != null && !drawing.isEmpty;
  final choice = drawing == null || pixels == null || duration == null
      ? _Share.clip
      : await showModalBottomSheet<_Share>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          builder: (context) => Padding(
            padding: EdgeInsets.only(
                bottom: 8 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (drawn)
                  ListTile(
                    key: const ValueKey('share-clip-drawn'),
                    leading: const Icon(Icons.draw_outlined),
                    title: const Text('Clip with drawings'),
                    subtitle: Text(drawing.moves
                        ? 'The marks on the video, timers counting.'
                        : 'The marks on the video.'),
                    onTap: () => Navigator.pop(context, _Share.clipDrawn),
                  ),
                ListTile(
                  key: const ValueKey('share-frame'),
                  leading: const Icon(Icons.image_outlined),
                  title:
                      Text(drawn ? 'This frame with drawings' : 'This frame'),
                  subtitle: const Text('A picture of what is on screen.'),
                  onTap: () => Navigator.pop(context, _Share.frame),
                ),
                ListTile(
                  key: const ValueKey('share-clip'),
                  leading: const Icon(Icons.movie_outlined),
                  title: const Text('Clip'),
                  subtitle: Text(drawn
                      ? 'As filmed, without the drawings.'
                      : 'As filmed.'),
                  onTap: () => Navigator.pop(context, _Share.clip),
                ),
              ],
            ),
          ),
        );
  if (choice == null || !context.mounted) return;

  final name = shareName(video);
  final messenger = ScaffoldMessenger.of(context);
  String? path;
  String mime;
  switch (choice) {
    case _Share.clip:
      path = video.path;
      mime = 'video/mp4';
    case _Share.clipDrawn:
      mime = 'video/mp4';
      final progress = ValueNotifier<double?>(null);
      final navigator = Navigator.of(context);
      var canceled = false;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => OptimizingDialog(
          progress: progress,
          stage: ValueNotifier('Drawing the marks onto the clip.'),
          title: 'Getting it ready',
          action: 'Cancel',
          onAction: () {
            canceled = true;
            VideoOptimizer.cancel();
          },
        ),
      );
      path = await ClipExport.clip(
        video,
        drawing: drawing!,
        pixels: pixels!,
        duration: duration!,
        name: name,
        canceled: () => canceled,
        onProgress: (p) => progress.value = p,
      );
      navigator.pop();
      if (canceled) return;
    case _Share.frame:
      mime = 'image/jpeg';
      final navigator = Navigator.of(context);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      path = await ClipExport.frame(video,
          drawing: drawing!, pixels: pixels!, name: name);
      navigator.pop();
  }
  if (path == null) {
    messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't get that ready to share.")));
    return;
  }
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path, mimeType: mime)],
    // Where the receiving app shows a caption, it says whose throw it is.
    text: shareCaption(video),
    subject: shareCaption(video),
  ));
}

/// The file's name as somebody receiving it sees it:
/// 'Ana Diaz - Discus 1 kg - 2026-11-04'. Nothing a file system objects to.
String shareName(ThrowVideo video) {
  final when = video.displayDate.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final parts = [
    if (video.athlete.trim().isNotEmpty) video.athlete.trim(),
    '${video.event.label} ${video.implementSpec.weightLabel}',
    '${when.year}-${two(when.month)}-${two(when.day)}',
  ];
  return parts
      .join(' - ')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// 'Ana Diaz · Discus · 1 kg · 52.18 m'.
String shareCaption(ThrowVideo video) {
  final distance = video.distance;
  return [
    throwTitle(video),
    if (distance != null) formatDistance(distance, video.distanceUnit),
  ].join(' · ');
}
