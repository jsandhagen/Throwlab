import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:flutter/services.dart' show rootBundle;

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../utils/meet_feed.dart';
import '../utils/meet_report.dart';
import '../utils/spectator_page.dart';
import '../widgets/gold.dart';
import 'results_sheet.dart';

/// Shares the competition in front of you with everybody standing at it.
///
/// The phone is the server. There is no hosting, no account and nothing
/// uploaded: this binds a socket, and anyone on the same wifi — or on the
/// phone's own hotspot, which is the case that actually works at a track —
/// opens the link in a browser and follows the competition. It is the only
/// shape of live sharing that survives a field with no signal on it, which
/// is most of them, and it is the reason the fonts are bundled too.
///
/// A share is one competition, not the meet. A link is handed over at a
/// ring by somebody standing at it, and the rest of the day's field are
/// other people's athletes who never agreed to be on anybody's phone — so
/// the discus link serves the discus and 404s everything else. A coach with
/// two rings going shares each, and gets a link for each.
///
/// Read-only by construction. There is no route that writes anything, so a
/// spectator cannot enter a mark, and nothing here touches the meet or the
/// record book except to read what is already there.
///
/// The meet is read through the callbacks handed to [start] rather than
/// copied, so every request answers with the competition as it stands. A
/// coach entering a mark does not notify this: the next poll simply sees
/// it.
class MeetServer extends ChangeNotifier {
  /// The ports to try, in order. 8080 first because a link somebody may
  /// have to read out loud is worth keeping short and familiar; anything
  /// already holding it means falling down the list, and then to whatever
  /// the system hands out.
  static const _ports = [8080, 8081, 8082, 8090, 0];

  /// No 0/O or 1/I: the token is read off a screen and typed by hand when
  /// the QR won't scan in the sun, which is a thing that happens at a
  /// track, and a link dictated across a sector cannot afford a character
  /// that reads two ways.
  static const _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// The two weights the page asks for. The app bundles four; a page this
  /// size only ever sets body and emphasis, and each file is a quarter of a
  /// megabyte over somebody's wifi.
  static const _fonts = {
    'r.ttf': 'assets/fonts/Barlow-Regular.ttf',
    's.ttf': 'assets/fonts/Barlow-SemiBold.ttf',
  };

  HttpServer? _server;
  String? _error;
  ColorScheme? _scheme;

  final Map<String, _Share> _byToken = {};

  /// How the server opens its socket. Swapped out in a test, which has no
  /// business binding a real port on whatever machine CI runs on.
  @visibleForTesting
  static Future<HttpServer> Function(int port) bind =
      (port) => HttpServer.bind(InternetAddress.anyIPv4, port);

  /// The phone's own address on the network it is on. Swapped out in a
  /// test, where there is no wifi to ask about.
  @visibleForTesting
  static Future<String?> Function() lanAddress = _findLanAddress;

  /// Where the page's typeface comes from. Swapped out in a test, which
  /// runs without an asset bundle behind it.
  @visibleForTesting
  static Future<Uint8List> Function(String asset) loadFont = (asset) async =>
      (await rootBundle.load(asset)).buffer.asUint8List();

  /// Whether anything at all is being served.
  bool get isSharing => _byToken.isNotEmpty;

  /// How many competitions are being shared, for a screen that wants to say
  /// so without naming them.
  int get shareCount => _byToken.length;

  /// Non-null when the socket wouldn't open. Sharing is an extra; a phone
  /// that refuses to bind still runs the meet exactly as before.
  String? get error => _error;

  /// The link for one competition, or null when it isn't being shared.
  String? urlFor(String meetId, ThrowEvent event, double implementKg) =>
      _find(meetId, event, implementKg)?.url;

  /// The same link spelled for somebody to act on rather than to look at:
  /// all capitals, which is what a QR is scanned from and what gets read
  /// out when it won't scan. Scheme and host are case-insensitive and the
  /// path is uppercase already, so this is the same link.
  ///
  /// It does not make the code any smaller — the encoder we use writes byte
  /// mode whatever the characters are, and QR's tighter alphanumeric mode
  /// has no '#' in its charset anyway, which a relay link would need. Short
  /// is what keeps the code fat here, not case.
  String? qrFor(String meetId, ThrowEvent event, double implementKg) =>
      urlFor(meetId, event, implementKg)?.toUpperCase();

  bool sharing(String meetId, ThrowEvent event, double implementKg) =>
      _find(meetId, event, implementKg) != null;

  _Share? _find(String meetId, ThrowEvent event, double implementKg) {
    for (final share in _byToken.values) {
      if (share.meetId == meetId &&
          share.event == event &&
          share.implementKg == implementKg) {
        return share;
      }
    }
    return null;
  }

  /// Starts sharing one competition. Returns whether it is now being
  /// served. Sharing the same one twice keeps the link it already has, so a
  /// coach reopening the sheet is handed the same QR the stand already
  /// scanned.
  ///
  /// The callbacks are how it reads the meet — live, per request, so
  /// nothing here can go stale or hold a copy of the competition that
  /// disagrees with the screen. [scheme] is the app's own, which is what
  /// paints the page in the app's colors rather than in guessed ones.
  Future<bool> start({
    required String meetId,
    required ThrowEvent event,
    required double implementKg,
    required ColorScheme scheme,
    required Meet? Function() meet,
    required List<ThrowResult> Function() results,
    bool Function(ThrowResult)? isPersonalBest,
  }) async {
    _scheme = scheme;
    final already = _find(meetId, event, implementKg);
    if (already != null) return true;

    if (_server == null && !await _open()) return false;
    final host = await lanAddress();
    if (host == null) {
      if (_byToken.isEmpty) await stopAll();
      _fail('This phone is not on a network. Turn on wifi or a hotspot.');
      return false;
    }

    final token = _newToken();
    _byToken[token] = _Share(
      token: token,
      url: 'http://$host:${_server!.port}/M/$token',
      meetId: meetId,
      event: event,
      implementKg: implementKg,
      meet: meet,
      results: results,
      isPersonalBest: isPersonalBest,
    );
    _error = null;
    notifyListeners();
    return true;
  }

  /// Opens the socket, trying each port in turn. The listener is attached
  /// once and serves every share.
  Future<bool> _open() async {
    for (final port in _ports) {
      try {
        _server = await bind(port);
        break;
      } on SocketException {
        // Something else has it. Try the next one down the list.
        continue;
      } catch (e) {
        _fail('$e');
        return false;
      }
    }
    final server = _server;
    if (server == null) {
      _fail('No port would open.');
      return false;
    }
    server.listen(_handle, onError: (_) {
      // A dead socket is a stopped share; say so rather than leaving links
      // on screen that nothing is answering.
      stopAll();
    });
    return true;
  }

  /// Stops sharing one competition, and closes the socket with the last of
  /// them — a port held open for nothing is a port held open.
  Future<void> stop(String meetId, ThrowEvent event, double implementKg) async {
    final share = _find(meetId, event, implementKg);
    if (share == null) return;
    _byToken.remove(share.token);
    if (_byToken.isEmpty) {
      await _close();
    }
    notifyListeners();
  }

  Future<void> stopAll() async {
    _byToken.clear();
    await _close();
    notifyListeners();
  }

  Future<void> _close() async {
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {
        // Already gone.
      }
    }
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    // Not awaited: dispose cannot be async, and a socket closing behind a
    // disposed notifier is nobody's problem.
    _server?.close(force: true);
    _server = null;
    _byToken.clear();
    super.dispose();
  }

  static String _newToken() {
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 6; i++)
        _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
    ]);
  }

  /// The address a phone is reachable on, preferring the private ranges a
  /// track's wifi or the phone's own hotspot hands out over anything else
  /// an Android has bound (a VPN, a cellular interface).
  static Future<String?> _findLanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      String? fallback;
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) return ip;
          // 172.16 – 172.31, which is the same private block written the
          // way nobody remembers.
          if (ip.startsWith('172.')) {
            final second = int.tryParse(ip.split('.')[1]) ?? 0;
            if (second >= 16 && second <= 31) return ip;
          }
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    // Nothing here is for a crawler, and a competition's field is a list of
    // names. Belt and braces on a LAN, and the right habit anyway.
    response.headers.set('X-Robots-Tag', 'noindex, nofollow');
    response.headers.set('Referrer-Policy', 'no-referrer');
    try {
      if (request.method != 'GET') {
        await _plain(response, HttpStatus.methodNotAllowed, 'GET only.');
        return;
      }
      final segments = request.uri.pathSegments;
      // /M/<token>[/...] and nothing else exists. A wrong or missing token
      // is a 404 rather than a 403: a link that has stopped being shared
      // should look like a link that was never there.
      final share =
          segments.length >= 2 && segments[0] == 'M' ? _byToken[segments[1]] : null;
      if (share == null) {
        await _plain(response, HttpStatus.notFound, 'Nothing here.');
        return;
      }
      final rest = segments.length > 2 ? segments[2] : '';
      switch (rest) {
        case '':
          await _page(response);
        case 'state':
          await _state(request, response, share);
        case 'results.pdf':
          await _sheet(response, share);
        case 'f':
          await _font(response, segments.length > 3 ? segments[3] : '');
        case 'pb.png':
          await _medal(response);
        default:
          await _plain(response, HttpStatus.notFound, 'Nothing here.');
      }
    } catch (e) {
      try {
        await _plain(response, HttpStatus.internalServerError, 'Sorry — $e');
      } catch (_) {
        // The socket went while we were answering it.
      }
    }
  }

  Future<void> _page(HttpResponse response) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    // Small enough not to be worth a caching story, and it changes when the
    // app updates, which a spectator's browser has no way to know.
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(spectatorPage(_scheme ?? const ColorScheme.dark()));
    await response.close();
  }

  /// Barlow, off the phone. The one thing on this page worth a browser
  /// cache: it is a quarter of a megabyte that never changes, and a
  /// spectator who reloads on flaky wifi should not fetch it twice.
  Future<void> _font(HttpResponse response, String name) async {
    final asset = _fonts[name];
    if (asset == null) {
      await _plain(response, HttpStatus.notFound, 'Nothing here.');
      return;
    }
    Uint8List bytes;
    try {
      bytes = await loadFont(asset);
    } catch (_) {
      // No bundle behind us. The page names a system fallback for exactly
      // this, so it is still perfectly readable.
      await _plain(response, HttpStatus.notFound, 'No font here.');
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('font', 'ttf');
    response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=86400');
    response.add(bytes);
    await response.close();
  }

  /// The personal-best medal, struck by the app's own painter and sent as
  /// pixels. Drawn once and held: it is the same badge on every card.
  Uint8List? _medalBytes;

  Future<void> _medal(HttpResponse response) async {
    try {
      _medalBytes ??= await medalPng(Medal.gold, size: 48);
    } catch (_) {
      await _plain(response, HttpStatus.notFound, 'No medal here.');
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('image', 'png');
    response.headers.set(HttpHeaders.cacheControlHeader, 'max-age=86400');
    response.add(_medalBytes!);
    await response.close();
  }

  Future<void> _state(
      HttpRequest request, HttpResponse response, _Share share) async {
    final competition = share.competition();
    if (competition == null) {
      await _plain(response, HttpStatus.notFound, 'That competition is gone.');
      return;
    }
    final feed = competitionFeed(
      share.meet()!,
      competition,
      share.results(),
      isPersonalBest: share.isPersonalBest,
    );
    // The clock in 'asOf' moves every second, so the tag is taken over the
    // competition without it: a quiet round between throws should cost a
    // 304 and not 15 KB, and the page's own clock is allowed to be as old
    // as the last thing that actually happened.
    final tag = '"${_fingerprint(jsonEncode({...feed}..remove('asOf')))}"';
    if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == tag) {
      response.statusCode = HttpStatus.notModified;
      response.headers.set(HttpHeaders.etagHeader, tag);
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.etagHeader, tag);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(feed));
    await response.close();
  }

  /// This competition's results sheet, written on demand — the same PDF the
  /// coach's own share button produces, because it is the same call.
  /// [meetResultsPdf] is pure Dart over the meet and the record book, so
  /// there is nothing to stage on disk first.
  ///
  /// This competition's and no other: the link was handed out at one ring.
  Future<void> _sheet(HttpResponse response, _Share share) async {
    final competition = share.competition();
    final meet = share.meet();
    if (competition == null || meet == null) {
      await _plain(response, HttpStatus.notFound, 'That competition is gone.');
      return;
    }
    final bytes = meetResultsPdf(meet, share.results(), only: competition);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('application', 'pdf');
    // Safe to quote unescaped: ResultsSheet.fileName has already stripped
    // the name to what a file system will take, which is a subset of what a
    // header will.
    response.headers.set('content-disposition',
        'attachment; filename="${ResultsSheet.fileName(meet, competition)}"');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.add(bytes);
    await response.close();
  }

  Future<void> _plain(HttpResponse response, int status, String body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(body);
    await response.close();
  }

  /// A cheap, stable hash for the ETag — FNV-1a, which is a few lines
  /// rather than a dependency. A collision costs one stale poll of a board
  /// that is about to be polled again, which is the right price for not
  /// pulling in a hashing library to compare two strings.
  static String _fingerprint(String body) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(body)) {
      hash ^= unit;
      // Kept inside 64 bits by hand: Dart's ints are 64-bit and signed, and
      // the multiply is allowed to overflow, which is what FNV expects.
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(36);
  }
}

/// One competition being served, and how to read it.
class _Share {
  const _Share({
    required this.token,
    required this.url,
    required this.meetId,
    required this.event,
    required this.implementKg,
    required this.meet,
    required this.results,
    this.isPersonalBest,
  });

  final String token;
  final String url;
  final String meetId;
  final ThrowEvent event;
  final double implementKg;

  final Meet? Function() meet;
  final List<ThrowResult> Function() results;
  final bool Function(ThrowResult)? isPersonalBest;

  /// The competition as it stands, looked up fresh: an athlete entered
  /// between one poll and the next is in the field by the second one.
  /// Null once the meet — or everybody in this event — has gone.
  MeetCompetition? competition() {
    final held = meet();
    if (held == null) return null;
    for (final competition in MeetCompetition.of(held)) {
      if (competition.event == event && competition.implementKg == implementKg) {
        return competition;
      }
    }
    return null;
  }
}
