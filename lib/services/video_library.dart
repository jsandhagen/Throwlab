import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/throw_video.dart';

/// Persists the list of imported throw videos.
///
/// v0.1 keeps metadata in SharedPreferences as JSON; the roadmap moves this
/// to SQLite once athlete profiles and per-throw metrics land.
class VideoLibrary extends ChangeNotifier {
  static const _storageKey = 'throwlab.videos';

  final List<ThrowVideo> _videos = [];
  bool _loaded = false;
  String? _storageError;

  List<ThrowVideo> get videos => List.unmodifiable(_videos);
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
      _storageError = null;
    } catch (e) {
      // getInstance() itself can throw (e.g. the storage plugin failed to
      // register); start empty and surface the error in the UI.
      _videos.clear();
      _storageError = '$e';
    } finally {
      // Always leave the loading state, even when storage is broken, so the
      // app never wedges on the startup spinner.
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> add(ThrowVideo video) async {
    _videos.insert(0, video);
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _videos.removeWhere((v) => v.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> update(ThrowVideo video) async {
    final index = _videos.indexWhere((v) => v.id == video.id);
    if (index == -1) return;
    _videos[index] = video;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, jsonEncode(_videos.map((v) => v.toJson()).toList()));
      _storageError = null;
    } catch (e) {
      // Keep the in-memory library usable even when persistence is broken.
      _storageError = '$e';
    }
  }
}
