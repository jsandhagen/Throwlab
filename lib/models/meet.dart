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
  MeetAttempt({required this.kind, this.resultId});

  MeetAttempt.mark(String this.resultId) : kind = AttemptKind.mark;
  MeetAttempt.foul()
      : kind = AttemptKind.foul,
        resultId = null;
  MeetAttempt.pass()
      : kind = AttemptKind.pass,
        resultId = null;

  final AttemptKind kind;

  /// The [ThrowMark] or [ThrowVideo] this attempt was recorded as.
  ///
  /// A foul keeps its clip — a throw that sailed out of the sector is
  /// exactly the one a coach wants to watch again — but never a distance:
  /// the clip's own is cleared when the round is called a foul, so a throw
  /// that didn't count can't stand as a personal best.
  final String? resultId;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (resultId != null) 'resultId': resultId,
      };

  factory MeetAttempt.fromJson(Map<String, dynamic> json) => MeetAttempt(
        kind: AttemptKind.values.asNameMap()[json['kind'] as String? ?? ''] ??
            AttemptKind.foul,
        resultId: json['resultId'] as String?,
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
    List<MeetAttempt?>? attempts,
  }) : attempts = attempts ?? [];

  final String id;
  String athlete;
  ThrowEvent event;
  double implementKg;

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
        'attempts': [
          for (final attempt in attempts) attempt?.toJson(),
        ],
      };

  factory MeetEntry.fromJson(Map<String, dynamic> json) => MeetEntry(
        id: json['id'] as String,
        athlete: json['athlete'] as String? ?? '',
        event: ThrowEvent.values.byName(json['event'] as String),
        implementKg: (json['implementKg'] as num).toDouble(),
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
    List<MeetEntry>? entries,
  }) : entries = entries ?? [];

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

  final List<MeetEntry> entries;

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
        'entries': [for (final entry in entries) entry.toJson()],
      };

  factory Meet.fromJson(Map<String, dynamic> json) => Meet(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        rounds: (json['rounds'] as num?)?.toInt() ?? 6,
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
    if (entry.attemptAt(round)?.kind != AttemptKind.mark) return null;
    return resultAt(round)?.distance;
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
