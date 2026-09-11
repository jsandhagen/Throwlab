import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/utils/heat_sheet_parser.dart';
import 'package:throwlab/utils/pdf_text.dart';
import 'package:throwlab/utils/pdf_writer.dart';

/// The parser against the programs meets actually hand out.
///
/// Every sheet here is shaped after a published one — a Hy-Tek meet program
/// with its page furniture on, a field-event flight sheet, a British
/// programme, an American sectional — because the parser's job is not to
/// read a tidy example but to read the page a coach is holding. What each
/// is modeled on is named above it.
void main() {
  /// A Hy-Tek meet program, and the awkward part of one: a field long
  /// enough to run onto the next page, so the page header, the meet title,
  /// the event heading and the column rule are all printed again in the
  /// middle of it.
  const hytekProgram = '''
Lincoln High School                    HY-TEK's MEET MANAGER 8.0 - 4:32 PM  4/18/2026  Page 3
                            Central Invitational - 4/18/2026
                                   Meet Program

Event 15  Boys Shot Put 12lb
===============================================================================
    Name                    Year School                  Seed Mark
===============================================================================
Flight  1 of  2  Finals
  1 Smith, John                 11 Lincoln                 44-06.00
  2 Okoye, Michael              12 Northside               43-11.50
  3 Barros, Caio                10 Eastside                42-00.25
Lincoln High School                    HY-TEK's MEET MANAGER 8.0 - 4:32 PM  4/18/2026  Page 4
                            Central Invitational - 4/18/2026
                                   Meet Program

Event 15  Boys Shot Put 12lb  (continued)
===============================================================================
    Name                    Year School                  Seed Mark
===============================================================================
Flight  2 of  2  Finals
  1 Sandhagen, Jakob            12 Lincoln                 48-02.50
  2 Fischer, Liam               11 Brighton                41-09.25
''';

  group('a Hy-Tek meet program', () {
    final found = parseHeatSheet(hytekProgram);

    test('is one event, however many pages its field runs to', () {
      expect(found.length, 1);
      expect(found.single.athletes.length, 5);
    });

    test('reads the flights off it', () {
      expect(found.single.flightCount, 2);
      expect(found.single.athletes.map((a) => a.flight), [1, 1, 1, 2, 2]);
    });

    test('takes the weight off the heading', () {
      expect(found.single.event, ThrowEvent.shotPut);
      expect(found.single.implementKg, 5.44);
      expect(found.single.weightGuessed, isFalse);
    });

    test('leaves the page furniture off the field', () {
      expect(found.single.athletes.map((a) => a.name), [
        'John Smith',
        'Michael Okoye',
        'Caio Barros',
        'Jakob Sandhagen',
        'Liam Fischer',
      ]);
    });
  });

  group('a heading printed again over the rest of a field', () {
    /// The other way Hy-Tek reprints one: the whole line in brackets.
    test('is a continuation in brackets, too', () {
      final found = parseHeatSheet('''
Event 15  Boys Shot Put 12lb
Flight  1 of  2
  1 Smith, John                 11 Lincoln                 44-06.00
Central Invitational                                               Page 4
(Event 15  Boys Shot Put 12lb)
    Name                    Year School                  Seed Mark
Flight  2 of  2
  1 Fischer, Liam               11 Brighton                41-09.25
''');
      expect(found.length, 1);
      expect(found.single.athletes.map((a) => a.flight), [1, 2]);
    });

    test('carries the flight over a page that turns inside one', () {
      // The page can break anywhere, including half way down a flight —
      // and the heading printed over the rest of it says nothing about
      // which flight that is. Starting again at one would file the back
      // half of flight 2 as flight 1.
      final found = parseHeatSheet('''
Event 15  Boys Shot Put 12lb
Flight  1 of  2
  1 Smith, John                 11 Lincoln                 44-06.00
Flight  2 of  2
  1 Sandhagen, Jakob            12 Lincoln                 48-02.50
Lincoln High School            HY-TEK's MEET MANAGER 8.0 - 4:32 PM  Page 4
Event 15  Boys Shot Put 12lb  (continued)
    Name                    Year School                  Seed Mark
  2 Fischer, Liam               11 Brighton                41-09.25
''');
      expect(found.single.athletes.map((a) => a.flight), [1, 2, 2]);
    });

    test('keeps the weight the heading gave the first time', () {
      // A continuation is often printed short, with the weight left off.
      // Reading it as its own event would put half the field under a
      // guessed implement — and a best is per weight.
      final found = parseHeatSheet('''
Event 15  Boys Shot Put 12lb
  1 Smith, John                 11 Lincoln                 44-06.00
Event 15  Boys Shot Put  (continued)
  2 Fischer, Liam               11 Brighton                41-09.25
''');
      expect(found.single.implementKg, 5.44);
      expect(found.single.weightGuessed, isFalse);
      expect(found.single.athletes.length, 2);
    });

    test('is not two events that merely throw the same thing', () {
      // Different events, not one printed twice: the junior boys and the
      // senior boys both put a shot, and their fields are not one field.
      final found = parseHeatSheet('''
Event 15  Boys Shot Put 12lb
  1 Smith, John                 11 Lincoln                 44-06.00
Event 16  Junior Boys Shot Put 4kg
  1 Fischer, Liam                9 Brighton                31-09.25
''');
      expect(found.length, 2);
      expect(found.map((e) => e.implementKg), [5.44, 4]);
    });
  });

  /// The same program with the rest of the afternoon in it. A heat sheet is
  /// mostly not throwing, and the running is what closes a throws event.
  const wholeAfternoon = '''
Event 12  Girls 100 Meter Dash
===============================================================================
    Name                    Year School                  Seed Time
===============================================================================
Heat  1 of  5  Prelims
  1 Diaz, Ana                   11 Central                   12.44
  2 Raman, Priya                12 Central                   12.81
Heat  2 of  5  Prelims
  1 Fox, Kit                    10 Brighton                  12.90

Event 13  Girls Discus 1kg
===============================================================================
    Name                    Year School                  Seed Mark
===============================================================================
  1 Diaz, Ana                   11 Central                 41.20m
  2 Achebe, Nkem                12 Croydon                 39.80m

Event 14  Boys 4x100 Meter Relay
===============================================================================
    School                                              Seed Time
===============================================================================
  1 Central HS                                            43.55
  2 Northside                                             44.10
''';

  group('the rest of the afternoon', () {
    final found = parseHeatSheet(wholeAfternoon);

    test('is left where it was found', () {
      expect(found.length, 1);
      expect(found.single.event, ThrowEvent.discus);
      expect(found.single.athletes.map((a) => a.name),
          ['Ana Diaz', 'Nkem Achebe']);
    });

    test('does not lend the discus the sprint heats', () {
      // 'Heat 2 of 5' over the 100 belongs to the 100. A discus that came
      // out of it in two flights would be a competition thrown in an order
      // nobody drew.
      expect(found.single.flightCount, 1);
      expect(found.single.athletes.every((a) => a.flight == 1), isTrue);
    });
  });

  /// A field-event flight sheet — the page the judge writes on, one per
  /// flight, with a position column and no seed marks at all.
  const flightSheet = '''
                              Occidental College
                              Field Event Flights

Event 5  Women's Shot Put 4kg
Flight 1 of 3
Pos Name                    Year School
 1  Haugen, Elin            SO   Bergen
 2  Lindqvist, Anna         JR   Umea
Flight 2 of 3
Pos Name                    Year School
 1  Moreau, Paule           SR   Lyon
Flight 3 of 3
Pos Name                    Year School
 1  Barros, Ines            FR   Porto
''';

  group('a field event flight sheet', () {
    final found = parseHeatSheet(flightSheet);

    test('reads a field with no seed marks in it', () {
      expect(found.single.athletes.map((a) => a.name),
          ['Elin Haugen', 'Anna Lindqvist', 'Paule Moreau', 'Ines Barros']);
      expect(found.single.athletes.first.team, 'Bergen');
      expect(found.single.athletes.first.seed, '');
    });

    test('reads all three flights, column headers and all', () {
      expect(found.single.flightCount, 3);
      expect(found.single.athletes.map((a) => a.flight), [1, 1, 2, 3]);
    });
  });

  /// A school-meet program off the web: names the way a person says them,
  /// a bare 'Flight 1' with no 'of', and no position numbers down the side.
  const webProgram = '''
Boys Shot Put - 12lb
Flight 1
John Smith           Lincoln           44-06.00
Michael Okoye        Northside         43-11.50
Flight 2
Jakob Sandhagen      Lincoln           48-02.50
''';

  group('a program with no numbers down the side', () {
    final found = parseHeatSheet(webProgram);

    test('reads the field off it anyway', () {
      expect(found.single.athletes.map((a) => a.name),
          ['John Smith', 'Michael Okoye', 'Jakob Sandhagen']);
      expect(found.single.athletes.first.team, 'Lincoln');
    });

    test('reads a bare flight heading, with no count after it', () {
      expect(found.single.flightCount, 2);
      expect(found.single.athletes.map((a) => a.flight), [1, 1, 2]);
    });
  });

  /// The same thing pasted out of a web page, where the columns come
  /// across as tabs rather than as runs of spaces.
  test('a field pasted with tabs in it reads the same', () {
    final found = parseHeatSheet('Event 15\tBoys Shot Put 12lb\n'
        'Flight 1 of 2\n'
        '1\tSmith, John\t11\tLincoln\t44-06.00\n'
        'Flight 2 of 2\n'
        '2\tFischer, Liam\t11\tBrighton\t41-09.25\n');
    expect(found.single.athletes.map((a) => a.name),
        ['John Smith', 'Liam Fischer']);
    expect(found.single.athletes.map((a) => a.flight), [1, 2]);
    expect(found.single.athletes.first.team, 'Lincoln');
  });

  /// A unified sectional, where the heading carries a qualifying band
  /// instead of a weight and the division is one no implement table knows.
  test('a heading with a band on it is still a shot put', () {
    final found = parseHeatSheet('''
Event 2  Mixed Shot Put 9'-12'11.75 Division 2-Tier 2
===============================================================================
    Name                    Year School                  Seed Mark
===============================================================================
Flight  1 of  2  Finals
  1 Hernandez, Jorge            11 Everett Unif           11-03.00
Flight  2 of  2  Finals
  1 Smith, Sarah                12 Haverhill Un           11-06.00
''');
    expect(found.single.event, ThrowEvent.shotPut);
    // Nothing on that line names an implement, so the weight is a guess —
    // which the import screen says out loud, because a best is per weight.
    expect(found.single.weightGuessed, isTrue);
    expect(found.single.flightCount, 2);
    expect(found.single.athletes.map((a) => a.name),
        ['Jorge Hernandez', 'Sarah Smith']);
  });

  /// A British programme: sections rather than flights, metric seeds, and
  /// the weight in the heading the way a UK sheet writes it.
  const programme = '''
Event 12  Men's Shot (7.26K)
    Name                         Club                      Seed
Section 1
  1 J Sandhagen                  Sale Harriers             14.20
  2 T Brandt                     Kiel                      13.86
Section 2
  1 R Novak                      Prague                    13.10
''';

  group('a programme with sections', () {
    final found = parseHeatSheet(programme);

    test('reads a section as the flight it is', () {
      expect(found.single.flightCount, 2);
      expect(found.single.athletes.map((a) => a.flight), [1, 1, 2]);
    });

    test('takes the weight out of the brackets', () {
      expect(found.single.implementKg, 7.26);
      expect(found.single.weightGuessed, isFalse);
    });
  });

  /// An American sectional: a three-figure event number, a division on the
  /// heading instead of a weight, and feet-and-inches seeds.
  const sectional = '''
Event 501  Girls Shot Put 5A
===============================================================================
    Name                    Year School                  Seed Mark
===============================================================================
Flight  1 of  2  Finals
  1 James, Janiya               12 Demopolis              28-02.50
  2 Hernandez, Sofia            11 Haverhill              27-06.00
Flight  2 of  2  Finals
  1 Diaz, Ana                   12 Central                31-00.25
''';

  group('a sectional with a division on the heading', () {
    final found = parseHeatSheet(sectional);

    test('guesses the weight, and says so', () {
      expect(found.single.implementKg, 4);
      expect(found.single.weightGuessed, isTrue);
    });

    test('still reads the flights and the seeds', () {
      expect(found.single.flightCount, 2);
      expect(found.single.athletes.last.seed, '31-00.25');
      expect(found.single.athletes.last.flight, 2);
    });
  });

  /// A championship field small enough to throw in one order, which a
  /// Hy-Tek sheet still prints a flight line over.
  test('a field of one flight is a field thrown in one order', () {
    const oneFlight = '''
Event 23  Women's Shot Put
===============================================================================
    Name                         School                   Seed Mark
===============================================================================
Flight  1 of  1  Finals
  1 Smith, Jane                  Alabama                  17.55m
  2 Okoye, Ada                   LSU                      16.90m
''';
    final found = parseHeatSheet(oneFlight);
    expect(found.single.flightCount, 1);
    expect(found.single.athletes.every((a) => a.flight == 1), isTrue);
  });

  _pdfRoundTrip();

  test('a program read whole comes out as a competition in flights', () {
    // The end of it: what the sheet said, in the order it throws, as the
    // meet screens will read it.
    final event = parseHeatSheet(hytekProgram).single;
    var order = 0;
    final competition = MeetCompetition(event.event, event.implementKg, [
      for (final athlete in event.athletes)
        MeetEntry(
          id: 'e${order + 1}',
          athlete: athlete.name,
          event: event.event,
          implementKg: event.implementKg,
          tracked: false,
          order: order++,
          flight: athlete.flight,
        ),
    ]);
    expect(competition.flights, [1, 2]);
    expect(competition.isFlighted, isTrue);

    final flight = MeetFlight(competition, rounds: 6);
    expect(flight.flight, 1);
    expect(flight.fieldSize, 3);
    expect(flight.inTheCircle?.athlete, 'John Smith');
    expect(flight.label, 'Flight 1 · round 1');
  });
}

/// The whole way in, on the path the import screen actually uses: a program
/// printed as a PDF, read back with the app's own reader, and parsed.
///
/// Written with [PdfSheet] because that is what a meet program is — fixed
/// width Courier, columns lined up by counting characters — and because it
/// puts a real page break in the middle of a real field, which is the part
/// of a sheet that has always been the hardest to read.
void _pdfRoundTrip() {
  group('a program that arrived as a PDF', () {
    HeatSheetEvent read() {
      final sheet = PdfSheet(footer: '');
      void page(int number) {
        sheet.line('Lincoln High School          '
            "HY-TEK's MEET MANAGER 8.0 - 4:32 PM  Page $number");
        sheet.line('                    Central Invitational - 4/18/2026');
        sheet.line('                            Meet Program');
        sheet.gap();
      }

      page(3);
      sheet.line('Event 15  Boys Shot Put 12lb');
      sheet.rule();
      sheet
          .line('    Name                    Year School            Seed Mark');
      sheet.rule();
      sheet.line('Flight  1 of  2  Finals');
      sheet
          .line('  1 Smith, John                 11 Lincoln          44-06.00');
      sheet
          .line('  2 Okoye, Michael              12 Northside        43-11.50');
      sheet.line('Flight  2 of  2  Finals');
      sheet
          .line('  1 Sandhagen, Jakob            12 Lincoln          48-02.50');

      // The page turns in the middle of flight 2, which is where a long
      // field puts it.
      sheet.pageBreak();
      page(4);
      sheet.line('Event 15  Boys Shot Put 12lb  (continued)');
      sheet.rule();
      sheet
          .line('    Name                    Year School            Seed Mark');
      sheet.rule();
      sheet
          .line('  2 Fischer, Liam               11 Brighton         41-09.25');

      final text = pdfText(sheet.save());
      expect(text, isNotNull, reason: 'the app could not read its own PDF');
      return parseHeatSheet(text!).single;
    }

    test('comes out as one field', () {
      expect(read().athletes.map((a) => a.name), [
        'John Smith',
        'Michael Okoye',
        'Jakob Sandhagen',
        'Liam Fischer',
      ]);
    });

    test('comes out in the flights it was printed in', () {
      final event = read();
      expect(event.flightCount, 2);
      expect(event.athletes.map((a) => a.flight), [1, 1, 2, 2]);
    });

    test('keeps the school and the seed off the row', () {
      final john = read().athletes.first;
      expect(john.team, 'Lincoln');
      expect(john.seed, '44-06.00');
    });

    test('knows what is being thrown', () {
      expect(read().implementKg, 5.44);
      expect(read().weightGuessed, isFalse);
    });
  });
}
