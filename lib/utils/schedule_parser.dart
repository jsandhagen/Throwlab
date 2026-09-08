/// Reading a season off a schedule.
///
/// A fixture list arrives as a page, not as data: an email, a screenshot of
/// a league's website, a PDF the association put out in September. This
/// turns the text of one into meets a coach can look over and accept — it
/// never writes anything itself, because a schedule is written by people
/// and read by a regex, and the two disagree often enough that a calendar
/// filled in silently would be worse than one filled in by hand.
library;

/// One meet read off a schedule, before anybody has agreed it is right.
class ScheduleCandidate {
  const ScheduleCandidate({
    required this.name,
    required this.date,
    required this.source,
    this.venue = '',
    this.notes = const [],
  });

  /// What the schedule called it: 'County Champs', 'Tiger Relays'.
  final String name;

  /// The day, at midnight local. A schedule that gives a start time has it
  /// dropped — a meet here is a day, and the throwing has its own order of
  /// events a timetable can't know.
  final DateTime date;

  /// Where, when the row said. Often the second column of one.
  final String venue;

  /// The line it was read off, so a coach reviewing the import can see what
  /// the parser made of what.
  final String source;

  /// What had to be guessed. Shown against the row: every one of these is a
  /// place the parser could be wrong in a way that looks right.
  final List<String> notes;

  ScheduleCandidate copyWith({String? name, DateTime? date, String? venue}) =>
      ScheduleCandidate(
        name: name ?? this.name,
        date: date ?? this.date,
        venue: venue ?? this.venue,
        source: source,
        notes: notes,
      );
}

/// Meets found in [text], in the order they appear on the page.
///
/// [today] is what an omitted year is judged against, and is passed in so a
/// test doesn't change answer in January.
List<ScheduleCandidate> parseSchedule(String text, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final lines = _lines(text);
  final documentYear = _documentYear(text, now);
  final found = <ScheduleCandidate>[];
  final seen = <String>{};

  for (var i = 0; i < lines.length && found.length < _maxCandidates; i++) {
    final hit = _findDate(lines[i], now: now, documentYear: documentYear);
    if (hit == null) continue;

    // The weekday is dropped from what sat in front of the date and nowhere
    // else: 'Sat, 12 April' has one, and so does the Sun Devil Classic.
    final line = lines[i];
    var rest = _stripTimes('${_stripWeekday(line.substring(0, hit.start))}  '
        '${line.substring(hit.end)}');
    var source = line;
    // A schedule laid out down the page rather than across it puts the date
    // on its own line and the meet under it. Only borrow the next line when
    // it isn't a date itself, or a run of dates would swallow each other.
    if (_strip(rest).isEmpty &&
        i + 1 < lines.length &&
        _findDate(lines[i + 1], now: now, documentYear: documentYear) == null) {
      rest = _stripTimes(lines[i + 1]);
      source = '$line — ${lines[i + 1]}';
      i++;
    }

    final fields = _splitFields(rest);
    var name = fields.$1;
    var venue = fields.$2;
    // A row that named only the place — the meet is the place, then.
    if (name.isEmpty && venue.isNotEmpty) {
      name = venue;
      venue = '';
    }
    if (name.isEmpty || _isHeading(name)) continue;

    final key = '${name.toLowerCase()}|${hit.date.toIso8601String()}';
    if (!seen.add(key)) continue;
    found.add(ScheduleCandidate(
      name: name,
      date: hit.date,
      venue: venue,
      source: source,
      notes: hit.notes,
    ));
  }

  return _flagCrowdedDays(found);
}

const _maxCandidates = 200;

/// How many rows on one day stop looking like a season and start looking
/// like the order of events at a single meet.
const _crowdedDay = 4;

/// A schedule's timetable read as a fixture list is the mistake this can't
/// catch on its own — a day with four rows against it is either a busy
/// Saturday or one meet's program, and only the coach knows which.
List<ScheduleCandidate> _flagCrowdedDays(List<ScheduleCandidate> found) {
  final perDay = <DateTime, int>{};
  for (final candidate in found) {
    perDay.update(candidate.date, (n) => n + 1, ifAbsent: () => 1);
  }
  if (!perDay.values.any((n) => n >= _crowdedDay)) return found;
  return [
    for (final candidate in found)
      if ((perDay[candidate.date] ?? 0) < _crowdedDay)
        candidate
      else
        ScheduleCandidate(
          name: candidate.name,
          date: candidate.date,
          venue: candidate.venue,
          source: candidate.source,
          notes: [
            ...candidate.notes,
            'Several rows share this day — this may be one meet\'s timetable',
          ],
        ),
  ];
}

List<String> _lines(String text) => text
    .replaceAll(' ', ' ')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((line) => line.trimRight())
    .where((line) => _strip(line).isNotEmpty)
    .toList();

/// Everything that isn't a letter or a digit, which is what a line has to
/// have some of to be worth reading.
String _strip(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

const _monthNames = r'january|jan|february|feb|march|mar|april|apr|may|'
    r'june|jun|july|jul|august|aug|september|sept|sep|october|oct|'
    r'november|nov|december|dec';

const _monthNumbers = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// A range — 'April 12-13', 'May 20/21' — is a two-day meet, which is one
/// meet starting on the first of them.
const _dayRange = r'(?:\s*(?:-|–|—|/|&|and)\s*\d{1,2}(?:st|nd|rd|th)?)?';

/// A range that runs into the next month — 'March 30 - Apr 3'. Still one
/// meet, still starting on the first day of it, and the second month has
/// to be swallowed or it reads as the name.
const _monthRange = '(?:\\s*(?:-|–|—|&|and)\\s*(?:$_monthNames)\\.?'
    r'\s*\d{1,2}(?:st|nd|rd|th)?)?';

final _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');

/// Only the slashed form, never `4-12`: a dash between two numbers is a
/// range of days at least as often as it is a date.
final _numericDate = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');

final _monthFirst = RegExp(
    '\\b($_monthNames)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?'
    '$_dayRange$_monthRange'
    r'(?:\s*,?\s*((?:19|20)\d{2}))?',
    caseSensitive: false);

final _dayFirst = RegExp(
    '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+($_monthNames)\\.?'
    r'(?:\s*,?\s*((?:19|20)\d{2}))?',
    caseSensitive: false);

class _DateHit {
  _DateHit(this.date, this.start, this.end, this.notes);

  final DateTime date;
  final int start;
  final int end;
  final List<String> notes;
}

/// The leftmost date on the line, whichever way it is written.
_DateHit? _findDate(String line, {required DateTime now, int? documentYear}) {
  _DateHit? best;
  void offer(_DateHit? hit) {
    if (hit == null) return;
    if (best == null || hit.start < best!.start) best = hit;
  }

  final iso = _isoDate.firstMatch(line);
  if (iso != null) {
    offer(_build(
      year: int.parse(iso.group(1)!),
      month: int.parse(iso.group(2)!),
      day: int.parse(iso.group(3)!),
      match: iso,
      now: now,
      documentYear: documentYear,
    ));
  }

  final month = _monthFirst.firstMatch(line);
  if (month != null) {
    offer(_build(
      year: _year(month.group(3)),
      month: _monthNumbers[month.group(1)!.toLowerCase().substring(0, 3)],
      day: int.parse(month.group(2)!),
      match: month,
      now: now,
      documentYear: documentYear,
    ));
  }

  final day = _dayFirst.firstMatch(line);
  if (day != null) {
    offer(_build(
      year: _year(day.group(3)),
      month: _monthNumbers[day.group(2)!.toLowerCase().substring(0, 3)],
      day: int.parse(day.group(1)!),
      match: day,
      now: now,
      documentYear: documentYear,
    ));
  }

  final numeric = _numericDate.firstMatch(line);
  if (numeric != null) {
    final first = int.parse(numeric.group(1)!);
    final second = int.parse(numeric.group(2)!);
    final notes = <String>[];
    int month;
    int day;
    if (first > 12 && second <= 12) {
      // 25/12 can only be read one way round.
      month = second;
      day = first;
    } else if (second > 12) {
      month = first;
      day = second;
    } else {
      // Both could be either. Month first is the commoner way to write it,
      // and the row says so on review rather than being quietly believed.
      month = first;
      day = second;
      notes.add('Read ${numeric.group(0)} as month first — check the day');
    }
    offer(_build(
      year: _year(numeric.group(3)),
      month: month,
      day: day,
      match: numeric,
      now: now,
      documentYear: documentYear,
      notes: notes,
    ));
  }

  return best;
}

int? _year(String? raw) {
  if (raw == null) return null;
  final value = int.parse(raw);
  if (raw.length > 2) return value;
  return value < 70 ? 2000 + value : 1900 + value;
}

_DateHit? _build({
  required int? year,
  required int? month,
  required int day,
  required Match match,
  required DateTime now,
  int? documentYear,
  List<String> notes = const [],
}) {
  if (month == null || month < 1 || month > 12 || day < 1) return null;
  if (day > _daysIn(month, year ?? documentYear ?? now.year)) return null;
  final all = [...notes];
  var resolved = year;
  if (resolved == null && documentYear != null) {
    resolved = documentYear;
  } else if (resolved == null) {
    resolved = _inferYear(month, day, now);
    all.add('No year on the schedule — assumed $resolved');
  }
  return _DateHit(DateTime(resolved, month, day), match.start, match.end, all);
}

int _daysIn(int month, int year) => DateTime(year, month + 1, 0).day;

/// Which year an undated row means.
///
/// The one that hasn't happened yet: a schedule is imported to plan a
/// season, not to remember one. The grace is for the meet that was last
/// weekend on a list somebody is only getting round to now.
int _inferYear(int month, int day, DateTime now) {
  final floor =
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 60));
  for (final year in [now.year - 1, now.year, now.year + 1]) {
    if (!DateTime(year, month, day).isBefore(floor)) return year;
  }
  return now.year;
}

/// The year written across the top of the page — '2027 Outdoor Schedule' —
/// which is what rows that give only a day and a month mean.
///
/// Only when the page agrees with itself: two plausible years on it and the
/// heading isn't a heading, so the rows fall back to being guessed at.
int? _documentYear(String text, DateTime now) {
  final years = <int>{};
  for (final match in RegExp(r'\b(?:19|20)\d{2}\b').allMatches(text)) {
    final year = int.parse(match.group(0)!);
    if (year >= now.year - 1 && year <= now.year + 2) years.add(year);
  }
  return years.length == 1 ? years.first : null;
}

final _leadingWeekday = RegExp(
    r'^[\s\-–—:|,·]*(mon|monday|tue|tues|tuesday|wed|weds|wednesday|thu|thur|'
    r'thurs|thursday|fri|friday|sat|saturday|sun|sunday)\.?\b',
    caseSensitive: false);

/// Drops the weekday off the front of what came before the date. Only
/// there: a Sun Devil Classic keeps its sun.
String _stripWeekday(String before) =>
    before.replaceFirst(_leadingWeekday, ' ');

final _times = RegExp(
    r'\b\d{1,2}:\d{2}\s*(?:[ap]\.?m\.?)?|\b\d{1,2}\s*[ap]\.?m\.?\b',
    caseSensitive: false);

/// A start time is not a meet's, it is one event's, and this app's meet is
/// a whole day. Dropping it beats storing it against the wrong thing.
String _stripTimes(String rest) => rest.replaceAll(_times, ' ');

final _columns = RegExp(r'\t+| {2,}');
final _dashes = RegExp(r'\s+(?:-|–|—|\||·|;)\s+');
final _parenthetical = RegExp(r'\(([^)]{2,})\)\s*$');
final _leadingAt = RegExp(r'^(?:@|at)\s+', caseSensitive: false);

/// Splits what is left of a row into a name and a venue.
///
/// A schedule is a table, however it was pasted: an `@`, a tab, a column of
/// spaces, a dash. Each of those is somebody's column rule, and the first
/// field is always what the meet is called.
(String, String) _splitFields(String raw) {
  // Trimmed first, or the gap the date was cut out of reads as a column
  // rule and swallows the whole row into one field.
  final rest = raw.trim();
  String name;
  var venue = '';

  final at = rest.indexOf('@');
  if (at != -1) {
    name = rest.substring(0, at);
    venue = rest.substring(at + 1);
  } else if (_columns.hasMatch(rest)) {
    final parts =
        rest.split(_columns).where((p) => _strip(p).isNotEmpty).toList();
    // A schedule's time column says 'TBD' where the time isn't settled,
    // and a row that starts with one still has a meet in it further along.
    while (parts.length > 1 && _isPlaceholder(parts.first)) {
      parts.removeAt(0);
    }
    name = parts.first;
    venue = parts.skip(1).join(', ');
  } else if (_dashes.hasMatch(rest)) {
    final parts = rest.split(_dashes).where((p) => _strip(p).isNotEmpty);
    name = parts.first;
    venue = parts.skip(1).join(', ');
  } else {
    final parens = _parenthetical.firstMatch(rest);
    if (parens != null) {
      name = rest.substring(0, parens.start);
      venue = parens.group(1)!;
    } else {
      name = rest;
    }
  }

  return (_tidy(name), _tidy(venue.replaceFirst(_leadingAt, '')));
}

/// A field as a person would have typed it: no column padding, no leftover
/// punctuation from the rule it was split on, and short enough to be a name
/// rather than a paragraph that happened to have a date in it.
String _tidy(String value) {
  var tidy = value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–—:|,·]+|[\s\-–—:|,·]+$'), '')
      .trim();
  if (tidy.length > 80) tidy = '${tidy.substring(0, 79).trimRight()}…';
  return tidy;
}

final _placeholders =
    RegExp(r'^[\s\-–—]*(?:tba|tbd|n/?a)[\s.]*$', caseSensitive: false);

/// A column with nothing in it yet, which is not what the meet is called.
bool _isPlaceholder(String field) => _placeholders.hasMatch(field);

final _headings = RegExp(
    r'^(date|day|days|meet|meets|event|events|location|locations|site|venue|'
    r'time|times|opponent|schedule|home|away|tba|tbd)$',
    caseSensitive: false);

/// A table's header row survives everything above it — it is a line of
/// words in columns — so it is thrown out by name at the end.
bool _isHeading(String name) =>
    _headings.hasMatch(name) || _strip(name).isEmpty;
