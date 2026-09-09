import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/athlete_record.dart';
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
          name: 'Bud', nickname: 'Bud', fullName: 'Robert Fischer');
      final json = record.toJson();
      expect(json.containsKey('school'), isFalse);
      final back = AthleteRecord.fromJson(json);
      expect(back.name, 'Bud');
      expect(back.fullName, 'Robert Fischer');
      expect(back.school, '');
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
          name: 'Bud', fullName: 'Robert Fischer', school: 'Central HS'));
      final reopened = AthleteLibrary();
      await reopened.load();
      expect(reopened.recordFor('Bud')?.school, 'Central HS');
      expect(reopened.recordFor('Bud')?.fullName, 'Robert Fischer');
    });
  });
}
