import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:http/http.dart' as http;

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/app_logo.dart';
import '../utils/meet_report.dart';
import '../utils/share_payload.dart';
import '../utils/spectator_page.dart';
import '../widgets/gold.dart';
import 'results_sheet.dart';

/// Shares the competition in front of you with anybody holding the link.
///
/// The phone is no longer the server — it is the thing that knows. It runs
/// the competition exactly as it always did and pushes the *answers* to a
/// relay, which holds them and hands them to whoever opens the link. What
/// changes is reach: a stand on a different network, a parent at work, an
/// athlete's grandmother. What it costs is signal, which a track usually
/// now has and used not to.
///
/// Nothing about the competition moves off the phone's own rules.
/// [competitionFeed] still runs `MeetStandings`, `MeetFlight` and
/// `MeetBoard` here and still spells every mark through `formatDistance`,
/// so the relay cannot become a second implementation of a competition
/// that disagrees with the coach's own screen. It holds a page and some
/// JSON and it does not know what a countback is.
///
/// Read-only at the far end, and that now has to be *arranged* rather than
/// simply true. On the LAN there was no route that wrote, so a spectator
/// could not enter a mark because nothing on the server could. A relay has
/// to accept a push from somewhere, so the token's two jobs are split: the
/// token in the link reads, and a [_Share.writeKey] that never leaves this
/// phone writes.
class MeetRelay extends ChangeNotifier {
  MeetRelay({
    String? base,
    http.Client? client,
    this.settle = const Duration(milliseconds: 400),
    this.retry = const Duration(seconds: 15),
    this.lively = const Duration(seconds: 4),
  })  : base = (base ?? _configuredBase).trim(),
        _client = client ?? http.Client();

  /// Where the relay lives, baked in at build time
  /// (`--dart-define=THROWLAB_RELAY=https://…`).
  ///
  /// A build that names none cannot share, and says so, rather than
  /// guessing at a hostname: a coach should never be typing a URL, and a
  /// wrong one fails at a ring with a stand watching.
  static const _configuredBase = String.fromEnvironment('THROWLAB_RELAY');

  /// The hostname every link is built on. Empty when this build has none.
  final String base;

  /// How long a burst of changes is allowed to settle before it is pushed.
  ///
  /// Entering a round touches the meet several times in a second — the
  /// mark, the library, the sort — and each one is a change worth showing
  /// but not a change worth its own upload.
  final Duration settle;

  /// How often a share is looked at again regardless.
  ///
  /// Not a heartbeat: a push with nothing to say costs nothing here
  /// because the fingerprint stops it. This is what gets a competition
  /// back to the stand after the signal came back, without waiting for
  /// somebody to throw.
  final Duration retry;

  /// How often the relay is asked what is being asked of *it*, while
  /// somebody is reading the competition.
  ///
  /// A push carries the followed sets back on its own, which covers every
  /// afternoon where marks are going in. This is for the gaps: a spectator
  /// who ticks a name while the field is walking back from the sector
  /// would otherwise wait for the next throw before the board became
  /// theirs. It is a few hundred bytes, and it slows to [retry] the moment
  /// nobody is reading — most links spend most of the day like that.
  final Duration lively;

  /// How long the first push waits for the medal before going without it.
  static const _medalPatience = Duration(seconds: 2);

  final http.Client _client;
  final Map<String, _Share> _byToken = {};

  Timer? _settling;
  Timer? _retrying;
  Timer? _asking;
  Listenable? _watching;
  String? _error;

  /// No 0/O or 1/I: the token is read off a screen and typed by hand when
  /// the QR will not scan in the sun, and a link dictated across a sector
  /// cannot afford a character that reads two ways.
  static const _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// Ten, where the phone's own server only ever needed six.
  ///
  /// Six characters is a billion, which is plenty of room inside one
  /// phone's own map and nowhere near enough on a hostname everybody
  /// shares: there, a token is guessable at a rate somebody else sets.
  /// Ten is a thousand million billion, and it is four more characters to
  /// read out on the afternoons the QR will not scan.
  static const _tokenLength = 10;

  bool get isSharing => _byToken.isNotEmpty;

  int get shareCount => _byToken.length;

  /// Non-null when something is wrong: no relay in this build, or the last
  /// push did not get through. Sharing is an extra — a phone that cannot
  /// reach the relay still runs the meet exactly as before.
  String? get error => _error;

  /// Whether everything being shared is actually on the relay.
  ///
  /// This is the question the LAN never had to ask. A failed push used to
  /// be a failed *fetch*, which the page saw for itself and said so; now
  /// the relay goes on answering with whatever it last heard, so a phone
  /// that has quietly stopped reaching it leaves a board on a stand that
  /// looks live and is an hour old. The coach is the only one who can be
  /// told.
  bool get reaching => _byToken.values.every((share) => share.sent != null);

  String? urlFor(String meetId, ThrowEvent event, double implementKg) =>
      _find(meetId, event, implementKg)?.url;

  /// The same link spelled for somebody to act on rather than to look at:
  /// all capitals, which is what a QR is scanned from and what gets read
  /// out when it will not scan. Scheme and host are case-insensitive and
  /// the path is uppercase already, so this is the same link.
  String? qrFor(String meetId, ThrowEvent event, double implementKg) =>
      urlFor(meetId, event, implementKg)?.toUpperCase();

  bool sharing(String meetId, ThrowEvent event, double implementKg) =>
      _find(meetId, event, implementKg) != null;

  _Share? _find(String meetId, ThrowEvent event, double implementKg) {
    for (final share in _byToken.values) {
      if (share.source.covers(meetId, event, implementKg)) return share;
    }
    return null;
  }

  /// Starts sharing one competition. Returns whether it is now on the
  /// relay.
  ///
  /// Sharing the same one twice keeps the link it already has, so a coach
  /// reopening the sheet is handed the same QR the stand already scanned.
  ///
  /// [changes] is what says the competition has moved — the meet and the
  /// record book, merged. Everything is pushed off that rather than on a
  /// clock: a mark entered at a ring should be on the stand's phone within
  /// the second, and an afternoon where nothing is thrown should cost
  /// nothing at all.
  Future<bool> start({
    required String meetId,
    required ThrowEvent event,
    required double implementKg,
    required ColorScheme scheme,
    required Meet? Function() meet,
    required List<ThrowResult> Function() results,
    bool Function(ThrowResult)? isPersonalBest,
    String Function(String athlete)? boardNames,
    Listenable? changes,
  }) async {
    if (base.isEmpty) {
      _fail('This build has no relay to share through.');
      return false;
    }
    final already = _find(meetId, event, implementKg);
    if (already != null) return true;

    final token = _newToken();
    final share = _Share(
      token: token,
      writeKey: _newWriteKey(),
      url: '$base/M/$token',
      scheme: scheme,
      source: ShareSource(
        meetId: meetId,
        event: event,
        implementKg: implementKg,
        meet: meet,
        results: results,
        isPersonalBest: isPersonalBest,
        boardNames: boardNames,
      ),
    );
    _byToken[token] = share;
    _watch(changes);

    // The page and the medal go with the first push and are held after it:
    // they are 50 KB that change when the app does, and re-sending them
    // behind every mark would be most of what this costs somebody.
    final landed = await _push(share, whole: true);
    if (!landed) {
      _byToken.remove(token);
      if (_byToken.isEmpty) _quiet();
      notifyListeners();
      return false;
    }
    _error = null;
    notifyListeners();
    return true;
  }

  /// Stops sharing one competition.
  ///
  /// The relay is not told. There is no route that deletes, because a
  /// route that deletes is a route somebody else can call; the competition
  /// ages out on its own instead, which is also what happens to a phone
  /// that goes flat on the way to the car park.
  Future<void> stop(String meetId, ThrowEvent event, double implementKg) async {
    final share = _find(meetId, event, implementKg);
    if (share == null) return;
    _byToken.remove(share.token);
    if (_byToken.isEmpty) _quiet();
    notifyListeners();
  }

  Future<void> stopAll() async {
    _byToken.clear();
    _quiet();
    notifyListeners();
  }

  /* ---- what makes a push happen ---------------------------------------- */

  void _watch(Listenable? changes) {
    if (changes == null || identical(changes, _watching)) {
      _retrying ??= Timer.periodic(retry, (_) => _pushMoved());
      _askAgain();
      return;
    }
    _watching?.removeListener(_changed);
    _watching = changes..addListener(_changed);
    _retrying ??= Timer.periodic(retry, (_) => _pushMoved());
    _askAgain();
  }

  void _quiet() {
    _settling?.cancel();
    _settling = null;
    _retrying?.cancel();
    _retrying = null;
    _asking?.cancel();
    _asking = null;
    _watching?.removeListener(_changed);
    _watching = null;
  }

  /// Books the next round of asking, at the pace the last one earned.
  ///
  /// Rescheduled rather than periodic because the pace changes: a link
  /// with a stand on it is worth asking after every few seconds, and one
  /// nobody has opened is worth the same minute everything else runs on.
  void _askAgain() {
    if (_byToken.isEmpty) return;
    final read = _byToken.values.any((share) => share.reading);
    _asking?.cancel();
    _asking = Timer(read ? lively : retry, _askAround);
  }

  /// Asks each share what is being asked of it, and answers whatever is
  /// owed.
  Future<void> _askAround() async {
    for (final share in [..._byToken.values]) {
      await _pollWanted(share);
      if (share.owing) await _push(share);
    }
    _askAgain();
  }

  /// One share's followed sets, off the relay.
  ///
  /// Behind the write key, because the sets are a list of who at this meet
  /// somebody cared enough to tick. A failure is nothing to report: the
  /// competition itself is not on this route, and the push that carries
  /// the same answer has its own error to raise.
  Future<void> _pollWanted(_Share share) async {
    if (share.pushing) return;
    try {
      final answer = await _client.get(
        Uri.parse('${share.url}/wanted'),
        headers: {'authorization': 'Bearer ${share.writeKey}'},
      );
      if (answer.statusCode != 200) return;
      _heard(share, answer.body);
    } catch (_) {
      // No signal. The next ask, or the next push, brings it back.
    }
  }

  /// What the relay said about who is being followed and whether anybody
  /// is reading.
  ///
  /// Read off whatever answered — a push and the asking route say the same
  /// thing, since they are the same question and the push is the hop this
  /// phone was making anyway.
  void _heard(_Share share, String body) {
    try {
      final said = jsonDecode(body);
      if (said is! Map) return;
      final wanted = said['wanted'];
      if (wanted is List) {
        share.wanted = [
          for (final key in wanted)
            if (key is String && key.isNotEmpty) key,
        ];
        // A set nobody is asking for any more is one this phone stops
        // working out, and stops holding an answer to.
        share.answered = {
          for (final entry in share.answered.entries)
            if (share.wanted.contains(entry.key)) entry.key: entry.value,
        };
      }
      if (said['reading'] is bool) share.reading = said['reading'] as bool;
    } catch (_) {
      // Not JSON, which a relay does not send. Nothing is owed on it.
    }
  }

  void _changed() {
    _settling?.cancel();
    _settling = Timer(settle, _pushMoved);
  }

  /// Pushes every share whose competition has moved since it last landed.
  ///
  /// A share whose last push failed has nothing recorded as landed, so it
  /// is retried here too without needing to be remembered separately.
  Future<void> _pushMoved() async {
    final before = _error;
    final wasReaching = reaching;
    for (final share in [..._byToken.values]) {
      await _push(share);
    }
    if (_error != before || reaching != wasReaching) notifyListeners();
  }

  /// One share, pushed if it has anything to say, and pushed again if the
  /// relay answered with a question nobody has answered yet.
  ///
  /// Twice at most, and twice by construction: the sets being followed come
  /// back on the answer to a push, so learning of one and answering it
  /// cannot be fewer hops than two. A third would be a spectator's tick
  /// driving this phone's uploads, which is a stranger with the link
  /// setting the pace.
  Future<bool> _push(_Share share, {bool whole = false}) async {
    var landed = await _send(share, whole: whole);
    if (landed && share.owing) landed = await _send(share);
    return landed;
  }

  /// One share, pushed if it has anything to say. Returns whether the
  /// relay is holding what this phone knows.
  Future<bool> _send(_Share share, {bool whole = false}) async {
    if (share.pushing) return share.sent != null;
    // The coach's own reading, and the same competition worked out again
    // around each set somebody at the ring is following — all at one
    // instant, so an overlay holds the difference the set makes and not
    // the clock.
    final packaged = share.source.packaged(
        following: [for (final key in share.wanted) key.split(',')]);
    if (packaged == null) {
      // The meet is gone, or everybody in this event is. Nothing to say
      // and nothing to fix — it ages out.
      return share.sent != null;
    }
    final payload = packaged.base;
    final answers = {
      for (final overlay in packaged.overlays)
        overlay.key: overlay.fingerprint,
    };
    // A round nobody threw in still moves this the moment somebody ticks a
    // name: the feed is the feed it was, and there is now an answer owed
    // on it that the relay has not got.
    final moved = whole ||
        payload.fingerprint != share.sent ||
        !mapEquals(share.answered, answers);
    if (!moved) return true;

    share.pushing = true;
    try {
      final body = <String, dynamic>{
        'fingerprint': payload.fingerprint,
        'feed': payload.feed,
        // Always sent, empty included: it is the whole of what this phone
        // is standing behind, so a set nobody is asking for any more is
        // one the relay stops holding rather than goes on serving.
        'overlays': {
          for (final overlay in packaged.overlays) overlay.key: overlay.toJson(),
        },
        ...await _statics(share, whole: whole),
        ...await _sheet(share),
      };
      final answer = await _client.put(
        Uri.parse('${share.url}/state'),
        headers: {
          'authorization': 'Bearer ${share.writeKey}',
          'content-type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (answer.statusCode == 409) {
        // Two phones on one token, which ten characters make improbable
        // and not impossible. The link is not this phone's, so it must
        // not go on being offered.
        _byToken.remove(share.token);
        if (_byToken.isEmpty) _quiet();
        _error = 'That link is already in use. Share it again for a new one.';
        return false;
      }
      if (answer.statusCode != 200) {
        _error = 'The relay would not take the competition '
            '(${answer.statusCode}).';
        share.sent = null;
        share.answered = const {};
        return false;
      }
      share.sent = payload.fingerprint;
      share.answered = answers;
      _heard(share, answer.body);
      _error = null;
      return true;
    } catch (e) {
      // No signal, most likely, which at a track is a thing that happens.
      // The share stays live and the retry brings it back.
      _error = 'Not reaching the relay — $e';
      share.sent = null;
      share.answered = const {};
      return false;
    } finally {
      share.pushing = false;
    }
  }

  /// The page and the medal, which go once.
  ///
  /// The page is the app's own — generated here off the app's own
  /// `ColorScheme`, so the theme stays `main.dart`'s to decide and there
  /// is no second copy of it anywhere to fall behind. The medal is struck
  /// by the app's own painter for the same reason it always was: every
  /// number in it is measured off a reference, and a badge that is nearly
  /// right is worse than none.
  Future<Map<String, dynamic>> _statics(_Share share,
      {required bool whole}) async {
    if (!whole) return const {};
    // With the question it asks on the way in. Answering it takes
    // something that will work the competition out again around whoever
    // was ticked, which is this phone and nothing else — so the relay
    // writes the sets down as they are asked for, hands them back here,
    // and what goes up with the next push is an answer per set. The page
    // cannot tell the difference and does not have one drawn for it: it
    // asks the same way and is answered the same way whether a phone on
    // the wifi or the relay is on the other end.
    final out = <String, dynamic>{
      'page': spectatorPage(share.scheme, servedByPhone: false),
    };
    try {
      // Never the thing a link waits on. Striking the badge goes through
      // the engine, which is quick on a phone and can be slow — or never
      // finish at all — anywhere else, and a coach standing at a ring with
      // no QR yet is a worse failure than a page whose medal 404s for one
      // round. The page has coped with that since it was served off the
      // phone.
      out['medal'] = base64Encode(
          await medalPng(Medal.gold, size: 48).timeout(_medalPatience));
    } catch (_) {
      // Timed out, or no painter behind us at all.
    }
    return out;
  }

  /// This competition's results sheet, as it stands.
  ///
  /// It used to be generated into the response, because there was a
  /// request to generate it into. There is no request here, so it rides
  /// with the competition — it is a few kilobytes against the feed's
  /// fifteen, and it means a spectator leaving at the fourth round leaves
  /// with the fourth round on it.
  Future<Map<String, dynamic>> _sheet(_Share share) async {
    final meet = share.source.meet();
    final competition = share.source.competition();
    if (meet == null || competition == null) return const {};
    try {
      return {
        'pdf': base64Encode(meetResultsPdf(meet, share.source.results(),
            only: competition, logo: await sheetLogo())),
        'sheetName': ResultsSheet.fileName(meet, competition),
      };
    } catch (_) {
      // A sheet that will not write is not worth losing the board over.
      return const {};
    }
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _quiet();
    _byToken.clear();
    _client.close();
    super.dispose();
  }

  static String _newToken() => _pick(_alphabet, _tokenLength);

  /// The half that never leaves the phone, so it is not read out and does
  /// not have to survive being dictated: the whole alphabet, and long.
  static String _newWriteKey() => _pick(
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 43);

  static String _pick(String alphabet, int length) {
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < length; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
  }
}

/// One competition on the relay: the link it is read on, the key it is
/// written with, and what the relay was last told.
class _Share {
  _Share({
    required this.token,
    required this.writeKey,
    required this.url,
    required this.scheme,
    required this.source,
  });

  final String token;
  final String writeKey;
  final String url;
  final ColorScheme scheme;
  final ShareSource source;

  /// The fingerprint the relay is holding, or null when it is holding
  /// nothing this phone is sure of — which is what a failed push leaves
  /// behind, and what makes the next one happen.
  String? sent;

  /// The sets of athletes somebody at the ring has asked to follow, as the
  /// relay last reported them. The page ticks them and the relay writes
  /// them down; this phone is the only thing that can answer them.
  List<String> wanted = const [];

  /// What has been answered, by set and by the fingerprint of the answer.
  /// The difference between this and [wanted] is the next push.
  Map<String, String> answered = const {};

  /// Whether anybody has read the competition lately. Paces the asking:
  /// a stand on the link is worth a few seconds, an empty one a minute.
  ///
  /// True until the relay says otherwise, because a share begins with a
  /// coach standing at a ring holding a QR out at somebody — which is the
  /// moment a link is most likely to be opened and a name ticked, and the
  /// one moment there is nothing on the record to say so. It costs one
  /// quick ask on a link nobody opens.
  bool reading = true;

  bool pushing = false;

  /// Sets being asked for that this phone has not answered at the
  /// fingerprint it is now holding.
  bool get owing {
    for (final key in wanted) {
      if (!answered.containsKey(key)) return true;
    }
    return false;
  }
}
