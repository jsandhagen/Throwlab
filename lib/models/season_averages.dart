import 'meet_history.dart';
import 'throw_event.dart';
import 'throw_video.dart';

/// What a season averages, at one event and implement weight.
///
/// A personal best is the one throw that came off, and a season is
/// remembered by it — but it is also the throw an athlete has least control
/// over. What they control is the other five: where the middle of a series
/// sits, and how much of it lands in the sector at all. Those move before a
/// best does, and they move back down again when something is wrong, which
/// is why a coach reads them and not only the high-water line.
///
/// Three averages, because a coach asks three different questions. The mean
/// of each meet's best is the level competed at. The mean of every measured
/// attempt at those meets is how reliably that level is reached. The mean
/// of everything measured, training included, is the season as the record
/// book holds it. The fouls sit beside all three: an average is only worth
/// what it was taken over, and a series averaging 60 off two marks and four
/// fouls is not a good afternoon.
///
/// Per weight for the same reason a personal best is: 17.80 m
/// with the 6 kg and 17.80 m with the 7.26 kg are not one number, and an
/// average that rolled them together would move every time the training
/// implement changed.
class SeasonAverages {
  const SeasonAverages._({
    required this.event,
    required this.implementKg,
    required this.meets,
    required this.averageBest,
    required this.meetsScored,
    required this.averageMeetMark,
    required this.meetMarks,
    required this.averageEveryMark,
    required this.everyMarks,
    required this.fouls,
    required this.attempts,
    required this.unit,
  });

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

  /// The mean of the best they took from each meet they got a mark at.
  final double? averageBest;

  /// How many meets that was over. A meet where everything fouled was a
  /// meet they were at, not an average of zero.
  final int meetsScored;

  /// The mean of every measured attempt at those meets.
  final double? averageMeetMark;

  /// How many attempts that was over.
  final int meetMarks;

  /// The mean of every measured throw of the season, training included —
  /// the whole record book at this event and weight.
  final double? averageEveryMark;

  /// How many throws that was over.
  final int everyMarks;

  /// Attempts fouled at a meet.
  final int fouls;

  /// Attempts taken at a meet, fouls and passes in.
  final int attempts;

  /// What share of the attempts were fouled, from 0 — null before anything
  /// has been thrown.
  double? get foulRate => attempts == 0 ? null : fouls / attempts;

  /// The unit to write these in: the one their most recent throw was
  /// measured in, since an average of marks called in feet belongs in feet.
  final DistanceUnit unit;

  /// Whether there is a mean here worth the name.
  ///
  /// Two throws, at the least. One is a measurement: its average is the
  /// throw itself, printed a second time under a heading that promises a
  /// season and a card that promises a trend.
  bool get hasAverage => everyMarks > 1 || meetMarks > 1 || meetsScored > 1;

  /// Whether there is anything here worth drawing.
  bool get isEmpty => !hasAverage;

  /// Whether the record book holds throws the meets don't — training marks,
  /// which is what makes [averageEveryMark] a second number rather than the
  /// same one again.
  bool get hasTraining => everyMarks > meetMarks;

  /// What the meet average has done over the season, first meet to last.
  ///
  /// Measured between the marks themselves rather than against the best,
  /// for the reason a progression is: a best only ever goes up, so anything
  /// measured off it draws every athlete as improving.
  double? get moved {
    final scored = [
      for (final meet in meets)
        if (meet.average != null) meet.average!,
    ];
    return scored.length < 2 ? null : scored.last - scored.first;
  }

  /// The meets that left an average behind, oldest first — the line a chart
  /// of the season is drawn through.
  List<MeetOuting> get scoredMeets => [
        for (final meet in meets)
          if (meet.average != null) meet,
      ];

  /// One reading per event and weight the athlete has thrown, in the order
  /// their bests are listed in — event order, heaviest implement first — so
  /// the averages line up with the marks above them.
  ///
  /// [outings] are their meets and [results] their record book; an athlete
  /// can have either without the other. Somebody who came in off a heat
  /// sheet untracked has competitions and no marks, and somebody who has
  /// only ever thrown on a Tuesday has marks and no competitions.
  static List<SeasonAverages> forSeason(
    Iterable<MeetOuting> outings,
    Iterable<ThrowResult> results,
  ) {
    String keyOf(ThrowEvent event, double implementKg) =>
        '${event.name}:$implementKg';
    final kinds = <String, (ThrowEvent, double)>{};
    final byMeet = <String, List<MeetOuting>>{};
    final byMark = <String, List<ThrowResult>>{};
    for (final outing in outings) {
      final key = keyOf(outing.event, outing.implementKg);
      kinds[key] = (outing.event, outing.implementKg);
      byMeet.putIfAbsent(key, () => []).add(outing);
    }
    for (final result in results) {
      if (result.distance == null) continue;
      final key = keyOf(result.event, result.implementKg);
      kinds[key] = (result.event, result.implementKg);
      byMark.putIfAbsent(key, () => []).add(result);
    }
    final all = [
      for (final kind in kinds.entries)
        SeasonAverages._read(
          kind.value.$1,
          kind.value.$2,
          byMeet[kind.key] ?? const [],
          byMark[kind.key] ?? const [],
        ),
    ];
    all.sort((a, b) {
      final byEvent = a.event.index.compareTo(b.event.index);
      return byEvent != 0 ? byEvent : b.implementKg.compareTo(a.implementKg);
    });
    return all;
  }

  static SeasonAverages _read(
    ThrowEvent event,
    double implementKg,
    List<MeetOuting> outings,
    List<ThrowResult> results,
  ) {
    final meets = [...outings]..sort((a, b) => a.date.compareTo(b.date));
    var bestTotal = 0.0;
    var scored = 0;
    var markTotal = 0.0;
    var marks = 0;
    var fouls = 0;
    var attempts = 0;
    for (final meet in meets) {
      attempts += meet.taken;
      fouls += meet.fouls;
      final best = meet.best;
      if (best != null) {
        bestTotal += best;
        scored++;
      }
      for (final mark in meet.series.legalMarks) {
        markTotal += mark;
        marks++;
      }
    }

    final measured = [...results]
      ..sort((a, b) => a.displayDate.compareTo(b.displayDate));
    var everyTotal = 0.0;
    for (final result in measured) {
      everyTotal += result.distance!;
    }

    return SeasonAverages._(
      event: event,
      implementKg: implementKg,
      meets: meets,
      averageBest: scored == 0 ? null : bestTotal / scored,
      meetsScored: scored,
      averageMeetMark: marks == 0 ? null : markTotal / marks,
      meetMarks: marks,
      averageEveryMark:
          measured.isEmpty ? null : everyTotal / measured.length,
      everyMarks: measured.length,
      fouls: fouls,
      attempts: attempts,
      // The newest throw spells the unit, the way the newest throw spells
      // an athlete's name. A rival's series is the fallback: an untracked
      // entry leaves nothing in the record book to read one off.
      unit: measured.isNotEmpty
          ? measured.last.distanceUnit
          : (meets.isEmpty ? DistanceUnit.meters : meets.last.unit),
    );
  }
}
