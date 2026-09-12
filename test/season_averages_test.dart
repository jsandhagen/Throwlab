import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_history.dart';
import 'package:throwlab/models/season_averages.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';

/// A meet Ana threw the given series at. A null round is a foul, so a
/// series reads the way it is called out: 69, F, 67.
Meet _meetFor(
  String id,
  DateTime on,
  List<double?> series, {
  ThrowEvent event = ThrowEvent.discus,
  double implementKg = 1,
}) {
  final meet = Meet(id: id, name: 'Meet $id', date: on);
  final entry = MeetEntry(
    id: '$id-mine',
    athlete: 'Ana Diaz',
    event: event,
    implementKg: implementKg,
  );
  for (var round = 0; round < series.length; round++) {
    entry.setAttempt(
      round,
      series[round] == null
          ? MeetAttempt.foul()
          : MeetAttempt.mark('$id-m$round'),
    );
  }
  meet.entries.add(entry);
  return meet;
}

/// The record book behind those series — every legal round, as a meet
/// writes it into the library the moment it is entered.
List<ThrowMark> _book(
  String id,
  DateTime on,
  List<double?> series, {
  ThrowEvent event = ThrowEvent.discus,
  double implementKg = 1,
}) =>
    [
      for (var round = 0; round < series.length; round++)
        if (series[round] != null)
          ThrowMark(
            id: '$id-m$round',
            athlete: 'Ana Diaz',
            event: event,
            implementKg: implementKg,
            distance: series[round]!,
            achievedOn: on,
          ),
    ];

/// A throw taken on a Tuesday, which is in the record book and at no meet.
ThrowMark _training(String id, DateTime on, double distance,
        {ThrowEvent event = ThrowEvent.discus, double implementKg = 1}) =>
    ThrowMark(
      id: id,
      athlete: 'Ana Diaz',
      event: event,
      implementKg: implementKg,
      distance: distance,
      achievedOn: on,
    );

List<MeetOuting> _outings(List<Meet> meets, List<ThrowMark> book) =>
    MeetOuting.forAthlete('Ana Diaz', meets, book);

/// Averages: what a season comes to between the bests.
void main() {
  final may = DateTime(2026, 5, 2);
  final june = DateTime(2026, 6, 13);

  group('one competition', () {
    test('averages the marks and counts the fouls beside them', () {
      final series = <double?>[69, null, 67, 80, null, 66];
      final outing =
          _outings([_meetFor('k1', june, series)], _book('k1', june, series))
              .single;
      expect(outing.average, closeTo(70.50, 0.001));
      expect(outing.fouls, 2);
      expect(outing.legalMarks, 4);
      expect(outing.taken, 6);
      // The best is still the best: an average sits beside the placing,
      // never in place of it.
      expect(outing.best, 80);
    });

    test('an afternoon of fouls averages nothing at all', () {
      final series = <double?>[null, null, null];
      final outing =
          _outings([_meetFor('k1', june, series)], const []).single;
      expect(outing.average, isNull);
      expect(outing.fouls, 3);
    });
  });

  group('a season', () {
    test('averages the bests and the whole of every series', () {
      final may1 = <double?>[60, null, 64];
      final june1 = <double?>[70, 66, null];
      final averages = SeasonAverages.forSeason(
        _outings(
          [_meetFor('k1', may, may1), _meetFor('k2', june, june1)],
          [..._book('k1', may, may1), ..._book('k2', june, june1)],
        ),
        [..._book('k1', may, may1), ..._book('k2', june, june1)],
      ).single;

      expect(averages.event, ThrowEvent.discus);
      // 64 and 70 — the level competed at.
      expect(averages.averageBest, closeTo(67.00, 0.001));
      expect(averages.meetsScored, 2);
      // 60, 64, 70, 66 — how reliably it is reached.
      expect(averages.averageMeetMark, closeTo(65.00, 0.001));
      expect(averages.meetMarks, 4);
      expect(averages.fouls, 2);
      expect(averages.attempts, 6);
      expect(averages.foulRate, closeTo(1 / 3, 0.001));
      // Nothing was thrown outside the meets, so there is no second
      // average to draw: it would be the competition one again.
      expect(averages.hasTraining, isFalse);
    });

    test('widens to the record book when there is training in it', () {
      final series = <double?>[60, 64];
      final averages = SeasonAverages.forSeason(
        _outings([_meetFor('k1', june, series)], _book('k1', june, series)),
        [
          ..._book('k1', june, series),
          _training('t1', may, 56),
          _training('t2', may, 60),
        ],
      ).single;

      expect(averages.averageMeetMark, closeTo(62.00, 0.001));
      // The whole season: the two at the meet and the two on a Tuesday.
      expect(averages.averageEveryMark, closeTo(60.00, 0.001));
      expect(averages.everyMarks, 4);
      expect(averages.hasTraining, isTrue);
    });

    test('keeps each implement to itself', () {
      final discus = <double?>[60, 64];
      final shot = <double?>[18, 19];
      final meets = [
        _meetFor('k1', june, discus),
        _meetFor('k2', june, shot,
            event: ThrowEvent.shotPut, implementKg: 4),
      ];
      final book = [
        ..._book('k1', june, discus),
        ..._book('k2', june, shot, event: ThrowEvent.shotPut, implementKg: 4),
      ];
      final averages = SeasonAverages.forSeason(_outings(meets, book), book);

      expect(averages, hasLength(2));
      // Event order, the way the bests above them are listed.
      expect(averages.first.event, ThrowEvent.shotPut);
      expect(averages.first.averageMeetMark, closeTo(18.50, 0.001));
      expect(averages.last.event, ThrowEvent.discus);
      expect(averages.last.averageMeetMark, closeTo(62.00, 0.001));
    });

    test('reads the meet average forwards, and says what it moved', () {
      final may1 = <double?>[60, 62];
      final june1 = <double?>[64, 68];
      final averages = SeasonAverages.forSeason(
        _outings(
          [_meetFor('k1', may, may1), _meetFor('k2', june, june1)],
          [..._book('k1', may, may1), ..._book('k2', june, june1)],
        ),
        [..._book('k1', may, may1), ..._book('k2', june, june1)],
      ).single;

      // Oldest first, whatever order the meets were read in: a line is
      // drawn in the direction the season was thrown.
      expect([for (final meet in averages.meets) meet.meet.id], ['k1', 'k2']);
      // 61 then 66.
      expect(averages.moved, closeTo(5.00, 0.001));
    });

    test('a season with one meet in it has nothing to compare', () {
      final series = <double?>[60, 62];
      final averages = SeasonAverages.forSeason(
        _outings([_meetFor('k1', june, series)], _book('k1', june, series)),
        _book('k1', june, series),
      ).single;
      expect(averages.moved, isNull);
      expect(averages.scoredMeets, hasLength(1));
    });

    test('training on its own still averages', () {
      final averages = SeasonAverages.forSeason(
        const [],
        [_training('t1', may, 56), _training('t2', june, 60)],
      ).single;
      expect(averages.averageEveryMark, closeTo(58.00, 0.001));
      expect(averages.averageBest, isNull);
      expect(averages.averageMeetMark, isNull);
      expect(averages.foulRate, isNull);
      expect(averages.isEmpty, isFalse);
    });

    test('an athlete with nothing on record has nothing to average', () {
      expect(SeasonAverages.forSeason(const [], const []), isEmpty);
    });
  });
}
