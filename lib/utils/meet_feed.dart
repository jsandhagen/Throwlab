import 'dart:ui' show Color;

import '../models/meet.dart';
import '../models/meet_board.dart';
import '../models/throw_video.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';

/// One competition as somebody watching it needs it: the standings, the
/// series and the board, worked out here and handed over as numbers and
/// words.
///
/// This is what a spectator's browser is served, and it is deliberately
/// *derived* rather than raw. The rules a competition is read by — who is
/// placed where, where the cut falls, which flight is in the ring, what
/// band of the sector is worth drawing — all live in [MeetStandings],
/// [MeetFlight] and [MeetBoard], and re-implementing any of them in
/// JavaScript would be a second record of the competition that can disagree
/// with the coach's own screen. So the page is handed the answers and draws
/// them. It knows nothing about countback, prelims or feet and inches.
///
/// One competition, not the meet. A link is handed out at a ring by
/// somebody standing at it, and what the people there are watching is the
/// discus — not the javelin two hours later, and not the rest of the day's
/// field, who are somebody else's athletes and have not agreed to be on
/// anybody's phone. The meet is around it as context: its name, the day,
/// and what the weather was doing.
///
/// Marks are already written the way they were measured — the unit a throw
/// was entered in, through [formatDistance], the one place that is decided
/// — so a sheet reading '191-08' and a board reading '191-08' can never
/// become the same throw in two notations.
Map<String, dynamic> competitionFeed(
  Meet meet,
  MeetCompetition competition,
  Iterable<ThrowResult> results, {
  DateTime? at,
  bool Function(ThrowResult result)? isPersonalBest,
}) {
  final held = results.toList();
  final standings = MeetStandings(competition, held,
      advancing: meet.advancing, prelimRounds: meet.prelimRounds);
  final flight =
      MeetFlight(competition, rounds: meet.rounds, standings: standings);
  final board = MeetBoard(standings, inTheCircle: flight.inTheCircle);

  return {
    'meet': meet.name.isEmpty ? 'Meet' : meet.name,
    'date': longThrowDate(meet.date),
    if (meet.venue.isNotEmpty) 'venue': meet.venue,
    if (meet.conditions.isNotEmpty)
      'conditions': [
        if (meet.conditions.summary.isNotEmpty) meet.conditions.summary,
        if (meet.conditions.note.isNotEmpty) meet.conditions.note,
      ].join(' · '),
    // What the page stamps its 'last updated' off. A spectator whose phone
    // has wandered off the wifi is owed the truth about how old the board
    // in front of them is.
    'asOf': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'id': competitionId(competition),
    'label': competition.label,
    'event': competition.event.name,
    // The color this event wears everywhere else in the app, so a spectator
    // who has seen the coach's screen is looking at the same discus.
    'tint': _hex(eventColor(competition.event)),
    'rounds': meet.rounds,
    // How many rounds everybody throws before the cut. Equal to 'rounds' in
    // a competition with no cut, which is what makes the last boxes of a
    // card worth graying or not.
    'prelims': meet.prelimRounds,
    'status': flight.label,
    'flight': _flight(flight, standings),
    'cut': {
      'advancing': meet.advancing,
      'has': standings.hasCut,
      'made': standings.cutMade,
      if (standings.cutMark != null)
        'mark': formatDistance(standings.cutMark!, _unitOfCut(standings)),
    },
    'places': [
      for (final place in standings.places)
        _place(meet, competition, place, standings, isPersonalBest),
    ],
    'board': _board(board),
  };
}

/// How a competition is named on the wire — the event and the weight it is
/// thrown at, which is exactly what makes it its own contest.
String competitionId(MeetCompetition competition) =>
    '${competition.event.name}:${competition.implementKg}';

/// Where the competition has got to, and the three an infield calls out.
///
/// The calls come through as rows rather than as bare names, because that
/// is what the app's own header puts up: what they are called, who they
/// are, where they stand and what they are standing on. Absent where there
/// is no order worth naming anybody in ([MeetFlight.hasOrder]) — a
/// competition of one is an athlete taking six throws, and announcing that
/// they are up says nothing.
Map<String, dynamic> _flight(MeetFlight flight, MeetStandings standings) {
  Map<String, dynamic>? who(String label, MeetEntry? entry) {
    if (entry == null) return null;
    final place = standings.placeOf(entry.id);
    final best = place?.best;
    return {
      'label': label,
      'name': entry.athlete,
      if (place != null && best != null) 'placeLabel': ordinalPlace(place.place),
      if (place != null && best != null)
        'mark': formatDistance(best, place.series.unit),
    };
  }

  // Whoever is in front. A competition that is over has a winner; one
  // still being thrown has somebody ahead, which is not the same thing and
  // shouldn't be written as though it were.
  //
  // Worth a line of their own only when they are not already on one: the
  // leader standing in the circle is named once, at the top, exactly as
  // the app's own header names them.
  MeetPlace? leading;
  for (final place in standings.places) {
    if (place.best == null) continue;
    final called = [flight.inTheCircle, flight.onDeck, flight.inTheHole]
        .any((entry) => entry?.id == place.entry.id);
    if (!called) leading = place;
    break;
  }

  return {
    if (flight.flightLabel.isNotEmpty) 'label': flight.flightLabel,
    'round': flight.round + 1,
    'done': flight.finished,
    'thrown': flight.thrown,
    'fieldSize': flight.fieldSize,
    // The words the app's own header uses, rather than two numbers for the
    // page to join up itself.
    'thrownLabel': flight.finished
        ? 'all in'
        : '${flight.thrown} of ${flight.fieldSize} thrown',
    'progress': flight.fieldSize == 0 ? 0.0 : flight.thrown / flight.fieldSize,
    'calls': [
      for (final call in [
        who('up', flight.inTheCircle),
        who('on deck', flight.onDeck),
        who('in the hole', flight.inTheHole),
      ])
        if (call != null) call,
    ],
    if (leading != null)
      'leading': who(flight.finished ? 'won by' : 'leading', leading.entry),
  };
}

Map<String, dynamic> _place(
  Meet meet,
  MeetCompetition competition,
  MeetPlace place,
  MeetStandings standings,
  bool Function(ThrowResult result)? isPersonalBest,
) {
  final series = place.series;
  final unit = series.unit;
  return {
    'place': place.place,
    'placeLabel': ordinalPlace(place.place),
    // Where they come in the throwing order. The places arrive ranked, and
    // the field is read the other way round as the round works down it —
    // one list, sorted twice, rather than the same athletes sent twice
    // over.
    'order': competition.entries.indexWhere((e) => e.id == place.entry.id),
    // The meet's own spelling, which is what the heat sheet said and what
    // the announcer will call. A nickname is the coach's shorthand for
    // somebody they know, and means nothing to a parent in the stand.
    'name': place.entry.athlete,
    'tracked': place.entry.tracked,
    if (place.entry.flight > 1) 'flight': place.entry.flight,
    'advancing': place.advancing,
    // What grays the last rounds of a card once the cut has been made.
    'throwsInFinal': standings.throwsInFinal(place.entry.id),
    if (place.best != null) 'best': formatDistance(place.best!, unit),
    if (series.bestRound != null) 'bestRound': series.bestRound! + 1,
    if (series.average != null) 'average': formatDistance(series.average!, unit),
    'fouls': series.fouls,
    'passes': series.passes,
    // 'averaging 42.13 m from 2 · 1 foul' — the coach's question rather
    // than the competition's, and only for their own athletes, exactly as
    // the app's own table asks it. A mean of one throw is that throw,
    // which the row already gives.
    if (place.entry.tracked && _consistency(series) != null)
      'consistency': _consistency(series),
    'series': [
      for (var round = 0; round < meet.rounds; round++)
        _round(place, series, round, isPersonalBest),
    ],
  };
}

/// How the series is going as a whole, in the words the app's standings
/// row says it in. Null before there is anything to say about it.
String? _consistency(MeetSeries series) {
  final marks = series.legalMarks.length;
  final average = marks > 1 ? series.average : null;
  final fouls = series.fouls;
  if (average == null && fouls == 0) return null;
  return [
    if (average != null)
      'averaging ${formatDistance(average, series.unit)} from $marks',
    if (fouls > 0) '$fouls foul${fouls == 1 ? '' : 's'}',
  ].join(' · ');
}

/// One box of a series: what became of the round, and the mark if it stood.
///
/// Null for a round nobody has thrown yet, which is what leaves the box
/// empty rather than drawing a foul in it.
Map<String, dynamic>? _round(
  MeetPlace place,
  MeetSeries series,
  int round,
  bool Function(ThrowResult result)? isPersonalBest,
) {
  final attempt = place.entry.attemptAt(round);
  if (attempt == null) return null;
  final distance = series.distanceAt(round);
  final result = series.resultAt(round);
  final mark =
      distance == null ? null : formatDistance(distance, series.unitAt(round));
  return {
    'kind': attempt.kind.name,
    if (mark != null) 'mark': mark,
    // The same mark as a series box writes it. Six boxes across a phone
    // have no room for a unit on every one, so the app's own card drops it
    // there and says it once on the best — and a box that wrapped '43.06'
    // onto a second line to fit ' m' would be worse than either.
    if (mark != null) 'short': mark.split(' ').first,
    // The record book's own rule, run over the same results the sheet uses
    // — so a throw the app wears a medal for is a throw the board says PB
    // against. Only a tracked athlete can hold one, which falls out for
    // free: nobody else's throw ever reaches the library to be ranked.
    if (result != null && (isPersonalBest?.call(result) ?? false)) 'pb': true,
  };
}

/// The board as coordinates, with the arithmetic already done.
///
/// [MeetBoard] has picked the band and the scale; all that is left is where
/// each line falls across it, which is [MeetBoard.fractionOf]. A mark the
/// band broke off comes through with a fraction outside 0..1 and says which
/// edge it went off, so the drawing can pin it there with an arrow instead
/// of pretending it is on the sector.
Map<String, dynamic> _board(MeetBoard board) => {
      'near': board.near,
      'far': board.far,
      'grid': board.grid,
      // '2 m lines' — what the app writes in the corner of its own board,
      // so a gap can be read as a distance without doing arithmetic off
      // the labels.
      'gridLabel': '${_trim(board.grid)} m lines',
      'hasCut': board.hasCut,
      'markerLines': board.markerLines,
      'marks': [
        for (final mark in board.marks)
          {
            'line': mark.line.name,
            'label': mark.label,
            'name': mark.boardName,
            'mark': formatDistance(mark.distance, mark.unit),
            'tracked': mark.tracked,
            'fraction': board.fractionOf(mark.distance),
            if (board.fractionOf(mark.distance) > 1) 'off': 'far',
            if (board.fractionOf(mark.distance) < 0) 'off': 'near',
          },
      ],
    };

/// What unit to write the cut in. It belongs to a place rather than to a
/// person, so it takes the unit of whoever is standing on it — the same
/// mark, read back the way it was measured.
DistanceUnit _unitOfCut(MeetStandings standings) {
  // The *last* qualifying place, the way [MeetStandings.cutMark] reads it —
  // not the first. The leader may have been measured in meters at a meet
  // where the athlete on the cut was taped in feet.
  var unit = DistanceUnit.meters;
  for (final place in standings.places) {
    if (!place.advancing) break;
    if (place.best != null) unit = place.series.unit;
  }
  return unit;
}

/// '2' rather than '2.0', and '0.5' kept — the board's rungs are round
/// numbers and a trailing zero on one reads as precision it hasn't got.
String _trim(double meters) => meters == meters.roundToDouble()
    ? meters.toStringAsFixed(0)
    : meters.toString();

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
