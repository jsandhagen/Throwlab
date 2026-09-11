import 'dart:math' as math;
import 'dart:typed_data';

import '../models/athlete_profile.dart';
import '../models/meet.dart';
import '../models/meet_board.dart';
import '../models/throw_video.dart';
import '../widgets/throw_card.dart';
import 'pdf_writer.dart';

/// A meet's results, as a sheet somebody can hand out.
///
/// The competition already knows all of this — the point is getting it off
/// the phone. A coach at the end of a Saturday has a results sheet in their
/// pocket that nobody else has, and the athletes, their parents and the
/// school's office all want a copy of it before anybody has written
/// anything up.
///
/// Laid out the way a meet program is laid out, because that is what it
/// will be read next to: place, name, the series round by round, and the
/// mark it was placed on. Standings order rather than throwing order — a
/// results sheet is the answer, not the running of it.
///
/// Pass [only] to print one competition instead of the whole day; a coach
/// whose athlete threw the discus has no use for the javelin's four pages.
Uint8List meetResultsPdf(
  Meet meet,
  Iterable<ThrowResult> results, {
  MeetCompetition? only,
  DateTime? printedOn,
}) {
  final printed = printedOn ?? DateTime.now();
  final sheet = PdfSheet(
    // The meet's own name on every page, because the pages come apart: a
    // results sheet is printed, pinned up, and photographed a page at a
    // time, and a loose second page that says only 'page 2 of 3' belongs
    // to no meet at all.
    footer: [
      if (meet.name.isNotEmpty) meet.name,
      'ThrowLab',
      'printed ${longThrowDate(printed)}',
    ].join('  ·  '),
  );

  sheet.line((meet.name.isEmpty ? 'Meet' : meet.name).toUpperCase(),
      size: 15, face: PdfFace.bold, spacing: 18);
  sheet.line(
    [
      longThrowDate(meet.date),
      if (meet.venue.isNotEmpty) meet.venue,
      _format(meet),
    ].join('  ·  '),
    size: 9,
  );
  if (meet.conditions.isNotEmpty) {
    sheet.line(
      [
        if (meet.conditions.summary.isNotEmpty) meet.conditions.summary,
        if (meet.conditions.note.isNotEmpty) meet.conditions.note,
      ].join('  ·  '),
      size: 9,
      face: PdfFace.oblique,
    );
  }

  final competitions = only != null
      ? [only]
      : [
          for (final competition in MeetCompetition.of(meet))
            if (competition.entries.isNotEmpty) competition,
        ];
  if (competitions.isEmpty) {
    sheet.rule();
    sheet.line('Nobody was entered.', size: 10, face: PdfFace.oblique);
    return sheet.save();
  }

  // The record book's own rule, run over the same marks the tables are
  // built from — so a throw the app already wears a medal for is a throw
  // the sheet says PB against. Nothing else on this page needs the
  // library: a best is a fact about the results, not about the app.
  final held = results.toList();
  final bests = personalBestIds(held);

  sheet.line(_countOf(meet, competitions, bests),
      size: 9, face: PdfFace.oblique);

  for (final competition in competitions) {
    _competition(sheet, meet, competition, held, bests);
  }

  _bestsSet(sheet, meet, competitions, held, bests);

  sheet.gap(4);
  sheet.line('X foul    -  pass    blank  not thrown    PB personal best',
      size: 8, face: PdfFace.oblique);
  return sheet.save();
}

/// What the day came to, in one line: how much was thrown, and how much of
/// it was worth keeping.
///
/// A results sheet is read first for its own athlete and second for the
/// shape of the afternoon, and the second question has a one-line answer
/// nobody has had to work out by hand.
String _countOf(
  Meet meet,
  List<MeetCompetition> competitions,
  Set<String> bests,
) {
  final athletes = <String>{};
  var thrown = 0;
  var best = 0;
  for (final competition in competitions) {
    for (final entry in competition.entries) {
      athletes.add(entry.athlete.trim().toLowerCase());
      for (final attempt in entry.attempts) {
        if (attempt == null || attempt.kind == AttemptKind.pass) continue;
        // A foul is a throw. It is the part of a series a coach reads
        // hardest, and a sheet that counted only the legal ones would say
        // a windy afternoon was a quiet one.
        thrown++;
        if (attempt.resultId != null && bests.contains(attempt.resultId)) {
          best++;
        }
      }
    }
  }
  return [
    _plural(competitions.length, 'event'),
    _plural(athletes.length, 'athlete'),
    _plural(thrown, 'throw'),
    if (best > 0) _plural(best, 'personal best', 'personal bests'),
  ].join('  ·  ');
}

String _plural(int count, String one, [String? many]) =>
    '$count ${count == 1 ? one : many ?? '${one}s'}';

/// One competition: the shape of it, then the table it adds up to.
void _competition(
  PdfSheet sheet,
  Meet meet,
  MeetCompetition competition,
  List<ThrowResult> results,
  Set<String> bests,
) {
  final standings = MeetStandings(competition, results,
      advancing: meet.advancing, prelimRounds: meet.prelimRounds);
  const size = 8.5;
  final width = sheet.columnsAt(size);
  // Place, the rounds and the mark are fixed; the name takes what is left
  // of the page, which is what keeps the columns lined up whether a meet
  // gives three attempts or six — but only up to a point. A name column
  // stretched the full width of a sheet leaves the eye to jump a hand's
  // breadth of nothing to reach the marks.
  final name =
      math.min(_widestName, width - 5 - _mark - _flag - _round * meet.rounds);

  // A heading is no use at the foot of a page with its table over the
  // leaf: keep it with the first few rows of one.
  sheet.reserve(80);
  sheet.rule();
  sheet.line(competition.label.toUpperCase(), size: 11, face: PdfFace.bold);
  sheet.line(
    [
      '${competition.entries.length} in the field',
      if (competition.isFlighted) '${competition.flights.length} flights',
      if (standings.hasCut) 'top ${standings.advancing} advance',
    ].join(' · '),
    size: 8,
    face: PdfFace.oblique,
    spacing: 12,
  );

  // Drawn to the table's own width rather than the page's, so the picture
  // and the numbers under it read as one block instead of two.
  _spread(sheet, standings,
      (5 + name + _mark + _flag + _round * meet.rounds) * size * 0.6);

  sheet.columns(
    _row(
      place: 'PL',
      name: 'NAME',
      width: name,
      rounds: [
        for (var round = 0; round < meet.rounds; round++) '${round + 1}',
      ],
      mark: 'BEST',
      face: PdfFace.bold,
    ),
    size: size,
  );

  for (var i = 0; i < standings.places.length; i++) {
    final place = standings.places[i];
    // The cut, drawn where it falls — the line everybody reads a results
    // sheet for.
    if (standings.hasCut &&
        i > 0 &&
        standings.places[i - 1].advancing &&
        !place.advancing) {
      sheet.line('-' * width, size: size, face: PdfFace.oblique);
    }
    final series = place.series;
    final best = place.best;
    final bestRound = series.bestRound;
    sheet.columns(
      _row(
        place: best == null ? '-' : '${place.place}',
        name: place.entry.athlete.isEmpty ? 'Unassigned' : place.entry.athlete,
        width: name,
        rounds: [
          for (var round = 0; round < meet.rounds; round++)
            _attempt(place.entry, series, round),
        ],
        mark:
            best == null ? '' : formatDistance(best, series.unitAt(bestRound!)),
        // The throw they were placed on, set in bold where it sits in the
        // series: which round it came in is half of what a coach reads a
        // series for, and a column of numbers all one weight hides it.
        emphasize: bestRound,
        // A personal best is the one thing on this page the meet itself
        // does not know — it takes the record book to say so.
        flag: _isBest(place, bests) ? 'PB' : '',
        // First place in bold, because a results sheet is read from the
        // top and that is the line it is read for.
        face: place.place == 1 && best != null ? PdfFace.bold : null,
      ),
      size: size,
    );
  }

  final story = _howItWasWon(standings);
  if (story.isNotEmpty) {
    sheet.line(story, size: 8, face: PdfFace.oblique, spacing: 14);
  }
}

/// Whether the throw this athlete was placed on is the furthest they have
/// ever thrown at this weight.
bool _isBest(MeetPlace place, Set<String> bests) {
  final round = place.series.bestRound;
  if (round == null) return false;
  final id = place.entry.attemptAt(round)?.resultId;
  return id != null && bests.contains(id);
}

/// How the competition was won, in the one sentence a report would open
/// with: which round it turned on, and by how much.
String _howItWasWon(MeetStandings standings) {
  final places = standings.places;
  // A competition of one is a person taking six throws. Nobody won it, and
  // a sheet that said so would be describing a contest that never happened.
  if (places.length < 2) return '';
  final won = places.first;
  final mark = won.best;
  final round = won.series.bestRound;
  if (mark == null || round == null) return '';
  final unit = won.series.unitAt(round);
  final inRound = 'Won in round ${round + 1}';

  // Second place is the next athlete with a mark who is not level with the
  // winner — a shared first place is settled by countback, and saying it
  // was won by nothing would be saying it wrong.
  for (final other in places.skip(1)) {
    final theirs = other.best;
    if (theirs == null) continue;
    if (theirs >= mark) return '$inRound, on countback.';
    final clear = formatDistance(mark - theirs, unit);
    return '$inRound, $clear clear of ${_named(other.entry)}.';
  }
  return '$inRound.';
}

String _named(MeetEntry entry) =>
    entry.athlete.isEmpty ? 'Unassigned' : entry.athlete;

/// The competition drawn: every throw of it against one scale.
///
/// The table under this says what everybody threw and hides what the
/// afternoon was like — whether the winner was clear or hunted, whether a
/// place was decided by a centimeter, who found it once and who was there
/// all day. That is a picture, and it is three rules and a row of ticks.
///
/// Drawn to a round number of meters off [boardSpans], exactly as the live
/// board is, so a gap on the page is a number of meters a reader can count
/// off the scale under it rather than a shape to be taken on trust.
void _spread(PdfSheet sheet, MeetStandings standings, double toWidth) {
  final shown = [
    for (final place in standings.places)
      if (place.best != null) place,
  ];
  // Nothing to compare: one line is not a picture of a competition.
  if (shown.length < 2) return;

  // One scale, in the unit most of the competition was measured in. The
  // table gives every mark in the unit it was entered in, which is right —
  // it is what the athlete was told at the sector — but a picture can only
  // have one scale, and the majority is the one that puts the fewest rows
  // of it against a number nobody read out.
  final unit = _unitOf(shown);
  double show(double meters) =>
      unit == DistanceUnit.feet ? meters / metersPerFoot : meters;

  final marks = <double>[
    for (final place in shown)
      for (final mark in place.series.legalMarks) show(mark),
  ]..sort();
  final band = _band(marks);

  // At most this many rows: the chart is the shape of the competition,
  // which is decided at the top of it, and the table below has everybody.
  const most = 12;
  final rows = shown.length > most ? shown.take(most).toList() : shown;

  const row = 10.0;
  const axis = 14.0;
  // Room over the top row for what is written across the chart rather than
  // in it — the cut, so far.
  const head = 8.0;
  const label = 116.0;
  final cut = standings.hasCut ? standings.cutMark : null;

  sheet.figure(rows.length * row + axis + head, (into) {
    const left = label;
    // Enough margin for the last ring's label to sit under its own line,
    // and the unit after it.
    final right = math.min(into.width, toWidth) - 26;
    double at(double value) =>
        left + (right - left) * ((value - band.near) / (band.far - band.near));

    // The rings of the scale, run the whole height of the chart so a gap
    // between two throws can be counted in meters rather than guessed at.
    for (var ring = band.near; ring <= band.far + 1e-9; ring += band.grid) {
      into.line(at(ring), axis - 3, at(ring), into.height - head,
          thickness: 0.4, gray: 0.86);
      into.text(_ring(ring),
          x: at(ring), y: 3, size: 6, gray: 0.45, align: PdfAlign.center);
    }
    into.text(unit == DistanceUnit.feet ? 'ft' : 'm',
        x: right + 10, y: 3, size: 6, gray: 0.45);
    // A field too long to draw says so, rather than quietly ending at the
    // twelfth name.
    if (rows.length < shown.length) {
      into.text('the first ${rows.length} of ${shown.length}',
          x: 0, y: 3, size: 6, gray: 0.45);
    }

    for (var i = 0; i < rows.length; i++) {
      final place = rows[i];
      final series = place.series;
      final y = into.height - head - (i + 1) * row + 3;
      final best = show(place.best!);

      into.text('${place.place}', x: 10, y: y, size: 7, align: PdfAlign.right);
      into.text(_fitPoints(_named(place.entry), label - 18, 7),
          x: 14, y: y, size: 7);

      // The bar runs from the floor of the scale to the throw they were
      // placed on, and every other legal throw of the series is a tick
      // along it: a series that arrived in one go and a series that was
      // there all day are the same number in the table and two different
      // afternoons.
      into.fill(left, y - 1, at(best) - left, 4.5,
          gray: place.place == 1 ? 0.62 : 0.82);
      for (final mark in series.legalMarks) {
        final x = at(show(mark));
        into.line(x, y - 2, x, y + 5.5, thickness: 0.7, gray: 0.25);
      }
    }

    // Where the cut falls, across everybody — the one line on the page
    // that says what a throw had to beat rather than what it was.
    if (cut != null && cut >= band.near && cut <= band.far) {
      final x = at(show(cut));
      into.line(x, axis - 3, x, into.height - head + 2,
          thickness: 0.7, dash: [2, 2]);
      into.text('cut',
          x: x, y: into.height - 6, size: 6, align: PdfAlign.center);
    }
  });
}

/// The unit most of a competition was measured in; meters on a tie, which
/// is what everything else in the app counts in.
DistanceUnit _unitOf(List<MeetPlace> places) {
  var feet = 0;
  for (final place in places) {
    final round = place.series.bestRound;
    if (round == null) continue;
    if (place.series.unitAt(round) == DistanceUnit.feet) feet++;
  }
  return feet > places.length / 2 ? DistanceUnit.feet : DistanceUnit.meters;
}

/// A ring's label, without the trailing zeros a round number doesn't need.
String _ring(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// The scale a competition is drawn to: deep enough to hold every throw in
/// it, on one of the board's own rungs.
///
/// Deliberately not [fitBand], which is allowed to leave a mark off the
/// board and draw it as an arrow instead — a screen can be pinched, and
/// paper cannot. So every throw is inside this one, and the rung only
/// decides how far apart the rings are.
({double near, double far, double grid}) _band(List<double> marks) {
  final low = marks.first;
  final high = marks.last;
  var rung = boardSpans.last;
  for (final span in boardSpans) {
    if (span >= high - low) {
      rung = span;
      break;
    }
  }
  final grid = gridFor(rung);
  final near = (low / grid).floorToDouble() * grid;
  final far = (high / grid).ceilToDouble() * grid;
  return (near: near, far: far == near ? near + grid : far, grid: grid);
}

/// A name cut to the points it has, rather than to a column of characters:
/// inside a drawing there is nothing to line it up with.
String _fitPoints(String text, double points, double size) {
  final fits = (points / (size * 0.6)).floor();
  if (fits <= 1) return '';
  return text.length <= fits ? text : '${text.substring(0, fits - 1)}.';
}

/// Room for one attempt, for the mark an athlete was placed on, and for
/// the two letters that say it was the furthest they have thrown. In
/// characters, which is the only unit a fixed-width sheet has.
const _round = 7;
const _mark = 10;
const _flag = 3;

/// As much of a name as a sheet will set before cutting it. Long enough for
/// a double-barrelled surname and the club after it.
const _widestName = 34;

/// One line of the table, every column where the header said it would be.
///
/// Built as runs rather than as one padded string so a cell can carry its
/// own weight — the throw somebody was placed on is set in bold inside the
/// series, which a single-face line has no way of saying.
List<PdfRun> _row({
  required String place,
  required String name,
  required int width,
  required List<String> rounds,
  required String mark,
  int? emphasize,
  String flag = '',
  PdfFace? face,
}) {
  final plain = face ?? PdfFace.regular;
  final runs = <PdfRun>[
    PdfRun(place.padLeft(2), 0, plain),
    PdfRun(_fit(name, width), 3, plain),
  ];
  var column = 3 + width + 1;
  for (var i = 0; i < rounds.length; i++) {
    runs.add(PdfRun(rounds[i].padLeft(_round), column,
        i == emphasize ? PdfFace.bold : plain));
    column += _round;
  }
  runs.add(PdfRun(mark.padLeft(_mark), column, plain));
  runs.add(PdfRun(flag.padLeft(_flag), column + _mark, PdfFace.bold));
  return runs;
}

/// Every personal best set at the meet, and what each one beat.
///
/// The last word of the sheet, because it is the part somebody will read
/// out. A meet knows what was thrown; only the record book behind it knows
/// which of those throws an athlete had never got near before.
void _bestsSet(
  PdfSheet sheet,
  Meet meet,
  List<MeetCompetition> competitions,
  List<ThrowResult> results,
  Set<String> bests,
) {
  final lines = <(String, String, String)>[];
  for (final competition in competitions) {
    final standings = MeetStandings(competition, results,
        advancing: meet.advancing, prelimRounds: meet.prelimRounds);
    for (final place in standings.places) {
      if (!_isBest(place, bests)) continue;
      final round = place.series.bestRound!;
      final unit = place.series.unitAt(round);
      final mark = place.best!;
      final before = _previousBest(place.entry, results, mark);
      lines.add((
        _named(place.entry),
        '${competition.label}  ${formatDistance(mark, unit)}',
        before == null
            ? 'first mark at this weight'
            : 'up ${formatDistance(mark - before, unit)} '
                'on ${formatDistance(before, unit)}',
      ));
    }
  }
  if (lines.isEmpty) return;

  sheet.reserve(40);
  sheet.rule();
  sheet.line('PERSONAL BESTS', size: 11, face: PdfFace.bold, spacing: 13);
  for (final (who, what, gain) in lines) {
    sheet.columns([
      PdfRun(_fit(who, 24), 0, PdfFace.bold),
      PdfRun(what, 25),
      PdfRun(gain, 58, PdfFace.oblique),
    ], size: 8.5);
  }
}

/// The furthest this athlete had thrown at this weight before [mark] — the
/// second-best of everything the record book holds for them, which is what
/// a new best beat. Null when there is nothing behind it.
double? _previousBest(MeetEntry entry, List<ThrowResult> results, double mark) {
  final athlete = entry.athlete.trim().toLowerCase();
  double? previous;
  var held = false;
  for (final result in results) {
    if (result.athlete.trim().toLowerCase() != athlete) continue;
    if (result.event != entry.event) continue;
    if (result.implementKg != entry.implementKg) continue;
    final distance = result.distance;
    if (distance == null) continue;
    // The best itself is skipped once — an athlete who has thrown it twice
    // has equalled their best, not bettered nothing.
    if (!held && distance == mark) {
      held = true;
      continue;
    }
    if (previous == null || distance > previous) previous = distance;
  }
  return previous;
}

/// What one round came to: the distance, X for a foul, - for a pass, and
/// nothing at all for a round nobody threw.
String _attempt(MeetEntry entry, MeetSeries series, int round) {
  final attempt = entry.attemptAt(round);
  if (attempt == null) return '';
  switch (attempt.kind) {
    case AttemptKind.foul:
      return 'X';
    case AttemptKind.pass:
      return '-';
    case AttemptKind.mark:
      final distance = series.distanceAt(round);
      // The mark behind the round has been deleted from the library; the
      // round still happened.
      if (distance == null) return '?';
      return formatDistance(distance, series.unitAt(round)).split(' ').first;
  }
}

/// A name in the space the column has, cut rather than wrapped: a table
/// that reflows is a table that no longer lines up.
String _fit(String text, int width) {
  if (width <= 1) return '';
  if (text.length <= width) return text.padRight(width);
  return '${text.substring(0, width - 1)}.';
}

/// '6 throws · everyone' or '3 + 3', the way the program printed it.
String _format(Meet meet) => meet.hasFinal
    ? '${meet.prelimRounds} + ${meet.rounds - meet.prelimRounds}'
    : '${meet.rounds} throws';
