import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meet.dart';

/// Persists the meets: who was entered, and what each attempt came to.
///
/// Kept apart from the throw library for the same reason the notes are: a
/// corrupt meet must cost the meets and never the clips. It stores no
/// distances of its own — every measured attempt points at a mark or a clip
/// in [VideoLibrary], which stays the one record of what an athlete has
/// thrown.
class MeetLibrary extends ChangeNotifier {
  static const _storageKey = 'throwlab.meets';

  final List<Meet> _meets = [];
  bool _loaded = false;
  String? _storageError;

  bool get isLoaded => _loaded;

  /// Non-null when reading or writing failed; the meet still works in
  /// memory, so a phone with broken storage doesn't lose the competition
  /// happening in front of it.
  String? get storageError => _storageError;

  /// Meets, most recent first — at a track, the one you are at.
  List<Meet> get meets => List.unmodifiable(_meets);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _meets.clear();
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          _meets.addAll(
              decoded.map((e) => Meet.fromJson(e as Map<String, dynamic>)));
        } catch (_) {
          // Corrupt store: recover with no meets rather than no app.
          _meets.clear();
        }
      }
      _storageError = null;
    } catch (e) {
      _meets.clear();
      _storageError = '$e';
    } finally {
      _sort();
      _loaded = true;
      notifyListeners();
    }
  }

  static String newMeetId() => 'k${DateTime.now().microsecondsSinceEpoch}';
  static String newEntryId() => 'e${DateTime.now().microsecondsSinceEpoch}';

  Meet? byId(String id) {
    for (final meet in _meets) {
      if (meet.id == id) return meet;
    }
    return null;
  }

  Future<void> save(Meet meet) async {
    final index = _meets.indexWhere((m) => m.id == meet.id);
    if (index == -1) {
      _meets.add(meet);
    } else {
      _meets[index] = meet;
    }
    _sort();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _meets.removeWhere((meet) => meet.id == id);
    await _persist();
    notifyListeners();
  }

  /// Enters an athlete, and hands back the entry so the caller can start
  /// recording against it straight away.
  Future<MeetEntry?> addEntry(
    String meetId, {
    required MeetEntry entry,
  }) async {
    final meet = byId(meetId);
    if (meet == null) return null;
    meet.entries.add(entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  /// Enters a whole field at once — a heat sheet's worth.
  ///
  /// One write rather than sixty: a meet's entries are stored as one blob,
  /// so adding them a name at a time rewrites the season on every one.
  Future<void> addEntries(String meetId, List<MeetEntry> entries) async {
    final meet = byId(meetId);
    if (meet == null || entries.isEmpty) return;
    meet.entries.addAll(entries);
    await _persist();
    notifyListeners();
  }

  Future<void> removeEntry(String meetId, String entryId) async {
    final meet = byId(meetId);
    if (meet == null) return;
    meet.entries.removeWhere((entry) => entry.id == entryId);
    await _persist();
    notifyListeners();
  }

  /// Records one round of one athlete's series — or clears it, with a null
  /// [attempt]. The mark or clip behind a measured attempt is the caller's
  /// to write to the library first: this stores only the pointer to it.
  Future<void> setAttempt(
    String meetId,
    String entryId,
    int round,
    MeetAttempt? attempt,
  ) async {
    final entry = byId(meetId)?.entryById(entryId);
    if (entry == null) return;
    entry.setAttempt(round, attempt);
    await _persist();
    notifyListeners();
  }

  /// The meet in progress: today's, if there is one. A coach opening the
  /// app between attempts wants the competition they are standing at, not
  /// a list of the ones they have been to.
  Meet? get live {
    final today = DateTime.now();
    for (final meet in _meets) {
      final date = meet.date.toLocal();
      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        return meet;
      }
    }
    return null;
  }

  void _sort() => _meets.sort((a, b) => b.date.compareTo(a.date));

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(_meets.map((m) => m.toJson()).toList()));
      _storageError = null;
    } catch (e) {
      // Keep the meet usable in memory even when persistence is broken.
      _storageError = '$e';
    }
  }
}

/// The meets in scope, or null when there are none.
///
/// A meet is context a screen shows on top of the library rather than
/// something it can't run without: an athlete's profile is their throws
/// first, and it still paints in a test — or on a phone whose meet store
/// failed to read — with nothing but the clips. So this is looked up
/// softly, the way the athlete records are.
MeetLibrary? meetsOf(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<MeetLibrary>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}
