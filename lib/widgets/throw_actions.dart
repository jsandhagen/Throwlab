import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../screens/trim_screen.dart';
import '../services/video_library.dart';
import 'athlete_picker.dart';
import 'distance_field.dart';
import 'throw_picker.dart';

enum _ThrowAction {
  athlete,
  implement,
  distance,
  note,
  frameRate,
  trim,
  delete
}

/// The per-throw edits that used to hang off a row's overflow menu: who
/// threw it, what they threw, how far it went, a note, the rate it was
/// filmed at, trimming it, and deleting it.
///
/// A sheet rather than a popup menu, because the library is stills now and a
/// long press in the middle of a grid has no corner to hang a menu off. It
/// opens with the throw it is about at the top, so a long press that landed
/// on the wrong card is obvious before anything is changed.
///
/// Returns true when the clip's file was replaced — a trim — which a screen
/// playing it has to reopen on, since its player still holds the old one.
Future<bool> showThrowActions(BuildContext context, ThrowVideo video) async {
  final library = context.read<VideoLibrary>();
  final scheme = Theme.of(context).colorScheme;
  final action = await showModalBottomSheet<_ThrowAction>(
    context: context,
    showDragHandle: true,
    // Allowed taller than the default half screen, and scrolling where even
    // that is short: seven rows under a header is more than half of a small
    // phone.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ThrowThumbnail(video, width: 64, height: 40),
              title: Text(throwTitle(video)),
              subtitle: Text(throwSubtitle(video),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(
                  video.athlete.isEmpty ? 'Set athlete' : 'Change athlete'),
              onTap: () => Navigator.pop(context, _ThrowAction.athlete),
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: Text('Implement · ${video.implementSpec.weightLabel}'),
              onTap: () => Navigator.pop(context, _ThrowAction.implement),
            ),
            ListTile(
              leading: const Icon(Icons.straighten),
              title: Text(
                  video.distance == null ? 'Add distance' : 'Change distance'),
              onTap: () => Navigator.pop(context, _ThrowAction.distance),
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2),
              title: Text(video.note.isEmpty ? 'Add note' : 'Edit note'),
              onTap: () => Navigator.pop(context, _ThrowAction.note),
            ),
            ListTile(
              leading: const Icon(Icons.shutter_speed),
              title: Text(
                  'Frame rate · ${video.captureFps.toStringAsFixed(0)} fps'),
              onTap: () => Navigator.pop(context, _ThrowAction.frameRate),
            ),
            ListTile(
              leading: const Icon(Icons.content_cut),
              title: const Text('Trim clip'),
              onTap: () => Navigator.pop(context, _ThrowAction.trim),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title:
                  Text('Delete throw', style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.pop(context, _ThrowAction.delete),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return false;
  switch (action) {
    case _ThrowAction.athlete:
      await _editAthlete(context, library, video);
    case _ThrowAction.implement:
      await _editImplement(context, library, video);
    case _ThrowAction.distance:
      await _editDistance(context, library, video);
    case _ThrowAction.note:
      await _editNote(context, library, video);
    case _ThrowAction.frameRate:
      await editCaptureFps(context, library, video);
    case _ThrowAction.trim:
      final trimmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => TrimScreen(video: video)),
      );
      return trimmed ?? false;
    case _ThrowAction.delete:
      // remove() reclaims the clip, its still and the scrub frames itself.
      await library.remove(video.id);
  }
  return false;
}

/// Tagging reuses the import flow's picker, so a name already in the library
/// is a tap rather than something to spell the same way twice.
Future<void> _editAthlete(
    BuildContext context, VideoLibrary library, ThrowVideo video) async {
  var name = video.athlete;
  final saved = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Athlete'),
      content: StatefulBuilder(
        builder: (context, setState) => AthletePicker(
          known: library.knownAthletes,
          value: name,
          onChanged: (value) => setState(() => name = value),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('Save')),
      ],
    ),
  );
  if (saved == null) return;
  video.athlete = saved.trim();
  await library.update(video);
}

/// What was thrown. The weight is what fixes the dimension the analyzer
/// calibrates against, so getting it wrong scales every measurement taken
/// from the clip.
Future<void> _editImplement(
    BuildContext context, VideoLibrary library, ThrowVideo video) async {
  final chosen = await showDialog<double>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('${video.event.label} implement'),
      children: [
        for (final spec in video.event.implements)
          RadioListTile<double>(
            value: spec.weightKg,
            groupValue: video.implementKg,
            title: Text(spec.weightLabel),
            subtitle: Text('${spec.usedBy} · '
                '${spec.referenceLabel.toLowerCase()} '
                '${(spec.nominalSize * 100).toStringAsFixed(1)} cm'),
            onChanged: (weight) => Navigator.pop(context, weight),
          ),
      ],
    ),
  );
  if (chosen == null) return;
  video.implementKg = chosen;
  await library.update(video);
}

/// How far it went, in meters or feet. Empty clears it — a throw can be a
/// foul, or measured later, and the card should then say nothing rather
/// than "0.00 m".
Future<void> _editDistance(
    BuildContext context, VideoLibrary library, ThrowVideo video) async {
  var meters = video.distance;
  var unit = video.distanceUnit;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Distance'),
      content: DistanceField(
        meters: video.distance,
        unit: video.distanceUnit,
        autofocus: true,
        onChanged: (value, entered) {
          meters = value;
          unit = entered;
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save')),
      ],
    ),
  );
  if (saved != true) return;
  video.distance = meters;
  video.distanceUnit = unit;
  await library.update(video);
}

Future<void> _editNote(
    BuildContext context, VideoLibrary library, ThrowVideo video) async {
  final controller = TextEditingController(text: video.note);
  final saved = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: 'e.g. "PB attempt, slight headwind"'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save')),
      ],
    ),
  );
  if (saved == null) return;
  video.note = saved;
  await library.update(video);
}

/// The rate the clip was really filmed at, which every speed and every time
/// the analyzer reads is scaled by. Read off the file on import, and wrong
/// often enough on a slow-motion clip to need a way to say so.
Future<void> editCaptureFps(
    BuildContext context, VideoLibrary library, ThrowVideo video) async {
  final fieldController =
      TextEditingController(text: video.captureFps.toStringAsFixed(0));
  final fps = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Recorded frame rate'),
      content: TextField(
        controller: fieldController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'capture fps',
          helperText: 'Auto-detected on import; override if the '
              'slow-mo rate was read wrong (usually 120 or 240)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, double.tryParse(fieldController.text)),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (fps == null || fps <= 0) return;
  video.captureFps = fps;
  await library.update(video);
}
