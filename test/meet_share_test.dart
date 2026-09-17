import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/meet_server.dart';
import 'package:throwlab/utils/meet_feed.dart';
import 'package:throwlab/utils/pdf_text.dart';

/// Sharing the competition with the people standing at it.
///
/// Two halves: the feed, which is the competition worked out once and
/// handed over as answers, and the server, which is the phone itself
/// answering a browser on the same wifi. The server half binds a real
/// socket on the loopback — there is no point faking an HTTP server to
/// test an HTTP server — and talks to it with dart:io's own client.
void main() {
  ThrowMark mark(String id, String athlete, double distance,
          {DistanceUnit unit = DistanceUnit.meters}) =>
      ThrowMark(
        id: id,
        athlete: athlete,
        event: ThrowEvent.discus,
        implementKg: 1,
        distance: distance,
        distanceUnit: unit,
        achievedOn: DateTime(2026, 6, 13),
      );

  MeetEntry entry(
    String id,
    String athlete,
    List<MeetAttempt?> attempts, {
    int order = 0,
    int flight = 1,
    bool tracked = true,
  }) {
    final made = MeetEntry(
      id: id,
      athlete: athlete,
      event: ThrowEvent.discus,
      implementKg: 1,
      tracked: tracked,
      order: order,
      flight: flight,
    );
    for (var round = 0; round < attempts.length; round++) {
      made.setAttempt(round, attempts[round]);
    }
    return made;
  }

  Meet meet({int rounds = 6, int prelimRounds = 6, int advancing = 99}) => Meet(
        id: 'k1',
        name: 'County Champs',
        date: DateTime(2026, 6, 13),
        venue: 'Sportcity',
        rounds: rounds,
        prelimRounds: prelimRounds,
        advancing: advancing,
      );

  /// Two throwers, one of them a rival whose marks live on the attempt
  /// rather than in the record book.
  (Meet, List<ThrowResult>) competition() {
    final made = meet();
    made.entries.addAll([
      entry('e1', 'Jakob Sandhagen', [
        MeetAttempt.mark('m1'),
        MeetAttempt.foul(),
        MeetAttempt.mark('m2'),
      ], order: 0),
      entry('e2', 'N. Achebe (Croydon)', [
        MeetAttempt.untracked(44.10),
        MeetAttempt.pass(),
      ], order: 1, tracked: false),
    ]);
    return (made, [mark('m1', 'Jakob Sandhagen', 41.2), mark('m2', 'Jakob Sandhagen', 46.55)]);
  }

  group('the feed', () {
    test('reads the competition in standings order, with the series', () {
      final (made, results) = competition();
      final feed = meetFeed(made, results, at: DateTime.utc(2026, 6, 13, 14));

      expect(feed['name'], 'County Champs');
      expect(feed['venue'], 'Sportcity');
      expect(feed['asOf'], '2026-06-13T14:00:00.000Z');

      final events = feed['competitions'] as List;
      expect(events, hasLength(1));
      final only = events.first as Map<String, dynamic>;
      expect(only['id'], 'discus:1.0');
      expect(only['label'], 'Discus · 1 kg');

      final places = only['places'] as List;
      expect(places.map((p) => p['name']),
          ['Jakob Sandhagen', 'N. Achebe (Croydon)']);
      expect(places.first['best'], '46.55 m');
      expect(places.first['placeLabel'], '1st');
      // Ranked first, but second in the throwing order — one list, sorted
      // twice, which is what the Series tab reads.
      expect(places.first['order'], 0);
      expect(places.last['tracked'], false);

      final series = places.first['series'] as List;
      expect(series[0]['mark'], '41.20 m');
      expect(series[1]['kind'], 'foul');
      expect(series[1].containsKey('mark'), isFalse);
      expect(series[2]['mark'], '46.55 m');
      // Untaken rounds are nothing at all, which is what leaves the box
      // empty rather than drawing a foul in it.
      expect(series[3], isNull);
      expect(places.first['bestRound'], 3);
      expect(places.first['fouls'], 1);
      expect(places.last['passes'], 1);
    });

    test('writes each mark in the unit it was measured in', () {
      final made = meet();
      made.entries.add(entry('e1', 'Ruth Oyelaran', [MeetAttempt.mark('m1')]));
      final feed = meetFeed(made,
          [mark('m1', 'Ruth Oyelaran', 12.19, unit: DistanceUnit.feet)]);
      final place = ((feed['competitions'] as List).first['places'] as List).first;
      // To the lesser quarter inch, the way the tape was read — never
      // '39.99 ft' beside a sheet that says 39-11.75.
      expect(place['best'], '39-11.75');
      expect((place['series'] as List).first['mark'], '39-11.75');
    });

    test('names the three an infield calls out', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.mark('m1')], order: 0),
        entry('e2', 'Ben', const [], order: 1),
        entry('e3', 'Cal', const [], order: 2),
        entry('e4', 'Dee', const [], order: 3),
      ]);
      final feed = meetFeed(made, [mark('m1', 'Ama', 40)]);
      final flight = (feed['competitions'] as List).first['flight'];
      expect(flight['up'], 'Ben');
      expect(flight['onDeck'], 'Cal');
      expect(flight['inTheHole'], 'Dee');
      expect(flight['round'], 1);
      expect(flight['thrown'], 1);
      expect(flight['fieldSize'], 4);
    });

    test('says where the cut falls and who is still in it', () {
      final made = meet(rounds: 6, prelimRounds: 3, advancing: 2);
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(50)], order: 0, tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(45)], order: 1, tracked: false),
        entry('e3', 'Cal', [MeetAttempt.untracked(40)], order: 2, tracked: false),
      ]);
      final only = (meetFeed(made, const [])['competitions'] as List).first;
      expect(only['prelims'], 3);
      expect(only['cut']['has'], isTrue);
      // Nobody has had their three yet, so nobody is out — an athlete
      // sitting third with a round in hand is still in the competition.
      expect(only['cut']['made'], isFalse);
      expect(only['cut']['mark'], '45.00 m');
      final places = only['places'] as List;
      expect(places.map((p) => p['advancing']), [true, true, false]);
      expect(places.every((p) => p['throwsInFinal'] == true), isTrue);
    });

    test('flags a personal best the way the record book does', () {
      final (made, results) = competition();
      final feed = meetFeed(made, results,
          isPersonalBest: (result) => result.id == 'm2');
      final series =
          ((feed['competitions'] as List).first['places'] as List).first['series'];
      expect(series[0].containsKey('pb'), isFalse);
      expect(series[2]['pb'], isTrue);
    });

    test('draws the board to a scale, with the marks across it', () {
      final (made, results) = competition();
      final board = (meetFeed(made, results)['competitions'] as List).first['board'];
      expect(board['far'] - board['near'], greaterThan(0));
      expect(board['markerLines'], isNotEmpty);
      final marks = board['marks'] as List;
      expect(marks, isNotEmpty);
      // The leader's line, labelled the way a board is read: the surname
      // and the school, never the initial.
      final first = marks.firstWhere((m) => m['line'] == 'first');
      expect(first['label'], '1st');
      expect(first['name'], 'Sandhagen');
      expect(first['mark'], '46.55 m');
      expect(first['fraction'], inInclusiveRange(0, 1));
    });

    test('sends every competition on the meet, not just one', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', const []),
        MeetEntry(
            id: 'e2',
            athlete: 'Ben',
            event: ThrowEvent.javelin,
            implementKg: 0.8),
      ]);
      final events = meetFeed(made, const [])['competitions'] as List;
      expect(events.map((e) => e['id']), ['discus:1.0', 'javelin:0.8']);
    });
  });

  group('the server', () {
    late MeetServer server;
    late Meet shared;
    late List<ThrowResult> results;

    late Future<HttpServer> Function(int) realBind;
    late Future<String?> Function() realAddress;

    setUp(() async {
      // Loopback rather than every interface: a test has no business
      // opening a port to whatever network CI is on. Both are static, so
      // what was there is put back rather than guessed at.
      realBind = MeetServer.bind;
      realAddress = MeetServer.lanAddress;
      MeetServer.bind =
          (port) => HttpServer.bind(InternetAddress.loopbackIPv4, port);
      MeetServer.lanAddress = () async => '127.0.0.1';
      final (made, marks) = competition();
      shared = made;
      results = marks;
      server = MeetServer();
      final started = await server.start(
        meetId: shared.id,
        meet: () => shared,
        results: () => results,
        isPersonalBest: (result) => result.id == 'm2',
      );
      expect(started, isTrue, reason: 'the socket should open on loopback');
    });

    tearDown(() async {
      await server.stop();
      MeetServer.bind = realBind;
      MeetServer.lanAddress = realAddress;
    });

    Future<({int status, List<int> bytes, HttpHeaders headers})> get(
      String path, {
      String? etag,
    }) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('${server.url}$path'));
        if (etag != null) request.headers.set('if-none-match', etag);
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return (
          status: response.statusCode,
          bytes: bytes,
          headers: response.headers
        );
      } finally {
        client.close(force: true);
      }
    }

    test('hands out a link with an unguessable token on it', () {
      expect(server.isSharing, isTrue);
      expect(server.meetId, shared.id);
      expect(server.url, startsWith('http://127.0.0.1:'));
      expect(server.url, matches(RegExp(r'/M/[23456789A-HJ-NP-Z]{6}$')));
      // Uppercase throughout, which is what lets a QR encoder use
      // alphanumeric mode and draw a fatter code.
      expect(server.qrPayload, server.url!.toUpperCase());
    });

    test('serves the page at the link', () async {
      final res = await get('');
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'text/html');
      final html = utf8.decode(res.bytes);
      expect(html, contains('<title>ThrowLab</title>'));
      // The page is full of typographic dashes and ellipses, and the feed
      // carries whatever a heat sheet spelled a name with. Both are written
      // through a content type that has to name its charset, or a browser
      // reads them as Latin-1 and paints mojibake.
      expect(html, contains('connecting…'));
      expect(res.headers.value('x-robots-tag'), contains('noindex'));
    });

    test('turns away anything that is not the shared meet', () async {
      final wrong = server.url!.replaceAll(RegExp(r'/M/\w+$'), '/M/AAAAAA');
      final client = HttpClient();
      final response = await (await client.getUrl(Uri.parse(wrong))).close();
      await response.drain<void>();
      client.close(force: true);
      expect(response.statusCode, 404);

      expect((await get('/library')).status, 404);
      expect((await get('/state/../state')).status, anyOf(404, 200));
    });

    test('answers the state with the competition as it stands', () async {
      shared.entryById('e2')!.athlete = 'Zoë Müller-Świątek';
      final state = await get('/state');
      expect(state.headers.contentType?.charset, 'utf-8');
      final first = jsonDecode(utf8.decode(state.bytes));
      expect(first['name'], 'County Champs');
      final named = (first['competitions'] as List).first['places'] as List;
      expect(named.map((p) => p['name']), contains('Zoë Müller-Świątek'));
      final places = (first['competitions'] as List).first['places'] as List;
      expect(places.first['best'], '46.55 m');

      // A mark entered on the phone shows up on the next poll without
      // anybody telling the server: it reads the meet, it does not hold a
      // copy of it.
      shared.entryById('e2')!.setAttempt(2, MeetAttempt.untracked(47.8));
      final second = jsonDecode(utf8.decode((await get('/state')).bytes));
      final after = (second['competitions'] as List).first['places'] as List;
      expect(after.first['name'], 'Zoë Müller-Świątek');
      expect(after.first['best'], '47.80 m');
    });

    test('costs a 304 while nothing is being thrown', () async {
      final fresh = await get('/state');
      final tag = fresh.headers.value('etag');
      expect(tag, isNotNull);

      final again = await get('/state', etag: tag);
      expect(again.status, 304);
      expect(again.bytes, isEmpty);

      // The clock in 'asOf' moves every second and must not be what
      // decides it — only the competition changing should.
      shared.entryById('e2')!.setAttempt(2, MeetAttempt.untracked(47.8));
      final moved = await get('/state', etag: tag);
      expect(moved.status, 200);
    });

    test('writes the results sheet on demand', () async {
      final res = await get('/results.pdf');
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'application/pdf');
      expect(res.headers.value('content-disposition'),
          contains('County Champs'));
      final text = pdfText(Uint8List.fromList(res.bytes))!;
      expect(text, contains('COUNTY CHAMPS'));
      expect(text, contains('Sandhagen'));
    });

    test('writes one competition\'s sheet when asked for it', () async {
      expect((await get('/results.pdf?event=discus:1.0')).status, 200);
      expect((await get('/results.pdf?event=javelin:0.8')).status, 404);
    });

    test('stops answering once sharing is stopped', () async {
      final url = server.url!;
      await server.stop();
      expect(server.isSharing, isFalse);
      expect(server.url, isNull);
      final client = HttpClient();
      await expectLater(
        client.getUrl(Uri.parse(url)).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
      client.close(force: true);
    });
  });
}
