import 'dart:ui' show Color;

import '../models/meet.dart';
import '../models/meet_board.dart';
import '../models/throw_event.dart';
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
///
/// [following] is who the person reading it came to watch, by entry id.
/// The app's own screens are read by the coach, so everything they say
/// about 'yours' — the line on the board, the band it is hung on, what is
/// needed to make the final, which flight yours are waiting in — is said
/// about [MeetEntry.tracked]. A spectator handed the link at a ring is
/// there for one athlete, who is usually not the coach's, so the page asks
/// the same questions about theirs instead. The page says nothing new: it
/// says the same sentences about somebody else. Empty is the feed as the
/// coach's own screen reads it, which is what a spectator gets until they
/// have chosen.
///
/// Several of them, because one is not the case worth building for: a
/// parent has two throwing, a club's supporter is watching four, and the
/// coach's own screen has always said 'yours' about a whole roster rather
/// than about one athlete. So it is a set, exactly as [MeetEntry.tracked]
/// is a set, and everything downstream takes them the same way — a line
/// each on the board, ticked down the field, the first of them in the
/// caption.
Map<String, dynamic> competitionFeed(
  Meet meet,
  MeetCompetition competition,
  Iterable<ThrowResult> results, {
  DateTime? at,
  bool Function(ThrowResult result)? isPersonalBest,
  Iterable<String>? following,
}) {
  final held = results.toList();
  // Anybody who has left the field — taken off the meet, or the whole
  // competition entered again — is nobody to follow. They simply come back
  // missing, which is what tells the page to stop asking for them.
  final followed = followedEntries(competition, following);
  final watched = {for (final entry in followed) entry.id};
  bool mine(MeetEntry entry) =>
      watched.isEmpty ? entry.tracked : watched.contains(entry.id);
  final standings = MeetStandings(competition, held,
      advancing: meet.advancing, prelimRounds: meet.prelimRounds);
  final flight =
      MeetFlight(competition, rounds: meet.rounds, standings: standings);
  final board = MeetBoard(standings,
      inTheCircle: flight.inTheCircle, following: followed);


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
    // Half the sector, in degrees. The board is drawn to the real angle
    // for the event — a javelin sector is narrower than a discus one, and
    // a board that drew them alike would be a picture of a wedge rather
    // than of the field in front of somebody.
    'sector': competition.event.sectorHalfAngleDeg,
    // The color this event wears everywhere else in the app, so a spectator
    // who has seen the coach's screen is looking at the same discus.
    'tint': _hex(eventColor(competition.event)),
    'rounds': meet.rounds,
    // How many rounds everybody throws before the cut. Equal to 'rounds' in
    // a competition with no cut, which is what makes the last boxes of a
    // card worth graying or not.
    'prelims': meet.prelimRounds,
    'status': flight.label,
    if (followed.isNotEmpty)
      // Echoed back so the page knows which of the ones it asked for the
      // phone found. Anybody the competition no longer holds is missing
      // from it, and the page drops them rather than following a ghost.
      'following': [
        for (final entry in followed) {'key': entry.id, 'name': entry.athlete},
      ],
    'flight': _flight(competition, flight, standings, mine),
    'cut': {
      'advancing': meet.advancing,
      'has': standings.hasCut,
      'made': standings.cutMade,
      // What the app writes over its own table: the cut as a promise
      // before it is made, and as a fact afterwards.
      'label': standings.cutMade
          ? 'the final'
          : 'top ${meet.advancing} advance',
      if (standings.cutMark != null)
        'mark': formatDistance(standings.cutMark!, _unitOfCut(standings)),
    },
    // What the board's own caption says under it — see [_caption].
    'caption': _caption(flight, standings, mine),
    'places': [
      for (final place in standings.places)
        _place(meet, competition, place, standings, isPersonalBest, mine),
    ],
    'board': _board(board),
  };
}

/// How a competition is named on the wire — the event and the weight it is
/// thrown at, which is exactly what makes it its own contest.
String competitionId(MeetCompetition competition) =>
    '${competition.event.name}:${competition.implementKg}';

/// Who [following] names in this competition, in the order the field is
/// read down. Empty for nobody, and anybody the competition no longer
/// holds is simply left out.
///
/// Entry ids rather than places in the throwing order, which is how
/// everything else about the field is keyed on the wire: the order is
/// redrawn for the final and shifts under every athlete below one entered
/// late, and a spectator who came to watch a daughter must not be quietly
/// handed somebody else's.
///
/// Read by walking the field once against a set rather than by looking
/// each name up in turn, so a link asked for a thousand ids costs the
/// field and not the asking.
List<MeetEntry> followedEntries(
    MeetCompetition competition, Iterable<String>? following) {
  if (following == null) return const [];
  final wanted = following.where((id) => id.isNotEmpty).toSet();
  if (wanted.isEmpty) return const [];
  return [
    for (final entry in competition.entries)
      if (wanted.contains(entry.id)) entry,
  ];
}

/// Where the competition has got to, and the three an infield calls out.
///
/// The calls come through as rows rather than as bare names, because that
/// is what the app's own header puts up: what they are called, who they
/// are, where they stand and what they are standing on. Absent where there
/// is no order worth naming anybody in ([MeetFlight.hasOrder]) — a
/// competition of one is an athlete taking six throws, and announcing that
/// they are up says nothing.
Map<String, dynamic> _flight(MeetCompetition competition, MeetFlight flight,
    MeetStandings standings, bool Function(MeetEntry entry) mine) {
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

  // Whose throw is next, order or no order — the athlete the live card is
  // built around. Their place in the throwing order rather than their id,
  // which is what the field is already keyed by on the wire.
  final up = flight.next;
  final upOrder =
      up == null ? -1 : competition.entries.indexWhere((e) => e.id == up.id);

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
    if (upOrder >= 0) 'upOrder': upOrder,
    // 'Jakob throws in flight 3' — for somebody watching a flight the
    // athletes they are here for are not in yet. [MeetFlight] writes it, so
    // the page and the screen say it in the same words, and asks it about
    // whoever the page is being read for.
    if (flight.laterFor(mine) case final later?) 'elsewhere': later,
  };
}

/// The lines the app prints under its board, in the words and the colors
/// it prints them in.
///
/// Every one of them is a question the competition answers and the browser
/// cannot — what the throw in the circle has to beat, what the coach's own
/// athlete is short of — so they are worked out here, next to the rules
/// they come from, and handed over as sentences. The tone names which of
/// the app's colors each is set in rather than a hex: the page already
/// holds the palette, and a caption that carried its own would be the one
/// place on it spelling a color of its own.
List<Map<String, dynamic>> _caption(MeetFlight flight,
    MeetStandings standings, bool Function(MeetEntry entry) mine) {
  final lines = <Map<String, dynamic>>[];
  final leader = standings.places.isEmpty ? null : standings.places.first;
  final up = flight.inTheCircle;
  final standing = up == null ? null : standings.placeOf(up.id);

  if (up == null || standing == null) {
    // Nobody in the circle: the round is over, or the competition is.
    if (leader != null && leader.best != null) {
      lines.add({
        'text': '${_named(leader.entry)} '
            '${flight.finished ? 'won it on' : 'leads on'} '
            '${formatDistance(leader.best!, _unitOf(leader))}',
        'tone': 'body',
      });
    }
  } else {
    // The calls above have said who is up. This says what the throw has to
    // do, and nothing at all when they are already leading it.
    final toLead = standings.neededFor(up.id, place: 1);
    if (toLead != null) {
      lines.add({
        'text': '${formatDistance(toLead, _unitOf(standing))} takes the lead',
        'tone': 'tint',
      });
    }
  }

  if (!standings.cutMade) {
    for (final place in standings.places) {
      if (!mine(place.entry)) continue;
      final needed = standings.neededToQualify(place.entry.id);
      if (needed == null) continue;
      lines.add({
        'text': '${_named(place.entry)} needs '
            '${formatDistance(needed, _unitOf(place))} to make the final',
        'tone': 'accent',
      });
      break;
    }
  }
  return lines;
}

String _named(MeetEntry entry) =>
    entry.athlete.isEmpty ? 'Unassigned' : entry.athlete;

/// The unit this athlete's competition is being measured in — theirs when
/// they have a mark, meters until they do.
DistanceUnit _unitOf(MeetPlace place) => place.series.bestRound == null
    ? DistanceUnit.meters
    : place.series.unitAt(place.series.bestRound!);

Map<String, dynamic> _place(
  Meet meet,
  MeetCompetition competition,
  MeetPlace place,
  MeetStandings standings,
  bool Function(ThrowResult result)? isPersonalBest,
  bool Function(MeetEntry entry) mine,
) {
  final series = place.series;
  final unit = series.unit;
  final ours = mine(place.entry);
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
    // What the page emphasizes: the coach's own, or the one athlete a
    // spectator chose to follow. Whose the marks are to keep is a separate
    // question and stays where it was.
    'mine': ours,
    'tracked': place.entry.tracked,
    // How a spectator asks to follow them. An id rather than the throwing
    // order — see [followedEntry].
    'key': place.entry.id,
    if (place.entry.flight > 1) 'flight': place.entry.flight,
    'advancing': place.advancing,
    // What grays the last rounds of a card once the cut has been made.
    'throwsInFinal': standings.throwsInFinal(place.entry.id),
    if (place.best != null) 'best': formatDistance(place.best!, unit),
    if (series.bestRound != null) 'bestRound': series.bestRound! + 1,
    if (series.average != null) 'average': formatDistance(series.average!, unit),
    'fouls': series.fouls,
    'passes': series.passes,
    // 'averaging 42.13 m from 2 · 1 foul' — the reader's question rather
    // than the competition's, and only for the athlete they are here for,
    // exactly as the app's own table asks it. A mean of one throw is that
    // throw, which the row already gives.
    if (ours && _consistency(series) != null) 'consistency': _consistency(series),
    // And what they are short of, which is the other line the app's table
    // prints under its own athletes. Only theirs, and only while the cut
    // is still to be made: what the rest of the field needs is not the
    // reader's problem, and once the final is drawn there is nothing left
    // to need.
    if (ours && !standings.cutMade)
      if (standings.neededToQualify(place.entry.id) case final needed?)
        'needed': 'needs ${formatDistance(needed, unit)} to make the final',
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
      // Everybody else in the competition: the spread of the field, drawn
      // with no name on it. Fractions rather than distances, since that is
      // all a faint line needs.
      'others': [for (final at in board.others) board.fractionOf(at)],
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
