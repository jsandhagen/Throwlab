import 'throw_event.dart';
import 'throw_mark.dart';
import 'throw_video.dart';

/// An athlete's furthest measured throw at one event and implement weight.
///
/// The weight is part of what a mark *is*: 17.80 m with the 6 kg shot and
/// 17.80 m with the 7.26 kg are two different achievements, and rolling them
/// together would let a lighter implement quietly erase the record set with
/// the heavy one. It is the same reason a throw is tagged by weight rather
/// than by gender — see [ImplementSpec].
class PersonalBest {
  const PersonalBest({required this.result, required this.attempts});

  /// The throw that holds the mark — filmed or merely written down.
  final ThrowResult result;

  /// The clip it came out of, or null when the throw was never filmed.
  /// What decides whether the mark opens a video or only reads as a row.
  ThrowVideo? get video => result is ThrowVideo ? result as ThrowVideo : null;

  /// Whether there is a clip behind it.
  bool get isFilmed => result is ThrowVideo;

  /// Measured throws the athlete has at this event and weight — the field
  /// the best was picked out of. One means the mark has nothing behind it
  /// yet, which is worth saying rather than hiding.
  final int attempts;

  ThrowEvent get event => result.event;
  double get implementKg => result.implementKg;
  ImplementSpec get implementSpec => event.specFor(implementKg);

  /// Metres. Non-null by construction: a best is only ever built from a
  /// throw that was measured.
  double get distance => result.distance!;

  DistanceUnit get unit => result.distanceUnit;
  DateTime get setOn => result.displayDate;

  /// '7.26 kg Shot Put' — what the mark is at, the way a result list writes
  /// it.
  String get label => '${implementSpec.weightLabel} ${event.label}';
}

/// One athlete, as the library knows them: their throws, and the best mark
/// they have at each thing they throw.
///
/// Derived rather than stored — a profile is a reading of the clips, so
/// re-tagging a throw or typing in a distance changes it with no separate
/// record to keep in step.
class AthleteProfile {
  const AthleteProfile({
    required this.name,
    required this.throws,
    required this.marks,
    required this.bests,
  });

  /// The spelling to show, taken from their most recent throw — the same
  /// rule the athlete picker uses, so "Sam" and "sam" stay one
  /// person here too.
  final String name;

  /// Their filmed throws, newest first.
  final List<ThrowVideo> throws;

  /// Their marks with no clip behind them, newest first. Usually the
  /// competition results — the throws that mattered are rarely the ones
  /// someone had a phone up for.
  final List<ThrowMark> marks;

  /// One entry per event and weight they have a measured throw at, in event
  /// order and heaviest implement first — the order the implement tables
  /// are written in, so a profile reads the same from one visit to the next
  /// rather than reshuffling as marks are added.
  final List<PersonalBest> bests;

  bool get isEmpty => throws.isEmpty && marks.isEmpty;

  /// Everything of theirs a best could come out of, newest first.
  List<ThrowResult> get results => [...throws, ...marks]
    ..sort((a, b) => b.displayDate.compareTo(a.displayDate));

  /// How many of their throws carry a distance. The rest are still clips
  /// worth watching; they just can't be a best.
  int get measured =>
      throws.where((video) => video.distance != null).length + marks.length;

  /// Everything they throw, in event order.
  List<ThrowEvent> get events {
    final seen = {
      for (final video in throws) video.event,
      for (final mark in marks) mark.event,
    };
    return [
      for (final event in ThrowEvent.values)
        if (seen.contains(event)) event,
    ];
  }

  /// Their most recent throw's date, null when they have none.
  DateTime? get lastThrewOn =>
      isEmpty ? null : results.first.displayDate;

  /// Their oldest throw's date, null when they have none.
  DateTime? get firstThrewOn => isEmpty ? null : results.last.displayDate;

  /// Their best at [event] and [implementKg], or null when they have no
  /// measured throw with it.
  PersonalBest? bestAt(ThrowEvent event, double implementKg) {
    for (final best in bests) {
      if (best.event == event && best.implementKg == implementKg) return best;
    }
    return null;
  }

  /// The profile [name] has across [videos] and [marks].
  factory AthleteProfile.of(
    String name,
    List<ThrowVideo> videos, [
    List<ThrowMark> marks = const [],
  ]) {
    final wanted = name.trim().toLowerCase();
    bool mine(ThrowResult result) =>
        result.athlete.trim().toLowerCase() == wanted;
    final clips = [
      for (final video in videos)
        if (mine(video)) video,
    ]..sort((a, b) => b.displayDate.compareTo(a.displayDate));
    final typed = [
      for (final mark in marks)
        if (mine(mark)) mark,
    ]..sort((a, b) => b.displayDate.compareTo(a.displayDate));

    final bests = <PersonalBest>[];
    for (final entry
        in _bestsByImplement([...clips, ...typed]).entries) {
      bests.add(PersonalBest(
          result: entry.value.result, attempts: entry.value.attempts));
    }
    bests.sort((a, b) {
      final byEvent = a.event.index.compareTo(b.event.index);
      return byEvent != 0
          ? byEvent
          : b.implementKg.compareTo(a.implementKg);
    });

    // The most recent throw spells the name; fall back to what was asked
    // for when they have nothing at all.
    final newest = [...clips, ...typed]
      ..sort((a, b) => b.displayDate.compareTo(a.displayDate));
    return AthleteProfile(
      name: newest.isEmpty ? name.trim() : newest.first.athlete.trim(),
      throws: clips,
      marks: typed,
      bests: bests,
    );
  }
}

/// A best under construction: the leader so far, and how many measured
/// throws it has seen off.
class _Standing {
  _Standing(this.result) : attempts = 1;

  ThrowResult result;
  int attempts;
}

/// The ids of every throw that stands as its athlete's personal best.
///
/// Two things keep a throw out: no distance (a clip nobody measured can't be
/// a best), and no athlete. An untagged throw belongs to nobody, and letting
/// "Unassigned" hold records would turn a pile of unrelated clips into one
/// fictional thrower — so those clips wear no medal until someone is put to
/// them.
Set<String> personalBestIds(List<ThrowResult> results) => {
      for (final standing in _bestsByImplement(results).values)
        standing.result.id,
    };

/// The leading throw for each athlete, event and implement weight, keyed so
/// that both the profile and the library's medals read the same rule.
Map<String, _Standing> _bestsByImplement(List<ThrowResult> results) {
  final standings = <String, _Standing>{};
  for (final result in results) {
    final athlete = result.athlete.trim().toLowerCase();
    if (athlete.isEmpty || result.distance == null) continue;
    final key = '$athlete|${result.event.name}|${result.implementKg}';
    final standing = standings[key];
    if (standing == null) {
      standings[key] = _Standing(result);
      continue;
    }
    standing.attempts++;
    if (_outranks(result, standing.result)) standing.result = result;
  }
  return standings;
}

/// Whether [candidate] takes the mark off [holder]. Further wins; on equal
/// marks the one thrown first keeps it, the way a record stands until it is
/// beaten rather than matched. The id settles the case where even the dates
/// are equal, so the medal never moves between two identical throws
/// depending on what order the library happens to be in.
bool _outranks(ThrowResult candidate, ThrowResult holder) {
  final difference = candidate.distance!.compareTo(holder.distance!);
  if (difference != 0) return difference > 0;
  final byDate = candidate.displayDate.compareTo(holder.displayDate);
  if (byDate != 0) return byDate < 0;
  return candidate.id.compareTo(holder.id) < 0;
}
