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
/// writes it into the library the moment it is entered. The averages are
/// read off the meets, but the meets are read off these.
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

List<MeetOuting> _outings(List<Meet> meets, List<ThrowMark> book) =>
    MeetOuting.forAthlete('Ana Diaz', meets, book);

/// A run of meets, thrown as given.
List<MeetOuting> _season(Map<String, (DateTime, List<double?>)> meets) {
  final competitions = <Meet>[];
  final book = <ThrowMark>[];
  for (final meet in meets.entries) {
    competitions.add(_meetFor(meet.key, meet.value.$1, meet.value.$2));
    book.addAll(_book(meet.key, meet.value.$1, meet.value.$2));
  }
  return _outings(competitions, book);
}

/// Averages: what a season of competitions comes to between the bests.
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
      final outing = _outings([_meetFor('k1', june, series)], const []).single;
      expect(outing.average, isNull);
      expect(outing.fouls, 3);
    });
  });

  group('a season', () {
    test('reads the meets two ways and keeps the count of each', () {
      final averages = SeasonAverages.forSeason(_season({
        'k1': (may, [60, null, 64]),
        'k2': (june, [70, 66, null]),
      })).single;

      expect(averages.event, ThrowEvent.discus);
      // 64 and 70 — the level competed at.
      expect(averages.averageBest, closeTo(67.00, 0.001));
      expect(averages.on(MeetLine.best), closeTo(67.00, 0.001));
      expect(averages.meetsScored, 2);
      // 60, 64, 70, 66 — how reliably it is reached.
      expect(averages.averageMark, closeTo(65.00, 0.001));
      expect(averages.on(MeetLine.average), closeTo(65.00, 0.001));
      expect(averages.marks, 4);
      expect(averages.fouls, 2);
      expect(averages.attempts, 6);
      expect(averages.foulRate, closeTo(1 / 3, 0.001));
    });

    test('names the furthest of them and the day it was thrown', () {
      final averages = SeasonAverages.forSeason(_season({
        'k1': (may, [60, 64]),
        'k2': (june, [70, 66]),
      })).single;
      expect(averages.best, 70);
      expect(averages.bestOn, june);
    });

    test('counts what was passed as well as what was fouled', () {
      final meet = _meetFor('k1', june, [60, 64]);
      meet.entries.single
        ..setAttempt(2, MeetAttempt.pass())
        ..setAttempt(3, MeetAttempt.foul());
      final averages = SeasonAverages.forSeason(
              _outings([meet], _book('k1', june, [60, 64])))
          .single;
      expect(averages.passes, 1);
      expect(averages.fouls, 1);
      expect(averages.attempts, 4);
    });

    test('has nothing to say about an athlete who has not competed', () {
      // The record book may be full of Tuesdays; the averages are about
      // meets, so with no meets there is nothing here to average.
      expect(SeasonAverages.forSeason(const []), isEmpty);
      expect(SeasonAverages.seasonsOf(const []), isEmpty);
    });

    test('keeps each implement to itself', () {
      final discus = <double?>[60, 64];
      final shot = <double?>[18, 19];
      final meets = [
        _meetFor('k1', june, discus),
        _meetFor('k2', june, shot, event: ThrowEvent.shotPut, implementKg: 4),
      ];
      final book = [
        ..._book('k1', june, discus),
        ..._book('k2', june, shot, event: ThrowEvent.shotPut, implementKg: 4),
      ];
      final averages = SeasonAverages.forSeason(_outings(meets, book));

      expect(averages, hasLength(2));
      // Event order, the way the bests above them are listed.
      expect(averages.first.event, ThrowEvent.shotPut);
      expect(averages.first.averageMark, closeTo(18.50, 0.001));
      expect(averages.last.event, ThrowEvent.discus);
      expect(averages.last.averageMark, closeTo(62.00, 0.001));
    });

    test('reads the season forwards, and says what it moved either way', () {
      final averages = SeasonAverages.forSeason(_season({
        'k1': (may, [60, 62]),
        'k2': (june, [64, 70]),
      })).single;

      // Oldest first, whatever order the meets were read in: a line is
      // drawn in the direction the season was thrown.
      expect([for (final meet in averages.meets) meet.meet.id], ['k1', 'k2']);
      // Averaged, 61 then 67. On the bests, 62 then 70.
      expect(averages.movement(MeetLine.average), closeTo(6.00, 0.001));
      expect(averages.movement(MeetLine.best), closeTo(8.00, 0.001));
    });

    test('a season with one meet in it has nothing to compare', () {
      final averages = SeasonAverages.forSeason(_season({
        'k1': (june, [60, 62]),
      })).single;
      expect(averages.movement(MeetLine.average), isNull);
      expect(averages.movement(MeetLine.best), isNull);
      expect(averages.scoredMeets, hasLength(1));
    });

    test('one throw at a meet is not an average of anything', () {
      final averages = SeasonAverages.forSeason(_season({
        'k1': (june, [60, null]),
      })).single;
      expect(averages.isEmpty, isTrue);
    });
  });

  group('split by season', () {
    final lastYear = DateTime(2025, 6, 14);
    final thisYear = DateTime(2026, 6, 13);

    List<MeetOuting> bothYears() => _season({
          'k1': (lastYear, [50, 54]),
          'k2': (thisYear, [60, 64]),
        });

    test('lists the seasons competed in, most recent first', () {
      expect(SeasonAverages.seasonsOf(bothYears()), [2026, 2025]);
    });

    test('a season is only named once, however much was thrown in it', () {
      expect(
        SeasonAverages.seasonsOf(_season({
          'k1': (thisYear, [60, 64]),
          'k2': (DateTime(2026, 8, 1), [62, 66]),
        })),
        [2026],
      );
    });

    test('averages only what was thrown in the season asked for', () {
      final outings = bothYears();

      final now = SeasonAverages.forSeason(outings, season: 2026).single;
      expect(now.season, 2026);
      expect(now.averageMark, closeTo(62.00, 0.001));
      expect(now.marks, 2);
      expect(now.meets, hasLength(1));

      final then = SeasonAverages.forSeason(outings, season: 2025).single;
      expect(then.averageMark, closeTo(52.00, 0.001));
      expect(then.marks, 2);

      // And every season is the two of them together, which is the number
      // a season on its own is worth telling apart from.
      final ever = SeasonAverages.forSeason(outings).single;
      expect(ever.season, isNull);
      expect(ever.averageMark, closeTo(57.00, 0.001));
      expect(ever.meets, hasLength(2));
    });

    test('a season nothing was thrown in averages nothing', () {
      expect(SeasonAverages.forSeason(bothYears(), season: 2024), isEmpty);
    });

    test('the history is one reading per season, read either way', () {
      final history =
          SeasonAverages.history(bothYears(), ThrowEvent.discus, 1);
      expect([for (final season in history) season.season], [2026, 2025]);
      expect(history.first.on(MeetLine.average), closeTo(62.00, 0.001));
      expect(history.first.on(MeetLine.best), closeTo(64.00, 0.001));
      expect(history.last.on(MeetLine.best), closeTo(54.00, 0.001));
    });
  });
}
