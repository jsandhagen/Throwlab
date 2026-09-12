import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/meet_conditions.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/utils/meet_report.dart';
import 'package:throwlab/services/results_sheet.dart';
import 'package:throwlab/utils/pdf_text.dart';

/// A meet's results as a sheet somebody can hand out.
///
/// Read back with the app's own PDF reader rather than checked byte for
/// byte: what matters is that a reader can open the file and find the
/// results in it, which is exactly what [pdfText] does for a schedule
/// coming the other way.
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

  MeetEntry entry(String id, String athlete, List<MeetAttempt?> attempts,
      {int order = 0, bool tracked = true}) {
    final made = MeetEntry(
      id: id,
      athlete: athlete,
      event: ThrowEvent.discus,
      implementKg: 1,
      tracked: tracked,
      order: order,
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

  String read(Meet made, List<ThrowResult> results, {MeetCompetition? only}) =>
      pdfText(meetResultsPdf(made, results,
          only: only, printedOn: DateTime(2026, 6, 14)))!;

  test('is a PDF a reader can open', () {
    final bytes = meetResultsPdf(meet(), const []);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(bytes.sublist(bytes.length - 6)), '%%EOF\n');
    expect(pdfText(bytes), isNotNull);
  });

  test('names the meet, the day and the format', () {
    final made = meet(rounds: 6, prelimRounds: 3, advancing: 8);
    made.entries.add(entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]));
    final text = read(made, [mark('m1', 'Ana Diaz', 41.20)]);

    expect(text, contains('COUNTY CHAMPS'));
    expect(text, contains('13 Jun 2026'));
    expect(text, contains('Sportcity'));
    expect(text, contains('3 + 3'));
  });

  test('carries what the day was like', () {
    final made = meet()
      ..conditions = const MeetConditions(
        sky: MeetSky.overcast,
        temperature: 54,
        wind: MeetWind.head,
        note: 'wet ring',
      );
    made.entries.add(entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]));
    final text = read(made, [mark('m1', 'Ana Diaz', 41.20)]);

    expect(text, contains('Overcast'));
    expect(text, contains('54'));
    expect(text, contains('Headwind'));
    expect(text, contains('wet ring'));
  });

  test('writes the series round by round, in standings order', () {
    final made = meet();
    made.entries.addAll([
      entry('e1', 'Ana Diaz', [
        MeetAttempt.mark('m1'),
        MeetAttempt.foul(),
        MeetAttempt.mark('m2'),
        MeetAttempt.pass(),
      ]),
      entry('e2', 'B. Rival', [MeetAttempt.untracked(44.90)],
          order: 1, tracked: false),
    ]);
    final text = read(
        made, [mark('m1', 'Ana Diaz', 41.20), mark('m2', 'Ana Diaz', 43.06)]);

    final lines = text.split('\n');
    // A name is on the page more than once: the chart over the table
    // labels it, the table gives it a row, and a personal best names it
    // again underneath. The row is the long one — it is the only line
    // carrying the whole series.
    String rowFor(String name) => lines
        .where((line) => line.contains(name))
        .reduce((a, b) => b.length > a.length ? b : a);
    final ana = rowFor('Ana Diaz');
    final rival = rowFor('B. Rival');
    expect(ana, contains('41.20'));
    expect(ana, contains('43.06'));
    // The foul and the pass are on the sheet: a series is not a list of
    // distances, and three fouls chasing a big one is the story of the
    // afternoon.
    expect(ana, contains('X'));
    // Furthest first, whoever they belong to.
    expect(lines.indexOf(rival), lessThan(lines.indexOf(ana)));
    expect(rival, contains('44.90'));
  });

  test('a mark measured in feet reads back the way a meet writes one', () {
    final made = meet();
    made.entries.add(entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]));
    final text =
        read(made, [mark('m1', 'Ana Diaz', 58.34, unit: DistanceUnit.feet)]);
    // Feet and inches, to the lesser quarter — what the meet called out and
    // what its own sheet will say. Not 191.40, which is the same throw in
    // a notation nobody there is using.
    expect(text, contains('191-04.75'));
    expect(text, isNot(contains('191.40')));
  });

  test('gives a series in feet the room it needs', () {
    final made = meet();
    made.entries.add(entry('e1', 'Ana Diaz', [
      MeetAttempt.mark('m1'),
      MeetAttempt.mark('m2'),
      MeetAttempt.mark('m3'),
    ]));
    final text = read(made, [
      mark('m1', 'Ana Diaz', 58.34, unit: DistanceUnit.feet),
      mark('m2', 'Ana Diaz', 61.02, unit: DistanceUnit.feet),
      mark('m3', 'Ana Diaz', 59.10, unit: DistanceUnit.feet),
    ]);
    final row = text
        .split('\n')
        .firstWhere((line) => line.contains('191-04.75'));
    // A column cut for '44.90' would run one of these into the next. The
    // series is measured before it is set, so every mark keeps its own
    // column whatever notation the meet used.
    expect(row, matches(RegExp(r'191-04\.75\s+200-02\.25\s+193-10\.75')));
  });

  test('draws the cut where it falls', () {
    final made = meet(rounds: 6, prelimRounds: 3, advancing: 1);
    made.entries.addAll([
      entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]),
      entry('e2', 'B. Rival', [MeetAttempt.untracked(30.00)],
          order: 1, tracked: false),
    ]);
    final text = read(made, [mark('m1', 'Ana Diaz', 41.20)]);
    expect(text, contains('top 1 advance'));
    // A rule of dashes between the qualifier and everybody else.
    expect(text, contains('-----'));
  });

  group('what the sheet makes of the day', () {
    /// Four in a discus, with a series each.
    Meet field({int advancing = 99}) {
      final made = meet(rounds: 6, prelimRounds: 3, advancing: advancing);
      made.entries.addAll([
        entry('e1', 'Ana Diaz', [
          MeetAttempt.mark('m1'),
          MeetAttempt.foul(),
          MeetAttempt.mark('m2'),
        ]),
        entry('e2', 'B. Rival', [
          MeetAttempt.untracked(42.00),
          MeetAttempt.untracked(42.60),
        ], order: 1, tracked: false),
        entry('e3', 'C. Third', [MeetAttempt.untracked(40.10)],
            order: 2, tracked: false),
        entry('e4', 'D. Fourth', [MeetAttempt.untracked(38.20)],
            order: 3, tracked: false),
      ]);
      return made;
    }

    List<ThrowResult> marks() =>
        [mark('m1', 'Ana Diaz', 41.20), mark('m2', 'Ana Diaz', 43.06)];

    test('counts the day up in one line', () {
      final text = read(field(), marks());
      // Six throws: Ana's two marks and her foul, and four from the rest —
      // a foul is a throw, and a sheet that left it out would call a windy
      // afternoon a quiet one.
      expect(text, contains('1 event'));
      expect(text, contains('4 athletes'));
      expect(text, contains('7 throws'));
    });

    test('says how it was won', () {
      final text = read(field(), marks());
      // Ana found it in the third round and won by 46 centimeters.
      expect(text, contains('Won in round 3, 0.46 m clear of B. Rival'));
    });

    test('says when it was won on countback', () {
      final made = meet();
      made.entries.addAll([
        entry('e1', 'Ana Diaz',
            [MeetAttempt.mark('m1'), MeetAttempt.mark('m2')]),
        entry('e2', 'B. Rival', [MeetAttempt.untracked(43.06)],
            order: 1, tracked: false),
      ]);
      final text = read(made, [
        mark('m1', 'Ana Diaz', 41.20),
        mark('m2', 'Ana Diaz', 43.06),
      ]);
      expect(text, contains('countback'));
    });

    test('marks a personal best, and says what it beat', () {
      final text = read(field(), marks());
      // Ana's 43.06 is the furthest the record book holds for her at this
      // weight — the one thing on the page the meet itself cannot know.
      expect(text, contains('PB'));
      expect(text, contains('PERSONAL BESTS'));
      expect(text, contains('up 1.86 m on 41.20 m'));
      expect(text, contains('1 personal best'));
    });

    test('leaves the PB off a throw the athlete has bettered before', () {
      // The same afternoon, with a further throw already in the book.
      final text = read(field(), [
        ...marks(),
        mark('m0', 'Ana Diaz', 45.90),
      ]);
      expect(text, isNot(contains('PERSONAL BESTS')));
      // Nothing to count in the line across the top either — though the
      // legend at the foot still says what a PB would look like.
      expect(text, isNot(contains('1 personal best')));
    });

    test('draws the competition to a scale the reader can count', () {
      final text = read(field(advancing: 2), marks());
      // The marker lines of the scale are labeled, and the cut is drawn
      // across them — a gap on the chart is a number of meters, not a
      // shape to be taken on trust.
      expect(text, contains('cut'));
      expect(text, contains(' m'));
      // Every ring between the shortest throw and the longest.
      for (final at in ['38', '40', '42', '44']) {
        expect(text, contains(at), reason: 'the $at line is on the scale');
      }
    });

    test('says nothing about a competition of one', () {
      final made = meet();
      made.entries.add(entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]));
      final text = read(made, [mark('m1', 'Ana Diaz', 41.20)]);
      // One line is not a picture of a competition, and nobody won a
      // contest they were alone in — the table is the whole of it.
      expect(text, isNot(contains('Won in round')));
      expect(text, isNot(contains('cut')));
      expect(text, contains('41.20'));
    });
  });

  test('one event at a time, when that is what was asked for', () {
    final made = meet();
    made.entries.addAll([
      entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]),
      MeetEntry(
        id: 'e2',
        athlete: 'J. Thrower',
        event: ThrowEvent.javelin,
        implementKg: 0.8,
        order: 1,
      )..setAttempt(0, MeetAttempt.untracked(51.00)),
    ]);
    final results = [mark('m1', 'Ana Diaz', 41.20)];

    final whole = read(made, results);
    expect(whole, contains('DISCUS'));
    expect(whole, contains('JAVELIN'));

    final discus = MeetCompetition.of(made)
        .firstWhere((competition) => competition.event == ThrowEvent.discus);
    final one = read(made, results, only: discus);
    expect(one, contains('DISCUS'));
    expect(one, isNot(contains('JAVELIN')));
  });

  test('says so when nobody was entered', () {
    expect(read(meet(), const []), contains('Nobody was entered'));
  });

  test('a long name is cut rather than allowed to break the columns', () {
    final made = meet();
    made.entries.add(entry(
        'e1',
        'Bartholomew Fitzwilliam-Cavendish of the Long Name Athletic Club',
        [MeetAttempt.mark('m1')]));
    final text = read(made, [
      mark(
          'm1',
          'Bartholomew Fitzwilliam-Cavendish of the Long Name Athletic Club',
          41.20)
    ]);
    expect(text, contains('Bartholomew'));
    expect(text, contains('41.20'));
  });

  test('a field too long for one page runs onto the next', () {
    final made = meet();
    final results = <ThrowResult>[];
    for (var i = 0; i < 60; i++) {
      made.entries
          .add(entry('e$i', 'Thrower $i', [MeetAttempt.mark('m$i')], order: i));
      results.add(mark('m$i', 'Thrower $i', 30 + i * 0.1));
    }
    final bytes =
        meetResultsPdf(made, results, printedOn: DateTime(2026, 6, 14));
    // More than one page, and everybody on one of them.
    final pages = int.parse(
        RegExp(r'/Count (\d+)').firstMatch(String.fromCharCodes(bytes))!
            .group(1)!);
    expect(pages, greaterThan(1));
    final text = pdfText(bytes)!;
    expect(text, contains('Thrower 0'));
    expect(text, contains('Thrower 59'));
    expect(text, contains('page 1 of $pages'));
    // And the meet's name on every one of them, because the pages come
    // apart.
    expect('County Champs'.allMatches(text).length, greaterThanOrEqualTo(pages));
  });

  group('the file it lands in', () {
    test('is named for the meet and the day', () {
      expect(ResultsSheet.fileName(meet(), null),
          'County Champs - 2026-06-13.pdf');
    });

    test('names the event when it is one event', () {
      final made = meet();
      made.entries.add(entry('e1', 'Ana Diaz', [MeetAttempt.mark('m1')]));
      expect(
        ResultsSheet.fileName(made, MeetCompetition.of(made).single),
        'County Champs - Discus 1 kg - 2026-06-13.pdf',
      );
    });

    test('keeps a meet named with punctuation out of the file system', () {
      final made = Meet(
          id: 'k2',
          name: 'St. Mary\'s / Open: "Round 1"',
          date: DateTime(2026, 4, 3));
      expect(ResultsSheet.fileName(made, null),
          'St. Mary s Open Round 1 - 2026-04-03.pdf');
    });
  });
}
