/// Reading a heat sheet: which events are being contested, and who is in
/// them.
///
/// A heat sheet is the programme a meet hands out — every event at it, in
/// order, with the field listed under each. Most of it is not throwing, and
/// most of the names are not the coach's athletes, so this reads the whole
/// page and hands back only the throws, leaving both of those judgements to
/// the screen that shows the result.
///
/// It is written against what a meet manager actually prints: a heading
/// naming the event, then a competitor a line, in columns. Where the
/// columns are spaces rather than tabs it still works, because that is what
/// `pdf_text` gives back for a page laid out in columns.
library;

import '../models/throw_event.dart';

/// One event off a heat sheet, with its field.
class HeatSheetEvent {
  const HeatSheetEvent({
    required this.event,
    required this.implementKg,
    required this.title,
    required this.athletes,
    this.weightGuessed = false,
  });

  final ThrowEvent event;

  /// What is being thrown. Taken off the heading where it says — '12lb',
  /// '(7.26kg)', '6K' — and guessed from who is throwing where it doesn't.
  final double implementKg;

  /// The heading as the sheet wrote it: 'Event 15 Boys Shot Put 12lb'.
  final String title;

  /// True when the sheet never said what weight, so the division decided
  /// it. A guess worth showing, because a best is per weight and putting
  /// one under the wrong implement is not a thing the athlete can undo.
  final bool weightGuessed;

  /// In the order the sheet listed them, which is the order they throw in
  /// unless the meet redraws it.
  final List<HeatSheetAthlete> athletes;

  HeatSheetEvent withWeight(double kg) => HeatSheetEvent(
        event: event,
        implementKg: kg,
        title: title,
        athletes: athletes,
        // Once a person has chosen it, it is not a guess any more.
        weightGuessed: false,
      );
}

/// One competitor on a heat sheet.
class HeatSheetAthlete {
  const HeatSheetAthlete({
    required this.name,
    this.team = '',
    this.seed = '',
    required this.source,
  });

  /// First name first, however the sheet wrote it round.
  final String name;

  /// Their school or club, where the sheet had a column for it.
  final String team;

  /// The mark they were entered on, as written — '44-06.00', '13.55m'.
  /// Kept to tell two people of the same name apart, never stored: a seed
  /// is a claim about last season, not something thrown here.
  final String seed;

  /// The line they were read off.
  final String source;
}

/// The throwing events on [text], with their fields.
///
/// Events with nobody under them are dropped: a heading with no field is a
/// line that looked like one and wasn't.
List<HeatSheetEvent> parseHeatSheet(String text) {
  final found = <HeatSheetEvent>[];
  final lines = text
      .replaceAll(' ', ' ')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');

  _Heading? open;
  var athletes = <HeatSheetAthlete>[];

  void close() {
    final heading = open;
    if (heading?.event != null && athletes.isNotEmpty) {
      found.add(HeatSheetEvent(
        event: heading!.event!,
        implementKg: heading.implementKg,
        title: heading.title,
        weightGuessed: heading.weightGuessed,
        athletes: athletes,
      ));
    }
    open = null;
    athletes = <HeatSheetAthlete>[];
  }

  for (final line in lines) {
    if (_isRule(line)) continue;

    final heading = _heading(line);
    if (heading != null) {
      // Any event heading ends the last one — including the 4x100 between
      // two throws, which is exactly what stops its field being read as
      // shot putters.
      close();
      open = heading.event == null ? null : heading;
      continue;
    }

    if (open == null || _isFurniture(line)) continue;
    final athlete = _athlete(line);
    if (athlete != null && athletes.length < _maxField) {
      athletes.add(athlete);
    }
  }
  close();

  return found;
}

/// Bigger than any throws field, and small enough that a page of prose read
/// as one competitor a line can't run away with the import.
const _maxField = 200;

/// A heading, before it is known whether anybody is under it. A null
/// [event] is an event this app doesn't do — it still closes the last one.
class _Heading {
  const _Heading({
    this.event,
    this.implementKg = 0,
    this.title = '',
    this.weightGuessed = false,
  });

  final ThrowEvent? event;
  final double implementKg;
  final String title;
  final bool weightGuessed;
}

final _rule = RegExp(r'^[\s=\-_*~.]*$');

bool _isRule(String line) => _rule.hasMatch(line);

/// The lines a meet manager prints between the heading and the field.
final _furniture = RegExp(
    r'^\s*(flight|heat|section|round|pool|group)\b.*\d|'
    r'^\s*(lane|pos|place|pl)\b|'
    r'^\s*name\b|'
    r'\bseed\s+mark\b|'
    r'^\s*\d+\s*$|'
    r'^\s*page\s+\d+',
    caseSensitive: false);

bool _isFurniture(String line) =>
    _furniture.hasMatch(line) || !line.contains(RegExp('[A-Za-z]'));

const _throwWords = {
  'shot put': ThrowEvent.shotPut,
  'shotput': ThrowEvent.shotPut,
  'shot': ThrowEvent.shotPut,
  'discus': ThrowEvent.discus,
  'disc': ThrowEvent.discus,
  'hammer': ThrowEvent.hammer,
  'javelin': ThrowEvent.javelin,
  'jav': ThrowEvent.javelin,
};

/// The events this app has no place for. Named so their fields are not read
/// as the last throws event's, and so a weight throw — which is a throw,
/// but not one of the four — doesn't turn into a hammer.
final _otherEvent = RegExp(
    r'\b(weight throw|super ?weight|dash|run|relay|hurdle|steeple|'
    r'meter|metre|mile|walk|jump|vault|pentathlon|heptathlon|decathlon|'
    r'\d{2,5}\s?m\b|\d+\s?x\s?\d+)',
    caseSensitive: false);

final _eventNumber = RegExp(r'^\s*event\b', caseSensitive: false);

/// The event words, longest first — see [_heading].
final _throwWordsByLength = _throwWords.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));

/// Whether [line] starts an event, and which one.
_Heading? _heading(String line) {
  final lower = line.toLowerCase();
  final numbered = _eventNumber.hasMatch(line);

  // A competitor is never a heading, whatever their school is called and
  // whatever their seed mark reads like — '41.20m' on the end of a row is
  // a throw, not the 20 metres. Only a numbered heading is trusted past
  // this, because that is the one shape nothing else has.
  if (!numbered && (_leadingPlace.hasMatch(line) || _seed(line) != null)) {
    return null;
  }

  // Longest name first, so 'shot put' is a shot put rather than whichever
  // of 'shot' and 'shot put' happens to be looked for first.
  ThrowEvent? event;
  for (final word in _throwWordsByLength) {
    if (lower.contains(word)) {
      event = _throwWords[word];
      break;
    }
  }

  final other = _otherEvent.hasMatch(line);
  if (event == null || other) {
    // Another event's heading, which still closes the throws one before it.
    // A line naming neither is just a line.
    return numbered || other ? const _Heading() : null;
  }

  final weight = _weight(line, event);
  return _Heading(
    event: event,
    implementKg: weight ?? _defaultWeight(line, event),
    title: line.trim().replaceAll(RegExp(r'\s{2,}'), ' '),
    weightGuessed: weight == null,
  );
}

/// The weight off a heading, in whatever unit it was printed in.
double? _weight(String line, ThrowEvent event) {
  final kg = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kg|k\b)', caseSensitive: false)
      .firstMatch(line);
  if (kg != null) return _snap(double.parse(kg.group(1)!), event);

  final pounds = RegExp(r'(\d+(?:\.\d+)?)\s*(?:lbs?|#)', caseSensitive: false)
      .firstMatch(line);
  if (pounds != null) {
    return _snap(double.parse(pounds.group(1)!) * 0.45359237, event);
  }

  final grams =
      RegExp(r'(\d{3,4})\s*g\b', caseSensitive: false).firstMatch(line);
  if (grams != null) return _snap(double.parse(grams.group(1)!) / 1000, event);

  return null;
}

/// The nearest weight the event is actually thrown at. A 12 lb shot is
/// 5.44 kg, which is nobody's implement — it is the 5 kg shell.
double _snap(double kg, ThrowEvent event) => event.specFor(kg).weightKg;

final _womens = RegExp(r"\b(women|woman|girls?|female|ladies|w)\b'?s?",
    caseSensitive: false);

/// What a division throws, for a sheet that didn't say.
///
/// Only two guesses are worth making — the senior men's implement and the
/// senior women's — because those are the two a heading names by division
/// rather than by weight. Anything else is a number the coach has to set,
/// and the screen says the weight was guessed so they know to look.
double _defaultWeight(String line, ThrowEvent event) {
  if (!_womens.hasMatch(line)) return event.defaultImplement.weightKg;
  switch (event) {
    case ThrowEvent.shotPut:
      return 4;
    case ThrowEvent.discus:
      return 1;
    case ThrowEvent.hammer:
      return 4;
    case ThrowEvent.javelin:
      return 0.6;
  }
}

final _columns = RegExp(r'\t+| {2,}');
final _leadingPlace = RegExp(r'^\s*\d{1,3}[.)]?\s+');
final _year =
    RegExp(r'^(?:\d{1,2}|fr|so|jr|sr|u\d{2})\b\.?\s*', caseSensitive: false);

/// A distance as a sheet writes a seed: '44-06.00', '13.55m', "141' 6".
final _seedMark =
    RegExp(r'''^\d+(?:-\d+(?:\.\d+)?|\.\d+\s*m?|'\s*\d+)\s*"?$''');

String? _seed(String line) {
  final parts = line.trim().split(_columns);
  final last = parts.last.trim();
  return _seedMark.hasMatch(last) ? last : null;
}

/// One competitor, or null for a line that isn't one.
HeatSheetAthlete? _athlete(String line) {
  final stripped = line.replaceFirst(_leadingPlace, '').trim();
  if (stripped.isEmpty) return null;

  final parts = stripped
      .split(_columns)
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  var name = parts.first;
  var team = '';
  var seed = '';
  if (parts.length > 1) {
    final last = parts.last;
    if (_seedMark.hasMatch(last)) {
      seed = last;
      parts.removeLast();
    }
    // Whatever is left between the name and the seed is the school, with
    // the year that is often glued to the front of it taken off.
    if (parts.length > 1) {
      team = parts.skip(1).join(' ').replaceFirst(_year, '').trim();
    }
  } else {
    // One column: a sheet that single-spaced everything. Take a seed off
    // the end if there is one and treat the rest as the name.
    final tail = RegExp(r'\s(\S+)$').firstMatch(name);
    if (tail != null && _seedMark.hasMatch(tail.group(1)!)) {
      seed = tail.group(1)!;
      name = name.substring(0, tail.start).trim();
    }
  }

  name = _naturalOrder(name);
  return _isName(name)
      ? HeatSheetAthlete(
          name: name, team: team, seed: seed, source: line.trim())
      : null;
}

final _nameish = RegExp(r"^[A-Za-z][A-Za-z'’.\- ]*[A-Za-z.]$");

/// Whether this is a person's name rather than a stray column of a table.
bool _isName(String name) =>
    name.length > 2 && name.length < 60 && _nameish.hasMatch(name);

/// 'Smith, John' is how a results system sorts a name and not how anybody
/// says one. The library holds people the way they are spoken about.
String _naturalOrder(String name) {
  var tidy = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  final comma = tidy.indexOf(',');
  if (comma > 0) {
    tidy = '${tidy.substring(comma + 1).trim()} ${tidy.substring(0, comma)}'
        .trim();
  }
  // A sheet printed in capitals is shouting, not spelling.
  if (tidy == tidy.toUpperCase() && tidy != tidy.toLowerCase()) {
    tidy = tidy
        .split(' ')
        .map((word) =>
            word.isEmpty ? word : word[0] + word.substring(1).toLowerCase())
        .join(' ');
  }
  return tidy;
}

/// Whether [sheet] names the same person as [known].
///
/// Exactly, or by surname and first initial: a heat sheet that prints
/// 'J Sandhagen' is naming the Jakob Sandhagen in the library, and a record
/// book that missed that would start a second athlete for the same person.
bool sameAthlete(String sheet, String known) {
  final a = _tokens(sheet);
  final b = _tokens(known);
  if (a.isEmpty || b.isEmpty) return false;
  if (a.join(' ') == b.join(' ')) return true;
  if (a.last != b.last) return false;
  final first = a.first;
  final other = b.first;
  return first.isNotEmpty &&
      other.isNotEmpty &&
      first[0] == other[0] &&
      (first.length == 1 || other.length == 1);
}

List<String> _tokens(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9'\s-]"), '')
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toList();

/// The name to file a competitor under: the library's spelling when it
/// already knows them, so a season doesn't end up split between 'J
/// Sandhagen' and 'Jakob Sandhagen'.
String? matchKnown(String sheet, List<String> known) {
  for (final name in known) {
    if (sameAthlete(sheet, name)) return name;
  }
  return null;
}
