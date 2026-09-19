import 'dart:convert';

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import 'meet_feed.dart';

/// One competition, packaged for whoever is carrying it to a spectator.
///
/// [MeetServer] used to work this out inside the request it was answering,
/// which was the right place while the phone was the only thing serving:
/// there was a request to read the meet on, and the answer went straight
/// back down it. A relay has no such request — the competition has to be
/// pushed at it, on the app's own clock — so the packaging is pulled out
/// to here, where it knows nothing about how it travels, and both sides
/// ask for exactly the same thing.
///
/// Nothing in here does I/O. It is [competitionFeed] plus the one number
/// that says whether the feed has moved.
class SharePayload {
  SharePayload(this.feed) : fingerprint = _fingerprintOf(feed);

  /// The competition as [competitionFeed] works it out: the answers, never
  /// the rules.
  final Map<String, dynamic> feed;

  /// A cheap, stable hash of everything in the feed *but* the clock.
  ///
  /// `asOf` moves every second, so hashing it would say the competition had
  /// changed between two throws when nothing had happened at all. Both
  /// sides spend this on the same question asked two ways: a server answers
  /// a poll with 304 rather than 15 KB, and a publisher skips an upload
  /// nobody is owed. The page's own clock is allowed to be as old as the
  /// last thing that was actually thrown.
  final String fingerprint;

  /// The fingerprint as an HTTP entity tag.
  String get etag => '"$fingerprint"';

  String encode() => jsonEncode(feed);

  static String _fingerprintOf(Map<String, dynamic> feed) =>
      fnv1a(jsonEncode({...feed}..remove('asOf')));
}

/// One competition being shared, and how to read it.
///
/// The meet is held as callbacks rather than copied, so every payload comes
/// out of the competition as it stands rather than out of a snapshot that
/// can disagree with the coach's own screen: a mark entered a moment ago is
/// in the next payload, and an athlete entered after the link went out is
/// in the field.
class ShareSource {
  const ShareSource({
    required this.meetId,
    required this.event,
    required this.implementKg,
    required this.meet,
    required this.results,
    this.isPersonalBest,
  });

  final String meetId;
  final ThrowEvent event;
  final double implementKg;

  final Meet? Function() meet;
  final List<ThrowResult> Function() results;
  final bool Function(ThrowResult)? isPersonalBest;

  /// Whether this is the competition being asked after — the meet, the
  /// event *and* the weight, since that is the contest an athlete is placed
  /// in and therefore the thing a link is handed over for.
  bool covers(String meetId, ThrowEvent event, double implementKg) =>
      this.meetId == meetId &&
      this.event == event &&
      this.implementKg == implementKg;

  /// The competition as it stands, looked up fresh. Null once the meet — or
  /// everybody in this event — has gone.
  MeetCompetition? competition() {
    final held = meet();
    return held == null ? null : _within(held);
  }

  /// The competition packaged, or null when there is no longer one to
  /// package.
  ///
  /// [following] is who the person reading it came to watch, by entry id.
  /// The answer is worked out around them rather than around the coach's
  /// own, so it is part of what is packaged — and part of what the
  /// fingerprint is taken over, since two spectators following two
  /// athletes must never be handed each other's board off one tag.
  SharePayload? payload({DateTime? at, Iterable<String>? following}) {
    final held = meet();
    if (held == null) return null;
    final competition = _within(held);
    if (competition == null) return null;
    return SharePayload(competitionFeed(held, competition, results(),
        at: at, isPersonalBest: isPersonalBest, following: following));
  }

  /// The competition packaged for the coach's own reading, and again for
  /// every set of athletes somebody standing at the ring has asked to
  /// follow.
  ///
  /// This is the shape a relay needs and a socket never did. Serving the
  /// competition itself, there is a request to read the question off and
  /// an answer to send straight back down it, so a spectator's set costs
  /// one more [payload] on the spot. Pushing it, there is one feed held
  /// for everybody — so the sets have to be answered in advance, which
  /// means knowing which ones are being asked ([MeetRelay] gets them back
  /// off the relay) and sending each answer as what it adds to the base
  /// rather than as a competition of its own.
  ///
  /// Every reading is taken at one instant, which is what lets the deltas
  /// hold nothing but the difference the set makes: two feeds worked out a
  /// second apart would differ on `asOf` as well, and the clock is the one
  /// thing in here that moves without anybody throwing.
  ({SharePayload base, List<FeedOverlay> overlays})? packaged({
    DateTime? at,
    Iterable<Iterable<String>> following = const [],
  }) {
    final now = at ?? DateTime.now();
    final base = payload(at: now);
    if (base == null) return null;
    final overlays = <FeedOverlay>[];
    final answered = <String>{};
    for (final set in following) {
      final key = followingKey(set);
      // Two spectators who ticked the same two names in a different order
      // are asking one question, and are answered once.
      if (key.isEmpty || !answered.add(key)) continue;
      final read = payload(at: now, following: key.split(','));
      if (read == null) continue;
      overlays.add(FeedOverlay(
        key: key,
        fingerprint: read.fingerprint,
        delta: feedDelta(base.feed, read.feed),
      ));
    }
    return (base: base, overlays: overlays);
  }

  MeetCompetition? _within(Meet held) {
    for (final competition in MeetCompetition.of(held)) {
      if (competition.event == event && competition.implementKg == implementKg) {
        return competition;
      }
    }
    return null;
  }
}

/// FNV-1a, which is a few lines rather than a dependency. A collision costs
/// one stale poll of a board that is about to be polled again, which is the
/// right price for not pulling in a hashing library to compare two strings.
String fnv1a(String body) {
  var hash = 0xcbf29ce484222325;
  for (final unit in utf8.encode(body)) {
    hash ^= unit;
    // Kept inside 64 bits by hand: Dart's ints are 64-bit and signed, and
    // the multiply is allowed to overflow, which is what FNV expects.
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(36);
}

/// How many athletes one answer may be about.
///
/// A whole field is a legitimate tick — a club's supporter really is there
/// for everybody — and past that it is somebody asking a phone at a track
/// to work the competition out a thousand ways. The page ticks names out
/// of a field, so this only ever bites on a link somebody has written by
/// hand.
const maxFollowed = 32;

/// The canonical name for a set of athletes somebody is following.
///
/// Sorted, deduplicated and capped, because the set is what an answer is
/// filed under at both ends: the relay records it under this when a poll
/// asks for it, and the phone answers under this when it is told. Two
/// spectators who ticked the same two names in a different order are
/// asking one question, and a key that disagreed across the wire would be
/// a competition worked out and then never found again.
///
/// Empty for nobody, which is the coach's own reading — the base feed, and
/// no overlay at all.
String followingKey(Iterable<String> ids) {
  final wanted = <String>{};
  for (final id in ids) {
    final trimmed = id.trim();
    // An id is an entry id. Anything longer than one is somebody writing
    // the query by hand, and it is filed under nothing.
    if (trimmed.isEmpty || trimmed.length > 64) continue;
    wanted.add(trimmed);
  }
  final sorted = wanted.toList()..sort();
  return sorted.take(maxFollowed).join(',');
}

/// One set's answer, as what it adds to the base feed.
///
/// Not a feed of its own: the phone holds a competition for the coach and
/// the same competition for every set being watched at the ring, and they
/// differ in a few rows and a board. Pushing each one whole would be the
/// base feed again per spectator, over a coach's cellular connection,
/// every round.
class FeedOverlay {
  const FeedOverlay({
    required this.key,
    required this.fingerprint,
    required this.delta,
  });

  /// The set this answers, as [followingKey] spells it.
  final String key;

  /// The fingerprint of the *composed* feed — the base with this applied —
  /// so the relay can hand it straight out as an entity tag and a
  /// spectator between rounds costs a 304 rather than the competition.
  /// Taken over the composed feed and not over the delta, because what a
  /// browser is holding is the composition.
  final String fingerprint;

  /// See [feedDelta].
  final Map<String, dynamic> delta;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'delta': delta,
      };
}

/// What one reading of a competition adds to another.
///
/// Shaped to the feed rather than general, because the difference a
/// followed set makes is a measured thing and not an arbitrary one. On a
/// field of sixteen it is `following`, `board` and a handful of rows of
/// `places` — and inside a row, the two or three fields that hang off
/// whose it is: `mine`, the averaging line, and what they need to qualify.
/// Everything else is the competition, which is the same competition
/// whoever is reading it.
///
/// So: a map is sent as the keys that moved, `places` is sent by the row,
/// and a row is sent the same way a map is. Sending a row whole was the
/// first shape of this and cost five hundred bytes to say `mine` had
/// turned over; a list is still replaced whole, because the one list
/// inside a row is a series and a series does not care who is watching it.
///
/// This knows the *shape* of what [competitionFeed] writes and nothing
/// whatever about a competition — it never has to, since both sides of the
/// subtraction were worked out by the rules already.
///
/// The counterpart lives in the relay, which applies it. There is no third
/// copy: the page is served the composition and cannot tell it was ever in
/// two pieces, which is what keeps one code path behind the phone's own
/// socket and behind the relay.
Map<String, dynamic> feedDelta(
    Map<String, dynamic> base, Map<String, dynamic> next) {
  final delta = _mapDelta(base, next, except: 'places') ?? <String, dynamic>{};

  final rows = <String, dynamic>{};
  final before = base['places'] as List? ?? const [];
  final after = next['places'] as List? ?? const [];
  if (before.length != after.length) {
    // The field itself moved between the two readings, which it cannot
    // when they are taken at one instant off one competition. Sending it
    // whole is the honest answer to something that should not happen
    // rather than a patch against a list of another length.
    (delta['set'] ??= <String, dynamic>{})['places'] = after;
  } else {
    for (var i = 0; i < after.length; i++) {
      final row = _mapDelta(
          before[i] as Map<String, dynamic>, after[i] as Map<String, dynamic>);
      if (row != null) rows['$i'] = row;
    }
  }
  if (rows.isNotEmpty) delta['places'] = rows;
  return delta;
}

/// The keys one map added, changed or stopped carrying, or null where it
/// carries the same as the other.
///
/// Values are whole: a nested map or a list is replaced rather than
/// subtracted again. What is nested in a feed is a board, a caption and a
/// series, and each of those either is the same or is different all the
/// way through — there is nothing in here that would be paid back for the
/// recursion.
Map<String, dynamic>? _mapDelta(
    Map<String, dynamic> base, Map<String, dynamic> next,
    {String? except}) {
  // Deep equality by the encoding both ends compare on anyway. Every value
  // in here came out of one builder in one pass, so two equal readings
  // encode identically.
  bool same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  final set = <String, dynamic>{};
  final drop = <String>[];
  for (final entry in next.entries) {
    if (entry.key == except) continue;
    if (!base.containsKey(entry.key) || !same(base[entry.key], entry.value)) {
      set[entry.key] = entry.value;
    }
  }
  for (final key in base.keys) {
    if (key == except || next.containsKey(key)) continue;
    drop.add(key);
  }
  if (set.isEmpty && drop.isEmpty) return null;
  return {
    if (set.isNotEmpty) 'set': set,
    if (drop.isNotEmpty) 'drop': drop,
  };
}
