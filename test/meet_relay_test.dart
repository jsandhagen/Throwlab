import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ColorScheme;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/meet_relay.dart';

/// Pushing a competition at the relay.
///
/// The relay half is tested where it runs, under miniflare in `worker/`.
/// This is the phone's side of the same wire: what it sends, when it
/// decides to send it, and what it does on the afternoons the signal is
/// not there — which is the part the LAN never had to have an answer for.
void main() {
  const base = 'https://share.test';

  ThrowMark mark(String id, double distance) => ThrowMark(
        id: id,
        athlete: 'Jakob Sandhagen',
        event: ThrowEvent.discus,
        implementKg: 1,
        distance: distance,
        achievedOn: DateTime(2026, 6, 13),
      );

  /// A discus with one athlete a round into it, and the marks behind it.
  (Meet, List<ThrowResult>) competition() {
    final meet = Meet(
      id: 'k1',
      name: 'County Champs',
      date: DateTime(2026, 6, 13),
      rounds: 6,
      prelimRounds: 6,
      advancing: 99,
    );
    final entry = MeetEntry(
      id: 'e1',
      athlete: 'Jakob Sandhagen',
      event: ThrowEvent.discus,
      implementKg: 1,
      order: 0,
    );
    entry.setAttempt(0, MeetAttempt.mark('m1'));
    meet.entries.add(entry);
    return (meet, [mark('m1', 41.2)]);
  }

  /// A relay that records what it was handed and answers however it is
  /// told to.
  ///
  /// The two routes are kept apart, because they are two different
  /// questions: `/state` is this phone saying what it knows, and `/wanted`
  /// is it asking who at the ring is being followed. A test about what
  /// gets pushed should not count the asking, which runs on its own clock.
  ///
  /// [watching] is what the relay says is being asked of it — the sets a
  /// spectator has ticked, as the page would have sent them. [asks] is
  /// handed in by the tests that care what the asking route was called
  /// with, so the rest are not made to name a list they never look at.
  ({MeetRelay relay, List<http.Request> pushes}) relayThat(
    int Function(int call) answers, {
    String on = base,
    Duration settle = const Duration(milliseconds: 5),
    Duration retry = const Duration(milliseconds: 20),
    Duration lively = const Duration(milliseconds: 20),
    List<String> Function()? watching,
    bool reading = false,
    List<http.Request>? asks,
  }) {
    final pushes = <http.Request>[];
    Map<String, dynamic> asking() =>
        {'wanted': watching?.call() ?? const <String>[], 'reading': reading};
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/wanted')) {
        asks?.add(request);
        return http.Response(jsonEncode({'ok': true, ...asking()}), 200);
      }
      pushes.add(request);
      final status = answers(pushes.length);
      return http.Response(
          status == 200 ? jsonEncode({'ok': true, ...asking()}) : 'no', status);
    });
    return (
      relay: MeetRelay(
          base: on,
          client: client,
          settle: settle,
          retry: retry,
          lively: lively),
      pushes: pushes,
    );
  }

  Future<bool> share(MeetRelay relay, Meet meet, List<ThrowResult> results,
      {Listenable? changes}) {
    return relay.start(
      meetId: meet.id,
      event: ThrowEvent.discus,
      implementKg: 1,
      scheme: const ColorScheme.dark(),
      meet: () => meet,
      results: () => results,
      changes: changes,
    );
  }

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  group('the link', () {
    test('is built on the relay this build was given', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();

      expect(await share(relay, meet, results), isTrue);
      final url = relay.urlFor('k1', ThrowEvent.discus, 1)!;

      expect(url, startsWith('$base/M/'));
      // Ten characters, and none of the ones that read two ways when a
      // link is dictated across a sector.
      final token = url.split('/').last;
      expect(token, matches(RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$')));
      expect(pushes.single.url.toString(), '$url/state');
    });

    test('is nothing at all in a build with no relay', () async {
      final (:relay, :pushes) = relayThat((_) => 200, on: '');
      final (meet, results) = competition();

      expect(await share(relay, meet, results), isFalse);
      expect(relay.isSharing, isFalse);
      expect(relay.error, contains('no relay'));
      // And nothing was sent anywhere.
      expect(pushes, isEmpty);
    });

    test('keeps the link a stand has already scanned', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();

      await share(relay, meet, results);
      final first = relay.urlFor('k1', ThrowEvent.discus, 1);
      await share(relay, meet, results);

      expect(relay.urlFor('k1', ThrowEvent.discus, 1), first);
      expect(relay.shareCount, 1);
      expect(pushes, hasLength(1));
    });

    test('is read-only: the key that writes is never in it', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      await share(relay, meet, results);

      final key = pushes.single.headers['authorization']!;
      expect(key, startsWith('Bearer '));
      expect(key.length, greaterThan('Bearer '.length + 30));
      expect(relay.urlFor('k1', ThrowEvent.discus, 1),
          isNot(contains(key.substring(7))));
    });
  });

  group('what goes over', () {
    test('sends the competition, the page and the sheet to begin with', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      await share(relay, meet, results);

      final body = bodyOf(pushes.single);
      expect(body['fingerprint'], isA<String>());
      // The answers, worked out here — the relay is handed places and
      // spelled marks, never the rules that made them.
      expect(body['feed']['label'], 'Discus · 1 kg');
      expect(body['feed']['places'], isNotEmpty);
      expect(body['page'], contains('<!doctype html>'));
      expect(body['sheetName'], contains('County Champs'));
      // A PDF holds compressed streams, so it is read as bytes: the point
      // is that a real sheet went with the competition.
      final pdf = base64Decode(body['pdf'] as String);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    });

    test('holds the page back once the stand has it', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);

      results.add(mark('m2', 46.55));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(pushes, hasLength(2));
      // 50 KB of page that changes when the app does, not when a
      // round does.
      expect(bodyOf(pushes.last).containsKey('page'), isFalse);
      expect(bodyOf(pushes.last).containsKey('medal'), isFalse);
      // The competition and its sheet do move.
      expect(bodyOf(pushes.last)['fingerprint'],
          isNot(bodyOf(pushes.first)['fingerprint']));
      expect(bodyOf(pushes.last)['pdf'], isNotNull);
    });
  });

  group('when it pushes', () {
    test('pushes a mark the moment it is entered', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);

      results.add(mark('m2', 46.55));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(pushes, hasLength(2));
      expect(jsonEncode(bodyOf(pushes.last)['feed']), contains('46.55'));
    });

    test('lets a burst of changes settle into one push', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);

      // Entering a round touches the meet several times in a second: the
      // mark, the library, the sort.
      results.add(mark('m2', 46.55));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      changes.bump();
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(pushes, hasLength(2));
    });

    test('says nothing on an afternoon where nothing is thrown', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);

      // The screen rebuilds for its own reasons; the competition has not
      // moved, so there is nothing to send.
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(pushes, hasLength(1));
    });
  });

  group('when the signal is not there', () {
    test('says so, and keeps the share up', () async {
      // Up, then down from the second push on.
      final (:relay, :pushes) = relayThat((call) => call == 1 ? 200 : 500);
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);
      expect(relay.reaching, isTrue);

      results.add(mark('m2', 46.55));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // The board on the stand is now older than the ring, and the coach
      // is the only one who can be told.
      expect(relay.reaching, isFalse);
      expect(relay.error, contains('would not take'));
      expect(relay.sharing('k1', ThrowEvent.discus, 1), isTrue);
    });

    test('brings the competition back once it can, unasked', () async {
      var up = true;
      final pushes = <http.Request>[];
      final client = MockClient((request) async {
        pushes.add(request);
        return http.Response(up ? '{"ok":true}' : 'no', up ? 200 : 500);
      });
      final relay = MeetRelay(
        base: base,
        client: client,
        settle: const Duration(milliseconds: 5),
        retry: const Duration(milliseconds: 20),
      );
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);

      up = false;
      results.add(mark('m2', 46.55));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(relay.reaching, isFalse);

      // Nobody throws again; the signal simply comes back. Waiting for
      // the next mark would leave the stand a round behind for as long as
      // the round lasts.
      up = true;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(relay.reaching, isTrue);
      expect(relay.error, isNull);
      relay.dispose();
    });

    test('gives up a link another phone already holds', () async {
      final (:relay, :pushes) = relayThat((_) => 409);
      final (meet, results) = competition();

      expect(await share(relay, meet, results), isFalse);
      // Ten characters make this improbable rather than impossible, and a
      // link that is not this phone's must not go on being offered.
      expect(relay.isSharing, isFalse);
      expect(relay.error, contains('already in use'));
    });
  });

  group('who is being followed', () {
    /// The same discus with a rival in it, so a set can be a part of the
    /// field rather than the whole of it.
    (Meet, List<ThrowResult>) withRival() {
      final (made, results) = competition();
      final rival = MeetEntry(
        id: 'e2',
        athlete: 'N. Achebe (Croydon)',
        event: ThrowEvent.discus,
        implementKg: 1,
        tracked: false,
        order: 1,
      );
      rival.setAttempt(0, MeetAttempt.untracked(49.1));
      made.entries.add(rival);
      return (made, results);
    }

    Map<String, dynamic> overlaysOf(http.Request request) =>
        (bodyOf(request)['overlays'] as Map).cast<String, dynamic>();

    test('works the competition out again for whoever the relay names',
        () async {
      final (:relay, :pushes) =
          relayThat((_) => 200, watching: () => ['e2']);
      final (meet, results) = withRival();

      await share(relay, meet, results);

      // Two hops, and two by construction: the sets being followed come
      // back on the answer to a push, so the first push is what learns of
      // this one and the second is what answers it.
      expect(pushes, hasLength(2));
      expect(overlaysOf(pushes.first), isEmpty);
      final answer = overlaysOf(pushes[1])['e2'] as Map;
      expect(answer['fingerprint'], isNotEmpty);

      // What it adds to the feed above, rather than a competition of its
      // own: the rows the set moves, and the board hung on them.
      final delta = answer['delta'] as Map;
      // Both rows move: the rival takes the emphasis and the coach's own
      // athlete loses it. Nobody else in the field is any different.
      expect((delta['places'] as Map).keys, ['0', '1']);
      expect(delta['set'], contains('following'));
      expect(delta['set'], contains('board'));
      expect(jsonEncode(delta).length,
          lessThan(jsonEncode(bodyOf(pushes[1])['feed']).length));
    });

    test('answers a name ticked while nobody is throwing', () async {
      var asked = <String>[];
      final asks = <http.Request>[];
      final (:relay, :pushes) = relayThat((_) => 200,
          watching: () => asked, reading: true, asks: asks);
      final (meet, results) = withRival();
      await share(relay, meet, results);
      expect(pushes, hasLength(1));

      // A spectator ticks a name while the field is walking back from the
      // sector. Nothing has been thrown, so nothing is going to be pushed
      // — the asking route is the other way the question arrives.
      asked = ['e2'];
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(asks, isNotEmpty);
      expect(asks.first.url.toString(), endsWith('/wanted'));
      // Behind the write key: who somebody cared enough to tick is the
      // coach's business, not the link's.
      expect(asks.first.headers['authorization'], isNotNull);
      expect(pushes.length, greaterThan(1));
      expect(overlaysOf(pushes.last), contains('e2'));
    });

    test('stops working out a set nobody is asking for any more', () async {
      var asked = <String>['e2'];
      final changes = _Changes();
      final (:relay, :pushes) =
          relayThat((_) => 200, watching: () => asked, reading: true);
      final (meet, results) = withRival();
      await share(relay, meet, results, changes: changes);
      expect(overlaysOf(pushes.last), contains('e2'));

      // The stand has gone home, and then somebody throws. Nothing is
      // uploaded to withdraw an answer on its own — a set nobody is asking
      // for costs nothing where it sits — but the next push carries the
      // whole of what this phone stands behind, and it is no longer in it.
      asked = <String>[];
      await Future<void>.delayed(const Duration(milliseconds: 60));
      results.add(mark('m2', 48.02));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(overlaysOf(pushes.last), isEmpty);
    });

    test('keeps asking nobody, and pushing nothing, for a quiet link',
        () async {
      final asks = <http.Request>[];
      final (:relay, :pushes) = relayThat((_) => 200, asks: asks);
      final (meet, results) = withRival();
      await share(relay, meet, results);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Nothing thrown and nobody following: the asking costs its few
      // hundred bytes and the competition is not sent again.
      expect(pushes, hasLength(1));
      expect(asks, isNotEmpty);
    });
  });

  group('stopping', () {
    test('stops pushing, and does not ask the relay to forget', () async {
      final (:relay, :pushes) = relayThat((_) => 200);
      final (meet, results) = competition();
      final changes = _Changes();
      await share(relay, meet, results, changes: changes);

      await relay.stop('k1', ThrowEvent.discus, 1);
      results.add(mark('m2', 46.55));
      meet.entries.first.setAttempt(1, MeetAttempt.mark('m2'));
      changes.bump();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(relay.isSharing, isFalse);
      // One push, and no second request of any kind: there is no route
      // that deletes, because a route that deletes is one somebody else
      // can call. It ages out instead.
      expect(pushes, hasLength(1));
      expect(pushes.every((p) => p.method == 'PUT'), isTrue);
    });
  });
}

/// Stands in for the meet and the record book together: the one thing that
/// says the competition has moved.
class _Changes extends ChangeNotifier {
  void bump() => notifyListeners();
}
