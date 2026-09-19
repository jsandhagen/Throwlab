import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/athlete_record.dart';
import 'package:throwlab/models/meet_board.dart' show boardNameOf;
import 'package:throwlab/services/athlete_library.dart';

/// The editable record alongside a derived profile: a nickname to show, and
/// the full name and school a heat sheet is matched against.
void main() {
  group('a record', () {
    test('shows the nickname when it has one, else the filed name', () {
      const filed = AthleteRecord(name: 'Robert Fischer');
      expect(filed.displayName, 'Robert Fischer');
      expect(filed.copyWith(nickname: 'Bud').displayName, 'Bud');
    });

    test('is empty until the coach fills something in', () {
      expect(const AthleteRecord(name: 'Bud').isEmpty, isTrue);
      expect(const AthleteRecord(name: 'Bud', school: 'Central HS').isEmpty,
          isFalse);
    });

    test('survives a round trip through JSON, dropping blank fields', () {
      const record = AthleteRecord(
          name: 'Bud', nickname: 'Bud', firstName: 'Robert', lastName: 'Fischer');
      final json = record.toJson();
      expect(json.containsKey('school'), isFalse);
      final back = AthleteRecord.fromJson(json);
      expect(back.name, 'Bud');
      expect(back.fullName, 'Robert Fischer');
      expect(back.school, '');
    });
  });

  group('the two halves of a name', () {
    test('join back up the way a program prints them', () {
      const bud = AthleteRecord(
          name: 'Bud', firstName: 'Robert', lastName: 'Fischer');
      expect(bud.fullName, 'Robert Fischer');
      // Nothing filled in is nothing to print, rather than a stray space.
      expect(const AthleteRecord(name: 'Bud').fullName, isEmpty);
      expect(
          const AthleteRecord(name: 'Bud', lastName: 'Fischer').fullName,
          'Fischer');
    });

    test('put the family name on the board, whatever it is made of', () {
      expect(
          const AthleteRecord(
                  name: 'Bud', firstName: 'Robert', lastName: 'Fischer')
              .boardName,
          'Fischer');
      // Three words and one surname. Read off a string this is a 'Berg'.
      expect(
          const AthleteRecord(
                  name: 'Anna', firstName: 'Anna', lastName: 'van der Berg')
              .boardName,
          'van der Berg');
    });

    test('draw the given name where the coach says there is no other', () {
      // The case the guess cannot get right: two given names and no family
      // name at all, which the last word reads as a surname.
      expect(boardNameOf('Anna Sofia'), 'Sofia');
      const record = AthleteRecord(name: 'Anna Sofia', firstName: 'Anna Sofia');
      expect(record.boardName, 'Anna Sofia');
      expect(athleteBoardName('Anna Sofia', record), 'Anna Sofia');
      // And with nothing said, the guess is still the best there is.
      expect(athleteBoardName('Anna Sofia', null), 'Sofia');
      expect(athleteBoardName('Nnamdi Achebe (Croydon)', null),
          'Achebe (Croydon)');
    });

    test('read a name stored before it had two halves', () {
      // One field on disk, split the way everything used to read it, so
      // nothing moves on the day of the upgrade — and the coach is looking
      // at two fields they can put right for whoever it was wrong for.
      final back = AthleteRecord.fromJson(
          {'name': 'Bud', 'fullName': 'Robert Fischer', 'school': 'Central HS'});
      expect(back.firstName, 'Robert');
      expect(back.lastName, 'Fischer');
      expect(back.school, 'Central HS');
      // A single word is a surname, which is what a board wants from it.
      expect(AthleteRecord.fromJson({'name': 'B', 'fullName': 'Fischer'}).lastName,
          'Fischer');
      // And the two fields win over a stale one written beside them.
      final both = AthleteRecord.fromJson({
        'name': 'Anna Sofia',
        'firstName': 'Anna Sofia',
        'fullName': 'Anna Sofia',
      });
      expect(both.lastName, isEmpty);
      expect(both.boardName, 'Anna Sofia');
    });
  });

  group('the library', () {
    late AthleteLibrary athletes;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      athletes = AthleteLibrary();
      await athletes.load();
    });

    test('resolves a display name by the same case rules as everywhere else',
        () async {
      await athletes.save(const AthleteRecord(name: 'Bud', nickname: 'Bud'));
      await athletes
          .save(const AthleteRecord(name: 'Robert Fischer', nickname: 'Bud'));
      // 'sam' and 'Sam' are one person, so the key is normalized.
      expect(athletes.displayName('robert fischer'), 'Bud');
      // No record: the name reads back unchanged.
      expect(athletes.displayName('Ana Diaz'), 'Ana Diaz');
    });

    test('drops a record cleared back to empty', () async {
      await athletes.save(const AthleteRecord(name: 'Bud', school: 'Central'));
      expect(athletes.recordFor('Bud'), isNotNull);
      await athletes.save(const AthleteRecord(name: 'Bud'));
      expect(athletes.recordFor('Bud'), isNull);
    });

    test('reloads what was saved', () async {
      await athletes.save(const AthleteRecord(
          name: 'Bud', firstName: 'Robert', lastName: 'Fischer', school: 'Central HS'));
      final reopened = AthleteLibrary();
      await reopened.load();
      expect(reopened.recordFor('Bud')?.school, 'Central HS');
      expect(reopened.recordFor('Bud')?.fullName, 'Robert Fischer');
    });
  });
}
