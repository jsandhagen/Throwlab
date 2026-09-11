/// Reading a heat sheet: which events are being contested, and who is in
/// them.
///
/// A heat sheet is the program a meet hands out — every event at it, in
/// order, with the field listed under each. Most of it is not throwing, and
/// most of the names are not the coach's athletes, so this reads the whole
/// page and hands back only the throws, leaving both of those judgments to
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

  /// How many flights the field is split into.
  ///
  /// One for a competition thrown in a single order, which is most of them.
  /// A big field is broken up on the sheet — 'Flight 1 of 3' over a dozen
  /// names, then the next dozen — and each flight throws its prelims right
  /// through before the next one starts, which is the whole reason this is
  /// read off the program rather than left to be worked out at the ring.
  int get flightCount =>
      athletes.map((athlete) => athlete.flight).toSet().length;

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
    this.flight = 1,
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

  /// Which flight of the event they are in, from 1 — read off the
  /// 'Flight 2 of 3' the sheet prints over their part of the field, and 1
  /// for a field it never split.
  final int flight;

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

  // Which flight the names being read are in. One until the sheet says
  // otherwise, and back to one under every new event heading — the
  // numbering starts again at each.
  var flight = 1;

  // Whether this field's rows carry a place or lane number in front of the
  // name. Once one has, a line without one is the page turning under the
  // field — the meet's name and the date printed again at the top of the
  // next one — and not a competitor.
  bool? numbered;

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
    numbered = null;
    flight = 1;
  }

  for (final line in lines) {
    if (_isRule(line)) continue;

    final heading = _heading(line);
    if (heading != null) {
      // A field too long for the page has its own heading printed again
      // over the rest of it — with '(continued)' after it, or the whole
      // line in brackets. That is the same event carrying on, not a second
      // one of the same name, and closing it here would cut the field in
      // two and start the flights over. Which is the field it happens to:
      // the long ones, and a long field is the flighted one.
      if (open != null && heading.continues(open!)) continue;
      // Any other event heading ends the last one — including the 4x100
      // between two throws, which is exactly what stops its field being
      // read as shot putters.
      close();
      open = heading.event == null ? null : heading;
      continue;
    }

    if (open == null) continue;

    // 'Flight 2 of 3' over the next dozen names. Read rather than skipped
    // over, because which flight an athlete is in decides when they throw
    // — and a coach whose thrower is in the last one has an hour to wait.
    final called = _flightNumber(line);
    if (called != null) {
      flight = called;
      continue;
    }

    if (_isFurniture(line)) continue;
    if (numbered == true && !_leadingPlace.hasMatch(line)) continue;
    final athlete = _athlete(line, flight);
    if (athlete != null && athletes.length < _maxField) {
      numbered ??= _leadingPlace.hasMatch(line);
      athletes.add(athlete);
    }
  }
  close();

  return found;
}

/// Bigger than any throws field, and small enough that a page of prose read
/// as one competitor a line can't run away with the import.
const _maxField = 200;

/// The heading over one flight's part of the field. A sheet calls it a
/// flight, a section or — borrowing the word the running gets — a heat, and
/// they all mean the same thing here: the group that walks in and throws
/// its prelims before the next one does.
///
/// The number has to follow the word for this to bite, so 'Flight Academy'
/// down a school column is a school and not a flight.
final _flightHeading = RegExp(
    r'^\s*(?:flight|section|heat|group|pool)\s*(?:no\.?|#)?\s*(\d{1,2})\b',
    caseSensitive: false);

/// Bigger than any meet splits a field into, and small enough that a stray
/// number read as a flight can't run the import up into the hundreds.
const _maxFlights = 30;

/// The flight [line] calls, or null for a line that calls none.
int? _flightNumber(String line) {
  final match = _flightHeading.firstMatch(line);
  if (match == null) return null;
  final number = int.parse(match.group(1)!);
  return number >= 1 && number <= _maxFlights ? number : null;
}

/// A heading, before it is known whether anybody is under it. A null
/// [event] is an event this app doesn't do — it still closes the last one.
class _Heading {
  const _Heading({
    this.event,
    this.implementKg = 0,
    this.title = '',
    this.key = '',
    this.continued = false,
    this.weightGuessed = false,
  });

  final ThrowEvent? event;
  final double implementKg;
  final String title;

  /// What two headings have to share to be the same event: [title] with the
  /// wrapping a continuation adds taken off. See the continuation above.
  final String key;

  /// Whether the line says in so many words that it is carrying an event
  /// on: '(continued)'.
  final bool continued;

  final bool weightGuessed;

  /// Whether this heading carries [open] on rather than starting something
  /// new.
  ///
  /// Two ways to tell, because a program reprints a heading two ways. The
  /// line may say so — and then it is allowed to be printed short, with the
  /// weight and the division left off, because the event it is continuing
  /// already said those. Or it is the same heading over again, brackets and
  /// all, which is the swimming side of Hy-Tek's house style and turns up
  /// on track programs too.
  bool continues(_Heading open) {
    if (event == null || open.event == null) return false;
    if (event != open.event) return false;
    return continued || key == open.key;
  }
}

/// The continuation words and the brackets a reprinted heading wears.
final _continued = RegExp(r'\(\s*cont(?:inued|\.)?\s*\)|\bcont(?:inued|\.)\b',
    caseSensitive: false);

/// A heading reduced to what identifies the event, so the same one printed
/// twice reads as one.
String _headingKey(String line) => line
    .toLowerCase()
    .replaceAll(_continued, ' ')
    // The brackets Hy-Tek wraps a whole reprinted heading in, and every
    // other bit of punctuation with them: two spellings of one heading are
    // the same event, and nothing here is what tells them apart.
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

final _rule = RegExp(r'^[\s=\-_*~.]*$');

bool _isRule(String line) => _rule.hasMatch(line);

/// The lines a meet manager prints between the heading and the field.
final _furniture = RegExp(
    r'^\s*(flight|heat|section|round|pool|group)\b.*\d|'
    r'^\s*(lane|pos|place|pl)\b|'
    r'^\s*name\b|'
    r'\bseed\s+mark\b|'
    r'^\s*\d+\s*$|'
    r'^\s*page\s+\d+|\bpage\s+\d+(\s+of\s+\d+)?\s*$',
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
  // a throw, not the 20 meters. Only a numbered heading is trusted past
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
    key: _headingKey(line),
    continued: _continued.hasMatch(line),
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

/// A high-school division, which throws a lighter implement than the senior
/// one a bare 'Men'/'Women' heading means. 'Boys' and 'Girls' are the words
/// a U.S. sheet uses for it; 'High School' and the U18-and-under age groups
/// land on the same weight. A bare 'HS' is deliberately not here — it turns
/// up in a host school's name often enough to mis-weight a senior heading.
final _highSchool = RegExp(
    r'\b(boys?|girls?|high\s*school|u1[0-8]|under[-\s]*1[0-8])\b',
    caseSensitive: false);

/// What a division throws, for a sheet that didn't say.
///
/// A heading names a division rather than a weight often enough that a
/// guess beats leaving it blank — but the guess is only as good as the two
/// axes a division word carries: senior or school, and men or women. The
/// screen still says the weight was guessed, because a division heading is
/// not a spec and a best is per weight.
///
/// The school implements are the U.S. high-school ones: the boys' 12 lb shot
/// and 1.6 kg discus, both their own weight rather than a rounded senior
/// shell (see [ImplementSpec]). Girls throw the 4 kg shot and 1 kg discus
/// that are also the senior women's, so only the boys' side needs the split.
/// Javelin is the 800 g for men and boys alike, which is why it doesn't.
double _defaultWeight(String line, ThrowEvent event) {
  final women = _womens.hasMatch(line);
  final school = _highSchool.hasMatch(line);
  switch (event) {
    case ThrowEvent.shotPut:
      if (women) return 4;
      return school ? 5.44 : 7.26;
    case ThrowEvent.discus:
      if (women) return 1;
      return school ? 1.6 : 2;
    case ThrowEvent.hammer:
      // Not a high-school event, so no school weight to guess: senior men's
      // or senior women's is the most a bare division heading can say.
      return women ? 4 : 7.26;
    case ThrowEvent.javelin:
      return women ? 0.6 : 0.8;
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
HeatSheetAthlete? _athlete(String line, int flight) {
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
          name: name,
          team: team,
          seed: seed,
          flight: flight,
          source: line.trim())
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

/// One of the coach's athletes, as much of them as helps place a name on a
/// sheet: the library spelling to file them under, and the full name and
/// school a coach may have filled in on their record.
class KnownAthlete {
  const KnownAthlete(
      {required this.name, this.fullName = '', this.school = ''});

  /// The library's own spelling — what a match is filed under, whichever
  /// field it was found on.
  final String name;

  /// The full name a program prints, when the library knows them by
  /// something shorter or by a nickname. Blank when the coach hasn't said.
  final String fullName;

  /// Their school or club, for the surname-and-school match below. Blank
  /// when unset.
  final String school;
}

/// The library name for a competitor written [sheet] from [team] on a
/// program, or null when none of the coach's athletes is this person.
///
/// Checked in order of how sure it is: the name or the full name by the same
/// exact-or-initial rule [sameAthlete] uses, then — only when the coach has
/// filled in a school — the same surname at the same school. The second
/// catches the athlete a sheet prints under a first name the library never
/// stored (a 'Robert' filed as 'Bud'), pinned down by where they throw so it
/// never links two strangers who happen to share a surname.
String? matchAthlete(String sheet, String team, List<KnownAthlete> known) {
  for (final athlete in known) {
    if (sameAthlete(sheet, athlete.name)) return athlete.name;
    if (athlete.fullName.isNotEmpty && sameAthlete(sheet, athlete.fullName)) {
      return athlete.name;
    }
  }
  if (team.trim().isEmpty) return null;
  for (final athlete in known) {
    if (athlete.school.isEmpty || !sameSchool(team, athlete.school)) continue;
    if (_sharesSurname(sheet, athlete.name) ||
        (athlete.fullName.isNotEmpty &&
            _sharesSurname(sheet, athlete.fullName))) {
      return athlete.name;
    }
  }
  return null;
}

/// Whether two names end on the same surname — the looser half of a
/// school-backed match, which the school is there to make safe.
bool _sharesSurname(String a, String b) {
  final x = _tokens(a);
  final y = _tokens(b);
  return x.isNotEmpty && y.isNotEmpty && x.last == y.last;
}

/// Whether two schools are the same one written two ways. 'Central', 'Central
/// HS' and 'Central High School' all read as one, because the words that say
/// *what kind* of school it is carry no identity — only 'Central' does.
bool sameSchool(String a, String b) {
  final x = _schoolTokens(a);
  final y = _schoolTokens(b);
  if (x.isEmpty || y.isEmpty) return false;
  // One a subset of the other covers an abbreviation against its spelled-out
  // form, and a bare 'Central' against 'Central Catholic'.
  return x.every(y.contains) || y.every(x.contains);
}

/// The words in a school name that actually name it — the kind-of-school
/// words ('HS', 'high school', 'academy'…) dropped, so they never stand in
/// for a match on their own.
final _schoolKind = RegExp(
    r'\b(hs|jhs|shs|high|junior|senior|middle|elementary|school|academy|'
    r'college|university|univ|institute|club|tc|track|field|athletics?|'
    r'the|of|at)\b',
    caseSensitive: false);

List<String> _schoolTokens(String school) => school
    .toLowerCase()
    .replaceAll(_schoolKind, ' ')
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toList();
