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

    test('a deleted meet stays deleted', () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet(id: 'k0', on: DateTime(2026, 4, 1)));
      await library.save(_meet(id: 'k1', on: DateTime(2026, 6, 1))
        ..entries.add(_entry()));

      await library.remove('k1');
      expect(library.meets.map((m) => m.id), ['k0']);

      // Gone from storage too, not just from the list in memory.
      final reopened = MeetLibrary();
      await reopened.load();
      expect(reopened.meets.map((m) => m.id), ['k0']);
      expect(reopened.byId('k1'), isNull);
    });

    test('deleting a meet nobody has is not an error', () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet(id: 'k0'));

      await library.remove('nothing');
      expect(library.meets, hasLength(1));
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

  group('the rest of the field', () {
    test('a rival keeps their distance on the attempt, not in the library',
        () {
      final entry = _entry(id: 'r1', athlete: 'M. Okoye')..tracked = false;
      entry.setAttempt(0, MeetAttempt.untracked(42.10));
      // Nothing in the record book, and the series still reads.
      final series = MeetSeries(entry, const []);
      expect(series.distanceAt(0), 42.10);
      expect(series.best, 42.10);
      expect(series.resultAt(0), isNull);
    });

    test('a rival survives a round trip through JSON', () {
      final meet = _meet();
      final entry = _entry(id: 'r1', athlete: 'M. Okoye')
        ..tracked = false
        ..order = 3;
      entry.setAttempt(
          0, MeetAttempt.untracked(191.40, distanceUnit: DistanceUnit.feet));
      meet.entries.add(entry);

      final read = Meet.fromJson(meet.toJson()).entries.single;
      expect(read.tracked, isFalse);
      expect(read.order, 3);
      expect(read.attemptAt(0)?.distance, 191.40);
      expect(read.attemptAt(0)?.distanceUnit, DistanceUnit.feet);
    });

    test('a meet from before the field was tracked reads as all mine', () {
      final read = MeetEntry.fromJson({
        'id': 'e1',
        'athlete': 'Ana Diaz',
        'event': 'discus',
        'implementKg': 1,
        'attempts': <dynamic>[],
      });
      expect(read.tracked, isTrue);
      expect(read.order, 0);
    });
  });

  group('the throwing order', () {
    test('sorts the entries, and ties keep the order they were added', () {
      final meet = _meet();
      meet.entries.addAll([
        _entry(id: 'a')..order = 2,
        _entry(id: 'b')..order = 0,
        _entry(id: 'c')..order = 2,
      ]);
      expect(meet.inOrder.map((e) => e.id), ['b', 'a', 'c']);
    });
  });

  group('standings', () {
    /// A competition of four, all on the same implement.
    Meet fieldOf(Map<String, List<double?>> series, {int advancing = 8}) {
      final meet = _meet(rounds: 6)..advancing = advancing;
      var order = 0;
      series.forEach((name, marks) {
        final entry = MeetEntry(
          id: name,
          athlete: name,
          event: ThrowEvent.discus,
          implementKg: 1,
          tracked: name == 'mine',
          order: order++,
        );
        for (var round = 0; round < marks.length; round++) {
          final mark = marks[round];
          entry.setAttempt(
              round,
              mark == null
                  ? MeetAttempt.foul()
                  : MeetAttempt.untracked(mark));
        }
        meet.entries.add(entry);
      });
      return meet;
    }

    MeetStandings standingsOf(Meet meet) => MeetStandings(
          MeetCompetition.of(meet).single,
          const [],
          advancing: meet.advancing,
        );

    test('places on the best throw, furthest first', () {
      final standings = standingsOf(fieldOf({
        'mine': [41.20, 43.06],
        'okoye': [44.90],
        'smith': [38.44],
      }));
      expect(standings.places.map((p) => p.entry.id), ['okoye', 'mine', 'smith']);
      expect(standings.places.map((p) => p.place), [1, 2, 3]);
    });

    test('a tie on the best is broken by the second best', () {
      final standings = standingsOf(fieldOf({
        'mine': [41.20, 39.00],
        'okoye': [41.20, 40.00],
      }));
      // Level on 41.20; Okoye's second throw is the further of the two.
      expect(standings.places.first.entry.id, 'okoye');
      expect(standings.places.map((p) => p.place), [1, 2]);
    });

    test('a series with nothing left to answer with loses the tie', () {
      final standings = standingsOf(fieldOf({
        'mine': [41.20],
        'okoye': [41.20, 30.00],
      }));
      expect(standings.places.first.entry.id, 'okoye');
    });

    test('two identical series share the place, and the next one skips it',
        () {
      final standings = standingsOf(fieldOf({
        'mine': [41.20],
        'okoye': [41.20],
        'smith': [38.00],
      }));
      expect(standings.places.map((p) => p.place), [1, 1, 3]);
    });

    test('an athlete yet to throw ranks below everyone who has', () {
      final standings = standingsOf(fieldOf({
        'waiting': <double?>[],
        'okoye': [30.00],
      }));
      expect(standings.places.map((p) => p.entry.id), ['okoye', 'waiting']);
      expect(standings.places.last.advancing, isFalse);
    });

    test('three fouls is not a mark', () {
      final standings = standingsOf(fieldOf({
        'mine': [null, null, null],
        'okoye': [30.00],
      }));
      expect(standings.places.first.entry.id, 'okoye');
      expect(standings.placeOf('mine')!.best, isNull);
    });
  });

  group('making the final', () {
    Meet cutOf(List<double> marks, {int advancing = 2}) {
      final meet = _meet()..advancing = advancing;
      for (var i = 0; i < marks.length; i++) {
        meet.entries.add(MeetEntry(
          id: 'e$i',
          athlete: 'Thrower $i',
          event: ThrowEvent.discus,
          implementKg: 1,
          tracked: i == marks.length - 1,
          order: i,
        )..setAttempt(0, MeetAttempt.untracked(marks[i])));
      }
      return meet;
    }

    MeetStandings standingsOf(Meet meet) => MeetStandings(
        MeetCompetition.of(meet).single, const [],
        advancing: meet.advancing);

    test('the top of the field goes through, the rest do not', () {
      final standings = standingsOf(cutOf([44, 43, 40]));
      expect(standings.hasCut, isTrue);
      expect(standings.places.map((p) => p.advancing), [true, true, false]);
      expect(standings.cutMark, 43);
    });

    test('nobody is cut when the field is smaller than the final', () {
      final standings = standingsOf(cutOf([44, 43], advancing: 8));
      expect(standings.hasCut, isFalse);
      expect(standings.neededToQualify('e1'), isNull);
    });

    test('what my athlete needs is a centimetre past the cut', () {
      // 40 m is last; 43 m holds the second and final qualifying place.
      final standings = standingsOf(cutOf([44, 43, 40]));
      expect(standings.neededToQualify('e2'), closeTo(43.01, 1e-9));
    });

    test('an athlete already through needs nothing', () {
      final standings = standingsOf(cutOf([40, 43, 44]));
      expect(standings.neededToQualify('e2'), isNull);
    });

    test('what it takes to win is a centimetre past the leader', () {
      final standings = standingsOf(cutOf([44, 43, 40]));
      expect(standings.neededFor('e2', place: 1), closeTo(44.01, 1e-9));
    });

    test('the final is thrown worst-placed first', () {
      final standings = standingsOf(cutOf([44, 43, 40], advancing: 2));
      // The leader throws last, and the athlete who missed out is not in it.
      expect(standings.finalOrder.map((e) => e.id), ['e1', 'e0']);
    });
  });

  group('three and three', () {
    /// A 3 + 3 with [advancing] going through, and a field whose series
    /// are given round by round.
    Meet threeAndThree(Map<String, List<double>> field, {int advancing = 2}) {
      final meet = Meet(
        id: 'k1',
        name: 'County Champs',
        date: DateTime(2026, 6, 13),
        rounds: 6,
        prelimRounds: 3,
        advancing: advancing,
      );
      var order = 0;
      field.forEach((name, marks) {
        final entry = MeetEntry(
          id: name,
          athlete: name,
          event: ThrowEvent.discus,
          implementKg: 1,
          tracked: name == 'mine',
          order: order++,
        );
        for (var round = 0; round < marks.length; round++) {
          entry.setAttempt(round, MeetAttempt.untracked(marks[round]));
        }
        meet.entries.add(entry);
      });
      return meet;
    }

    MeetStandings standingsOf(Meet meet) => MeetStandings(
          MeetCompetition.of(meet).single,
          const [],
          advancing: meet.advancing,
          prelimRounds: meet.prelimRounds,
        );

    test('is six rounds with the cut after three', () {
      final meet = threeAndThree(const {});
      expect(meet.hasFinal, isTrue);
      expect(meet.rounds, 6);
      expect(meet.prelimRounds, 3);
    });

    test('a meet where everyone throws the lot has no final', () {
      expect(Meet(id: 'k', name: 'Open', date: DateTime(2026, 5, 2)).hasFinal,
          isFalse);
    });

    test('the cut is not made until the whole field has had its three', () {
      final standings = standingsOf(threeAndThree(const {
        'mine': [41.20, 41.50, 42.00],
        'okoye': [44.90, 44.00, 45.10],
        // Still one to throw: nobody is out yet.
        'smith': [38.44, 39.00],
      }));
      expect(standings.cutMade, isFalse);
      // So everyone still has rounds coming, last place included.
      expect(standings.throwsInFinal('smith'), isTrue);
    });

    test('once it is made, only the qualifiers throw on', () {
      final standings = standingsOf(threeAndThree(const {
        'mine': [41.20, 41.50, 42.00],
        'okoye': [44.90, 44.00, 45.10],
        'smith': [38.44, 39.00, 38.10],
      }));
      expect(standings.cutMade, isTrue);
      expect(standings.throwsInFinal('okoye'), isTrue);
      expect(standings.throwsInFinal('mine'), isTrue);
      expect(standings.throwsInFinal('smith'), isFalse);
    });

    test('a competition with no cut never closes a round', () {
      final meet = threeAndThree(const {
        'mine': [41.20, 41.50, 42.00],
        'okoye': [44.90, 44.00, 45.10],
      }, advancing: 8);
      final standings = standingsOf(meet);
      expect(standings.cutMade, isFalse);
      expect(standings.throwsInFinal('mine'), isTrue);
    });

    test('the format survives a round trip through JSON', () {
      final read = Meet.fromJson(threeAndThree(const {}).toJson());
      expect(read.rounds, 6);
      expect(read.prelimRounds, 3);
      expect(read.hasFinal, isTrue);
    });

    test('a meet stored before the final existed keeps all its rounds', () {
      final read = Meet.fromJson({
        'id': 'k1',
        'name': 'Spring Open',
        'date': '2026-05-02T00:00:00.000',
        'rounds': 6,
        'entries': <dynamic>[],
      });
      expect(read.prelimRounds, 6);
      expect(read.hasFinal, isFalse);
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
