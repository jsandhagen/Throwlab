import 'throw_event.dart';
import 'throw_video.dart';

/// What became of one attempt.
///
/// A series is not a list of distances: two of the six are usually a foul
/// and a pass, and a coach reads the pattern — three fouls chasing a big
/// one — as much as the best. Dropping them would lose exactly the part of
/// a competition a video is meant to explain.
enum AttemptKind {
  /// Measured and legal. Carries a [MeetAttempt.resultId].
  mark,

  /// Thrown and not measured: over the board, out of the sector, out the
  /// back of the circle.
  foul,

  /// Not thrown. Standard in a final once a place is safe.
  pass,
}

/// One of an athlete's six throws at a meet.
///
/// A measured attempt records nothing about the throw itself — it points at
/// the mark or the clip in the record book, which is where the distance,
/// the implement and the personal best already live. That way a meet can't
/// disagree with the library about how far something went, and a throw
/// filmed here is an ordinary throw everywhere else in the app.
class MeetAttempt {
  MeetAttempt({
    required this.kind,
    this.resultId,
    this.distance,
    this.distanceUnit = DistanceUnit.metres,
  });

  MeetAttempt.mark(String this.resultId)
      : kind = AttemptKind.mark,
        distance = null,
        distanceUnit = DistanceUnit.metres;

  /// A measured throw by someone the record book has no business holding —
  /// see [MeetEntry.tracked]. The number lives on the attempt itself.
  MeetAttempt.untracked(double this.distance,
      {this.distanceUnit = DistanceUnit.metres})
      : kind = AttemptKind.mark,
        resultId = null;

  MeetAttempt.foul()
      : kind = AttemptKind.foul,
        resultId = null,
        distance = null,
        distanceUnit = DistanceUnit.metres;
  MeetAttempt.pass()
      : kind = AttemptKind.pass,
        resultId = null,
        distance = null,
        distanceUnit = DistanceUnit.metres;

  final AttemptKind kind;

  /// The [ThrowMark] or [ThrowVideo] this attempt was recorded as.
  ///
  /// A foul keeps its clip — a throw that sailed out of the sector is
  /// exactly the one a coach wants to watch again — but never a distance:
  /// the clip's own is cleared when the round is called a foul, so a throw
  /// that didn't count can't stand as a personal best.
  final String? resultId;

  /// Metres, for an attempt with no [resultId] behind it. Only a rival's
  /// throw is stored this way; one of the coach's own athletes keeps its
  /// distance in the library, where a personal best can see it.
  final double? distance;

  /// The unit [distance] was entered in, and the one it reads back in.
  final DistanceUnit distanceUnit;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (resultId != null) 'resultId': resultId,
        if (distance != null) 'distance': distance,
        if (distance != null) 'distanceUnit': distanceUnit.name,
      };

  factory MeetAttempt.fromJson(Map<String, dynamic> json) => MeetAttempt(
        kind: AttemptKind.values.asNameMap()[json['kind'] as String? ?? ''] ??
            AttemptKind.foul,
        resultId: json['resultId'] as String?,
        distance: (json['distance'] as num?)?.toDouble(),
        distanceUnit: DistanceUnit.values
                .asNameMap()[json['distanceUnit'] as String? ?? ''] ??
            DistanceUnit.metres,
      );
}

/// One athlete in one event at a meet — a card in the results, and the row
/// a coach taps at.
///
/// An athlete in two events is two entries: the implement differs, the
/// series are separate, and so is the personal best each one is chasing.
class MeetEntry {
  MeetEntry({
    required this.id,
    required this.athlete,
    required this.event,
    required this.implementKg,
    this.tracked = true,
    this.order = 0,
    List<MeetAttempt?>? attempts,
  }) : attempts = attempts ?? [];

  final String id;
  String athlete;
  ThrowEvent event;
  double implementKg;

  /// Whether this is one of the coach's own athletes.
  ///
  /// The rest of the field is worth recording — an athlete is placed
  /// against them, and what it takes to make the final is whatever they
  /// throw — but their marks are not the coach's to keep. An untracked
  /// entry writes nothing to the library: no clip, no mark, no name in the
  /// athlete list, and no chance of a rival's throw turning up as somebody's
  /// personal best. Its distances live on its attempts instead.
  bool tracked;

  /// Where in the flight they throw. The order is drawn before the
  /// competition and drawn again for the final, so it is stored rather
  /// than inferred from the order they were entered in.
  int order;

  /// One slot per round, oldest first, with a null for a round nobody has
  /// entered anything for yet. Shorter than the meet's round count until
  /// the later rounds are thrown, and never with a trailing null — an
  /// empty round at the end is simply absent.
  final List<MeetAttempt?> attempts;

  ImplementSpec get implementSpec => event.specFor(implementKg);

  MeetAttempt? attemptAt(int round) =>
      round >= 0 && round < attempts.length ? attempts[round] : null;

  /// Records (or clears) one round, growing the series to reach it.
  void setAttempt(int round, MeetAttempt? attempt) {
    if (round < 0) return;
    while (attempts.length <= round) {
      attempts.add(null);
    }
    attempts[round] = attempt;
    while (attempts.isNotEmpty && attempts.last == null) {
      attempts.removeLast();
    }
  }

  /// Where the next throw goes when the coach taps the athlete rather than
  /// a particular round. The first gap, so an attempt skipped over and
  /// filled in later doesn't push the series out of order.
  int get nextRound {
    for (var round = 0; round < attempts.length; round++) {
      if (attempts[round] == null) return round;
    }
    return attempts.length;
  }

  /// How many rounds have anything in them at all.
  int get taken => attempts.where((attempt) => attempt != null).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'athlete': athlete,
        'event': event.name,
        'implementKg': implementKg,
        'tracked': tracked,
        'order': order,
        'attempts': [
          for (final attempt in attempts) attempt?.toJson(),
        ],
      };

  factory MeetEntry.fromJson(Map<String, dynamic> json) => MeetEntry(
        id: json['id'] as String,
        athlete: json['athlete'] as String? ?? '',
        event: ThrowEvent.values.byName(json['event'] as String),
        implementKg: (json['implementKg'] as num).toDouble(),
        tracked: json['tracked'] as bool? ?? true,
        order: (json['order'] as num?)?.toInt() ?? 0,
        attempts: [
          for (final raw in (json['attempts'] as List<dynamic>? ?? []))
            raw == null
                ? null
                : MeetAttempt.fromJson(raw as Map<String, dynamic>),
        ],
      );
}

/// A competition: who threw, in what, and what each attempt came to.
///
/// The meet owns none of the throws. It is an order of events over marks
/// and clips that live in the library like any others, so a series entered
/// at the track on Saturday is already in the athlete's record book by the
/// time the coach is home.
class Meet {
  Meet({
    required this.id,
    required this.name,
    required this.date,
    this.rounds = 6,
    int? prelimRounds,
    this.advancing = 8,
    List<MeetEntry>? entries,
  })  : prelimRounds = prelimRounds ?? rounds,
        entries = entries ?? [];

  final String id;

  /// 'County Champs'. What the athlete will call it in a year's time.
  String name;

  /// The day it was thrown. A meet is entered on the day, but a coach
  /// typing up a results sheet afterwards needs to be able to say when.
  DateTime date;

  /// Attempts per athlete. Six is a championship; a school meet or an
  /// early-season open is often three or four, and a series of six boxes
  /// where only three were ever thrown reads as three fouls.
  int rounds;

  /// How many rounds everyone throws before the cut.
  ///
  /// A championship throws three and then gives the leaders three more —
  /// "3 + 3", which is [rounds] 6 and this 3. Equal to [rounds] when the
  /// whole field throws the lot, which is what a meet with no cut is.
  int prelimRounds;

  /// Whether the field is cut part-way: three rounds, then the final.
  bool get hasFinal => prelimRounds < rounds;

  /// How many of a competition go through to the final rounds. Eight is
  /// the usual cut; a small section takes everyone, which is what a number
  /// at or above the field size means here.
  int advancing;

  final List<MeetEntry> entries;

  /// The entries in the order they throw.
  List<MeetEntry> get inOrder {
    final sorted = [...entries];
    // A stable sort, so entries sharing a position keep the order they
    // were added in rather than swapping about between builds.
    final added = {for (var i = 0; i < entries.length; i++) entries[i].id: i};
    sorted.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : added[a.id]!.compareTo(added[b.id]!);
    });
    return sorted;
  }

  MeetEntry? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'date': date.toIso8601String(),
        'rounds': rounds,
        'prelimRounds': prelimRounds,
        'advancing': advancing,
        'entries': [for (final entry in entries) entry.toJson()],
      };

  factory Meet.fromJson(Map<String, dynamic> json) => Meet(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        rounds: (json['rounds'] as num?)?.toInt() ?? 6,
        // A meet stored before the final existed had no cut: everyone
        // entered threw every round of it.
        prelimRounds: (json['prelimRounds'] as num?)?.toInt(),
        advancing: (json['advancing'] as num?)?.toInt() ?? 8,
        entries: [
          for (final raw in (json['entries'] as List<dynamic>? ?? []))
            MeetEntry.fromJson(raw as Map<String, dynamic>),
        ],
      );
}

/// One entry's series read against the record book: the distances behind
/// its measured attempts, and which of them won the competition.
///
/// The lookup is passed in rather than reached for, because the meet screen
/// already holds the library and a series is rebuilt on every change to it
/// — a mark edited from an athlete's profile shows through here without the
/// meet being told about it.
class MeetSeries {
  MeetSeries(this.entry, Iterable<ThrowResult> results)
      : _byId = {for (final result in results) result.id: result};

  final MeetEntry entry;
  final Map<String, ThrowResult> _byId;

  /// The mark or clip recorded for this round, or null when the round was
  /// a foul, a pass, untaken — or when its result has since been deleted
  /// from the library, which leaves the attempt standing with nothing to
  /// show for it.
  ThrowResult? resultAt(int round) {
    final id = entry.attemptAt(round)?.resultId;
    return id == null ? null : _byId[id];
  }

  /// How far the round went, or null when it doesn't count: a foul, a
  /// pass, or a round nobody has entered. Read from the attempt's kind
  /// rather than from the clip, so a filmed foul is a foul even though the
  /// footage of it is still there.
  double? distanceAt(int round) {
    final attempt = entry.attemptAt(round);
    if (attempt == null || attempt.kind != AttemptKind.mark) return null;
    return resultAt(round)?.distance ?? attempt.distance;
  }

  /// What unit the round was measured in — the record's, or the attempt's
  /// own for an athlete the library doesn't hold.
  DistanceUnit unitAt(int round) =>
      resultAt(round)?.distanceUnit ??
      entry.attemptAt(round)?.distanceUnit ??
      DistanceUnit.metres;

  /// Every legal mark of the series, furthest first. This is the series a
  /// competition is placed on: the best decides, and the rest of it breaks
  /// a tie.
  List<double> get legalMarks {
    final marks = <double>[
      for (var round = 0; round < entry.attempts.length; round++)
        if (distanceAt(round) != null) distanceAt(round)!,
    ];
    marks.sort((a, b) => b.compareTo(a));
    return marks;
  }

  /// Whether the round was filmed. A clip is a [ThrowVideo]; a mark typed
  /// in because nobody had the camera up is not.
  bool filmedAt(int round) => resultAt(round) is ThrowVideo;

  /// The furthest legal attempt — the one the athlete is placed on.
  double? get best {
    double? furthest;
    for (var round = 0; round < entry.attempts.length; round++) {
      final distance = distanceAt(round);
      if (distance == null) continue;
      if (furthest == null || distance > furthest) furthest = distance;
    }
    return furthest;
  }

  /// Which round the [best] came in; null when nothing has been measured.
  /// Ties keep the earlier round, the way a competition breaks them.
  int? get bestRound {
    int? which;
    double? furthest;
    for (var round = 0; round < entry.attempts.length; round++) {
      final distance = distanceAt(round);
      if (distance == null) continue;
      if (furthest == null || distance > furthest) {
        furthest = distance;
        which = round;
      }
    }
    return which;
  }
}

/// One competition inside a meet: everyone throwing the same implement.
///
/// A meet is several competitions at once — the discus and the javelin are
/// not the same contest, and neither are the 6 kg and the 4 kg shot. An
/// athlete is placed against the people holding the same implement and
/// nobody else, so this is the unit standings are worked out over.
class MeetCompetition {
  const MeetCompetition(this.event, this.implementKg, this.entries);

  final ThrowEvent event;
  final double implementKg;
  final List<MeetEntry> entries;

  ImplementSpec get implementSpec => event.specFor(implementKg);

  String get label => '${event.label} · ${implementSpec.weightLabel}';

  /// The competitions in a meet, in the order they were first entered.
  static List<MeetCompetition> of(Meet meet) {
    final grouped = <String, List<MeetEntry>>{};
    final keys = <String, (ThrowEvent, double)>{};
    for (final entry in meet.inOrder) {
      final key = '${entry.event.name}:${entry.implementKg}';
      keys[key] = (entry.event, entry.implementKg);
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    return [
      for (final key in grouped.keys)
        MeetCompetition(keys[key]!.$1, keys[key]!.$2, grouped[key]!),
    ];
  }
}

/// One athlete's position in a competition.
class MeetPlace {
  const MeetPlace({
    required this.place,
    required this.entry,
    required this.series,
    required this.advancing,
  });

  /// 1-based, and shared by a genuine tie — two athletes on second means
  /// nobody is third.
  final int place;

  final MeetEntry entry;
  final MeetSeries series;

  /// Whether this place currently goes through to the final rounds.
  final bool advancing;

  double? get best => series.best;
}

/// Where a competition stands: who is winning, who is through to the final,
/// and what it would take to get there.
///
/// Places are worked out the way a competition works them out — the best
/// throw decides, and a tie on it is broken by each athlete's second-best,
/// then third, and so on down the series. That matters at the cut more than
/// anywhere else: two athletes level on 41.20 are separated by what else
/// they threw, not by who is listed first.
class MeetStandings {
  MeetStandings(
    this.competition,
    Iterable<ThrowResult> results, {
    this.advancing = 8,
    this.prelimRounds = 0,
  }) {
    final ranked = [
      for (final entry in competition.entries)
        (entry: entry, series: MeetSeries(entry, results)),
    ]..sort((a, b) => _compare(a.series, b.series));

    var place = 0;
    for (var i = 0; i < ranked.length; i++) {
      // A tie shares a place, and the next one down skips the numbers the
      // tie used up.
      if (i == 0 || _compare(ranked[i - 1].series, ranked[i].series) != 0) {
        place = i + 1;
      }
      places.add(MeetPlace(
        place: place,
        entry: ranked[i].entry,
        series: ranked[i].series,
        // Everyone level with the last qualifying place goes through with
        // it: a tie is not broken by cutting one of them.
        advancing: place <= advancing && ranked[i].series.best != null,
      ));
    }
  }

  final MeetCompetition competition;

  /// How many go through. The cut only exists when more than this many are
  /// entered.
  final int advancing;

  /// How many rounds are thrown before the cut; 0 in a competition that
  /// doesn't have one.
  final int prelimRounds;

  final List<MeetPlace> places = [];

  /// Whether anybody is going to be left out.
  bool get hasCut => places.length > advancing;

  /// Whether the cut has actually happened, rather than being where the
  /// field would be cut if it stopped now.
  ///
  /// It takes everyone having had their three: an athlete sitting ninth
  /// with a round in hand is not out, and closing their last rounds while
  /// they still have one to throw would be wrong.
  bool get cutMade =>
      hasCut &&
      prelimRounds > 0 &&
      competition.entries.every((entry) => entry.taken >= prelimRounds);

  /// Whether this athlete still has throws coming. Everyone does until the
  /// cut is made; after it, only the athletes who went through.
  bool throwsInFinal(String entryId) =>
      !cutMade || (placeOf(entryId)?.advancing ?? false);

  MeetPlace? placeOf(String entryId) {
    for (final place in places) {
      if (place.entry.id == entryId) return place;
    }
    return null;
  }

  /// The mark currently holding the last qualifying place — what a throw
  /// has to beat to make the final.
  double? get cutMark {
    double? last;
    for (final place in places) {
      if (!place.advancing) break;
      last = place.best ?? last;
    }
    return last;
  }

  /// What [entryId] has to throw to reach [place].
  ///
  /// A centimetre past whoever is standing there, because a competition is
  /// measured to the centimetre and equalling a mark does not overtake it —
  /// it goes to a countback the athlete behind has already lost. Null when
  /// the place is empty or already theirs: any legal throw will do.
  double? neededFor(String entryId, {required int place}) {
    final mine = placeOf(entryId);
    if (mine == null || mine.place <= place) return null;
    double? target;
    for (final other in places) {
      if (other.entry.id == entryId) continue;
      if (other.place <= place) target = other.best ?? target;
    }
    if (target == null) return null;
    return target + 0.01;
  }

  /// What [entryId] has to throw to make the final, or null when they are
  /// already through — or when nobody is being cut.
  double? neededToQualify(String entryId) {
    if (!hasCut) return null;
    final mine = placeOf(entryId);
    if (mine == null || mine.advancing) return null;
    return neededFor(entryId, place: advancing);
  }

  /// The order the final is thrown in: the qualifiers, worst-placed first,
  /// which is how a competition draws it — the leader throws last.
  List<MeetEntry> get finalOrder => [
        for (final place in places.reversed)
          if (place.advancing) place.entry,
      ];

  /// Ranks two series against each other: best mark first, then down the
  /// series a mark at a time. Fewer marks loses a tie it can't answer.
  static int _compare(MeetSeries a, MeetSeries b) {
    final mine = a.legalMarks;
    final theirs = b.legalMarks;
    final depth = mine.length > theirs.length ? mine.length : theirs.length;
    for (var i = 0; i < depth; i++) {
      if (i >= mine.length) return 1;
      if (i >= theirs.length) return -1;
      if (mine[i] != theirs[i]) return theirs[i].compareTo(mine[i]);
    }
    return 0;
  }
}
