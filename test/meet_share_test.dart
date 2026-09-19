import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ColorScheme;
import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/meet_server.dart';
import 'package:throwlab/utils/meet_feed.dart';
import 'package:throwlab/utils/pdf_text.dart';
import 'package:throwlab/utils/share_payload.dart';

/// Sharing a competition with the people standing at it.
///
/// Two halves: the feed, which is one competition worked out once and
/// handed over as answers, and the server, which is the phone itself
/// answering a browser on the same wifi. The server half binds a real
/// socket on the loopback — there is no point faking an HTTP server to test
/// an HTTP server — and talks to it with dart:io's own client.
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
    ThrowEvent event = ThrowEvent.discus,
    double implementKg = 1,
  }) {
    final made = MeetEntry(
      id: id,
      athlete: athlete,
      event: event,
      implementKg: implementKg,
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

  /// The discus of a meet, and the marks behind it. One of the two is a
  /// rival, whose distances live on the attempt rather than in the record
  /// book.
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
    return (
      made,
      [
        mark('m1', 'Jakob Sandhagen', 41.2),
        mark('m2', 'Jakob Sandhagen', 46.55),
      ]
    );
  }

  /// The one competition on [made] — or the one matching [event].
  MeetCompetition only(Meet made, [ThrowEvent? event]) =>
      MeetCompetition.of(made)
          .firstWhere((c) => event == null || c.event == event);

  Map<String, dynamic> feedOf(Meet made, List<ThrowResult> results,
          {DateTime? at,
          bool Function(ThrowResult)? isPersonalBest,
          ThrowEvent? event,
          List<String>? following}) =>
      competitionFeed(made, only(made, event), results,
          at: at, isPersonalBest: isPersonalBest, following: following);

  group('the feed', () {
    test('reads the competition in standings order, with the series', () {
      final (made, results) = competition();
      final feed = feedOf(made, results, at: DateTime.utc(2026, 6, 13, 14));

      expect(feed['meet'], 'County Champs');
      expect(feed['venue'], 'Sportcity');
      expect(feed['asOf'], '2026-06-13T14:00:00.000Z');
      expect(feed['id'], 'discus:1.0');
      expect(feed['label'], 'Discus · 1 kg');
      expect(feed['event'], 'discus');
      // The color the discus wears everywhere else in the app.
      expect(feed['tint'], '#69f0ae');

      final places = feed['places'] as List;
      expect(places.map((p) => p['name']),
          ['Jakob Sandhagen', 'N. Achebe (Croydon)']);
      expect(places.first['best'], '46.55 m');
      expect(places.first['placeLabel'], '1st');
      // Ranked first, and first in the throwing order too — one list,
      // sorted twice, which is what the Series tab reads.
      expect(places.first['order'], 0);
      expect(places.last['tracked'], false);

      final series = places.first['series'] as List;
      expect(series[0]['mark'], '41.20 m');
      expect(series[1]['kind'], 'foul');
      expect(series[1].containsKey('mark'), isFalse);
      expect(series[2]['mark'], '46.55 m');
      // A box writes the mark without its unit; six across a phone have no
      // room for one on every one.
      expect(series[2]['short'], '46.55');
      // Untaken rounds are nothing at all, which is what leaves the box
      // empty rather than drawing a foul in it.
      expect(series[3], isNull);
      expect(places.first['bestRound'], 3);
      expect(places.first['fouls'], 1);
      expect(places.last['passes'], 1);
      // The line the app writes under its own athletes, and only under
      // them — the rest of the field is here to be placed against.
      expect(places.first['consistency'], 'averaging 43.88 m from 2 · 1 foul');
      expect(places.last.containsKey('consistency'), isFalse);
    });

    test('writes each mark in the unit it was measured in', () {
      final made = meet();
      made.entries.add(entry('e1', 'Ruth Oyelaran', [MeetAttempt.mark('m1')]));
      final feed = feedOf(
          made, [mark('m1', 'Ruth Oyelaran', 12.19, unit: DistanceUnit.feet)]);
      final place = (feed['places'] as List).first;
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
      final flight = feedOf(made, [mark('m1', 'Ama', 40)])['flight'];
      final calls = flight['calls'] as List;
      expect(calls.map((c) => c['label']), ['up', 'on deck', 'in the hole']);
      expect(calls.map((c) => c['name']), ['Ben', 'Cal', 'Dee']);
      expect(flight['round'], 1);
      expect(flight['thrown'], 1);
      expect(flight['fieldSize'], 4);
      // The words the app's own header uses, rather than two numbers for
      // the page to join up itself.
      expect(flight['thrownLabel'], '1 of 4 thrown');
      expect(flight['progress'], 0.25);
      // Whoever is in front, with the mark they are in front on.
      expect(flight['leading']['label'], 'leading');
      expect(flight['leading']['name'], 'Ama');
      expect(flight['leading']['mark'], '40.00 m');
    });

    test('says where the cut falls and who is still in it', () {
      final made = meet(rounds: 6, prelimRounds: 3, advancing: 2);
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(50)],
            order: 0, tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(45)],
            order: 1, tracked: false),
        entry('e3', 'Cal', [MeetAttempt.untracked(40)],
            order: 2, tracked: false),
      ]);
      final feed = feedOf(made, const []);
      expect(feed['prelims'], 3);
      expect(feed['cut']['has'], isTrue);
      // Nobody has had their three yet, so nobody is out — an athlete
      // sitting third with a round in hand is still in the competition.
      expect(feed['cut']['made'], isFalse);
      expect(feed['cut']['mark'], '45.00 m');
      final places = feed['places'] as List;
      expect(places.map((p) => p['advancing']), [true, true, false]);
      expect(places.every((p) => p['throwsInFinal'] == true), isTrue);
    });

    test('hands over the lines the app prints under its board', () {
      final made = meet(rounds: 6, prelimRounds: 3, advancing: 2);
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(50)],
            order: 0, tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(45)],
            order: 1, tracked: false),
        // The coach's own, third and out of the final as things stand.
        entry('e3', 'Cal', [MeetAttempt.mark('m1')], order: 2),
        entry('e4', 'Dee', const [], order: 3, tracked: false),
      ]);
      final feed = feedOf(made, [mark('m1', 'Cal', 40)]);
      final caption = feed['caption'] as List;
      // What the throw in the circle has to do, in the event's own color,
      // and what the coach's athlete is short of, in the theme's.
      expect(caption.first['text'], '50.01 m takes the lead');
      expect(caption.first['tone'], 'tint');
      expect(caption.last['text'], 'Cal needs 45.01 m to make the final');
      expect(caption.last['tone'], 'accent');
      // And on the row itself, which is where the standings say it.
      final cal = (feed['places'] as List).firstWhere((p) => p['name'] == 'Cal');
      expect(cal['needed'], 'needs 45.01 m to make the final');
      // The rest of the field never carries it: what they need is not the
      // coach's problem.
      final ama = (feed['places'] as List).first;
      expect(ama.containsKey('needed'), isFalse);
      // What the cut is, over the table.
      expect(feed['cut']['label'], 'top 2 advance');
    });

    test('names who is about to throw, and the sector they throw into', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.mark('m1')], order: 0),
        entry('e2', 'Ben', const [], order: 1),
      ]);
      final feed = feedOf(made, [mark('m1', 'Ama', 40)]);
      // Where in the throwing order the live card's athlete sits, which is
      // what the field is already keyed by on the wire.
      expect(feed['flight']['upOrder'], 1);
      expect((feed['places'] as List)
          .firstWhere((p) => p['order'] == 1)['name'], 'Ben');
      // Half the sector, so the board is drawn to the real angle for the
      // event rather than to a wedge somebody picked.
      expect(feed['sector'], closeTo(34.92 / 2, 0.001));
      expect(feedOf(meet()..entries.addAll([
            entry('j1', 'Ama', const [], event: ThrowEvent.javelin,
                implementKg: 0.8),
          ]), const [], event: ThrowEvent.javelin)['sector'],
          closeTo(28.96 / 2, 0.001));
    });

    test('says when the coach’s own throw, for a flight that is not theirs',
        () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', const [], order: 0, flight: 1, tracked: false),
        entry('e2', 'Ben', const [], order: 1, flight: 1, tracked: false),
        entry('e3', 'Cal', const [], order: 2, flight: 2),
      ]);
      expect(feedOf(made, const [])['flight']['elsewhere'],
          'Cal throws in flight 2');
    });

    test('flags a personal best the way the record book does', () {
      final (made, results) = competition();
      final feed =
          feedOf(made, results, isPersonalBest: (result) => result.id == 'm2');
      final series = (feed['places'] as List).first['series'];
      expect(series[0].containsKey('pb'), isFalse);
      expect(series[2]['pb'], isTrue);
    });

    test('draws the board to a scale, with the marks across it', () {
      final (made, results) = competition();
      final board = feedOf(made, results)['board'];
      expect(board['far'] - board['near'], greaterThan(0));
      expect(board['markerLines'], isNotEmpty);
      // What the app captions its own board with, so a gap can be read as
      // a distance without arithmetic off the labels.
      expect(board['gridLabel'], endsWith(' m lines'));
      final marks = board['marks'] as List;
      // The leader's line, labelled the way a board is read: the surname
      // and the school, never the initial.
      final first = marks.firstWhere((m) => m['line'] == 'first');
      expect(first['label'], '1st');
      expect(first['name'], 'Sandhagen');
      expect(first['mark'], '46.55 m');
      expect(first['fraction'], inInclusiveRange(0, 1));
      // Nothing is off this board, so nothing carries an edge.
      expect(marks.every((m) => !m.containsKey('off')), isTrue);
    });

    test('says how far out a mark the band broke off landed', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Runaway', [MeetAttempt.untracked(60)],
            order: 0, tracked: false),
        entry('e2', 'Mine', [MeetAttempt.mark('m1')], order: 1),
        entry('e3', 'Rival', [MeetAttempt.untracked(40.4)],
            order: 2, tracked: false),
      ]);
      final board =
          feedOf(made, [mark('m1', 'Mine', 40.2)])['board'] as Map;
      final runaway = (board['marks'] as List)
          .firstWhere((m) => m['name'] == 'Runaway');
      // Off the far edge, with how far past it — a distance, so it is
      // spelled here rather than subtracted in a browser. The page draws
      // an arrow that way and prints this beside it.
      expect(runaway['off'], 'far');
      expect(runaway['out'], endsWith(' m'));
      expect(double.parse((runaway['out'] as String).split(' ').first),
          closeTo(60 - (board['far'] as double), 0.005));
    });

    test('names the coach’s own as the page’s until somebody chooses', () {
      final (made, results) = competition();
      final feed = feedOf(made, results);
      // Nobody has said who they are here for, so the page reads as the
      // coach's own screen — which is what it has always been.
      expect(feed.containsKey('following'), isFalse);
      final places = feed['places'] as List;
      for (final place in places) {
        expect(place['mine'], place['tracked']);
      }
      // And every row carries the key a spectator would tick it by.
      expect(places.map((p) => p['key']), containsAll(['e1', 'e2']));
    });

    test('says the same things about the athlete a spectator follows', () {
      final made = meet(rounds: 6, prelimRounds: 3, advancing: 1);
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(50)],
            order: 0, tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(45), MeetAttempt.foul()],
            order: 1, tracked: false),
        // The coach's own, who a parent in the stand has no reason to
        // be reading the board for.
        entry('e3', 'Cal', [MeetAttempt.mark('m1'), MeetAttempt.foul()],
            order: 2),
      ]);
      final results = [mark('m1', 'Cal', 40)];

      // The coach's screen: Cal is theirs, and the lines are about Cal.
      final coach = feedOf(made, results);
      expect((coach['caption'] as List).last['text'],
          'Cal needs 50.01 m to make the final');

      // The same competition, read by somebody who came to watch Ben.
      final feed = feedOf(made, results, following: ['e2']);
      expect(feed['following'], [
        {'key': 'e2', 'name': 'Ben'}
      ]);
      final places = feed['places'] as List;
      final ben = places.firstWhere((p) => p['name'] == 'Ben');
      final cal = places.firstWhere((p) => p['name'] == 'Cal');
      // The emphasis, the averaging line and what is left to do all move
      // to Ben — and Cal is the rest of the field now, exactly as Ben was.
      expect(ben['mine'], isTrue);
      expect(cal['mine'], isFalse);
      // Whose marks the coach keeps has not changed, and is not the same
      // question.
      expect(ben['tracked'], isFalse);
      expect(cal['tracked'], isTrue);
      expect(ben['consistency'], '1 foul');
      expect(cal.containsKey('consistency'), isFalse);
      expect(ben['needed'], 'needs 50.01 m to make the final');
      expect(cal.containsKey('needed'), isFalse);
      // Not a new sentence anywhere: the caption is the app's own line,
      // about the athlete it is being read for.
      expect((feed['caption'] as List).last['text'],
          'Ben needs 50.01 m to make the final');
    });

    test('draws the board’s own line for whoever is being followed', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(50)],
            order: 0, tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(49)],
            order: 1, tracked: false),
        entry('e3', 'Cal', [MeetAttempt.untracked(48)],
            order: 2, tracked: false),
        entry('e4', 'Dee', [MeetAttempt.untracked(47)],
            order: 3, tracked: false),
      ]);
      // Nobody's board: the podium, and the rest of the field as the faint
      // lines behind it.
      final plain = feedOf(made, const [])['board']['marks'] as List;
      expect(plain.map((m) => m['line']), isNot(contains('mine')));

      final marks = feedOf(made, const [], following: ['e4'])['board']['marks']
          as List;
      final mine = marks.firstWhere((m) => m['line'] == 'mine');
      // Named the way a board names one, and labelled with the place they
      // have to climb.
      expect(mine['name'], 'Dee');
      expect(mine['label'], '4th');
    });

    test('follows as many of the field as somebody ticked', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(50)],
            order: 0, tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(49)],
            order: 1, tracked: false),
        entry('e3', 'Cal', [MeetAttempt.untracked(48)],
            order: 2, tracked: false),
        entry('e4', 'Dee', [MeetAttempt.untracked(47)],
            order: 3, tracked: false),
        entry('e5', 'Eve', [MeetAttempt.untracked(46)],
            order: 4, tracked: false),
      ]);
      // A parent with two in the field, and a club's supporter with four:
      // one is not the case this is built for, and the coach's own 'yours'
      // was never one athlete either.
      final feed = feedOf(made, const [], following: ['e4', 'e5']);
      expect(feed['following'], [
        {'key': 'e4', 'name': 'Dee'},
        {'key': 'e5', 'name': 'Eve'},
      ]);
      final places = feed['places'] as List;
      expect(
          places.where((p) => p['mine'] == true).map((p) => p['name']),
          ['Dee', 'Eve']);
      // A line each on the board, the way a coach's board draws a line for
      // each of theirs.
      final marks = feed['board']['marks'] as List;
      expect(marks.where((m) => m['line'] == 'mine').map((m) => m['name']),
          ['Dee', 'Eve']);
      // Echoed back in the order the field is read down, whatever order
      // the boxes were ticked in.
      expect(feedOf(made, const [], following: ['e5', 'e4'])['following'],
          feed['following']);
      // And anybody the competition no longer holds is simply left out,
      // which leaves the rest of the ticks alone.
      expect(feedOf(made, const [], following: ['e4', 'eGone'])['following'], [
        {'key': 'e4', 'name': 'Dee'}
      ]);
    });

    test('drops a choice the competition no longer holds', () {
      final (made, results) = competition();
      final feed = feedOf(made, results, following: ['e404']);
      // Somebody taken off the meet is nobody to follow. The answer comes
      // back without one, which is what tells the page to stop asking —
      // and it reads as the coach's own again in the meantime.
      expect(feed.containsKey('following'), isFalse);
      expect((feed['places'] as List)
          .firstWhere((p) => p['name'] == 'Jakob Sandhagen')['mine'], isTrue);
    });

    test('asks the flight question about whoever is being followed', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', const [], order: 0, flight: 1, tracked: false),
        entry('e2', 'Ben', const [], order: 1, flight: 1, tracked: false),
        entry('e3', 'Cal', const [], order: 2, flight: 2),
        entry('e4', 'Dee', const [], order: 3, flight: 3, tracked: false),
      ]);
      // The coach is told when theirs throw; a spectator, when theirs do —
      // and it is the same sentence, off [MeetFlight].
      expect(feedOf(made, const [])['flight']['elsewhere'],
          'Cal throws in flight 2');
      expect(feedOf(made, const [], following: ['e4'])['flight']['elsewhere'],
          'Dee throws in flight 3');
      // Nothing at all while one of the ones being followed is in the
      // ring's own flight, because the cards below say it better.
      expect(feedOf(made, const [], following: ['e2', 'e4'])['flight']
          .containsKey('elsewhere'), isFalse);
    });

    test('carries one competition and never the rest of the meet', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ama', [MeetAttempt.untracked(40)], tracked: false),
        entry('e2', 'Ben', [MeetAttempt.untracked(60)],
            tracked: false, event: ThrowEvent.javelin, implementKg: 0.8),
      ]);
      final feed = feedOf(made, const [], event: ThrowEvent.javelin);
      expect(feed['label'], 'Javelin · 800 g');
      // The discus field is somebody else's business, and never appears.
      expect(jsonEncode(feed), isNot(contains('Ama')));
    });
  });

  /// One competition packaged, and the fingerprint that says whether it has
  /// moved.
  ///
  /// The fingerprint has two jobs, and they have to be the same answer: a
  /// server spends it on an ETag so a quiet round costs a 304, and the
  /// publisher pushing at a relay spends it on whether there is anything
  /// worth uploading at all. A hash that moved on its own clock would turn
  /// a competition standing still into a push every few seconds.
  group('the payload', () {
    ShareSource sourceOf(Meet made, List<ThrowResult> results) => ShareSource(
          meetId: made.id,
          event: ThrowEvent.discus,
          implementKg: 1,
          meet: () => made,
          results: () => results,
        );

    test('carries the same competition the feed works out', () {
      final (made, results) = competition();
      final payload = sourceOf(made, results).payload(at: DateTime.utc(2026))!;

      expect(payload.feed, feedOf(made, results, at: DateTime.utc(2026)));
      expect(jsonDecode(payload.encode()), payload.feed);
      expect(payload.etag, '"${payload.fingerprint}"');
    });

    test('holds its fingerprint still while the clock runs', () {
      final (made, results) = competition();
      final source = sourceOf(made, results);

      final early = source.payload(at: DateTime.utc(2026, 6, 13, 14))!;
      final later = source.payload(at: DateTime.utc(2026, 6, 13, 15))!;

      expect(later.feed['asOf'], isNot(early.feed['asOf']));
      expect(later.fingerprint, early.fingerprint);
    });

    test('moves its fingerprint the moment a mark is entered', () {
      final (made, results) = competition();
      final source = sourceOf(made, results);
      final before = source.payload(at: DateTime.utc(2026))!;

      results.add(mark('m3', 'Jakob Sandhagen', 48.02));
      made.entries.first.setAttempt(3, MeetAttempt.mark('m3'));

      expect(source.payload(at: DateTime.utc(2026))!.fingerprint,
          isNot(before.fingerprint));
    });

    test('reads the competition live rather than holding a copy', () {
      final (made, results) = competition();
      final source = sourceOf(made, results);
      source.payload();

      made.entries.add(entry('e3', 'Ama Boateng', [MeetAttempt.untracked(39.5)],
          order: 2, tracked: false));

      expect(jsonEncode(source.payload()!.feed), contains('Boateng'));
    });

    test('has nothing to package once the competition is gone', () {
      final (made, results) = competition();

      expect(sourceOf(made, results).payload(), isNotNull);
      // The meet itself gone — a share outliving the meet it was handed out
      // for is a link with nothing behind it, not a crash.
      expect(
          ShareSource(
            meetId: made.id,
            event: ThrowEvent.discus,
            implementKg: 1,
            meet: () => null,
            results: () => results,
          ).payload(),
          isNull);
      // And the meet still there with nobody left in this event.
      made.entries.clear();
      expect(sourceOf(made, results).payload(), isNull);
    });

    test('knows which competition it is the share for', () {
      final (made, results) = competition();
      final source = sourceOf(made, results);

      expect(source.covers(made.id, ThrowEvent.discus, 1), isTrue);
      // A weight is a competition of its own: a best is per implement, and
      // so is the contest an athlete is placed in.
      expect(source.covers(made.id, ThrowEvent.discus, 1.6), isFalse);
      expect(source.covers(made.id, ThrowEvent.javelin, 1), isFalse);
      expect(source.covers('another', ThrowEvent.discus, 1), isFalse);
    });
  });

  group('a followed set, over the relay', () {
    ShareSource sourceOf(Meet made, List<ThrowResult> results) => ShareSource(
          meetId: made.id,
          event: ThrowEvent.discus,
          implementKg: 1,
          meet: () => made,
          results: () => results,
        );

    /// A field big enough for a set to be a part of, rather than most of
    /// it: one of the coach's own and three other people's.
    (Meet, List<ThrowResult>) wideField() {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Jakob Sandhagen',
            [MeetAttempt.mark('m1'), MeetAttempt.mark('m2')], order: 0),
        entry('e2', 'N. Achebe (Croydon)', [MeetAttempt.untracked(49.10)],
            order: 1, tracked: false),
        entry('e3', 'Ama Boateng (Sale)', [MeetAttempt.untracked(44.30)],
            order: 2, tracked: false),
        entry('e4', 'Rosa Duarte (Wirral)', [MeetAttempt.untracked(38.90)],
            order: 3, tracked: false),
      ]);
      return (
        made,
        [
          mark('m1', 'Jakob Sandhagen', 46.55),
          mark('m2', 'Jakob Sandhagen', 44.02),
        ]
      );
    }

    test('names one question one way however it was ticked', () {
      expect(followingKey(['e3', 'e1']), 'e1,e3');
      expect(followingKey(['e1', 'e3']), 'e1,e3');
      expect(followingKey([' e1 ', 'e1', '', 'e3']), 'e1,e3');
      expect(followingKey([]), isEmpty);
      // A link written by hand rather than ticked out of a field.
      expect(followingKey([List.filled(80, 'x').join()]), isEmpty);
      expect(
          followingKey([for (var i = 0; i < 40; i++) 'e$i']).split(',').length,
          maxFollowed);
    });

    test('answers a set as exactly what it adds to the coach\'s reading', () {
      final (made, results) = wideField();
      final at = DateTime.utc(2026, 6, 13, 14);
      final packaged =
          sourceOf(made, results).packaged(at: at, following: [['e3']])!;
      final overlay = packaged.overlays.single;
      final read = feedOf(made, results, at: at, following: ['e3']);

      expect(overlay.key, 'e3');
      // The base is the coach's own reading, untouched — the page that
      // asks nothing is handed the competition it always was.
      expect(packaged.base.feed, feedOf(made, results, at: at));

      // Every top-level key that moved is in the delta, and every one that
      // did not is absent from it. That is what makes applying it at the
      // other end the same competition as working it out here.
      final set = (overlay.delta['set'] as Map?) ?? const {};
      for (final key in read.keys) {
        if (key == 'places') continue;
        final moved = jsonEncode(packaged.base.feed[key]) != jsonEncode(read[key]);
        expect(set.containsKey(key), moved, reason: key);
      }
      final rows = (overlay.delta['places'] as Map?) ?? const {};
      final before = packaged.base.feed['places'] as List;
      final after = read['places'] as List;
      for (var i = 0; i < after.length; i++) {
        final moved = jsonEncode(before[i]) != jsonEncode(after[i]);
        expect(rows.containsKey('$i'), moved, reason: 'place $i');
      }
    });

    test('sends the rows the set moves and not the field', () {
      final (made, results) = wideField();
      final packaged = sourceOf(made, results)
          .packaged(at: DateTime.utc(2026), following: [['e3']])!;
      final rows = packaged.overlays.single.delta['places'] as Map;

      // Following somebody takes the emphasis off the coach's own and puts
      // it on them. Nobody else in the field is any different, so a field
      // of four sends two rows rather than four — the coach's own, second
      // on 46.55, and Boateng, third on 44.30. Read in standings order,
      // which is the order the places arrive in.
      expect(rows.keys.toSet(), {'1', '2'});
      expect((packaged.base.feed['places'] as List), hasLength(4));
    });

    test('sends a row as the fields that moved, not as the row again', () {
      final (made, results) = wideField();
      final packaged = sourceOf(made, results)
          .packaged(at: DateTime.utc(2026), following: [['e3']])!;
      final rows = packaged.overlays.single.delta['places'] as Map;

      // Whose a row is, and the two lines that hang off that: the
      // averaging line under the coach's own, and what they need to
      // qualify. The name, the place, the series and the rest are the same
      // row whoever is reading it, and are not sent again to say so.
      expect((rows['2'] as Map)['set'], contains('mine'));
      expect((rows['2'] as Map)['set'], isNot(contains('name')));
      expect((rows['2'] as Map)['set'], isNot(contains('series')));
      // And the two lines that only ever appear under whoever's board it
      // is come off the row that stopped being theirs.
      expect((rows['1'] as Map)['set'], {'mine': false});
      expect((rows['1'] as Map)['drop'], ['consistency']);
      // Which is most of the point: a row is five hundred bytes and this
      // is a few dozen.
      expect(jsonEncode(rows['1']).length, lessThan(100));
    });

    test('takes every reading at one instant, so the clock is never in it',
        () {
      final (made, results) = wideField();
      final packaged = sourceOf(made, results)
          .packaged(at: DateTime.utc(2026), following: [['e3']])!;

      expect((packaged.overlays.single.delta['set'] as Map?) ?? const {},
          isNot(contains('asOf')));
    });

    test('fingerprints what the browser will be holding', () {
      final (made, results) = wideField();
      final at = DateTime.utc(2026);
      final packaged =
          sourceOf(made, results).packaged(at: at, following: [['e2', 'e3']])!;

      // The composition, not the difference: the relay hands this straight
      // out as an entity tag, and what is on the other end of it is the
      // competition read for that set.
      expect(packaged.overlays.single.fingerprint,
          SharePayload(feedOf(made, results, at: at, following: ['e2', 'e3']))
              .fingerprint);
      expect(packaged.overlays.single.fingerprint,
          isNot(packaged.base.fingerprint));
    });

    test('answers two spectators who ticked one set once', () {
      final (made, results) = wideField();
      final packaged = sourceOf(made, results).packaged(
          at: DateTime.utc(2026),
          following: [
            ['e3', 'e2'],
            ['e2', 'e3'],
          ]);

      expect(packaged!.overlays, hasLength(1));
      expect(packaged.overlays.single.key, 'e2,e3');
    });

    test('has nothing to add for somebody the field no longer holds', () {
      final (made, results) = wideField();
      final packaged = sourceOf(made, results)
          .packaged(at: DateTime.utc(2026), following: [['gone']])!;

      // The competition is the competition. Nothing is echoed back under
      // `following`, which is what tells the page to stop asking for them
      // rather than to go on following a ghost.
      expect(packaged.overlays.single.delta, isEmpty);
      expect(packaged.base.feed, isNot(contains('following')));
    });

    test('sends the field whole if it ever moved underneath a reading', () {
      // It cannot, taken at one instant off one competition — but a patch
      // against a list of another length would be worse than the bytes.
      final delta = feedDelta(
        {'places': [1, 2, 3]},
        {'places': [1, 2]},
      );
      expect(delta['set'], {'places': [1, 2]});
      expect(delta, isNot(contains('places')));
    });

    test('says what a key stopped carrying', () {
      expect(feedDelta({'a': 1, 'b': 2}, {'a': 1}), {'drop': ['b']});
    });
  });

  group('the server', () {
    late Future<HttpServer> Function(int) realBind;
    late Future<String?> Function() realAddress;
    late Future<Uint8List> Function(String) realFont;

    late MeetServer server;
    late Meet shared;
    late List<ThrowResult> results;

    /// Starts sharing one of [shared]'s competitions.
    Future<bool> share(ThrowEvent event, double kg) => server.start(
          meetId: shared.id,
          event: event,
          implementKg: kg,
          scheme: const ColorScheme.dark(),
          meet: () => shared,
          results: () => results,
          isPersonalBest: (result) => result.id == 'm2',
        );

    setUp(() async {
      // Loopback rather than every interface: a test has no business
      // opening a port to whatever network CI is on. All three are static,
      // so what was there is put back rather than guessed at.
      realBind = MeetServer.bind;
      realAddress = MeetServer.lanAddress;
      realFont = MeetServer.loadFont;
      MeetServer.bind =
          (port) => HttpServer.bind(InternetAddress.loopbackIPv4, port);
      MeetServer.lanAddress = () async => '127.0.0.1';
      // There is no asset bundle behind a plain unit test, so the real
      // Barlow cannot be read here; the shape of the route is what this
      // checks.
      MeetServer.loadFont = (asset) async => Uint8List.fromList([0, 1, 0, 0]);

      final (made, marks) = competition();
      shared = made;
      results = marks;
      server = MeetServer();
      expect(await share(ThrowEvent.discus, 1), isTrue,
          reason: 'the socket should open on loopback');
    });

    tearDown(() async {
      await server.stopAll();
      MeetServer.bind = realBind;
      MeetServer.lanAddress = realAddress;
      MeetServer.loadFont = realFont;
    });

    String url() => server.urlFor(shared.id, ThrowEvent.discus, 1)!;

    Future<({int status, List<int> bytes, HttpHeaders headers})> get(
      String path, {
      String? etag,
      String? from,
    }) async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('${from ?? url()}$path'));
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
      expect(server.shareCount, 1);
      expect(server.sharing(shared.id, ThrowEvent.discus, 1), isTrue);
      expect(server.sharing(shared.id, ThrowEvent.javelin, 0.8), isFalse);
      expect(url(), startsWith('http://127.0.0.1:'));
      expect(url(), matches(RegExp(r'/M/[23456789A-HJ-NP-Z]{6}$')));
      expect(server.qrFor(shared.id, ThrowEvent.discus, 1), url().toUpperCase());
    });

    test('keeps the link a stand has already scanned', () async {
      final first = url();
      expect(await share(ThrowEvent.discus, 1), isTrue);
      expect(url(), first);
      expect(server.shareCount, 1);
    });

    test('serves the page at the link', () async {
      final res = await get('');
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'text/html');
      final html = utf8.decode(res.bytes);
      expect(html, contains('<title>ThrowLab</title>'));
      // The app's own type, off the phone rather than off a network that
      // isn't there.
      expect(html, contains('url("f/r.ttf")'));
      // The page is full of typographic dashes and ellipses, and the feed
      // carries whatever a heat sheet spelled a name with. Both are written
      // through a content type that has to name its charset, or a browser
      // reads them as Latin-1 and paints mojibake.
      expect(html, contains('connecting…'));
      expect(res.headers.value('x-robots-tag'), contains('noindex'));
    });

    test('serves the app’s own typeface', () async {
      final res = await get('/f/r.ttf');
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'font/ttf');
      expect(res.bytes, isNotEmpty);
      expect((await get('/f/nothing.ttf')).status, 404);
    });

    test('turns away anything that is not this competition', () async {
      final wrong = url().replaceAll(RegExp(r'/M/\w+$'), '/M/AAAAAA');
      expect((await get('', from: wrong)).status, 404);
      expect((await get('/library')).status, 404);
    });

    test('answers the state with the competition as it stands', () async {
      shared.entryById('e2')!.athlete = 'Zoë Müller-Świątek';
      final state = await get('/state');
      expect(state.headers.contentType?.charset, 'utf-8');
      final first = jsonDecode(utf8.decode(state.bytes));
      expect(first['meet'], 'County Champs');
      expect(first['label'], 'Discus · 1 kg');
      final places = first['places'] as List;
      expect(places.first['best'], '46.55 m');
      expect(places.map((p) => p['name']), contains('Zoë Müller-Świątek'));

      // A mark entered on the phone shows up on the next poll without
      // anybody telling the server: it reads the meet, it does not hold a
      // copy of it.
      shared.entryById('e2')!.setAttempt(2, MeetAttempt.untracked(47.8));
      final second = jsonDecode(utf8.decode((await get('/state')).bytes));
      final after = second['places'] as List;
      expect(after.first['name'], 'Zoë Müller-Świątek');
      expect(after.first['best'], '47.80 m');
    });

    test('picks up an athlete entered after the link went out', () async {
      shared.entries.add(entry('e3', 'Late Arrival',
          [MeetAttempt.untracked(60)], order: 2, tracked: false));
      final feed = jsonDecode(utf8.decode((await get('/state')).bytes));
      expect((feed['places'] as List).first['name'], 'Late Arrival');
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
      expect((await get('/state', etag: tag)).status, 200);
    });

    test('reads who a browser is watching off its own poll', () async {
      final plain = jsonDecode(utf8.decode((await get('/state')).bytes));
      expect(plain.containsKey('following'), isFalse);
      expect((plain['places'] as List)
          .firstWhere((p) => p['name'] == 'Jakob Sandhagen')['mine'], isTrue);

      // Nothing is registered and nothing is stored: the choice rides on
      // the poll, and the phone works this one answer out around it.
      final watching =
          jsonDecode(utf8.decode((await get('/state?f=e2')).bytes));
      expect(watching['following'], [
        {'key': 'e2', 'name': 'N. Achebe (Croydon)'}
      ]);
      final places = watching['places'] as List;
      expect(places.firstWhere((p) => p['name'] == 'N. Achebe (Croydon)')
          ['mine'], isTrue);
      expect(places.firstWhere((p) => p['name'] == 'Jakob Sandhagen')['mine'],
          isFalse);

      // Several of them, comma-separated, because somebody at a ring is as
      // likely to have two in the field as one.
      final both =
          jsonDecode(utf8.decode((await get('/state?f=e1,e2')).bytes));
      expect((both['following'] as List).map((f) => f['key']), ['e1', 'e2']);
      expect((both['places'] as List).every((p) => p['mine'] == true), isTrue);

      // And a key this competition doesn't hold is simply nobody.
      final gone = jsonDecode(utf8.decode((await get('/state?f=eGone')).bytes));
      expect(gone.containsKey('following'), isFalse);
    });

    test('never hands one spectator another’s board', () async {
      final mine = await get('/state');
      final tag = mine.headers.value('etag');
      expect(tag, isNotNull);
      // The same competition read for somebody else is a different answer,
      // so a tag that was current for one reader is stale for the other —
      // two people on one link are never served each other's board.
      final theirs = await get('/state?f=e2', etag: tag);
      expect(theirs.status, 200);
      expect(jsonDecode(utf8.decode(theirs.bytes))['following'].first['key'],
          'e2');
    });

    test('writes this competition’s results sheet and no other', () async {
      shared.entries.add(entry('j1', 'T. Brandt (Kiel)',
          [MeetAttempt.untracked(63.4)],
          order: 9, tracked: false, event: ThrowEvent.javelin, implementKg: 0.8));
      final res = await get('/results.pdf');
      expect(res.status, 200);
      expect(res.headers.contentType?.mimeType, 'application/pdf');
      expect(
          res.headers.value('content-disposition'), contains('County Champs'));
      final text = pdfText(Uint8List.fromList(res.bytes))!;
      expect(text, contains('COUNTY CHAMPS'));
      expect(text, contains('Sandhagen'));
      // The javelin was never on this link, and is not on its sheet.
      expect(text, isNot(contains('Brandt')));
    });

    test('shares two rings at once, each on its own link', () async {
      shared.entries.add(entry('j1', 'T. Brandt (Kiel)',
          [MeetAttempt.untracked(63.4)],
          order: 9, tracked: false, event: ThrowEvent.javelin, implementKg: 0.8));
      expect(await share(ThrowEvent.javelin, 0.8), isTrue);
      expect(server.shareCount, 2);

      final javelin = server.urlFor(shared.id, ThrowEvent.javelin, 0.8)!;
      expect(javelin, isNot(url()));
      final feed =
          jsonDecode(utf8.decode((await get('/state', from: javelin)).bytes));
      expect(feed['label'], 'Javelin · 800 g');
      expect(jsonEncode(feed), isNot(contains('Sandhagen')));

      // Stopping one leaves the other answering.
      await server.stop(shared.id, ThrowEvent.javelin, 0.8);
      expect(server.shareCount, 1);
      expect((await get('/state')).status, 200);
      expect((await get('/state', from: javelin)).status, 404);
    });

    test('stops answering once sharing is stopped', () async {
      final was = url();
      await server.stop(shared.id, ThrowEvent.discus, 1);
      expect(server.isSharing, isFalse);
      expect(server.urlFor(shared.id, ThrowEvent.discus, 1), isNull);
      final client = HttpClient();
      await expectLater(
        client.getUrl(Uri.parse(was)).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
      client.close(force: true);
    });
  });
}
