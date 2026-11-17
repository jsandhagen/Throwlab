import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notebook.dart';
import '../models/training_note.dart';
import 'note_store.dart';

/// Persists the coach's notebook: its pages, the sections they are filed
/// in, and the pictures on them.
///
/// Its own store, beside the training notes rather than in them: a page is
/// the coach's, not an athlete's, and a list of notes per athlete has no
/// business turning up pages that belong to nobody. Both lists are lists of
/// objects with an `id`, which is what lets a backup merge them.
class NotebookLibrary extends ChangeNotifier implements NoteStore {
  static const pagesKey = 'throwlab.notebook';
  static const sectionsKey = 'throwlab.notebookSections';

  final List<NotebookPage> _pages = [];
  final List<NotebookSection> _sections = [];
  bool _loaded = false;
  String? _storageError;

  bool get isLoaded => _loaded;

  /// Non-null when reading or writing failed; the notebook still works in
  /// memory.
  String? get storageError => _storageError;

  /// Pinned first, then the most recently edited.
  List<NotebookPage> get pages => List.unmodifiable(_pages);

  /// In the order the coach put them.
  List<NotebookSection> get sections => List.unmodifiable(_sections);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pages
        ..clear()
        ..addAll(_read(prefs.getString(pagesKey), NotebookPage.fromJson));
      _sections
        ..clear()
        ..addAll(
            _read(prefs.getString(sectionsKey), NotebookSection.fromJson));
      _storageError = null;
    } catch (e) {
      _pages.clear();
      _sections.clear();
      _storageError = '$e';
    } finally {
      _sort();
      _loaded = true;
      notifyListeners();
    }
  }

  /// A stored list, or nothing at all if it will not read: a corrupt store
  /// recovers with an empty notebook rather than no app.
  static List<T> _read<T>(
      String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null) return const [];
    try {
      return [
        for (final entry in jsonDecode(raw) as List<dynamic>)
          fromJson(entry as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  NotebookPage? byId(String id) {
    for (final page in _pages) {
      if (page.id == id) return page;
    }
    return null;
  }

  NotebookSection? sectionById(String? id) {
    if (id == null) return null;
    for (final section in _sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  /// The pages in one section. A page whose section has gone — deleted, or
  /// never restored — counts as in none, rather than in nowhere.
  List<NotebookPage> pagesIn(String? sectionId) => [
        for (final page in _pages)
          if (sectionById(page.sectionId)?.id == sectionId) page,
      ];

  static String newPageId() => 'p${DateTime.now().microsecondsSinceEpoch}';
  static String newSectionId() => 's${DateTime.now().microsecondsSinceEpoch}';

  /// A fresh page, not yet stored — the editor stores it the first time
  /// it saves, so backing out of an empty one leaves an empty page, which
  /// the screen that opened it tidies away.
  NotebookPage draft({String? sectionId}) {
    final now = DateTime.now();
    return NotebookPage(
      id: newPageId(),
      createdAt: now,
      updatedAt: now,
      sectionId: sectionId,
    );
  }

  /// Writes [page] back, inserting it if it is new. Stores a copy, so a
  /// half-typed change cannot reach storage until it is saved.
  Future<void> save(NotebookPage page) async {
    page.updatedAt = DateTime.now();
    _put(page);
    await _persist();
    notifyListeners();
  }

  @override
  Future<void> saveDocument(NoteDocument document) =>
      save(document as NotebookPage);

  /// Pins or unpins a page without counting as an edit of it: where it
  /// sits among the unpinned pages is still when its words last changed.
  Future<void> setPinned(String id, bool pinned) async {
    final page = byId(id);
    if (page == null) return;
    page.pinned = pinned;
    _sort();
    await _persist();
    notifyListeners();
  }

  /// Refiles a page, again without counting as an edit.
  Future<void> moveTo(String id, String? sectionId) async {
    final page = byId(id);
    if (page == null) return;
    page.sectionId = sectionId;
    await _persist();
    notifyListeners();
  }

  void _put(NotebookPage page) {
    final index = _pages.indexWhere((p) => p.id == page.id);
    if (index == -1) {
      _pages.add(page.copy());
    } else {
      _pages[index] = page.copy();
    }
    _sort();
  }

  @override
  Future<void> remove(String id) async {
    final index = _pages.indexWhere((p) => p.id == id);
    if (index == -1) return;
    final removed = _pages.removeAt(index);
    await _persist();
    notifyListeners();
    await _deletePictures(removed);
  }

  Future<NotebookSection> addSection(String name) async {
    final section = NotebookSection(id: newSectionId(), name: name.trim());
    _sections.add(section);
    await _persist();
    notifyListeners();
    return section;
  }

  Future<void> renameSection(String id, String name) async {
    final section = sectionById(id);
    if (section == null) return;
    section.name = name.trim();
    await _persist();
    notifyListeners();
  }

  /// Moves a section along the row by [by] places.
  Future<void> moveSection(String id, int by) async {
    final from = _sections.indexWhere((s) => s.id == id);
    final to = from + by;
    if (from == -1 || to < 0 || to >= _sections.length) return;
    _sections.insert(to, _sections.removeAt(from));
    await _persist();
    notifyListeners();
  }

  /// Deletes a section. Its pages are kept, in no section — a coach tidying
  /// the shelves has not asked to throw the pages away.
  Future<void> removeSection(String id) async {
    _sections.removeWhere((s) => s.id == id);
    for (final page in _pages) {
      if (page.sectionId == id) page.sectionId = null;
    }
    await _persist();
    notifyListeners();
  }

  @override
  Future<String?> adoptPicture(
      String pageId, String blockId, String sourcePath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/notebook/$pageId');
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

  @override
  Future<void> deletePicture(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The block that pointed at it is already gone.
    }
  }

  Future<void> _deletePictures(NotebookPage page) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/notebook/${page.id}');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // The page itself is already gone.
    }
  }

  void _sort() => _pages.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          pagesKey, jsonEncode([for (final page in _pages) page.toJson()]));
      await prefs.setString(sectionsKey,
          jsonEncode([for (final section in _sections) section.toJson()]));
      _storageError = null;
    } catch (e) {
      _storageError = '$e';
    }
  }
}
