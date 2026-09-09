import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/utils/heat_sheet_parser.dart';

/// A meet program as a meet manager prints one: a title, rules, column
/// headers, flights, and the events of a whole afternoon — most of which is
/// not throwing.
const _program = '''
                    Central Invitational - 4/12/2027
                          Meet Program

Event 15  Boys Shot Put 12lb
=======================================================================
    Name                    Year School                  Seed Mark
=======================================================================
Flight  1 of  2
  1 Smith, John                 12 Central HS            44-06.00
  2 Jones, Mike                 11 Northside             42-11.00
Flight  2 of  2
  1 SANDHAGEN, JAKOB            12 Central HS            48-02.50

Event 16  Girls Discus
=======================================================================
  1 Diaz, Ana                   11 Central HS            41.20m
  2 Okoye, M                    12 Barnet                39.80m

Event 17  Boys 4x100 Meter Relay
=======================================================================
  1 Central HS                                              43.55
  2 Northside                                               44.10
''';

void main() {
  group('a meet program', () {
    final found = parseHeatSheet(_program);

    test('reads only the throwing off it', () {
      expect(
          found.map((e) => e.event), [ThrowEvent.shotPut, ThrowEvent.discus]);
    });

    test('leaves the relay field where it found it', () {
      // The 4x100 closes the discus rather than joining it.
      expect(found.last.athletes.length, 2);
      expect(found.expand((e) => e.athletes).map((a) => a.name),
          isNot(contains('Central HS')));
    });

    test('says a name the way a person would', () {
      expect(found.first.athletes.map((a) => a.name),
          ['John Smith', 'Mike Jones', 'Jakob Sandhagen']);
    });

    test('keeps the school and the seed off the same row', () {
      final john = found.first.athletes.first;
      expect(john.team, 'Central HS');
      expect(john.seed, '44-06.00');
    });

    test('skips the rules, the flights and the column headers', () {
      final names = found.expand((e) => e.athletes).map((a) => a.name);
      expect(names.any((n) => n.toLowerCase().contains('flight')), isFalse);
      expect(names, isNot(contains('Name')));
      expect(names.length, 5);
    });
  });

  group('what is being thrown', () {
    HeatSheetEvent one(String heading) =>
        parseHeatSheet('$heading\n 1 Diaz, Ana  Central  40.00m').single;

    test('comes off the heading in pounds', () {
      // A 12 lb shot is its own implement, not a rounded 5 kg: it is what
      // a U.S. high school boy throws all season, and a best is per weight.
      final shot = one('Event 15 Boys Shot Put 12lb');
      expect(shot.implementKg, 5.44);
      expect(shot.weightGuessed, isFalse);
    });

    test('comes off the heading in kilos, however it is written', () {
      expect(one("Event 3 Men's Hammer 6K").implementKg, 6);
      // The U.S. high school discus, which sheets write as a 1.6K.
      expect(one('Event 12 Boys Discus 1.6K').implementKg, 1.6);
      expect(one('Event 4 Senior Discus (1.75kg)').implementKg, 1.75);
      expect(one("Event 9 Women's Javelin 600g").implementKg, 0.6);
    });

    test('is guessed from the division when the sheet never says', () {
      final girls = one('Event 16 Girls Discus');
      expect(girls.implementKg, 1);
      expect(girls.weightGuessed, isTrue);

      // Boys is a high-school division, so an unweighted heading is read as
      // the U.S. school implements — the 1.6 kg discus and the 12 lb shot —
      // rather than the senior men's.
      final boysDiscus = one('Event 17 Boys Discus');
      expect(boysDiscus.implementKg, 1.6);
      expect(boysDiscus.weightGuessed, isTrue);

      final boysShot = one('Event 18 Boys Shot Put');
      expect(boysShot.implementKg, 5.44);

      // A senior heading still gets the senior weight.
      expect(one('Event 19 Mens Shot Put').implementKg, 7.26);
      expect(one('Event 20 Mens Discus').implementKg, 2);
    });

    test('reads a shot put as a shot put, not as a shot', () {
      expect(one('Event 1 Shot Put').event, ThrowEvent.shotPut);
    });

    test('leaves a weight throw alone — it is not one of the four', () {
      expect(
          parseHeatSheet('Event 8 Mens Weight Throw 35lb\n'
              ' 1 Smith, John  Central  55-00.00'),
          isEmpty);
    });
  });

  group('a competitor is not a heading', () {
    test('however metric their seed mark reads', () {
      // '41.20m' on the end of a row is a throw, not the 20 meters — and
      // reading it as another event closed the discus over it.
      final found = parseHeatSheet('Event 16 Girls Discus\n'
              '  1 Diaz, Ana                   11 Central HS      41.20m')
          .single;
      expect(found.athletes.single.name, 'Ana Diaz');
      expect(found.athletes.single.seed, '41.20m');
    });

    test('however their school is spelled', () {
      final found = parseHeatSheet('Event 16 Girls Discus\n'
              '  1 Diaz, Ana                   11 Discus Throwers Club')
          .single;
      expect(found.athletes.single.name, 'Ana Diaz');
    });
  });

  group('matching the library', () {
    test('takes a name spelled the same', () {
      expect(sameAthlete('Ana Diaz', 'Ana Diaz'), isTrue);
      expect(sameAthlete('ana diaz', 'Ana Diaz'), isTrue);
    });

    test('takes a first initial, which is how sheets print one', () {
      expect(sameAthlete('J Sandhagen', 'Jakob Sandhagen'), isTrue);
      expect(sameAthlete('Jakob Sandhagen', 'J. Sandhagen'), isTrue);
    });

    test('will not merge two people who share an initial', () {
      expect(sameAthlete('John Smith', 'Jane Smith'), isFalse);
      expect(sameAthlete('Ana Diaz', 'Ana Okoye'), isFalse);
    });

    test("files a match under the library's spelling", () {
      expect(matchKnown('J Sandhagen', ['Ana Diaz', 'Jakob Sandhagen']),
          'Jakob Sandhagen');
      expect(matchKnown('M Okoye', ['Ana Diaz']), isNull);
    });
  });

  group('matching on a record', () {
    // The coach knows this athlete by a nickname no program would print, but
    // has filled in the full name and school off one.
    const bud = KnownAthlete(
        name: 'Bud', fullName: 'Robert Fischer', school: 'Central HS');

    // The names come in as the parser hands them over — first name first,
    // however the sheet wrote them round.
    test('finds a full name the library spelling could never reach', () {
      expect(matchAthlete('Robert Fischer', 'Central HS', [bud]), 'Bud');
      expect(matchAthlete('R Fischer', 'Central', [bud]), 'Bud');
    });

    test('takes a same-surname athlete at the same school', () {
      // The sheet prints 'Bobby', which is neither the nickname nor the full
      // first name — the school is what makes the surname match safe.
      expect(matchAthlete('Bobby Fischer', 'Central High School', [bud]),
          'Bud');
    });

    test('will not link a shared surname at a different school', () {
      expect(matchAthlete('Bobby Fischer', 'Northside', [bud]), isNull);
    });

    test('still takes a plain name match with no record filled in', () {
      const plain = KnownAthlete(name: 'Ana Diaz');
      expect(matchAthlete('Ana Diaz', 'Barnet', [plain]), 'Ana Diaz');
      expect(matchAthlete('M Okoye', 'Barnet', [plain]), isNull);
    });
  });

  group('reading a school two ways', () {
    test('sees past the kind-of-school words', () {
      expect(sameSchool('Central HS', 'Central High School'), isTrue);
      expect(sameSchool('Central', 'Central HS'), isTrue);
      expect(sameSchool('St. Mary Academy', 'St Mary'), isTrue);
    });

    test('keeps two different schools apart', () {
      expect(sameSchool('Central HS', 'Northside HS'), isFalse);
      // Two bare kind-words are not a school in common.
      expect(sameSchool('High School', 'Track Club'), isFalse);
    });
  });

  group('a page turning under a field', () {
    // What a meet program prints across a page break: the meet's masthead
    // again, in the middle of a flight, with the rest of the field under
    // it.
    final found = parseHeatSheet('''
Event 36 Men Shot Put
Flight   1 of  1   Finals
  1  Koch, Josh  Concordia
  2  Jensen, Connor  Concordia
Washington Track Events LLC  Hy-Tek's MEET MANAGER  7:05 PM  Page 9
Portland Twilight
Portland, OR
Meet Program
  3  Mitchell, Cody  Linfield
''').single;

    test('is not three more competitors', () {
      expect(found.athletes.map((a) => a.name),
          ['Josh Koch', 'Connor Jensen', 'Cody Mitchell']);
    });
  });

  group('what it will not read', () {
    test('a page with no events on it', () {
      expect(parseHeatSheet('Squad list\nBring your own implements'), isEmpty);
    });

    test('an event with nobody under it', () {
      expect(parseHeatSheet('Event 15 Boys Shot Put\n=====\n'), isEmpty);
    });
  });
}
