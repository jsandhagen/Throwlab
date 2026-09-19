import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:http/http.dart' as http;

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
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

  /// How long the first push waits for the medal before going without it.
  static const _medalPatience = Duration(seconds: 2);

  final http.Client _client;
  final Map<String, _Share> _byToken = {};

  Timer? _settling;
  Timer? _retrying;
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
      return;
    }
    _watching?.removeListener(_changed);
    _watching = changes..addListener(_changed);
    _retrying ??= Timer.periodic(retry, (_) => _pushMoved());
  }

  void _quiet() {
    _settling?.cancel();
    _settling = null;
    _retrying?.cancel();
    _retrying = null;
    _watching?.removeListener(_changed);
    _watching = null;
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

  /// One share, pushed if it has anything to say. Returns whether the
  /// relay is holding what this phone knows.
  Future<bool> _push(_Share share, {bool whole = false}) async {
    if (share.pushing) return share.sent != null;
    final payload = share.source.payload();
    if (payload == null) {
      // The meet is gone, or everybody in this event is. Nothing to say
      // and nothing to fix — it ages out.
      return share.sent != null;
    }
    if (!whole && payload.fingerprint == share.sent) return true;

    share.pushing = true;
    try {
      final body = <String, dynamic>{
        'fingerprint': payload.fingerprint,
        'feed': payload.feed,
        ...await _statics(share, whole: whole),
        ..._sheet(share),
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
        return false;
      }
      share.sent = payload.fingerprint;
      _error = null;
      return true;
    } catch (e) {
      // No signal, most likely, which at a track is a thing that happens.
      // The share stays live and the retry brings it back.
      _error = 'Not reaching the relay — $e';
      share.sent = null;
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
    // Without the question it asks on the way in: answering it takes
    // something that will work the competition out again around whoever was
    // ticked, and a relay holds one feed for everybody. Asked and ignored is
    // a control that looks broken. ROADMAP, Phase 9.
    final out = <String, dynamic>{
      'page': spectatorPage(share.scheme,
          asksWhoYouFollow: false, servedByPhone: false),
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
  Map<String, dynamic> _sheet(_Share share) {
    final meet = share.source.meet();
    final competition = share.source.competition();
    if (meet == null || competition == null) return const {};
    try {
      return {
        'pdf': base64Encode(
            meetResultsPdf(meet, share.source.results(), only: competition)),
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

  bool pushing = false;
}
