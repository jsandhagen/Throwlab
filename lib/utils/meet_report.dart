import 'dart:math' as math;
import 'dart:typed_data';

import '../models/meet.dart';
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
    footer: 'Recorded in ThrowLab  ·  printed ${longThrowDate(printed)}',
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

  for (final competition in competitions) {
    _competition(sheet, meet, competition, results);
  }

  sheet.gap(4);
  sheet.line('X foul    -  pass    blank  not thrown',
      size: 8, face: PdfFace.oblique);
  return sheet.save();
}

/// One competition's table.
void _competition(
  PdfSheet sheet,
  Meet meet,
  MeetCompetition competition,
  Iterable<ThrowResult> results,
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
  final name = math.min(_widestName, width - 4 - _mark - _round * meet.rounds);

  sheet.rule();
  sheet.line(competition.label.toUpperCase(), size: 11, face: PdfFace.bold);
  sheet.line(
    '${competition.entries.length} in the field'
    '${standings.hasCut ? ' · top ${standings.advancing} advance' : ''}',
    size: 8,
    face: PdfFace.oblique,
    spacing: 14,
  );
  sheet.line(
    _row(
      place: 'PL',
      name: 'NAME',
      width: name,
      rounds: [
        for (var round = 0; round < meet.rounds; round++) '${round + 1}',
      ],
      mark: 'BEST',
    ),
    size: size,
    face: PdfFace.bold,
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
    sheet.line(
      _row(
        place: best == null ? '-' : '${place.place}',
        name: place.entry.athlete.isEmpty ? 'Unassigned' : place.entry.athlete,
        width: name,
        rounds: [
          for (var round = 0; round < meet.rounds; round++)
            _attempt(place.entry, series, round),
        ],
        mark: best == null
            ? ''
            : formatDistance(best, series.unitAt(series.bestRound!)),
      ),
      size: size,
    );
  }
}

/// Room for one attempt, and for the mark an athlete was placed on. In
/// characters, which is the only unit a fixed-width sheet has.
const _round = 7;
const _mark = 10;

/// As much of a name as a sheet will set before cutting it. Long enough for
/// a double-barrelled surname and the club after it.
const _widestName = 34;

/// One line of the table, every column where the header said it would be.
String _row({
  required String place,
  required String name,
  required int width,
  required List<String> rounds,
  required String mark,
}) {
  final buffer = StringBuffer()
    ..write(place.padLeft(2))
    ..write(' ')
    ..write(_fit(name, width))
    ..write(' ');
  for (final round in rounds) {
    buffer.write(round.padLeft(_round));
  }
  buffer.write(mark.padLeft(_mark));
  return buffer.toString();
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
