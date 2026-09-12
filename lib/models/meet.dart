import 'meet_conditions.dart';
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
    this.distanceUnit = DistanceUnit.meters,
  });

  MeetAttempt.mark(String this.resultId)
      : kind = AttemptKind.mark,
        distance = null,
        distanceUnit = DistanceUnit.meters;

  /// A measured throw by someone the record book has no business holding —
  /// see [MeetEntry.tracked]. The number lives on the attempt itself.
  MeetAttempt.untracked(double this.distance,
      {this.distanceUnit = DistanceUnit.meters})
      : kind = AttemptKind.mark,
        resultId = null;

  MeetAttempt.foul()
      : kind = AttemptKind.foul,
        resultId = null,
        distance = null,
        distanceUnit = DistanceUnit.meters;
  MeetAttempt.pass()
      : kind = AttemptKind.pass,
        resultId = null,
        distance = null,
        distanceUnit = DistanceUnit.meters;

  final AttemptKind kind;

  /// The [ThrowMark] or [ThrowVideo] this attempt was recorded as.
  ///
  /// A foul keeps its clip — a throw that sailed out of the sector is
  /// exactly the one a coach wants to watch again — but never a distance:
  /// the clip's own is cleared when the round is called a foul, so a throw
  /// that didn't count can't stand as a personal best.
  final String? resultId;

  /// Meters, for an attempt with no [resultId] behind it. Only a rival's
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
            DistanceUnit.meters,
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
    int flight = 1,
    List<MeetAttempt?>? attempts,
  })  : flight = flight < 1 ? 1 : flight,
        attempts = attempts ?? [];

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

  /// Which flight they throw in, from 1.
  ///
  /// A big field is not thrown in one order. Thirty shot putters are split
  /// into flights of a dozen, and each flight throws its prelims right
  /// through before the next one walks in — so a coach whose athlete is in
  /// flight 3 has an hour to wait, and the app has no business calling
  /// them into the circle.
  ///
  /// One flight is the ordinary case, and a competition where nobody says
  /// otherwise is simply not flighted. The cut dissolves them: a final is
  /// thrown by the qualifiers as one group, whichever flight they came
  /// through, which is why nothing here survives into it.
  int flight;

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
        // Left off a competition thrown in one order, which is most of
        // them — and read back as flight 1 either way.
        if (flight > 1) 'flight': flight,
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
        flight: (json['flight'] as num?)?.toInt() ?? 1,
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
    this.venue = '',
    this.rounds = 6,
    int? prelimRounds,
    this.advancing = 8,
    this.conditions = const MeetConditions(),
    List<MeetEntry>? entries,
  })  : prelimRounds = prelimRounds ?? rounds,
        entries = entries ?? [];

  final String id;

  /// 'County Champs'. What the athlete will call it in a year's time.
  String name;

  /// The day it was thrown. A meet is entered on the day, but a coach
  /// typing up a results sheet afterwards needs to be able to say when.
  DateTime date;

  /// Where it is — 'Sportcity' or 'Hayward Field'. Empty for a meet nobody
  /// bothered to say, which is most of them when the coach is standing at
  /// it. A fixture list is the one place it matters: a season read off a
  /// schedule in September is a list of names, dates and car parks.
  String venue;

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

  /// What the day was like. Empty for a meet nobody wrote it down at, which
  /// is the default — the weather is worth recording, not worth demanding
  /// before a competition can be started.
  MeetConditions conditions;

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
        if (venue.isNotEmpty) 'venue': venue,
        'rounds': rounds,
        'prelimRounds': prelimRounds,
        'advancing': advancing,
        if (conditions.isNotEmpty) 'conditions': conditions.toJson(),
        'entries': [for (final entry in entries) entry.toJson()],
      };

  factory Meet.fromJson(Map<String, dynamic> json) => Meet(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        venue: json['venue'] as String? ?? '',
        rounds: (json['rounds'] as num?)?.toInt() ?? 6,
        // A meet stored before the final existed had no cut: everyone
        // entered threw every round of it.
        prelimRounds: (json['prelimRounds'] as num?)?.toInt(),
        advancing: (json['advancing'] as num?)?.toInt() ?? 8,
        conditions: json['conditions'] == null
            ? const MeetConditions()
            : MeetConditions.fromJson(
                json['conditions'] as Map<String, dynamic>),
        entries: [
          for (final raw in (json['entries'] as List<dynamic>? ?? []))
            MeetEntry.fromJson(raw as Map<String, dynamic>),
        ],
      );
}

/// The season split the way a coach reads it: what is on today, what is
/// coming, and what has been thrown.
///
/// A list of meets newest-first is a record of a season, which is the
/// wrong way round for planning one — the next fixture is the one being
/// asked about, and it sits at the bottom of that list under everything
/// that has already happened. So the future comes first here, and it runs
/// forwards.
class MeetSeason {
  MeetSeason(List<Meet> meets, {DateTime? today})
      : today = [],
        upcoming = [],
        past = [] {
    final now = _startOfDay(today ?? DateTime.now());
    for (final meet in meets) {
      final day = _startOfDay(meet.date.toLocal());
      if (day == now) {
        this.today.add(meet);
      } else if (day.isAfter(now)) {
        upcoming.add(meet);
      } else {
        past.add(meet);
      }
    }
    // Forwards through what is coming, backwards through what is done: both
    // run away from today, which is where the coach is standing.
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    past.sort((a, b) => b.date.compareTo(a.date));
  }

  /// The meet being thrown right now, if there is one.
  final List<Meet> today;

  /// Still to come, soonest first.
  final List<Meet> upcoming;

  /// Already thrown, most recent first.
  final List<Meet> past;

  bool get isEmpty => today.isEmpty && upcoming.isEmpty && past.isEmpty;
}

DateTime _startOfDay(DateTime when) =>
    DateTime(when.year, when.month, when.day);

/// Whole days from today to [date]: 0 for a meet on today, negative for one
/// already thrown. Counted between the days rather than by the hours, so a
/// meet at nine tomorrow morning is one day off at any time tonight.
int daysUntil(DateTime date, {DateTime? now}) => _startOfDay(date.toLocal())
    .difference(_startOfDay((now ?? DateTime.now()).toLocal()))
    .inDays;

/// How far off a meet is, as a coach would say it: 'tomorrow', 'in 5 days',
/// 'in 3 weeks'. Null for today and for anything already thrown, which the
/// season says by which heading it puts them under.
///
/// Also null for anything further off than a couple of months. 'In 34
/// weeks' is not something anybody counts, and next spring's fixtures are
/// read by their dates — the countdown is for the meets close enough to be
/// packing for.
String? countdownTo(DateTime date, {DateTime? now}) {
  final days = daysUntil(date, now: now);
  if (days <= 0 || days > 60) return null;
  if (days == 1) return 'tomorrow';
  if (days < 14) return 'in $days days';
  return 'in ${(days / 7).round()} weeks';
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
      DistanceUnit.meters;

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

  /// What the series averaged, over the throws that were measured.
  ///
  /// A foul is not a nought. It is a throw that went unmeasured, and
  /// averaging it in as zero would say an athlete who fouled twice threw
  /// half as far as they did — so it is counted in [fouls] instead, which
  /// is the honest way to carry it. The two are read together: an average
  /// off four marks and an average off six are different afternoons.
  double? get average {
    final marks = legalMarks;
    if (marks.isEmpty) return null;
    var total = 0.0;
    for (final mark in marks) {
      total += mark;
    }
    return total / marks.length;
  }

  /// How many rounds were thrown and not measured.
  int get fouls => _rounds(AttemptKind.foul);

  /// How many were passed up.
  int get passes => _rounds(AttemptKind.pass);

  int _rounds(AttemptKind kind) {
    var count = 0;
    for (final attempt in entry.attempts) {
      if (attempt?.kind == kind) count++;
    }
    return count;
  }

  /// The unit the series was measured in — the first legal round's, since a
  /// competition is measured one way all afternoon. Meters for a series
  /// with nothing on the board, which has no mark to write anyway.
  DistanceUnit get unit {
    for (var round = 0; round < entry.attempts.length; round++) {
      if (distanceAt(round) != null) return unitAt(round);
    }
    return DistanceUnit.meters;
  }

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

  /// The flights this is thrown in, in the order they throw.
  ///
  /// One of them for the competition small enough to be thrown in a single
  /// order, which is most of them — [isFlighted] is the question worth
  /// asking, and the answer is no until a sheet says otherwise.
  List<int> get flights {
    final seen = <int>{for (final entry in entries) entry.flight};
    return seen.toList()..sort();
  }

  bool get isFlighted => flights.length > 1;

  /// Everybody in one flight, in the order they throw it.
  List<MeetEntry> entriesIn(int flight) => [
        for (final entry in entries)
          if (entry.flight == flight) entry,
      ];

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

/// '1st', '2nd', '3rd', '11th' — a place, written the way it is read out.
String ordinalPlace(int place) {
  // The teens are the exception every naive version of this gets wrong:
  // eleventh, not eleven-first.
  final tens = place % 100;
  if (tens >= 11 && tens <= 13) return '${place}th';
  return switch (place % 10) {
    1 => '${place}st',
    2 => '${place}nd',
    3 => '${place}rd',
    _ => '${place}th',
  };
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
  /// A centimeter past whoever is standing there, because a competition is
  /// measured to the centimeter and equalling a mark does not overtake it —
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

/// The flight being thrown, and where it has got to: which round is up,
/// who is in the circle, and who follows them.
///
/// Between attempts a coach asks two questions — how far through this round
/// are we, and how long until my athlete is up — and both are arithmetic
/// over the throwing order and the series already entered. Working them out
/// here rather than inside a screen keeps them testable, and keeps the
/// meet's card and the event's own header saying the same thing.
///
/// A big competition is thrown a flight at a time, so this is worked out
/// over one flight rather than over the whole field: flight 2 standing on
/// the grass with nothing entered must not hold the round at one while
/// flight 1 throws its third. The flight being thrown is the first that is
/// still owed a round, and [flight] names it. The cut dissolves them — the
/// qualifiers come back as one group — and a competition small enough to
/// be thrown in a single order never had them, which is the case every
/// caller that says nothing about flights is in.
class MeetFlight {
  factory MeetFlight(
    MeetCompetition competition, {
    required int rounds,
    MeetStandings? standings,
    int? flight,
  }) {
    // Anybody who missed the cut is out of the count. Leaving them in would
    // hold the round at the cut for the rest of the competition, because
    // rounds they will never throw stay empty forever.
    final live = [
      for (final entry in competition.entries)
        if (standings == null || standings.throwsInFinal(entry.id)) entry,
    ];

    // How far a flight throws before it stands down for the next one: its
    // prelims, where there is a cut coming. A competition nobody is being
    // cut from has no prelims to stop at, so its flights throw the lot.
    final prelims = standings != null &&
            standings.hasCut &&
            standings.prelimRounds > 0 &&
            standings.prelimRounds < rounds
        ? standings.prelimRounds
        : rounds;

    final flights = competition.flights;
    // Which flight is up: the first still owed a round. Null for a field
    // thrown in one order, and once the cut has dissolved the flights.
    int? current;
    if (flights.length > 1 && !(standings?.cutMade ?? false)) {
      for (final number in flights) {
        if (flight != null ? number == flight : _owed(live, number, prelims)) {
          current = number;
          break;
        }
      }
    }

    final field = current == null
        ? live
        : [
            for (final entry in live)
              if (entry.flight == current) entry,
          ];

    // The last round this group of throws runs to: the competition's, when
    // the field is throwing as one, and the prelims for a flight.
    final limit = current == null ? rounds : prelims;

    // The round being thrown is the earliest one anybody still in it is
    // owed — a round is not over until the last of them has had it.
    var round = limit;
    for (final entry in field) {
      if (entry.nextRound < round) round = entry.nextRound;
    }
    return MeetFlight._(
      competition: competition,
      rounds: rounds,
      round: round,
      flight: current,
      flightCount: flights.length,
      limit: limit,
      field: field,
      waiting: round >= limit
          ? const []
          : [
              for (final entry in field)
                // '<=' rather than '==': an athlete whose earlier round was
                // skipped over is still owed a throw, and is up now.
                if (entry.nextRound <= round) entry,
            ],
      isFinal: standings != null &&
          standings.cutMade &&
          round >= standings.prelimRounds,
    );
  }

  /// Whether anybody in [flight] is still owed one of its [prelims].
  static bool _owed(List<MeetEntry> live, int flight, int prelims) {
    for (final entry in live) {
      if (entry.flight == flight && entry.nextRound < prelims) return true;
    }
    return false;
  }

  const MeetFlight._({
    required this.competition,
    required this.rounds,
    required this.round,
    required this.flight,
    required this.flightCount,
    required this.limit,
    required this.field,
    required this.waiting,
    required this.isFinal,
  });

  final MeetCompetition competition;

  /// How many attempts the meet gives.
  final int rounds;

  /// The round being thrown, from 0. Equal to [limit] once the last attempt
  /// this group of throws is owed is in.
  final int round;

  /// Which flight this is, from 1 — null for a competition thrown in one
  /// order, and for a final, which the qualifiers throw as one group.
  final int? flight;

  /// How many flights the competition is split into; 1 when it isn't.
  final int flightCount;

  /// The round this group of throws runs to: the competition's [rounds]
  /// when the whole field is throwing together, and the prelims for a
  /// flight that stands down after them.
  final int limit;

  /// Everyone who still has throws coming — the flight being thrown, the
  /// whole field before the cut where there are no flights, and the
  /// qualifiers after it.
  final List<MeetEntry> field;

  /// Who has yet to throw this round, in the order they throw.
  final List<MeetEntry> waiting;

  /// Whether [round] is one of the final's.
  final bool isFinal;

  bool get finished => round >= rounds;

  /// Whether this flight has thrown everything it is here for. The same as
  /// [finished] where the field throws as one, and true of a flight that
  /// has had its prelims and handed the ring over.
  bool get flightDone => round >= limit;

  /// Whether the competition is split into flights at all.
  bool get isFlighted => flightCount > 1;

  /// 'Flight 2 of 3' — which flight is up, for a screen with room to say
  /// how many are coming. Empty where there is only one, and once the cut
  /// has dissolved them.
  String get flightLabel =>
      flight == null ? '' : 'Flight $flight of $flightCount';

  /// Whether there is an order worth naming anybody in.
  ///
  /// A competition of one is a person taking six throws. They are always
  /// up, which is not news — and a screen that says so is telling a coach
  /// what the only card on it already shows.
  bool get hasOrder => fieldSize > 1;

  /// Whose throw is next, order or no order. A competition of one still
  /// has somebody about to throw, and a screen that offers to write their
  /// mark down has to know who it belongs to.
  MeetEntry? get next => waiting.isEmpty ? null : waiting.first;

  /// Who is in the circle, for anything that names them: the same athlete,
  /// unless there is no order worth calling — see [hasOrder].
  MeetEntry? get inTheCircle => hasOrder ? next : null;

  /// Who follows them, and who follows that — the three an infield calls
  /// out, and the reason a coach knows whether they have time to walk round
  /// to the other side of the cage.
  ///
  /// Null once the round runs out of athletes: the next one up is at the
  /// top of the order again, and naming them would be guessing at a round
  /// that hasn't started.
  MeetEntry? get onDeck => hasOrder && waiting.length > 1 ? waiting[1] : null;
  MeetEntry? get inTheHole =>
      hasOrder && waiting.length > 2 ? waiting[2] : null;

  /// How many of this round have been thrown, and out of how many. The pair
  /// a progress bar is drawn from.
  int get thrown => field.length - waiting.length;
  int get fieldSize => field.length;

  /// How many throws until [entryId] is up: 0 for the athlete in the
  /// circle, null for one with nothing coming this round.
  int? throwsUntil(String entryId) {
    if (!hasOrder) return null;
    for (var i = 0; i < waiting.length; i++) {
      if (waiting[i].id == entryId) return i;
    }
    return null;
  }

  /// 'Round 3 of 6', 'Flight 2 · round 1', 'Final · round 5', 'Done' — the
  /// one phrase for how far through a competition is, wherever it is being
  /// shown.
  ///
  /// A flighted competition says which flight instead of counting the
  /// rounds out of six: the flight is the part that changes what a coach
  /// does next, and 'of 3' is on [flightLabel] for the screens with the
  /// width for it.
  String get label {
    if (finished) return 'Done';
    if (isFinal) return 'Final · round ${round + 1}';
    if (flight != null) {
      return flightDone
          ? 'Flight $flight · done'
          : 'Flight $flight · round ${round + 1}';
    }
    return 'Round ${round + 1} of $rounds';
  }
}
