import 'throw_event.dart';
import 'throw_video.dart';

/// An athlete's furthest measured throw at one event and implement weight.
///
/// The weight is part of what a mark *is*: 17.80 m with the 6 kg shot and
/// 17.80 m with the 7.26 kg are two different achievements, and rolling them
/// together would let a lighter implement quietly erase the record set with
/// the heavy one. It is the same reason a throw is tagged by weight rather
/// than by gender — see [ImplementSpec].
class PersonalBest {
  const PersonalBest({required this.video, required this.attempts});

  /// The throw that holds the mark.
  final ThrowVideo video;

  /// Measured throws the athlete has at this event and weight — the field
  /// the best was picked out of. One means the mark has nothing behind it
  /// yet, which is worth saying rather than hiding.
  final int attempts;

  ThrowEvent get event => video.event;
  double get implementKg => video.implementKg;
  ImplementSpec get implementSpec => video.implementSpec;

  /// Metres. Non-null by construction: a best is only ever built from a
  /// throw that was measured.
  double get distance => video.distance!;

  DistanceUnit get unit => video.distanceUnit;
  DateTime get setOn => video.displayDate;

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
    required this.bests,
  });

  /// The spelling to show, taken from their most recent throw — the same
  /// rule the athlete picker uses, so "Sam" and "sam" stay one
  /// person here too.
  final String name;

  /// Their throws, newest first.
  final List<ThrowVideo> throws;

  /// One entry per event and weight they have a measured throw at, in event
  /// order and heaviest implement first — the order the implement tables
  /// are written in, so a profile reads the same from one visit to the next
  /// rather than reshuffling as marks are added.
  final List<PersonalBest> bests;

  bool get isEmpty => throws.isEmpty;

  /// How many of their throws carry a distance. The rest are still clips
  /// worth watching; they just can't be a best.
  int get measured => throws.where((video) => video.distance != null).length;

  /// Everything they throw, in event order.
  List<ThrowEvent> get events {
    final seen = {for (final video in throws) video.event};
    return [
      for (final event in ThrowEvent.values)
        if (seen.contains(event)) event,
    ];
  }

  /// Their most recent throw's date, null when they have none.
  DateTime? get lastThrewOn =>
      throws.isEmpty ? null : throws.first.displayDate;

  /// Their oldest throw's date, null when they have none.
  DateTime? get firstThrewOn => throws.isEmpty ? null : throws.last.displayDate;

  /// Their best at [event] and [implementKg], or null when they have no
  /// measured throw with it.
  PersonalBest? bestAt(ThrowEvent event, double implementKg) {
    for (final best in bests) {
      if (best.event == event && best.implementKg == implementKg) return best;
    }
    return null;
  }

  /// The profile [name] has across [videos].
  factory AthleteProfile.of(String name, List<ThrowVideo> videos) {
    final wanted = name.trim().toLowerCase();
    final mine = [
      for (final video in videos)
        if (video.athlete.trim().toLowerCase() == wanted) video,
    ]..sort((a, b) => b.displayDate.compareTo(a.displayDate));

    final bests = <PersonalBest>[];
    for (final entry in _bestsByImplement(mine).entries) {
      bests.add(PersonalBest(
          video: entry.value.video, attempts: entry.value.attempts));
    }
    bests.sort((a, b) {
      final byEvent = a.event.index.compareTo(b.event.index);
      return byEvent != 0
          ? byEvent
          : b.implementKg.compareTo(a.implementKg);
    });

    return AthleteProfile(
      // The most recent throw spells the name; fall back to what was asked
      // for when they have no throws at all.
      name: mine.isEmpty ? name.trim() : mine.first.athlete.trim(),
      throws: mine,
      bests: bests,
    );
  }
}

/// A best under construction: the leader so far, and how many measured
/// throws it has seen off.
class _Standing {
  _Standing(this.video) : attempts = 1;

  ThrowVideo video;
  int attempts;
}

/// The ids of every throw that stands as its athlete's personal best.
///
/// Two things keep a throw out: no distance (a clip nobody measured can't be
/// a best), and no athlete. An untagged throw belongs to nobody, and letting
/// "Unassigned" hold records would turn a pile of unrelated clips into one
/// fictional thrower — so those clips wear no medal until someone is put to
/// them.
Set<String> personalBestIds(List<ThrowVideo> videos) => {
      for (final standing in _bestsByImplement(videos).values)
        standing.video.id,
    };

/// The leading throw for each athlete, event and implement weight, keyed so
/// that both the profile and the library's medals read the same rule.
Map<String, _Standing> _bestsByImplement(List<ThrowVideo> videos) {
  final standings = <String, _Standing>{};
  for (final video in videos) {
    final athlete = video.athlete.trim().toLowerCase();
    if (athlete.isEmpty || video.distance == null) continue;
    final key = '$athlete|${video.event.name}|${video.implementKg}';
    final standing = standings[key];
    if (standing == null) {
      standings[key] = _Standing(video);
      continue;
    }
    standing.attempts++;
    if (_outranks(video, standing.video)) standing.video = video;
  }
  return standings;
}

/// Whether [candidate] takes the mark off [holder]. Further wins; on equal
/// marks the one thrown first keeps it, the way a record stands until it is
/// beaten rather than matched. The id settles the case where even the dates
/// are equal, so the medal never moves between two identical throws
/// depending on what order the library happens to be in.
bool _outranks(ThrowVideo candidate, ThrowVideo holder) {
  final difference = candidate.distance!.compareTo(holder.distance!);
  if (difference != 0) return difference > 0;
  final byDate = candidate.displayDate.compareTo(holder.displayDate);
  if (byDate != 0) return byDate < 0;
  return candidate.id.compareTo(holder.id) < 0;
}
