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
  SharePayload? payload({DateTime? at}) {
    final held = meet();
    if (held == null) return null;
    final competition = _within(held);
    if (competition == null) return null;
    return SharePayload(competitionFeed(held, competition, results(),
        at: at, isPersonalBest: isPersonalBest));
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
