import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/athlete_record.dart';

/// Persists the editable athlete records — the nickname, full name and
/// school a coach fills in about the people they coach.
///
/// Kept off its own storage key, like the notes and the marks, so a corrupt
/// record list costs the labels and never the clips. A record is filed under
/// the athlete's library spelling, matched case-insensitively so 'Sam' and
/// 'sam' resolve to one person the same way they do everywhere else.
class AthleteLibrary extends ChangeNotifier {
  static const _storageKey = 'throwlab.athletes';

  /// Keyed by the normalized name, so a lookup is a spelling away from any
  /// throw's athlete tag.
  final Map<String, AthleteRecord> _records = {};
  bool _loaded = false;
  String? _storageError;

  bool get isLoaded => _loaded;

  /// Non-null when reading or writing failed; the records still work in
  /// memory, they just won't survive a restart.
  String? get storageError => _storageError;

  List<AthleteRecord> get records => List.unmodifiable(_records.values);

  static String _key(String name) => name.trim().toLowerCase();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _records.clear();
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          for (final entry in decoded) {
            final record =
                AthleteRecord.fromJson(entry as Map<String, dynamic>);
            if (record.name.isEmpty || record.isEmpty) continue;
            _records[_key(record.name)] = record;
          }
        } catch (_) {
          // Corrupt store: recover with no records rather than no app.
          _records.clear();
        }
      }
      _storageError = null;
    } catch (e) {
      _records.clear();
      _storageError = '$e';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// The record for [name], or null when the coach has filled in nothing.
  AthleteRecord? recordFor(String name) => _records[_key(name)];

  /// What to show for [name]: their nickname when they have one, else the
  /// name as filed. The one call every screen makes, so a nickname set once
  /// reads through the whole app.
  String displayName(String name) => _records[_key(name)]?.displayName ?? name;

  /// Files [record] under its name, or drops it when the coach has cleared
  /// every field — an empty record is nothing worth keeping.
  Future<void> save(AthleteRecord record) async {
    final key = _key(record.name);
    if (record.name.trim().isEmpty) return;
    if (record.isEmpty) {
      _records.remove(key);
    } else {
      _records[key] = record.copyWith(name: record.name.trim());
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String name) async {
    _records.remove(_key(name));
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey,
          jsonEncode(_records.values.map((r) => r.toJson()).toList()));
      _storageError = null;
    } catch (e) {
      _storageError = '$e';
    }
  }
}

/// The records service in scope, or null when there is none.
///
/// The nickname is decoration a screen shows on top of the library, not a
/// thing it can't run without: a widget mounted in a test with only the
/// clips still paints, under the plain library spelling. So this is looked
/// up softly rather than demanded, and the caller falls back to the name.
AthleteLibrary? athleteRecordsOf(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<AthleteLibrary>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// [AthleteLibrary.displayName] against whatever records are in scope, or the
/// name unchanged when none are.
String displayNameOf(BuildContext context, String name, {bool listen = true}) =>
    athleteRecordsOf(context, listen: listen)?.displayName(name) ?? name;
