import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The whole library in one file, and back again.
///
/// Everything ThrowLab knows lives on the phone — the clips, the marks, the
/// meets, the notes, the athletes — and a phone is lost, dropped in a
/// steeplechase pit or swapped for a new one at the end of a contract. So a
/// backup is one zip a coach can put somewhere that isn't the phone: the
/// stored data as it is, and every file it points at, laid out so that a
/// restore can put each one back under whatever directory the new phone
/// gives the app.
///
/// A restore *merges* rather than replaces. What is in the backup and not on
/// the phone comes back; what is on the phone is never changed or removed,
/// even where the backup holds an older copy of it. That makes the one
/// mistake a restore could make — wiping a season with last month's file —
/// impossible, and costs nothing on the phone it is usually restored onto,
/// which is a new one with nothing on it.
class LibraryBackup {
  static const format = 'throwlab-backup';
  static const version = 1;
  static const manifestName = 'throwlab-backup.json';

  /// The stored lists a restore merges, and what one entry is known by.
  /// Athletes are keyed by the library spelling, case aside, the same way
  /// `AthleteLibrary` keys them.
  static const merged = {
    'throwlab.videos': 'id',
    'throwlab.marks': 'id',
    'throwlab.meets': 'id',
    'throwlab.notes': 'id',
    'throwlab.athletes': 'name',
  };

  /// Writes a backup of [prefs] — the app's stored values, by key — and of
  /// every file they name, to [outPath]. [docs] is the app's documents
  /// directory, which the files under it are stored relative to.
  ///
  /// The files are found by reading the data rather than by walking the
  /// directory: a path stored anywhere in it is a file somebody will want
  /// back, and the directory also holds the scrub stills, which are hundreds
  /// of megabytes a clip and are cut again from the clip on the first open.
  /// Stored, not compressed — a clip is already as small as it gets.
  static Future<BackupSummary> write({
    required Map<String, Object> prefs,
    required String docs,
    required String outPath,
    ValueChanged<double>? onProgress,
    bool Function()? canceled,
  }) async {
    final entries = <String, String>{};
    var external = 0;
    for (final path in _filesIn(prefs.values)) {
      if (entries.containsKey(path)) continue;
      final relative = _under(path, docs);
      entries[path] = relative != null
          ? 'files/$relative'
          : 'external/${external++}_${_basename(path)}';
    }
    final sizes = {
      for (final path in entries.keys) path: await File(path).length(),
    };
    final total = sizes.values.fold<int>(0, (a, b) => a + b);
    final summary =
        BackupSummary.of(prefs, files: entries.length, bytes: total);
    final manifest = {
      'format': format,
      'version': version,
      'createdAt': DateTime.now().toIso8601String(),
      'docs': docs,
      'summary': summary.toJson(),
      'files': entries,
      'prefs': {
        for (final entry in prefs.entries) entry.key: _tag(entry.value),
      },
    };

    final staging = '$outPath.part';
    _deleteQuietly(staging);
    final encoder = ZipFileEncoder();
    encoder.create(staging, level: ZipFileEncoder.store);
    try {
      final bytes = utf8.encode(jsonEncode(manifest));
      encoder.addArchiveFile(ArchiveFile.bytes(manifestName, bytes));
      var done = 0;
      for (final entry in entries.entries) {
        if (canceled?.call() ?? false) throw const BackupCanceled();
        await encoder.addFile(File(entry.key), entry.value);
        done += sizes[entry.key]!;
        onProgress?.call(total == 0 ? 1 : done / total);
      }
      await encoder.close();
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      _deleteQuietly(staging);
      rethrow;
    }
    // Renamed into place only once it is whole, so a backup that died half
    // way is never mistaken for one that didn't.
    await File(staging).rename(outPath);
    return summary;
  }

  /// What the backup at [zipPath] holds, read off its manifest without
  /// touching anything — for the question asked before a restore.
  static Future<BackupInfo> inspect(String zipPath) async {
    final input = InputFileStream(zipPath);
    try {
      return BackupInfo._(_manifest(ZipDecoder().decodeStream(input)));
    } finally {
      await input.close();
    }
  }

  /// Merges the backup at [zipPath] into [current] — the phone's own stored
  /// values — putting its files back under [docs], and returns the values
  /// to store and what came back. Nothing is written to storage here: the
  /// caller stores them and has every library read itself again.
  static Future<RestoreResult> restore(
    String zipPath, {
    required Map<String, Object> current,
    required String docs,
    ValueChanged<double>? onProgress,
  }) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final manifest = _manifest(archive);
      final oldDocs = manifest['docs'] as String;
      final files = (manifest['files'] as Map).cast<String, String>();

      // Where each file the backup names lands on this phone.
      final destinations = <String, String>{
        for (final entry in files.entries)
          entry.key: _destination(entry.value, docs),
      };
      String moved(String value) {
        final exact = destinations[value];
        if (exact != null) return exact;
        // Paths the backup carries no file for — the scrub stills'
        // directory — still move to the new documents directory, where they
        // are cut again.
        if (value.startsWith('$oldDocs/')) {
          return '$docs/${value.substring(oldDocs.length + 1)}';
        }
        return value;
      }

      final incoming = {
        for (final entry in (manifest['prefs'] as Map).entries)
          entry.key as String: _rewrite(_untag(entry.value), moved),
      };

      final values = Map<String, Object>.of(current);
      final added = <String, int>{};
      for (final entry in incoming.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value == null) continue;
        final id = merged[key];
        if (id == null) {
          // A setting — the unit marks are typed in, a folded section — is
          // the phone's own once it has one.
          values.putIfAbsent(key, () => value);
          continue;
        }
        final mergedList = mergeStored(
          current[key] as String?,
          value as String,
          id: id,
          adopt: key == 'throwlab.videos' ? _uncutStills : null,
        );
        added[key] = mergedList.added;
        values[key] = mergedList.json;
      }

      // The files, last: a file whose place is already taken is the phone's
      // own copy of something it kept, and is left alone.
      final total = files.length;
      var done = 0;
      for (final entry in files.entries) {
        final target = destinations[entry.key]!;
        final file = archive.find(entry.value);
        if (file != null && file.isFile && !File(target).existsSync()) {
          await Directory(File(target).parent.path).create(recursive: true);
          final staging = '$target.restoring';
          final output = OutputFileStream(staging);
          file.writeContent(output);
          await output.close();
          await File(staging).rename(target);
        }
        done++;
        onProgress?.call(total == 0 ? 1 : done / total);
      }
      return RestoreResult(values: values, added: added);
    } finally {
      await input.close();
    }
  }

  /// [incoming]'s entries added to [existing]'s, by [id]: what is already
  /// there stays as it is, and is never replaced by the backup's copy.
  /// [adopt] is given each entry that is added, to fix it up for the phone
  /// it is arriving on.
  @visibleForTesting
  static ({String json, int added}) mergeStored(
    String? existing,
    String incoming, {
    required String id,
    void Function(Map<String, dynamic> entry)? adopt,
  }) {
    List<dynamic> read(String? raw) {
      if (raw == null) return [];
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : [];
      } catch (_) {
        return [];
      }
    }

    String keyOf(dynamic entry) =>
        entry is Map ? '${entry[id] ?? ''}'.trim().toLowerCase() : '';
    final list = read(existing);
    final have = {for (final entry in list) keyOf(entry)};
    var added = 0;
    for (final entry in read(incoming)) {
      final key = keyOf(entry);
      if (key.isEmpty || !have.add(key)) continue;
      adopt?.call(entry as Map<String, dynamic>);
      list.add(entry);
      added++;
    }
    return (json: jsonEncode(list), added: added);
  }

  /// A clip's scrub stills are not in a backup, so a clip that comes back
  /// says it has none, and has them cut again the first time it is opened.
  static void _uncutStills(Map<String, dynamic> video) {
    video['scrubFrameCount'] = 0;
    video['scrubFramesVersion'] = 0;
  }

  /// Every absolute path to a file that exists, anywhere in [values] —
  /// including inside the JSON the libraries store their lists as.
  @visibleForTesting
  static Set<String> filesIn(Iterable<Object> values) => _filesIn(values);

  static Set<String> _filesIn(Iterable<Object> values) {
    final found = <String>{};
    void visit(dynamic value) {
      if (value is String) {
        if (value.startsWith('/') && !value.contains('\n')) {
          if (FileSystemEntity.typeSync(value) == FileSystemEntityType.file) {
            found.add(value);
          }
          return;
        }
        final trimmed = value.trimLeft();
        if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
          try {
            visit(jsonDecode(value));
          } catch (_) {
            // Text that happens to start with a bracket.
          }
        }
      } else if (value is List) {
        value.forEach(visit);
      } else if (value is Map) {
        value.values.forEach(visit);
      }
    }

    values.forEach(visit);
    return found;
  }

  /// [value] with every string in it — and in any JSON it holds — passed
  /// through [moved].
  static Object? _rewrite(Object? value, String Function(String) moved) {
    if (value is String) {
      final trimmed = value.trimLeft();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        try {
          return jsonEncode(_walk(jsonDecode(value), moved));
        } catch (_) {}
      }
      return moved(value);
    }
    if (value is List<String>) return [for (final s in value) moved(s)];
    return value;
  }

  static dynamic _walk(dynamic value, String Function(String) moved) {
    if (value is String) return moved(value);
    if (value is List) return [for (final v in value) _walk(v, moved)];
    if (value is Map) {
      return {
        for (final entry in value.entries) entry.key: _walk(entry.value, moved),
      };
    }
    return value;
  }

  static String? _under(String path, String dir) =>
      path.startsWith('$dir/') ? path.substring(dir.length + 1) : null;

  static String _basename(String path) => path.split('/').last;

  /// Where a backup's entry goes under [docs]. Only names a backup could
  /// have written are honored, and none that climb out of the directory —
  /// a zip is a file somebody handed the phone, and its names are not to be
  /// trusted to stay where they say.
  static String _destination(String entry, String docs) {
    final parts = entry.split('/');
    if (parts.length < 2 ||
        parts.any((p) => p.isEmpty || p == '.' || p == '..') ||
        (parts.first != 'files' && parts.first != 'external')) {
      throw const FormatException('Not a ThrowLab backup.');
    }
    final rest = parts.skip(1).join('/');
    return parts.first == 'files' ? '$docs/$rest' : '$docs/restored/$rest';
  }

  static Map<String, dynamic> _manifest(Archive archive) {
    final file = archive.find(manifestName);
    if (file == null) throw const FormatException('Not a ThrowLab backup.');
    final manifest = jsonDecode(utf8.decode(file.content));
    if (manifest is! Map<String, dynamic> || manifest['format'] != format) {
      throw const FormatException('Not a ThrowLab backup.');
    }
    if ((manifest['version'] as num? ?? 0) > version) {
      throw const FormatException(
          'This backup was made by a newer ThrowLab. Update the app first.');
    }
    return manifest;
  }

  /// SharedPreferences holds five kinds of value, and a restore has to put
  /// each back as the kind it was.
  static Map<String, Object> _tag(Object value) => switch (value) {
        String() => {'s': value},
        bool() => {'b': value},
        int() => {'i': value},
        double() => {'d': value},
        List<String>() => {'l': value},
        _ => {'s': '$value'},
      };

  static Object? _untag(Object? tagged) {
    if (tagged is! Map || tagged.isEmpty) return null;
    final entry = tagged.entries.first;
    return switch (entry.key) {
      's' => entry.value as String,
      'b' => entry.value as bool,
      'i' => (entry.value as num).toInt(),
      'd' => (entry.value as num).toDouble(),
      'l' => (entry.value as List).cast<String>().toList(),
      _ => null,
    };
  }
}

/// Thrown out of [LibraryBackup.write] when it was asked to stop; nothing
/// is left behind.
class BackupCanceled implements Exception {
  const BackupCanceled();
}

/// How much a backup holds, in the words a coach would check it by.
class BackupSummary {
  const BackupSummary({
    required this.clips,
    required this.marks,
    required this.meets,
    required this.notes,
    required this.files,
    required this.bytes,
  });

  factory BackupSummary.of(Map<String, Object> prefs,
      {required int files, required int bytes}) {
    int count(String key) {
      try {
        final decoded = jsonDecode(prefs[key] as String? ?? '[]');
        return decoded is List ? decoded.length : 0;
      } catch (_) {
        return 0;
      }
    }

    return BackupSummary(
      clips: count('throwlab.videos'),
      marks: count('throwlab.marks'),
      meets: count('throwlab.meets'),
      notes: count('throwlab.notes'),
      files: files,
      bytes: bytes,
    );
  }

  factory BackupSummary.fromJson(Map<String, dynamic> json) => BackupSummary(
        clips: (json['clips'] as num?)?.toInt() ?? 0,
        marks: (json['marks'] as num?)?.toInt() ?? 0,
        meets: (json['meets'] as num?)?.toInt() ?? 0,
        notes: (json['notes'] as num?)?.toInt() ?? 0,
        files: (json['files'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );

  final int clips;
  final int marks;
  final int meets;
  final int notes;
  final int files;
  final int bytes;

  Map<String, dynamic> toJson() => {
        'clips': clips,
        'marks': marks,
        'meets': meets,
        'notes': notes,
        'files': files,
        'bytes': bytes,
      };

  /// '12 clips · 30 marks · 4 meets · 2 notes'.
  String get contents {
    String of(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    return [
      of(clips, 'clip'),
      of(marks, 'mark'),
      of(meets, 'meet'),
      of(notes, 'note'),
    ].join(' · ');
  }

  String get size => formatBytes(bytes);
}

/// '820 MB', '1.4 GB'.
String formatBytes(int bytes) {
  if (bytes < 1000 * 1000) return '${(bytes / 1000).ceil()} KB';
  if (bytes < 1000 * 1000 * 1000) return '${(bytes / 1e6).round()} MB';
  return '${(bytes / 1e9).toStringAsFixed(1)} GB';
}

class BackupInfo {
  BackupInfo._(Map<String, dynamic> manifest)
      : createdAt = DateTime.tryParse(manifest['createdAt'] as String? ?? ''),
        summary = BackupSummary.fromJson(
            (manifest['summary'] as Map?)?.cast<String, dynamic>() ?? {});

  final DateTime? createdAt;
  final BackupSummary summary;
}

class RestoreResult {
  const RestoreResult({required this.values, required this.added});

  /// Every stored value the phone should hold now.
  final Map<String, Object> values;

  /// How many entries came back, by stored list.
  final Map<String, int> added;

  int addedTo(String key) => added[key] ?? 0;

  bool get addedAnything => added.values.any((n) => n > 0);
}

/// The app's end of it: its stored values and its documents directory, read
/// and written. Kept out of [LibraryBackup] so that is a function of files
/// and maps a test can hand it.
class LibraryBackups {
  /// The app's own stored values. Only ThrowLab's: a plugin's keys are its
  /// own business and would come back on a phone with another version of it.
  static Future<Map<String, Object>> storedValues() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in prefs.getKeys())
        if (key.startsWith('throwlab.') && prefs.get(key) != null)
          key: prefs.get(key)!,
    };
  }

  /// Writes a backup into the app's temporary directory and returns it.
  /// Only the newest is kept there: the share sheet hands the file to
  /// another app, which may still be reading it after the sheet has closed,
  /// so it is cleared out by the next backup rather than straight away.
  static Future<({File file, BackupSummary summary})> create({
    ValueChanged<double>? onProgress,
    bool Function()? canceled,
  }) async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    final temp = Directory('${(await getTemporaryDirectory()).path}/backup');
    if (await temp.exists()) await temp.delete(recursive: true);
    await temp.create(recursive: true);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'ThrowLab backup ${now.year}-${two(now.month)}-'
        '${two(now.day)}.zip';
    final out = File('${temp.path}/$name');
    final summary = await LibraryBackup.write(
      prefs: await storedValues(),
      docs: docs,
      outPath: out.path,
      onProgress: onProgress,
      canceled: canceled,
    );
    return (file: out, summary: summary);
  }

  /// Merges the backup at [zipPath] into what the phone holds and stores
  /// the result. The caller has every library read itself again.
  static Future<RestoreResult> restore(
    String zipPath, {
    ValueChanged<double>? onProgress,
  }) async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    final result = await LibraryBackup.restore(
      zipPath,
      current: await storedValues(),
      docs: docs,
      onProgress: onProgress,
    );
    final prefs = await SharedPreferences.getInstance();
    for (final entry in result.values.entries) {
      final value = entry.value;
      switch (value) {
        case String():
          await prefs.setString(entry.key, value);
        case bool():
          await prefs.setBool(entry.key, value);
        case int():
          await prefs.setInt(entry.key, value);
        case double():
          await prefs.setDouble(entry.key, value);
        case List<String>():
          await prefs.setStringList(entry.key, value);
      }
    }
    return result;
  }
}

void _deleteQuietly(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {
    // Already gone.
  }
}
