import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/meet.dart';
import '../models/throw_video.dart';
import '../utils/meet_report.dart';

/// Gets a meet's results off the phone.
///
/// The sheet is written into the app's own storage and then handed to
/// whatever the phone opens PDFs with, which is where the share sheet, the
/// printer and the mail client all live. Nothing is uploaded anywhere: a
/// results sheet is a file, and a coach at a track has no signal to send it
/// with anyway.
class ResultsSheet {
  /// Writes the sheet and opens it. Returns where it was written, or null
  /// when it couldn't be — a phone with no room left, most likely, which is
  /// worth saying rather than failing silently.
  static Future<String?> share(
    Meet meet,
    Iterable<ThrowResult> results, {
    MeetCompetition? only,
  }) async {
    try {
      final bytes = meetResultsPdf(meet, results, only: only);
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory('${docs.path}/results');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final file = File('${folder.path}/${fileName(meet, only)}');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// What the file is called once it lands in somebody's downloads: the
  /// meet, and the event when it is one event's sheet. Named for a human
  /// rather than for the app, because that is the only place this file is
  /// ever going to be read.
  static String fileName(Meet meet, MeetCompetition? only) {
    final parts = [
      meet.name.isEmpty ? 'Meet' : meet.name,
      if (only != null) only.label.replaceAll(' · ', ' '),
      '${meet.date.year}-'
          '${meet.date.month.toString().padLeft(2, '0')}-'
          '${meet.date.day.toString().padLeft(2, '0')}',
    ];
    final safe = parts
        .join(' - ')
        // Anything a file system might object to, and the runs of spaces
        // that taking it out leaves behind.
        .replaceAll(RegExp(r'[^A-Za-z0-9 \-_.]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$safe.pdf';
  }
}
