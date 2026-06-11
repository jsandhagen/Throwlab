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

  List<ThrowVideo> get videos => List.unmodifiable(_videos);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _videos.clear();
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _videos.addAll(decoded
            .map((e) => ThrowVideo.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // Corrupt store: recover with an empty library instead of leaving
        // the app stuck on the loading spinner.
        _videos.clear();
      }
    }
    _loaded = true;
    notifyListeners();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(_videos.map((v) => v.toJson()).toList()));
  }
}
