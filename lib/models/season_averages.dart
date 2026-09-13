import 'meet_history.dart';
import 'throw_event.dart';
import 'throw_video.dart';

/// What one meet is worth on the line a season is drawn as.
///
/// A season reads two ways and a coach wants both. The average of a series
/// is how the whole afternoon went; the best of it is what the afternoon
/// was scored on. An athlete whose averages climb while their bests stand
/// still is closing on something, and one whose bests hold up on a falling
/// average is living off one throw a day — neither shows on the other's
/// line.
enum MeetLine {
  /// Every measured attempt of the series, averaged.
  average,

  /// The furthest of them: the throw the placing was made on.
  best,
}

/// What one meet came to, on the line being drawn. Null for a competition
/// with nothing measured — a series of fouls is not a nought.
double? meetValue(MeetOuting meet, MeetLine line) =>
    line == MeetLine.average ? meet.average : meet.best;

/// What a season of competitions averages, at one event and implement.
///
/// A personal best is the one throw that came off, and a season is
/// remembered by it — but it is also the throw an athlete has least control
/// over. What they control is the other five: where the middle of a series
/// sits, and how much of it lands in the sector at all. Those move before a
/// best does, and they move back down again when something is wrong, which
/// is why a coach reads them and not only the high-water line.
///
/// Meets only. Training is thrown under conditions nobody is recording —
/// a light implement, a short run, a good day at the end of a session — and
/// a number built out of it answers a question about Saturday with
/// Tuesday's throwing. What an athlete does in training is on the
/// progression under their best, where every measured throw is drawn
/// against the calendar; this is about competitions.
///
/// Two averages, because a competition can be read two ways — see
/// [MeetLine] — and the fouls sit beside both: an average is only worth
/// what it was taken over, and a series averaging 60 off two marks and
/// four fouls is not a good afternoon.
///
/// Per weight for the same reason a personal best is: 17.80 m with the 6 kg
/// and 17.80 m with the 7.26 kg are not one number, and an average that
/// rolled them together would move every time the training implement
/// changed.
class SeasonAverages {
  const SeasonAverages._({
    required this.season,
    required this.event,
    required this.implementKg,
    required this.meets,
    required this.averageBest,
    required this.meetsScored,
    required this.averageMark,
    required this.marks,
    required this.best,
    required this.bestOn,
    required this.fouls,
    required this.passes,
    required this.attempts,
    required this.unit,
  });

  /// The year this is over, or null for every season on record.
  final int? season;

  final ThrowEvent event;
  final double implementKg;

  ImplementSpec get implementSpec => event.specFor(implementKg);

  /// 'Discus · 1 kg' — the way a competition names itself, which is what
  /// these are read off. A best is written the other way round ('1 kg
  /// Discus') because it is a mark in a record book rather than a contest,
  /// and the two sitting one under the other on a profile should not read
  /// as the same row twice.
  String get label => '${event.label} · ${implementSpec.weightLabel}';

  /// Every meet at this event and weight, oldest first — the season in the
  /// direction it was thrown, which is the direction a chart of it reads.
  final List<MeetOuting> meets;

  /// The mean of the best they took from each meet they got a mark at:
  /// the level competed at.
  final double? averageBest;

  /// How many meets that was over. A meet where everything fouled was a
  /// meet they were at, not an average of zero.
  final int meetsScored;

  /// The mean of every measured attempt at those meets: how reliably that
  /// level is reached.
  final double? averageMark;

  /// How many attempts that was over.
  final int marks;

  /// The furthest they threw at a meet all season, and the day of it.
  final double? best;
  final DateTime? bestOn;

  /// Attempts fouled, and attempts passed up.
  final int fouls;
  final int passes;

  /// Attempts taken, fouls and passes in.
  final int attempts;

  /// What share of the attempts were fouled, from 0 — null before anything
  /// has been thrown.
  double? get foulRate => attempts == 0 ? null : fouls / attempts;

  /// The unit to write these in: the one their most recent competition was
  /// measured in, since an average of marks called in feet belongs in feet.
  final DistanceUnit unit;

  /// The figure for one reading of a season — see [MeetLine].
  double? on(MeetLine line) =>
      line == MeetLine.average ? averageMark : averageBest;

  /// Whether there is a mean here worth the name.
  ///
  /// Two throws, at the least. One is a measurement: its average is the
  /// throw itself, printed a second time under a heading that promises a
  /// season and a card that promises a trend.
  bool get hasAverage => marks > 1;

  /// Whether there is anything here worth drawing.
  bool get isEmpty => !hasAverage;

  /// The meets that left a mark behind, oldest first — the line a chart of
  /// the season is drawn through. The same meets whichever way it is read:
  /// a series with an average has a best, and one without has neither.
  List<MeetOuting> get scoredMeets => [
        for (final meet in meets)
          if (meet.average != null) meet,
      ];

  /// What the season moved, first meet to last, read the given way.
  ///
  /// Measured between the meets themselves rather than against the best of
  /// them, for the reason a progression is: a best only ever goes up, so
  /// anything measured off it draws every athlete as improving.
  double? movement(MeetLine line) {
    final scored = scoredMeets;
    if (scored.length < 2) return null;
    return meetValue(scored.last, line)! - meetValue(scored.first, line)!;
  }

  /// The seasons there is a competition on record for, most recent first.
  ///
  /// A season is a calendar year here, which is a simplification and an
  /// honest one for an outdoor season: it starts in the spring and is over
  /// by the autumn, so a year holds exactly one of them. The indoor winter
  /// is the case it does not fit — December and February are one season and
  /// two years — and when that is worth splitting properly this is the one
  /// place that has to learn about it.
  ///
  /// Fewer than two and there is nothing to split: an athlete with one
  /// season on record has no second one to be told apart from, and should
  /// not be asked to choose between a year and itself.
  static List<int> seasonsOf(Iterable<MeetOuting> outings) {
    final years = <int>{
      for (final outing in outings) outing.date.toLocal().year,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// The same reading taken one season at a time, most recent first.
  ///
  /// An average is read against the one before it, and the picker's whole
  /// job is to keep the seasons from being blended — so the comparison has
  /// to be handed over as a list of them rather than as a career. Only the
  /// seasons this event and weight was thrown in: a discus average has
  /// nothing to say about a winter somebody spent on the shot.
  static List<SeasonAverages> history(
    Iterable<MeetOuting> outings,
    ThrowEvent event,
    double implementKg,
  ) =>
      [
        for (final season in seasonsOf(outings))
          for (final reading in forSeason(outings, season: season))
            if (reading.event == event && reading.implementKg == implementKg)
              reading,
      ];

  /// One reading per event and weight they have competed at, in the order
  /// their bests are listed in — event order, heaviest implement first — so
  /// the averages line up with the marks above them.
  ///
  /// [season] narrows it to one year, and null is every season there has
  /// ever been. An average over a career says what an athlete has been
  /// rather than what they are — two seasons ago pulls this spring's number
  /// down, and a coach reading it in June is asking about this spring.
  static List<SeasonAverages> forSeason(
    Iterable<MeetOuting> outings, {
    int? season,
  }) {
    final kinds = <String, (ThrowEvent, double)>{};
    final byMeet = <String, List<MeetOuting>>{};
    for (final outing in outings) {
      if (season != null && outing.date.toLocal().year != season) continue;
      final key = '${outing.event.name}:${outing.implementKg}';
      kinds[key] = (outing.event, outing.implementKg);
      byMeet.putIfAbsent(key, () => []).add(outing);
    }
    final all = [
      for (final kind in kinds.entries)
        SeasonAverages._read(
            season, kind.value.$1, kind.value.$2, byMeet[kind.key]!),
    ];
    all.sort((a, b) {
      final byEvent = a.event.index.compareTo(b.event.index);
      return byEvent != 0 ? byEvent : b.implementKg.compareTo(a.implementKg);
    });
    return all;
  }

  static SeasonAverages _read(
    int? season,
    ThrowEvent event,
    double implementKg,
    List<MeetOuting> outings,
  ) {
    final meets = [...outings]..sort((a, b) => a.date.compareTo(b.date));
    var bestTotal = 0.0;
    var scored = 0;
    var markTotal = 0.0;
    var marks = 0;
    var fouls = 0;
    var passes = 0;
    var attempts = 0;
    double? furthest;
    DateTime? furthestOn;
    for (final meet in meets) {
      attempts += meet.taken;
      fouls += meet.fouls;
      passes += meet.series.passes;
      final best = meet.best;
      if (best != null) {
        bestTotal += best;
        scored++;
        if (furthest == null || best > furthest) {
          furthest = best;
          furthestOn = meet.date;
        }
      }
      for (final mark in meet.series.legalMarks) {
        markTotal += mark;
        marks++;
      }
    }

    return SeasonAverages._(
      season: season,
      event: event,
      implementKg: implementKg,
      meets: meets,
      averageBest: scored == 0 ? null : bestTotal / scored,
      meetsScored: scored,
      averageMark: marks == 0 ? null : markTotal / marks,
      marks: marks,
      best: furthest,
      bestOn: furthestOn,
      fouls: fouls,
      passes: passes,
      attempts: attempts,
      // The most recent competition spells the unit: a meet measured in
      // feet is written back in feet, averages and all.
      unit: meets.isEmpty ? DistanceUnit.meters : meets.last.unit,
    );
  }
}
