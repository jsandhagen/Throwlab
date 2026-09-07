import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/meet_library.dart';

Meet _meet({String id = 'k1', DateTime? on, int rounds = 6}) => Meet(
      id: id,
      name: 'County Champs',
      date: on ?? DateTime(2026, 6, 13),
      rounds: rounds,
    );

MeetEntry _entry({String id = 'e1', String athlete = 'Ana Diaz'}) => MeetEntry(
      id: id,
      athlete: athlete,
      event: ThrowEvent.discus,
      implementKg: 1,
    );

ThrowMark _mark(String id, double distance) => ThrowMark(
      id: id,
      athlete: 'Ana Diaz',
      event: ThrowEvent.discus,
      implementKg: 1,
      distance: distance,
      achievedOn: DateTime(2026, 6, 13),
    );

ThrowVideo _clip(String id, {double? distance}) => ThrowVideo(
      id: id,
      path: '/$id.mp4',
      event: ThrowEvent.discus,
      implementKg: 1,
      importedAt: DateTime(2026, 6, 13),
      athlete: 'Ana Diaz',
      distance: distance,
    );

/// Meets: a competition as the coach records it, over the marks and clips
/// that go into the record book anyway.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a series', () {
    test('grows to reach the round being recorded', () {
      final entry = _entry();
      entry.setAttempt(3, MeetAttempt.mark('m1'));
      expect(entry.attempts.length, 4);
      expect(entry.attemptAt(0), isNull);
      expect(entry.attemptAt(3)?.resultId, 'm1');
    });

    test('never keeps an empty round hanging off the end', () {
      final entry = _entry();
      entry.setAttempt(2, MeetAttempt.foul());
      entry.setAttempt(2, null);
      expect(entry.attempts, isEmpty);
      expect(entry.taken, 0);
    });

    test('the next throw goes in the first gap, not on the end', () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('m1'));
      entry.setAttempt(2, MeetAttempt.foul());
      // Round 2 was entered before round 1 was — the coach missed one and
      // came back to it.
      expect(entry.nextRound, 1);
    });

    test('an untouched series starts at the first round', () {
      expect(_entry().nextRound, 0);
    });
  });

  group('read against the record book', () {
    test('the furthest legal attempt is the best', () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('m1'));
      entry.setAttempt(1, MeetAttempt.foul());
      entry.setAttempt(2, MeetAttempt.mark('m2'));
      final series = MeetSeries(entry, [_mark('m1', 41.20), _mark('m2', 43.06)]);
      expect(series.best, 43.06);
      expect(series.bestRound, 2);
    });

    test('a tie stays with the round that got there first', () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('m1'));
      entry.setAttempt(1, MeetAttempt.mark('m2'));
      final series = MeetSeries(entry, [_mark('m1', 41.20), _mark('m2', 41.20)]);
      expect(series.bestRound, 0);
    });

    test('a filmed foul keeps its clip and counts for nothing', () {
      final entry = _entry();
      // The throw was filmed, then called out of the sector.
      entry.setAttempt(
          0, MeetAttempt(kind: AttemptKind.foul, resultId: 'v1'));
      final series = MeetSeries(entry, [_clip('v1', distance: 44)]);
      expect(series.filmedAt(0), isTrue);
      expect(series.distanceAt(0), isNull);
      expect(series.best, isNull);
    });

    test('a mark deleted from the library leaves the round showing nothing',
        () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('gone'));
      final series = MeetSeries(entry, const []);
      expect(series.resultAt(0), isNull);
      expect(series.distanceAt(0), isNull);
    });

    test('a typed mark is not filmed; a clip is', () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('m1'));
      entry.setAttempt(1, MeetAttempt.mark('v1'));
      final series = MeetSeries(entry, [_mark('m1', 40), _clip('v1')]);
      expect(series.filmedAt(0), isFalse);
      expect(series.filmedAt(1), isTrue);
    });

    test('a pass is neither a distance nor a foul', () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.pass());
      final series = MeetSeries(entry, const []);
      expect(series.distanceAt(0), isNull);
      expect(entry.attemptAt(0)!.kind, AttemptKind.pass);
      expect(entry.taken, 1);
    });
  });

  group('storage', () {
    test('a meet survives a round trip through JSON', () {
      final meet = _meet(rounds: 4);
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('m1'));
      entry.setAttempt(2, MeetAttempt.pass());
      meet.entries.add(entry);

      final read = Meet.fromJson(meet.toJson());
      expect(read.name, 'County Champs');
      expect(read.rounds, 4);
      expect(read.entries.single.athlete, 'Ana Diaz');
      expect(read.entries.single.event, ThrowEvent.discus);
      expect(read.entries.single.attemptAt(0)?.resultId, 'm1');
      expect(read.entries.single.attemptAt(1), isNull);
      expect(read.entries.single.attemptAt(2)?.kind, AttemptKind.pass);
    });

    test('meets reload in the order they were thrown, newest first',
        () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet(id: 'old', on: DateTime(2026, 4, 1)));
      await library.save(_meet(id: 'new', on: DateTime(2026, 6, 1)));

      final reopened = MeetLibrary();
      await reopened.load();
      expect(reopened.meets.map((m) => m.id), ['new', 'old']);
    });

    test('a corrupt store costs the meets, not the app', () async {
      SharedPreferences.setMockInitialValues(
          {'throwlab.meets': 'not json at all'});
      final library = MeetLibrary();
      await library.load();
      expect(library.isLoaded, isTrue);
      expect(library.meets, isEmpty);
    });

    test('attempts are stored as they are entered', () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet());
      await library.addEntry('k1', entry: _entry());
      await library.setAttempt('k1', 'e1', 0, MeetAttempt.mark('m1'));
      await library.setAttempt('k1', 'e1', 1, MeetAttempt.foul());

      final reopened = MeetLibrary();
      await reopened.load();
      final entry = reopened.byId('k1')!.entries.single;
      expect(entry.attemptAt(0)?.resultId, 'm1');
      expect(entry.attemptAt(1)?.kind, AttemptKind.foul);
    });

    test('removing an athlete leaves the rest of the meet alone', () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet());
      await library.addEntry('k1', entry: _entry(id: 'e1'));
      await library.addEntry('k1',
          entry: _entry(id: 'e2', athlete: 'Bea Cole'));
      await library.removeEntry('k1', 'e1');
      expect(library.byId('k1')!.entries.single.athlete, 'Bea Cole');
    });
  });

  group('the meet in progress', () {
    test("is today's", () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet(id: 'past', on: DateTime(2026, 4, 1)));
      await library.save(_meet(id: 'today', on: DateTime.now()));
      expect(library.live?.id, 'today');
    });

    test('is nothing at all on a day with no meet', () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet(id: 'past', on: DateTime(2026, 4, 1)));
      expect(library.live, isNull);
    });
  });
}
