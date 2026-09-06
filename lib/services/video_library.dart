import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/athlete_profile.dart';
import '../models/throw_mark.dart';
import '../models/throw_video.dart';

/// Persists the throws: the imported clips, and the marks that were only
/// ever written down.
///
/// v0.1 keeps metadata in SharedPreferences as JSON; the roadmap moves this
/// to SQLite once athlete profiles and per-throw metrics land. The two are
/// stored under separate keys so an app that only ever knew about clips
/// reads its own list back unchanged.
class VideoLibrary extends ChangeNotifier {
  static const _storageKey = 'throwlab.videos';
  static const _marksKey = 'throwlab.marks';

  final List<ThrowVideo> _videos = [];
  final List<ThrowMark> _marks = [];
  bool _loaded = false;
  String? _storageError;

  /// The throws standing as a personal best. Recomputed on every change
  /// rather than asked for per card: the library paints a shelf of cards at
  /// a time, and each one would otherwise re-scan the whole library to find
  /// out whether it is wearing a medal.
  Set<String> _bests = const {};

  List<ThrowVideo> get videos => List.unmodifiable(_videos);

  /// Marks with no clip behind them, newest first.
  List<ThrowMark> get marks => List.unmodifiable(_marks);

  /// Everything a personal best could come out of.
  List<ThrowResult> get results => [..._videos, ..._marks];

  bool get isLoaded => _loaded;

  /// Non-null when reading or writing SharedPreferences failed; the library
  /// still works in memory, but imports won't survive a restart.
  String? get storageError => _storageError;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _videos.clear();
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          _videos.addAll(decoded
              .map((e) => ThrowVideo.fromJson(e as Map<String, dynamic>)));
        } catch (_) {
          // Corrupt store: recover with an empty library.
          _videos.clear();
        }
      }
      final rawMarks = prefs.getString(_marksKey);
      _marks.clear();
      if (rawMarks != null) {
        try {
          final decoded = jsonDecode(rawMarks) as List<dynamic>;
          _marks.addAll(decoded
              .map((e) => ThrowMark.fromJson(e as Map<String, dynamic>)));
        } catch (_) {
          // A corrupt mark list costs the marks, never the clips.
          _marks.clear();
        }
      }
      _sortMarks();
      _storageError = null;
    } catch (e) {
      // getInstance() itself can throw (e.g. the storage plugin failed to
      // register); start empty and surface the error in the UI.
      _videos.clear();
      _marks.clear();
      _storageError = '$e';
    } finally {
      _bests = personalBestIds(results);
      // Always leave the loading state, even when storage is broken, so the
      // app never wedges on the startup spinner.
      _loaded = true;
      notifyListeners();
    }
  }

  /// Every athlete already in the library, most recently thrown first, so
  /// tagging a new clip is picking a name rather than typing it. Matching
  /// is case-insensitive — "Sam" and "sam" are one athlete — and the
  /// spelling from the most recent throw wins.
  ///
  /// Marks count as throws here: an athlete first entered from a results
  /// sheet is offered by name on the next import, like anyone else.
  List<String> get knownAthletes {
    final seen = <String>{};
    final names = <String>[];
    final all = results;
    // Ties keep the order the library is already in, so clips sharing a
    // date don't reshuffle the list from one call to the next.
    final order = {for (var i = 0; i < all.length; i++) all[i].id: i};
    all.sort((a, b) {
      final byDate = b.displayDate.compareTo(a.displayDate);
      return byDate != 0 ? byDate : order[a.id]!.compareTo(order[b.id]!);
    });
    for (final result in all) {
      final name = result.athlete.trim();
      if (name.isEmpty) continue;
      if (seen.add(name.toLowerCase())) names.add(name);
    }
    return names;
  }

  /// Athletes who have marks but not one clip. They would otherwise be
  /// invisible in a library built out of stills — which is exactly the
  /// athlete whose season is in a results sheet rather than on a phone.
  List<String> get athletesWithoutClips {
    final filmed = {
      for (final video in _videos) video.athlete.trim().toLowerCase(),
    };
    final seen = <String>{};
    final names = <String>[];
    for (final mark in _marks) {
      final name = mark.athlete.trim();
      if (name.isEmpty || filmed.contains(name.toLowerCase())) continue;
      if (seen.add(name.toLowerCase())) names.add(name);
    }
    return names;
  }

  /// When [name] last threw anything at all, clip or mark.
  DateTime? lastThrewOn(String name) {
    final wanted = name.trim().toLowerCase();
    DateTime? latest;
    for (final result in results) {
      if (result.athlete.trim().toLowerCase() != wanted) continue;
      if (latest == null || result.displayDate.isAfter(latest)) {
        latest = result.displayDate;
      }
    }
    return latest;
  }

  /// Whether this throw is the furthest its athlete has thrown that event
  /// and weight — what puts the gold frame and the medal on its card. A
  /// clip loses the medal to a further mark that was never filmed, because
  /// the athlete did in fact throw further.
  bool isPersonalBest(ThrowResult result) => _bests.contains(result.id);

  /// What the library knows about one athlete: their throws, newest first,
  /// their marks, and their best at each thing they throw.
  AthleteProfile profileFor(String name) =>
      AthleteProfile.of(name, _videos, _marks);

  Future<void> add(ThrowVideo video) async {
    _videos.insert(0, video);
    _bests = personalBestIds(results);
    await _save();
    notifyListeners();
  }

  /// Records a throw nobody filmed. Ids carry an 'm' so a mark and a clip
  /// can never collide in the set of record holders.
  static String newMarkId() =>
      'm${DateTime.now().microsecondsSinceEpoch}';

  Future<void> addMark(ThrowMark mark) async {
    _marks.add(mark);
    _sortMarks();
    _bests = personalBestIds(results);
    await _save();
    notifyListeners();
  }

  Future<void> updateMark(ThrowMark mark) async {
    final index = _marks.indexWhere((m) => m.id == mark.id);
    if (index == -1) return;
    _marks[index] = mark;
    _sortMarks();
    _bests = personalBestIds(results);
    await _save();
    notifyListeners();
  }

  Future<void> removeMark(String id) async {
    _marks.removeWhere((mark) => mark.id == id);
    _bests = personalBestIds(results);
    await _save();
    notifyListeners();
  }

  void _sortMarks() =>
      _marks.sort((a, b) => b.achievedOn.compareTo(a.achievedOn));

  Future<void> remove(String id) async {
    final index = _videos.indexWhere((v) => v.id == id);
    final removed = index == -1 ? null : _videos[index];
    _videos.removeWhere((v) => v.id == id);
    _bests = personalBestIds(results);
    await _save();
    notifyListeners();
    if (removed != null) await _deleteFiles(removed);
  }

  /// Reclaims a deleted clip's disk: the re-encoded video, its thumbnail,
  /// and the pre-extracted scrub frames — which run to hundreds of MB per
  /// clip, so leaving them behind fills the phone. Only paths inside the
  /// app's own documents directory are touched, so a clip still pointing at
  /// the user's gallery file (re-encoding failed at import) is left alone.
  /// Best-effort: a failed delete costs space, never data.
  Future<void> _deleteFiles(ThrowVideo video) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final owned = '${docs.path}/';
      for (final path in [video.path, video.thumbnailPath]) {
        if (path == null || !path.startsWith(owned)) continue;
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      final frames = video.scrubFramesDir;
      if (frames != null && frames.startsWith(owned)) {
        final dir = Directory(frames);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (_) {
      // Leaves the files behind; the library entry is already gone.
    }
  }

  Future<void> update(ThrowVideo video) async {
    final index = _videos.indexWhere((v) => v.id == video.id);
    if (index == -1) return;
    _videos[index] = video;
    _bests = personalBestIds(results);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(_videos.map((v) => v.toJson()).toList()));
      await prefs.setString(
          _marksKey, jsonEncode(_marks.map((m) => m.toJson()).toList()));
      _storageError = null;
    } catch (e) {
      // Keep the in-memory library usable even when persistence is broken.
      _storageError = '$e';
    }
  }
}
