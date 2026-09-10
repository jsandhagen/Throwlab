import 'meet.dart';
import 'throw_event.dart';
import 'throw_video.dart';

/// One athlete's competition at one meet, read back off the season.
///
/// A personal best says what an athlete has thrown; it says nothing about
/// the afternoon it came out of. A coach going into a championship wants
/// the other half: how the series ran, where it placed, what the day was
/// like, and whether the big throw came in the first round or the last.
/// That is all in the meets already — this is the reading of it from the
/// athlete's side rather than the competition's.
class MeetOuting {
  const MeetOuting({
    required this.meet,
    required this.entry,
    required this.series,
    required this.place,
    required this.fieldSize,
  });

  final Meet meet;
  final MeetEntry entry;
  final MeetSeries series;

  /// Where they finished, or null when they never got a mark on the board.
  final MeetPlace? place;

  /// How many were in the competition — a win off two is not a win off
  /// twenty, and a place with no field beside it reads like one.
  final int fieldSize;

  ThrowEvent get event => entry.event;
  double get implementKg => entry.implementKg;
  ImplementSpec get implementSpec => entry.implementSpec;
  DateTime get date => meet.date;

  /// The furthest they threw that day, or null for a series of fouls.
  double? get best => series.best;

  /// Which round it came in, from 1 — the number that says whether they
  /// opened big or built into it.
  int? get bestRound => series.bestRound == null ? null : series.bestRound! + 1;

  /// How many attempts they actually took, fouls and passes included.
  int get taken => entry.taken;

  /// How many of those were measured.
  int get legalMarks => series.legalMarks.length;

  /// Whether they won it. A field of one is not a competition, so it is
  /// not a win either.
  bool get won => fieldSize > 1 && place?.place == 1;

  /// Every meet [athlete] has thrown at, most recent first.
  ///
  /// Matched on the athlete tag the way the rest of the app matches it — by
  /// spelling, ignoring case — and including entries the meet holds as part
  /// of the wider field. An athlete who came in off a heat sheet under a
  /// spelling nobody linked is still the person who threw that day; leaving
  /// them out would put a hole in their season without saying so.
  static List<MeetOuting> forAthlete(
    String athlete,
    Iterable<Meet> meets,
    Iterable<ThrowResult> results,
  ) {
    final wanted = athlete.trim().toLowerCase();
    if (wanted.isEmpty) return const [];
    final outings = <MeetOuting>[];
    for (final meet in meets) {
      // Standings are per competition, and worked out once for each one
      // this athlete is in rather than once per entry.
      final standings = <String, MeetStandings>{};
      for (final competition in MeetCompetition.of(meet)) {
        for (final entry in competition.entries) {
          if (entry.athlete.trim().toLowerCase() != wanted) continue;
          final key = '${competition.event.name}:${competition.implementKg}';
          final table = standings.putIfAbsent(
              key,
              () => MeetStandings(competition, results,
                  advancing: meet.advancing, prelimRounds: meet.prelimRounds));
          outings.add(MeetOuting(
            meet: meet,
            entry: entry,
            series: MeetSeries(entry, results),
            place: table.placeOf(entry.id)?.best == null
                ? null
                : table.placeOf(entry.id),
            fieldSize: competition.entries.length,
          ));
        }
      }
    }
    outings.sort((a, b) => b.date.compareTo(a.date));
    return outings;
  }
}

/// What an athlete's meets add up to at one event and implement.
///
/// The numbers a coach quotes without looking them up: how many times out,
/// how many won, and what the season's marks average. Kept off to the side
/// of the outings themselves so a screen can show the tally without walking
/// the list again.
class MeetRecord {
  factory MeetRecord(List<MeetOuting> outings) {
    var wins = 0;
    var podiums = 0;
    var scored = 0;
    var total = 0.0;
    double? best;
    for (final outing in outings) {
      if (outing.won) wins++;
      final place = outing.place?.place;
      if (place != null && place <= 3 && outing.fieldSize > 1) podiums++;
      final mark = outing.best;
      if (mark == null) continue;
      scored++;
      total += mark;
      if (best == null || mark > best) best = mark;
    }
    return MeetRecord._(
      outings: outings.length,
      wins: wins,
      podiums: podiums,
      best: best,
      // Over the meets they got a mark at: a series of three fouls is a
      // competition they were at, not a distance to average in as zero.
      averageBest: scored == 0 ? null : total / scored,
    );
  }

  const MeetRecord._({
    required this.outings,
    required this.wins,
    required this.podiums,
    required this.best,
    required this.averageBest,
  });

  final int outings;
  final int wins;

  /// Top three, in a competition with somebody else in it.
  final int podiums;

  /// The furthest they have thrown at a meet.
  final double? best;

  /// The mean of their best from each meet they got one at.
  final double? averageBest;
}
