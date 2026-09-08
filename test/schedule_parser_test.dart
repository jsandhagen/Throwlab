import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/utils/schedule_parser.dart';

/// Every test reads its schedule on the same September afternoon, so a row
/// with no year on it doesn't change meaning when the suite is run in March.
final _today = DateTime(2026, 9, 8);

List<ScheduleCandidate> parse(String text) =>
    parseSchedule(text, today: _today);

void main() {
  group('a fixture list in columns', () {
    const schedule = '''
2027 Outdoor Track & Field Schedule

Date      Meet                       Site
3/13      Tiger Relays               Auburn, AL
3/27      Spring Invitational        Home
4/10      County Championships       Sportcity, Manchester
''';

    test('reads a meet a row', () {
      final found = parse(schedule);
      expect(found.map((c) => c.name), [
        'Tiger Relays',
        'Spring Invitational',
        'County Championships',
      ]);
    });

    test('takes the year off the top of the page', () {
      expect(parse(schedule).first.date, DateTime(2027, 3, 13));
    });

    test('keeps the second column as the venue', () {
      expect(parse(schedule).map((c) => c.venue),
          ['Auburn, AL', 'Home', 'Sportcity, Manchester']);
    });

    test('throws the header row away', () {
      expect(parse(schedule).any((c) => c.name.toLowerCase() == 'meet'),
          isFalse);
    });
  });

  group('dates', () {
    test('reads a month by name, either way round', () {
      expect(parse('Sat, April 12 2027 — Spring Open').single.date,
          DateTime(2027, 4, 12));
      expect(parse('Sunday 13 April 2027 - League Match').single.date,
          DateTime(2027, 4, 13));
    });

    test('reads an ISO date', () {
      expect(parse('2027-05-02  Loughborough Open').single.date,
          DateTime(2027, 5, 2));
    });

    test('starts a two-day meet on its first day', () {
      expect(parse('April 12-13, 2027  National Champs').single.date,
          DateTime(2027, 4, 12));
    });

    test('assumes the season that has not happened yet', () {
      final found = parse('April 12  Spring Open').single;
      expect(found.date, DateTime(2027, 4, 12));
      expect(found.notes.single, contains('No year'));
    });

    test('takes a day past 12 as the day, whichever side it is on', () {
      expect(parse('25/12/2026  Boxing Day Throws').single.date,
          DateTime(2026, 12, 25));
      expect(parse('12/25/2026  Boxing Day Throws').single.date,
          DateTime(2026, 12, 25));
    });

    test('says so when a slashed date could be read either way', () {
      final found = parse('4/12/2027  Spring Open').single;
      expect(found.date, DateTime(2027, 4, 12));
      expect(found.notes.single, contains('month first'));
    });

    test('ignores a date that is not one', () {
      expect(parse('13/13/2027  Not A Date'), isEmpty);
    });
  });

  group('the rest of the row', () {
    test('splits a venue off an @', () {
      final found = parse('Sat 12 April 2027  Spring Open @ Hayward Field')
          .single;
      expect(found.name, 'Spring Open');
      expect(found.venue, 'Hayward Field');
    });

    test('splits a venue out of brackets', () {
      final found = parse('12 April 2027 League Match (Sportcity)').single;
      expect(found.name, 'League Match');
      expect(found.venue, 'Sportcity');
    });

    test('splits a venue off a dash', () {
      final found = parse('12 April 2027 | Spring Open – Sportcity').single;
      expect(found.name, 'Spring Open');
      expect(found.venue, 'Sportcity');
    });

    test('drops a start time rather than storing it as the day', () {
      final found =
          parse('Sat 12 April 2027, 10:30 am  Spring Open').single;
      expect(found.name, 'Spring Open');
      expect(found.date, DateTime(2027, 4, 12));
    });

    test('keeps a weekday that is part of a name', () {
      expect(parse('12 April 2027  Sun Devil Classic').single.name,
          'Sun Devil Classic');
    });

    test('takes the meet off the next line when the date is alone on one',
        () {
      final found = parse('''
Friday 12 April 2027
    Loughborough Open — Loughborough
''').single;
      expect(found.name, 'Loughborough Open');
      expect(found.venue, 'Loughborough');
    });

    test('leaves a comma alone, since a venue is full of them', () {
      // 'Tiger Relays, Auburn, AL' has no honest split, so the row is left
      // as the coach typed it rather than cut in a place they didn't mean.
      final found = parse('12 April 2027 Tiger Relays, Auburn, AL').single;
      expect(found.name, 'Tiger Relays, Auburn, AL');
      expect(found.venue, isEmpty);
    });
  });

  group('what it refuses to do', () {
    test('reads nothing off a page with no dates on it', () {
      expect(parse('Throwing squad\nBring your own implements'), isEmpty);
    });

    test('enters the same meet once', () {
      expect(
          parse('12 April 2027 Spring Open\n12 April 2027 Spring Open').length,
          1);
    });

    test('warns when a day is crowded enough to be one meet timetable', () {
      // A timetable pasted with the date repeated down it: four meets on
      // one day is a Saturday, four rows on one day is a programme.
      final found = parse('''
6/12/2027  10:00  Hammer, Men
6/12/2027  11:30  Shot Put, Women
6/12/2027  13:00  Discus, Men
6/12/2027  14:30  Javelin, Women
''');
      expect(found.length, 4);
      expect(found.every((c) => c.notes.any((n) => n.contains('timetable'))),
          isTrue);
    });
  });
}
