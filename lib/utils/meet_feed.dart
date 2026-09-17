import '../models/meet.dart';
import '../models/meet_board.dart';
import '../models/throw_video.dart';
import '../widgets/throw_card.dart';

/// A meet as somebody watching it needs it: the standings, the series and
/// the board, worked out here and handed over as numbers and words.
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
/// The whole meet goes out, not the competition the coach happens to be
/// looking at. A parent following the discus should not be dragged sideways
/// every time the coach walks to the javelin, and a page holding every
/// competition can switch between them without asking for anything.
///
/// Marks are already written the way they were measured — the unit a throw
/// was entered in, through [formatDistance], the one place that is decided
/// — so a sheet reading '191-08' and a board reading '191-08' can never
/// become the same throw in two notations.
Map<String, dynamic> meetFeed(
  Meet meet,
  Iterable<ThrowResult> results, {
  DateTime? at,
  bool Function(ThrowResult result)? isPersonalBest,
}) {
  final held = results.toList();
  return {
    'name': meet.name.isEmpty ? 'Meet' : meet.name,
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
    'competitions': [
      for (final competition in MeetCompetition.of(meet))
        _competition(meet, competition, held, isPersonalBest),
    ],
  };
}

Map<String, dynamic> _competition(
  Meet meet,
  MeetCompetition competition,
  List<ThrowResult> results,
  bool Function(ThrowResult result)? isPersonalBest,
) {
  final standings = MeetStandings(competition, results,
      advancing: meet.advancing, prelimRounds: meet.prelimRounds);
  final flight =
      MeetFlight(competition, rounds: meet.rounds, standings: standings);
  final board = MeetBoard(standings, inTheCircle: flight.inTheCircle);

  return {
    // Stable across polls and across rounds, so the page can keep a
    // spectator on the event they chose while the meet moves underneath.
    'id': '${competition.event.name}:${competition.implementKg}',
    'label': competition.label,
    'event': competition.event.name,
    'rounds': meet.rounds,
    // How many rounds everybody throws before the cut. Equal to 'rounds'
    // in a competition with no cut, which is what makes the last boxes of
    // a card worth graying or not.
    'prelims': meet.prelimRounds,
    'status': flight.label,
    'flight': _flight(flight),
    'cut': {
      'advancing': meet.advancing,
      'has': standings.hasCut,
      'made': standings.cutMade,
      if (standings.cutMark != null)
        'mark': formatDistance(standings.cutMark!, _unitOfMark(standings)),
    },
    'places': [
      for (final place in standings.places)
        _place(meet, competition, place, standings, isPersonalBest),
    ],
    'board': _board(board),
  };
}

/// Where the competition has got to, and the three an infield calls out.
///
/// Names only — the page has no business with entry ids, and a call is read
/// out loud rather than clicked on. Absent where there is no order worth
/// naming anybody in ([MeetFlight.hasOrder]): a competition of one is an
/// athlete taking six throws, and announcing that they are up says nothing.
Map<String, dynamic> _flight(MeetFlight flight) => {
      if (flight.flightLabel.isNotEmpty) 'label': flight.flightLabel,
      'round': flight.round + 1,
      'done': flight.finished,
      'thrown': flight.thrown,
      'fieldSize': flight.fieldSize,
      if (flight.inTheCircle != null) 'up': flight.inTheCircle!.athlete,
      if (flight.onDeck != null) 'onDeck': flight.onDeck!.athlete,
      if (flight.inTheHole != null) 'inTheHole': flight.inTheHole!.athlete,
    };

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
    // Where they come in the throwing order. The places arrive ranked,
    // and the field is read the other way round as the round works down
    // it — one list, sorted twice, rather than the same athletes sent
    // twice over.
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
    if (series.average != null)
      'average': formatDistance(series.average!, unit),
    'fouls': series.fouls,
    'passes': series.passes,
    'series': [
      for (var round = 0; round < meet.rounds; round++)
        _round(place, series, round, isPersonalBest),
    ],
  };
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
/// [MeetBoard] has picked the band and the scale; all that is left is
/// where each line falls across it, which is [MeetBoard.fractionOf]. A
/// mark the band broke off comes through with a fraction outside 0..1 and
/// says which edge it went off, so the drawing can pin it there with an
/// arrow instead of pretending it is on the sector.
Map<String, dynamic> _board(MeetBoard board) => {
      'near': board.near,
      'far': board.far,
      'grid': board.grid,
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
DistanceUnit _unitOfMark(MeetStandings standings) {
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
