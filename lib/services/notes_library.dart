import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/training_note.dart';

/// Persists the training notes, and the pictures in them.
///
/// Kept apart from the throw library rather than bolted onto it: notes are
/// about an athlete over a season, throws are about one clip, and the two
/// have no reason to be written to storage together. Notes reference their
/// athlete by name, the same way a throw does, so re-tagging works the same
/// everywhere — there is still no athlete record to keep in step.
class NotesLibrary extends ChangeNotifier {
  static const _storageKey = 'throwlab.notes';

  final List<TrainingNote> _notes = [];
  bool _loaded = false;
  String? _storageError;

  bool get isLoaded => _loaded;

  /// Non-null when reading or writing failed; notes still work in memory.
  String? get storageError => _storageError;

  List<TrainingNote> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _notes.clear();
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          _notes.addAll(decoded
              .map((e) => TrainingNote.fromJson(e as Map<String, dynamic>)));
        } catch (_) {
          // Corrupt store: recover with no notes rather than no app.
          _notes.clear();
        }
      }
      _storageError = null;
    } catch (e) {
      _notes.clear();
      _storageError = '$e';
    } finally {
      _sort();
      _loaded = true;
      notifyListeners();
    }
  }

  /// One athlete's notes, most recently edited first — a note you are in
  /// the middle of is the one you want at the top tomorrow.
  List<TrainingNote> notesFor(String athlete) {
    final wanted = athlete.trim().toLowerCase();
    return [
      for (final note in _notes)
        if (note.athlete.trim().toLowerCase() == wanted) note,
    ];
  }

  TrainingNote? byId(String id) {
    for (final note in _notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  static String newNoteId() => 'n${DateTime.now().microsecondsSinceEpoch}';
  static String newBlockId() => 'b${DateTime.now().microsecondsSinceEpoch}';

  /// Writes [note] back, inserting it if it is new. The caller owns the
  /// object it is editing; this stores a copy, so a half-typed change can't
  /// reach storage until it is saved.
  Future<void> save(TrainingNote note) async {
    note.updatedAt = DateTime.now();
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) {
      _notes.add(note.copy());
    } else {
      _notes[index] = note.copy();
    }
    _sort();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index == -1) return;
    final removed = _notes.removeAt(index);
    await _persist();
    notifyListeners();
    await _deletePictures(removed);
  }

  /// Copies a picked picture into the app's own storage and hands back the
  /// path to store on the block.
  ///
  /// The gallery's copy can be moved or cleaned up at any time, and on
  /// Android the picker's own temporary file certainly will be — so a note
  /// that pointed at either would quietly lose its pictures.
  Future<String?> adoptPicture(String noteId, String blockId,
      String sourcePath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/notes/$noteId');
      await dir.create(recursive: true);
      final extension =
          sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final target = '${dir.path}/$blockId.$extension';
      await File(sourcePath).copy(target);
      return target;
    } catch (e) {
      _storageError = '$e';
      notifyListeners();
      return null;
    }
  }

  /// Reclaims one deleted block's picture. Best-effort, like the note-wide
  /// sweep below: a picture that will not delete costs space, never data.
  Future<void> deletePicture(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The block that pointed at it is already gone.
    }
  }

  /// Reclaims a deleted note's pictures. Best-effort: a failed delete costs
  /// space, never data.
  Future<void> _deletePictures(TrainingNote note) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/notes/${note.id}');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // The note itself is already gone.
    }
  }

  void _sort() =>
      _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(_notes.map((n) => n.toJson()).toList()));
      _storageError = null;
    } catch (e) {
      _storageError = '$e';
    }
  }
}
