import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_conditions.dart';
import 'package:throwlab/models/meet_board.dart';
import 'package:throwlab/models/meet_history.dart';
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
      final series =
          MeetSeries(entry, [_mark('m1', 41.20), _mark('m2', 43.06)]);
      expect(series.best, 43.06);
      expect(series.bestRound, 2);
    });

    test('a tie stays with the round that got there first', () {
      final entry = _entry();
      entry.setAttempt(0, MeetAttempt.mark('m1'));
      entry.setAttempt(1, MeetAttempt.mark('m2'));
      final series =
          MeetSeries(entry, [_mark('m1', 41.20), _mark('m2', 41.20)]);
      expect(series.bestRound, 0);
    });

    test('a filmed foul keeps its clip and counts for nothing', () {
      final entry = _entry();
      // The throw was filmed, then called out of the sector.
      entry.setAttempt(0, MeetAttempt(kind: AttemptKind.foul, resultId: 'v1'));
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

    test('meets reload in the order they were thrown, newest first', () async {
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
      await library.save(
          _meet(id: 'k1', on: DateTime(2026, 6, 1))..entries.add(_entry()));

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
    test('a rival keeps their distance on the attempt, not in the library', () {
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
          entry.setAttempt(round,
              mark == null ? MeetAttempt.foul() : MeetAttempt.untracked(mark));
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
      expect(
          standings.places.map((p) => p.entry.id), ['okoye', 'mine', 'smith']);
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

    test('two identical series share the place, and the next one skips it', () {
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

    MeetStandings standingsOf(Meet meet) =>
        MeetStandings(MeetCompetition.of(meet).single, const [],
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

    test('what my athlete needs is a centimeter past the cut', () {
      // 40 m is last; 43 m holds the second and final qualifying place.
      final standings = standingsOf(cutOf([44, 43, 40]));
      expect(standings.neededToQualify('e2'), closeTo(43.01, 1e-9));
    });

    test('an athlete already through needs nothing', () {
      final standings = standingsOf(cutOf([40, 43, 44]));
      expect(standings.neededToQualify('e2'), isNull);
    });

    test('what it takes to win is a centimeter past the leader', () {
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

  group('the season', () {
    final today = DateTime(2026, 6, 13);
    Meet on(String id, DateTime date) => _meet(id: id, on: date);

    test('puts today, what is coming and what is done in their own piles', () {
      final season = MeetSeason([
        on('past', DateTime(2026, 5, 2)),
        on('soon', DateTime(2026, 6, 20)),
        on('now', today),
        on('later', DateTime(2026, 7, 4)),
        on('older', DateTime(2026, 4, 1)),
      ], today: today);
      expect(season.today.map((m) => m.id), ['now']);
      // Forwards through what is coming...
      expect(season.upcoming.map((m) => m.id), ['soon', 'later']);
      // ...and backwards through what is done.
      expect(season.past.map((m) => m.id), ['past', 'older']);
    });

    test('counts a meet later today as today, whatever time it is', () {
      final season = MeetSeason([on('now', DateTime(2026, 6, 13, 19, 30))],
          today: DateTime(2026, 6, 13, 7));
      expect(season.today.map((m) => m.id), ['now']);
    });

    test('is empty when there are no meets', () {
      expect(MeetSeason(const [], today: today).isEmpty, isTrue);
    });

    test('counts the days to a fixture', () {
      int away(DateTime date) => daysUntil(date, now: today);
      expect(away(DateTime(2026, 6, 14)), 1);
      expect(away(DateTime(2026, 7, 6)), 23);
      expect(away(today), 0);
      // Already thrown, counted backwards.
      expect(away(DateTime(2026, 6, 1)), -12);
      // Counted between the days, not by the hours: a meet at nine
      // tomorrow morning is one day off at any time tonight.
      expect(
          daysUntil(DateTime(2026, 6, 14, 9), now: DateTime(2026, 6, 13, 23)),
          1);
    });

    test('says how far off a fixture is', () {
      String? away(DateTime date) => countdownTo(date, now: today);
      expect(away(DateTime(2026, 6, 14)), 'tomorrow');
      expect(away(DateTime(2026, 6, 18)), 'in 5 days');
      expect(away(DateTime(2026, 7, 4)), 'in 3 weeks');
      // Today and anything already thrown say nothing: the heading has.
      expect(away(today), isNull);
      expect(away(DateTime(2026, 6, 1)), isNull);
      // Nor does next season, which is read by its dates.
      expect(away(DateTime(2027, 3, 13)), isNull);
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

  group('the flight', () {
    /// A discus competition with a field of [names], each carrying the
    /// rounds already thrown.
    MeetCompetition field(Map<String, List<double?>> series) {
      final entries = <MeetEntry>[];
      var order = 0;
      for (final name in series.keys) {
        final entry = MeetEntry(
          id: 'e${order + 1}',
          athlete: name,
          event: ThrowEvent.discus,
          implementKg: 1,
          tracked: false,
          order: order++,
        );
        final thrown = series[name]!;
        for (var round = 0; round < thrown.length; round++) {
          entry.setAttempt(
              round,
              thrown[round] == null
                  ? MeetAttempt.foul()
                  : MeetAttempt.untracked(thrown[round]!));
        }
        entries.add(entry);
      }
      return MeetCompetition(ThrowEvent.discus, 1, entries);
    }

    test('is on the earliest round anybody is still owed', () {
      final flight = MeetFlight(
        field({
          'Ana Diaz': [41.20, 42.00],
          'M. Okoye': [44.90],
          'J. Smith': [38.44],
        }),
        rounds: 6,
      );
      expect(flight.round, 1);
      expect(flight.label, 'Round 2 of 6');
      // Ana has had her second; the other two have not.
      expect(flight.thrown, 1);
      expect(flight.fieldSize, 3);
    });

    test('puts the next athlete owed a throw in the circle', () {
      final flight = MeetFlight(
        field({
          'Ana Diaz': [41.20],
          'M. Okoye': <double?>[],
          'J. Smith': <double?>[],
        }),
        rounds: 6,
      );
      expect(flight.inTheCircle?.athlete, 'M. Okoye');
      expect(flight.onDeck?.athlete, 'J. Smith');
      expect(flight.throwsUntil('e2'), 0);
      expect(flight.throwsUntil('e3'), 1);
      // Ana has thrown this round: nothing of hers is coming.
      expect(flight.throwsUntil('e1'), isNull);
    });

    test('an athlete whose earlier round was skipped is up now', () {
      final competition = field({
        'Ana Diaz': [41.20, 42.00],
        'M. Okoye': [44.90, 45.00],
      });
      // The coach missed Okoye's first and filled the second in; the round
      // still owed is behind the one being thrown.
      competition.entries[1].setAttempt(0, null);
      final flight = MeetFlight(competition, rounds: 6);
      expect(flight.round, 0);
      expect(flight.inTheCircle?.athlete, 'M. Okoye');
    });

    test('says nothing about who is next on the last throw of a round', () {
      final flight = MeetFlight(
        field({
          'Ana Diaz': [41.20],
          'M. Okoye': <double?>[],
        }),
        rounds: 6,
      );
      expect(flight.inTheCircle?.athlete, 'M. Okoye');
      expect(flight.onDeck, isNull);
    });

    test('is done once the last attempt of the competition is in', () {
      final flight = MeetFlight(
        field({
          'Ana Diaz': [41.20, 42.00, 43.00],
        }),
        rounds: 3,
      );
      expect(flight.finished, isTrue);
      expect(flight.label, 'Done');
      expect(flight.inTheCircle, isNull);
      expect(flight.thrown, 1);
    });

    test('leaves out the athletes the cut left behind', () {
      final competition = field({
        'Ana Diaz': [41.20, 42.00, 43.00],
        'M. Okoye': [44.90, 45.00, 46.00],
        'J. Smith': [30.00, 31.00, 32.00],
      });
      final standings =
          MeetStandings(competition, const [], advancing: 2, prelimRounds: 3);
      final flight = MeetFlight(competition, rounds: 6, standings: standings);
      // Smith is out, so the final is a competition of two — and the round
      // is not held at three waiting for rounds he will never throw.
      expect(flight.fieldSize, 2);
      expect(flight.round, 3);
      expect(flight.isFinal, isTrue);
      expect(flight.label, 'Final · round 4');
    });
  });

  group('the conditions', () {
    test('are nothing until somebody writes something down', () {
      expect(const MeetConditions().isEmpty, isTrue);
      expect(const MeetConditions(wind: MeetWind.head).isEmpty, isFalse);
      expect(const MeetConditions(note: '  ').isEmpty, isTrue);
    });

    test('read as a coach would say them', () {
      const conditions = MeetConditions(
        sky: MeetSky.overcast,
        temperature: 53.6,
        wind: MeetWind.head,
      );
      expect(conditions.summary, 'Overcast · 54°F · Headwind');
    });

    test('leave out what nobody said', () {
      expect(const MeetConditions(wind: MeetWind.tail).summary, 'Tailwind');
      expect(const MeetConditions().summary, '');
    });

    test('survive the meet being stored and read back', () async {
      final library = MeetLibrary();
      await library.load();
      await library.save(_meet()
        ..conditions = const MeetConditions(
          sky: MeetSky.rain,
          temperature: 8,
          temperatureUnit: TemperatureUnit.celsius,
          wind: MeetWind.cross,
          note: 'wet ring',
        ));

      final reread = MeetLibrary();
      await reread.load();
      final conditions = reread.byId('k1')!.conditions;
      expect(conditions.sky, MeetSky.rain);
      expect(conditions.temperature, 8);
      expect(conditions.temperatureUnit, TemperatureUnit.celsius);
      expect(conditions.wind, MeetWind.cross);
      expect(conditions.note, 'wet ring');
    });

    test('a meet stored before there were any reads back with none', () {
      final meet = Meet.fromJson({
        'id': 'k1',
        'name': 'County Champs',
        'date': DateTime(2026, 6, 13).toIso8601String(),
      });
      expect(meet.conditions.isEmpty, isTrue);
    });
  });

  group("an athlete's meets", () {
    /// A meet Ana threw at, against [rivals] who each threw once.
    Meet meetFor(String id, DateTime on, List<double> series,
        {List<double> rivals = const []}) {
      final meet = _meet(id: id, on: on);
      final mine = MeetEntry(
        id: '$id-mine',
        athlete: 'Ana Diaz',
        event: ThrowEvent.discus,
        implementKg: 1,
      );
      for (var round = 0; round < series.length; round++) {
        mine.setAttempt(round, MeetAttempt.mark('$id-m$round'));
      }
      meet.entries.add(mine);
      for (var i = 0; i < rivals.length; i++) {
        meet.entries.add(MeetEntry(
          id: '$id-r$i',
          athlete: 'Rival $i',
          event: ThrowEvent.discus,
          implementKg: 1,
          tracked: false,
          order: i + 1,
        )..setAttempt(0, MeetAttempt.untracked(rivals[i])));
      }
      return meet;
    }

    /// The record book behind those series.
    List<ThrowMark> book(String id, List<double> series, DateTime on) => [
          for (var round = 0; round < series.length; round++)
            ThrowMark(
              id: '$id-m$round',
              athlete: 'Ana Diaz',
              event: ThrowEvent.discus,
              implementKg: 1,
              distance: series[round],
              achievedOn: on,
            ),
        ];

    test('read back as the afternoons they were', () {
      final on = DateTime(2026, 6, 13);
      final meet = meetFor('k1', on, [41.20, 43.06], rivals: [40.00]);
      final outings = MeetOuting.forAthlete(
          'Ana Diaz', [meet], book('k1', [41.20, 43.06], on));

      expect(outings, hasLength(1));
      final outing = outings.single;
      expect(outing.meet.id, 'k1');
      expect(outing.best, 43.06);
      // The one that counted was her second, which is the shape of the
      // afternoon rather than the number.
      expect(outing.bestRound, 2);
      expect(outing.taken, 2);
      expect(outing.fieldSize, 2);
      expect(outing.place?.place, 1);
      expect(outing.won, isTrue);
    });

    test('run most recent first', () {
      final june = DateTime(2026, 6, 13);
      final may = DateTime(2026, 5, 2);
      final outings = MeetOuting.forAthlete(
        'Ana Diaz',
        [
          meetFor('k1', may, [40.00]),
          meetFor('k2', june, [43.06])
        ],
        [
          ...book('k1', [40.00], may),
          ...book('k2', [43.06], june)
        ],
      );
      expect([for (final outing in outings) outing.meet.id], ['k2', 'k1']);
    });

    test('a competition of one is not a win', () {
      final on = DateTime(2026, 6, 13);
      final outing = MeetOuting.forAthlete(
              'Ana Diaz',
              [
                meetFor('k1', on, [41.20])
              ],
              book('k1', [41.20], on))
          .single;
      expect(outing.place?.place, 1);
      expect(outing.won, isFalse);
    });

    test('a series of fouls places nowhere', () {
      final meet = _meet();
      meet.entries.add(MeetEntry(
        id: 'e1',
        athlete: 'Ana Diaz',
        event: ThrowEvent.discus,
        implementKg: 1,
      )
        ..setAttempt(0, MeetAttempt.foul())
        ..setAttempt(1, MeetAttempt.foul()));
      final outing = MeetOuting.forAthlete('Ana Diaz', [meet], const []).single;
      expect(outing.best, isNull);
      expect(outing.place, isNull);
      expect(outing.taken, 2);
    });

    test('are matched however the name was spelled', () {
      final on = DateTime(2026, 6, 13);
      expect(
        MeetOuting.forAthlete(
            'ana diaz',
            [
              meetFor('k1', on, [41.20])
            ],
            book('k1', [41.20], on)),
        hasLength(1),
      );
      expect(
          MeetOuting.forAthlete('', [
            meetFor('k1', on, [41.20])
          ], const []),
          isEmpty);
    });

    test('add up to a record', () {
      final june = DateTime(2026, 6, 13);
      final may = DateTime(2026, 5, 2);
      final record = MeetRecord(MeetOuting.forAthlete(
        'Ana Diaz',
        [
          meetFor('k1', may, [40.00], rivals: [45.00]),
          meetFor('k2', june, [44.00], rivals: [42.00]),
        ],
        [
          ...book('k1', [40.00], may),
          ...book('k2', [44.00], june)
        ],
      ));
      expect(record.outings, 2);
      expect(record.wins, 1);
      expect(record.podiums, 2);
      expect(record.best, 44.00);
      expect(record.averageBest, 42.00);
    });
  });

  group('the board', () {
    /// A discus competition where each athlete threw once.
    MeetCompetition field(List<(String, double, bool)> entries) =>
        MeetCompetition(ThrowEvent.discus, 1, [
          for (var i = 0; i < entries.length; i++)
            MeetEntry(
              id: 'e$i',
              athlete: entries[i].$1,
              event: ThrowEvent.discus,
              implementKg: 1,
              tracked: entries[i].$3,
              order: i,
            )..setAttempt(0, MeetAttempt.untracked(entries[i].$2)),
        ]);

    MeetStandings table(MeetCompetition competition, {int advancing = 99}) =>
        MeetStandings(competition, const [],
            advancing: advancing, prelimRounds: 3);

    test('draws the podium, furthest first', () {
      final board = MeetBoard(table(field([
        ('Ana Diaz', 41.20, false),
        ('M. Okoye', 44.90, false),
        ('J. Smith', 43.06, false),
      ])));
      expect(
          [for (final mark in board.marks) mark.label], ['1st', '2nd', '3rd']);
      expect(board.marks.first.distance, 44.90);
      expect(board.marks.first.name, 'M. Okoye');
      expect(board.marks.last.distance, 41.20);
    });

    test('is empty until somebody has a mark', () {
      final competition = MeetCompetition(ThrowEvent.discus, 1, [
        MeetEntry(
            id: 'e1',
            athlete: 'Ana Diaz',
            event: ThrowEvent.discus,
            implementKg: 1)
          ..setAttempt(0, MeetAttempt.foul()),
      ]);
      expect(MeetBoard(table(competition)).isEmpty, isTrue);
    });

    test('puts a band either side of a single mark', () {
      final board = MeetBoard(table(field([('Ana Diaz', 41.20, true)])));
      expect(board.near, closeTo(40.70, 1e-9));
      expect(board.far, closeTo(41.70, 1e-9));
      expect(board.fractionOf(41.20), closeTo(0.5, 1e-9));
    });

    test('runs from the near edge to the far one', () {
      final board = MeetBoard(table(field([
        ('Ana Diaz', 40.00, false),
        ('M. Okoye', 44.00, false),
      ])));
      expect(board.fractionOf(board.near), 0);
      expect(board.fractionOf(board.far), 1);
    });

    test('draws the cut when it is not already one of the places', () {
      final board = MeetBoard(table(
        field([
          ('A', 44.90, false),
          ('B', 43.20, false),
          ('C', 43.06, false),
          ('D', 42.00, false),
          ('E', 40.00, false),
        ]),
        advancing: 4,
      ));
      final cut = board.marks.firstWhere((m) => m.line == BoardLine.cut);
      expect(cut.distance, 42.00);
      expect(cut.label, 'the cut');
      expect(cut.name, isEmpty);
    });

    test('says nothing twice when the cut falls on a place already drawn', () {
      final board = MeetBoard(table(
        field([
          ('A', 44.90, false),
          ('B', 43.20, false),
          ('C', 43.06, false),
        ]),
        advancing: 2,
      ));
      expect(board.marks.where((m) => m.line == BoardLine.cut), isEmpty);
    });

    test("draws the coach's own athlete wherever they are standing", () {
      final board = MeetBoard(table(field([
        ('A', 44.90, false),
        ('B', 43.20, false),
        ('C', 43.06, false),
        ('Ana Diaz', 41.20, true),
      ])));
      final mine = board.marks.firstWhere((m) => m.line == BoardLine.mine);
      expect(mine.name, 'Ana Diaz');
      // Labelled with the place they have to climb, not with whose it is.
      expect(mine.label, '4th');
      expect(mine.tracked, isTrue);
      // And the band opens far enough to hold them.
      expect(board.near, lessThan(41.20));
    });

    test('draws the athlete in the circle when they are off the podium', () {
      final competition = field([
        ('A', 44.90, false),
        ('B', 43.20, false),
        ('C', 43.06, false),
        ('D', 41.20, false),
      ]);
      final board =
          MeetBoard(table(competition), inTheCircle: competition.entries.last);
      final up = board.marks.firstWhere((m) => m.line == BoardLine.upNow);
      expect(up.name, 'D');
      expect(up.label, '4th');
    });

    test('leaves the athlete in the circle to their place on the podium', () {
      final competition = field([
        ('A', 44.90, false),
        ('B', 43.20, false),
      ]);
      final board =
          MeetBoard(table(competition), inTheCircle: competition.entries.first);
      expect(board.marks.where((m) => m.line == BoardLine.upNow), isEmpty);
      expect(board.marks, hasLength(2));
    });

    test('keeps the rest of the field to marks inside the band', () {
      final board = MeetBoard(table(field([
        ('A', 44.90, false),
        ('B', 44.80, false),
        ('C', 44.70, false),
        // Inside the band the podium sets, and a long way outside it.
        ('D', 44.65, false),
        ('E', 30.00, false),
      ])));
      expect(board.others, [44.65]);
      // The stragglers don't drag the band down over the marks that decide
      // it — that is what the standings table is for.
      expect(board.near, greaterThan(44.0));
    });
  });
}
