import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/throw_video.dart';
import '../services/video_library.dart';
import 'athlete_picker.dart';
import 'throw_picker.dart';

enum _ThrowAction { athlete, note, delete }

/// The per-throw edits that used to hang off a row's overflow menu: who
/// threw it, a note, and deleting it.
///
/// A sheet rather than a popup menu, because the library is stills now and a
/// long press in the middle of a grid has no corner to hang a menu off. It
/// opens with the throw it is about at the top, so a long press that landed
/// on the wrong card is obvious before anything is changed.
Future<void> showThrowActions(BuildContext context, ThrowVideo video) async {
  final library = context.read<VideoLibrary>();
  final scheme = Theme.of(context).colorScheme;
  final action = await showModalBottomSheet<_ThrowAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
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
            title: Text(video.athlete.isEmpty
                ? 'Set athlete'
                : 'Change athlete'),
            onTap: () => Navigator.pop(context, _ThrowAction.athlete),
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2),
            title: Text(video.note.isEmpty ? 'Add note' : 'Edit note'),
            onTap: () => Navigator.pop(context, _ThrowAction.note),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('Delete throw',
                style: TextStyle(color: scheme.error)),
            onTap: () => Navigator.pop(context, _ThrowAction.delete),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _ThrowAction.athlete:
      await _editAthlete(context, library, video);
    case _ThrowAction.note:
      await _editNote(context, library, video);
    case _ThrowAction.delete:
      // remove() reclaims the clip, its still and the scrub frames itself.
      await library.remove(video.id);
  }
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
