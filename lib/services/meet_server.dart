import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/meet.dart';
import '../models/throw_video.dart';
import '../utils/meet_feed.dart';
import '../utils/meet_report.dart';
import '../utils/spectator_page.dart';
import 'results_sheet.dart';

/// Shares the competition in front of you with everybody standing at it.
///
/// The phone is the server. There is no hosting, no account and nothing
/// uploaded: this binds a socket, and anyone on the same wifi — or on the
/// phone's own hotspot, which is the case that actually works at a track —
/// opens the link in a browser and follows the meet. It is the only shape
/// of live sharing that survives a field with no signal on it, which is
/// most of them, and it is the reason the fonts are bundled too.
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

  HttpServer? _server;
  String? _meetId;
  String? _token;
  String? _url;
  String? _error;

  Meet? Function()? _meet;
  List<ThrowResult> Function()? _results;
  bool Function(ThrowResult)? _isPersonalBest;

  /// How the server opens its socket. Swapped out in a test, which has no
  /// business binding a real port on whatever machine CI runs on.
  @visibleForTesting
  static Future<HttpServer> Function(int port) bind =
      (port) => HttpServer.bind(InternetAddress.anyIPv4, port);

  /// The phone's own address on the network it is on. Swapped out in a
  /// test, where there is no wifi to ask about.
  @visibleForTesting
  static Future<String?> Function() lanAddress = _findLanAddress;

  bool get isSharing => _server != null;

  /// Which meet is being shared, so a screen can tell whether it is this
  /// one — sharing is per meet, and a coach at two in a weekend should not
  /// see the other one's link over this one's field.
  String? get meetId => _meetId;

  /// What to put on the QR and in somebody's hand.
  String? get url => _url;

  /// Non-null when the socket wouldn't open. Sharing is an extra; a phone
  /// that refuses to bind still runs the meet exactly as before.
  String? get error => _error;

  /// The link spelled for somebody to act on rather than to look at:
  /// all capitals, which is what a QR is scanned from and what gets read
  /// out when it won't scan. Scheme and host are case-insensitive and the
  /// path is uppercase already, so this is the same link.
  ///
  /// It does not make the code any smaller — the encoder we use writes
  /// byte mode whatever the characters are, and QR's tighter alphanumeric
  /// mode has no '#' in its charset anyway, which the relay link will
  /// need. Short is what keeps the code fat here, not case.
  String? get qrPayload => _url?.toUpperCase();

  /// Starts sharing [meetId]. Returns whether the socket opened.
  ///
  /// The three callbacks are how it reads the meet — live, per request, so
  /// nothing here can go stale or hold a copy of the competition that
  /// disagrees with the screen.
  Future<bool> start({
    required String meetId,
    required Meet? Function() meet,
    required List<ThrowResult> Function() results,
    bool Function(ThrowResult)? isPersonalBest,
  }) async {
    await stop();
    _meet = meet;
    _results = results;
    _isPersonalBest = isPersonalBest;
    _meetId = meetId;
    _token = _newToken();

    for (final port in _ports) {
      try {
        _server = await bind(port);
        break;
      } on SocketException {
        // Something else has it. Try the next one, and let the last
        // failure be the one reported.
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

    final host = await lanAddress();
    if (host == null) {
      await stop();
      _fail('This phone is not on a network. Turn on wifi or a hotspot.');
      return false;
    }

    _url = 'http://$host:${server.port}/M/$_token';
    _error = null;
    server.listen(_handle, onError: (_) {
      // A dead socket is a stopped share; say so rather than leaving a
      // link on screen that nothing is answering.
      stop();
    });
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _meetId = null;
    _token = null;
    _url = null;
    _meet = null;
    _results = null;
    _isPersonalBest = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {
        // Already gone.
      }
    }
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _url = null;
    _meetId = null;
    _token = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Not awaited: dispose cannot be async, and a socket closing behind a
    // disposed notifier is nobody's problem.
    _server?.close(force: true);
    _server = null;
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
    // Nothing here is for a crawler, and a meet's field is a list of
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
      if (segments.length < 2 ||
          segments[0] != 'M' ||
          _token == null ||
          segments[1] != _token) {
        await _plain(response, HttpStatus.notFound, 'Nothing here.');
        return;
      }
      final rest = segments.length > 2 ? segments[2] : '';
      switch (rest) {
        case '':
          await _page(response);
        case 'state':
          await _state(request, response);
        case 'results.pdf':
          await _sheet(request, response);
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
    // Small enough not to be worth a caching story, and it changes when
    // the app updates, which a spectator's browser has no way to know.
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(spectatorPage);
    await response.close();
  }

  Future<void> _state(HttpRequest request, HttpResponse response) async {
    final meet = _meet?.call();
    if (meet == null) {
      await _plain(response, HttpStatus.notFound, 'That meet is gone.');
      return;
    }
    final feed = meetFeed(
      meet,
      _results?.call() ?? const [],
      isPersonalBest: _isPersonalBest,
    );
    // The clock in 'asOf' moves every second, so the tag is taken over the
    // competition without it: a quiet round between throws should cost a
    // 304 and not 15 KB, and the page's own clock is allowed to be as old
    // as the last thing that actually happened.
    final tag = '"${_fingerprint(jsonEncode({...feed}..remove('asOf')))}"';
    final body = jsonEncode(feed);
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
    response.write(body);
    await response.close();
  }

  /// The results sheet, written on demand — the same PDF the coach's own
  /// share button produces, because it is the same call. [meetResultsPdf]
  /// is pure Dart over the meet and the record book, so there is nothing
  /// to stage on disk first.
  Future<void> _sheet(HttpRequest request, HttpResponse response) async {
    final meet = _meet?.call();
    if (meet == null) {
      await _plain(response, HttpStatus.notFound, 'That meet is gone.');
      return;
    }
    final wanted = request.uri.queryParameters['event'];
    MeetCompetition? only;
    if (wanted != null) {
      for (final competition in MeetCompetition.of(meet)) {
        if ('${competition.event.name}:${competition.implementKg}' == wanted) {
          only = competition;
          break;
        }
      }
      if (only == null) {
        await _plain(response, HttpStatus.notFound, 'No such event.');
        return;
      }
    }
    final bytes = meetResultsPdf(meet, _results?.call() ?? const [], only: only);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('application', 'pdf');
    // Safe to quote unescaped: ResultsSheet.fileName has already stripped
    // the name to what a file system will take, which is a subset of what
    // a header will.
    response.headers.set('content-disposition',
        'attachment; filename="${ResultsSheet.fileName(meet, only)}"');
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
