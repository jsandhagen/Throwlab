import 'dart:io';

import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../screens/home_screen.dart' show OptimizingDialog;
import '../services/video_optimizer.dart';
import '../utils/throw_finder.dart';

/// Looks for the throw in a clip on its way in, and asks whether to keep
/// only that. Returns the window to cut to, or null to keep the whole clip —
/// which is also the answer when there was nothing to find, the clip was
/// short, or the scan was skipped.
///
/// Asked rather than done: the finder reads motion, not throws, and a clip
/// cut to the wrong four seconds has lost the one it was filmed for. One
/// look at the frame it picked as the throw settles it, so that frame is
/// what the question is put over. [keepsOriginal] says whether the uncut
/// clip survives elsewhere — a gallery import does, the camera's own file
/// does not — because that is what a coach is deciding about.
Future<ThrowWindow?> offerCutToThrow(
  BuildContext context, {
  required String path,
  required ThrowEvent event,
  required double fps,
  required double captureFps,
  required bool keepsOriginal,
}) async {
  final progress = ValueNotifier<double?>(null);
  final stage = ValueNotifier<String>(
      'Looking for the throw, so the waiting either side of it can go.');
  final navigator = Navigator.of(context);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => OptimizingDialog(
      progress: progress,
      stage: stage,
      title: 'Finding the throw',
    ),
  ).whenComplete(() => open = false);
  final window = await VideoOptimizer.findThrowIn(
    path,
    event: event,
    fps: fps,
    captureFps: captureFps,
    onProgress: (p) => progress.value = p,
  );
  final stills = window == null
      ? const <String?>[]
      : await Future.wait([
          VideoOptimizer.grabStill(path, window.start),
          VideoOptimizer.grabStill(path, window.peak),
          VideoOptimizer.grabStill(path, window.end - 0.05),
        ]);
  if (open) navigator.pop();
  if (window == null || !context.mounted) return null;
  final cut = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => FoundThrowSheet(
      window: window,
      stills: stills,
      keepsOriginal: keepsOriginal,
    ),
  );
  for (final still in stills) {
    if (still != null) File(still).delete().ignore();
  }
  return cut == true ? window : null;
}

/// The question [offerCutToThrow] asks: the throw it found, as the frames
/// either end of what would be kept and the one it picked as the throw, and
/// how much of the clip that is.
class FoundThrowSheet extends StatelessWidget {
  const FoundThrowSheet({
    super.key,
    required this.window,
    required this.stills,
    required this.keepsOriginal,
  });

  final ThrowWindow window;

  /// Start, throw, end — any of them null where the still failed.
  final List<String?> stills;
  final bool keepsOriginal;

  static String clock(double seconds) {
    final whole = seconds.floor();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labels = [
      'Starts ${clock(window.start)}',
      'The throw',
      'Ends ${clock(window.end)}'
    ];
    return SingleChildScrollView(
      child: Padding(
        // The foot of a sheet is the sheet's to keep clear of the navigation
        // bar — see the note on bottom sheets in CLAUDE.md.
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 16 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Found the throw', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'At ${clock(window.peak)} — keeps '
              '${window.length.toStringAsFixed(1)} s of '
              '${clock(window.duration)}.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: i == 1 ? 4 : 3,
                    child: _Still(
                      path: i < stills.length ? stills[i] : null,
                      label: labels[i],
                      lit: i == 1,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              keepsOriginal
                  ? 'The original stays in your gallery.'
                  : 'The rest of the recording is not kept.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('found-keep-whole'),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep whole clip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('found-cut'),
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.content_cut),
                    label: const Text('Cut to the throw'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Still extends StatelessWidget {
  const _Still({required this.path, required this.label, required this.lit});

  final String? path;
  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = this.path;
    return Column(
      children: [
        SizedBox(
          height: lit ? 160 : 132,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            // In front of the still, or the picture covers its own edge.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: lit ? scheme.primary : scheme.outlineVariant,
                width: lit ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: path == null
                  ? Icon(Icons.image_not_supported_outlined,
                      color: scheme.onSurfaceVariant)
                  : Image.file(File(path), fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: lit ? scheme.primary : scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
