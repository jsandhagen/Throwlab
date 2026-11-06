import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/home_screen.dart' show OptimizingDialog;
import '../services/athlete_library.dart';
import '../services/backup.dart';
import '../services/meet_library.dart';
import '../services/notes_library.dart';
import '../services/video_library.dart';
import 'distance_field.dart';

/// Makes a backup and hands it to the share sheet, to go to Drive, the Files
/// app, a laptop — anywhere that is not only this phone, which is the
/// whole point of it.
Future<void> backUpLibrary(BuildContext context) async {
  final library = context.read<VideoLibrary>();
  final meets = context.read<MeetLibrary>();
  final notes = context.read<NotesLibrary>();
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Back up the library'),
      content: Text(
        'Every clip, mark, meet, note and athlete in one file'
        '${_counted(library.videos.length, library.marks.length, meets.meets.length, notes.notes.length)}.\n\n'
        'Save it to Google Drive or Files, somewhere off this phone. It '
        'includes every clip, so it can be large.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            key: const ValueKey('backup-go'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Back up')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final progress = ValueNotifier<double?>(null);
  var canceled = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => OptimizingDialog(
      progress: progress,
      stage: ValueNotifier('Packing the clips and everything written about '
          'them into one file.'),
      title: 'Backing up',
      action: 'Cancel',
      onAction: () => canceled = true,
    ),
  );
  ({File file, BackupSummary summary})? made;
  String? failure;
  try {
    final result = await LibraryBackups.create(
      onProgress: (p) => progress.value = p,
      canceled: () => canceled,
    );
    made = result;
  } on BackupCanceled {
    // Asked to stop; nothing to say.
  } catch (e) {
    failure = '$e';
  }
  navigator.pop();
  if (made == null) {
    if (failure != null) {
      messenger.showSnackBar(SnackBar(
          content: Text("Couldn't make the backup. Is the phone full? "
              '($failure)')));
    }
    return;
  }
  await SharePlus.instance.share(ShareParams(
    files: [XFile(made.file.path, mimeType: 'application/zip')],
    subject: 'ThrowLab backup',
  ));
}

/// Picks a backup and brings back whatever in it isn't on this phone.
Future<void> restoreLibrary(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await openFile(acceptedTypeGroups: const [
    XTypeGroup(
      label: 'ThrowLab backup',
      extensions: ['zip'],
      mimeTypes: ['application/zip'],
    ),
  ]);
  if (picked == null || !context.mounted) return;

  BackupInfo info;
  try {
    info = await LibraryBackup.inspect(picked.path);
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text("That file couldn't be read as a ThrowLab backup.")));
    return;
  }
  if (!context.mounted) return;
  final made = info.createdAt;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        '${made == null ? 'A backup' : 'Made ${_date(made)}'}: '
        '${info.summary.contents} (${info.summary.size}).\n\n'
        'Anything in it that isn\'t on this phone comes back. Nothing '
        'already here is changed or removed.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            key: const ValueKey('restore-go'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final videos = context.read<VideoLibrary>();
  final meets = context.read<MeetLibrary>();
  final notes = context.read<NotesLibrary>();
  final athletes = context.read<AthleteLibrary>();
  final navigator = Navigator.of(context);
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      // Not stoppable: a restore half done is a library half merged, and
      // one finished is a few seconds more.
      child: OptimizingDialog(
        progress: progress,
        stage: ValueNotifier('Putting the clips back.'),
        title: 'Restoring',
        action: null,
      ),
    ),
  );
  RestoreResult? result;
  String? failure;
  try {
    result = await LibraryBackups.restore(picked.path,
        onProgress: (p) => progress.value = p);
    await Future.wait([
      videos.load(),
      meets.load(),
      notes.load(),
      athletes.load(),
      DistanceField.loadPreference(),
    ]);
  } catch (e) {
    failure = '$e';
  }
  navigator.pop();
  messenger.showSnackBar(SnackBar(
    content: Text(result == null
        ? "Couldn't restore that backup. Is the phone full? ($failure)"
        : restoredMessage(result)),
  ));
}

/// 'Restored 12 clips, 30 marks and 4 meets.'
String restoredMessage(RestoreResult result) {
  String? of(String key, String one) {
    final n = result.addedTo(key);
    return n == 0 ? null : '$n $one${n == 1 ? '' : 's'}';
  }

  final parts = [
    of('throwlab.videos', 'clip'),
    of('throwlab.marks', 'mark'),
    of('throwlab.meets', 'meet'),
    of('throwlab.notes', 'note'),
    of('throwlab.athletes', 'athlete record'),
  ].whereType<String>().toList();
  if (parts.isEmpty) {
    return 'Everything in that backup is already on this phone.';
  }
  final list = parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  return 'Restored $list.';
}

/// ': 8 clips, 44 marks and 2 meets', leaving out what there is none of.
String _counted(int clips, int marks, int meets, int notes) {
  String? of(int n, String one) =>
      n == 0 ? null : '$n $one${n == 1 ? '' : 's'}';
  final parts = [
    of(clips, 'clip'),
    of(marks, 'mark'),
    of(meets, 'meet'),
    of(notes, 'note'),
  ].whereType<String>().toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return ': ${parts.single}';
  return ': ${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

String _date(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = when.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
