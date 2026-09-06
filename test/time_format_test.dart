import 'package:flutter_test/flutter_test.dart';

import 'package:throwlab/utils/time_format.dart';

void main() {
  group('formatShortDate', () {
    final now = DateTime(2026, 9, 6, 14, 30);

    test('names today and yesterday', () {
      expect(formatShortDate(DateTime(2026, 9, 6, 7), now: now), 'Today');
      expect(
          formatShortDate(DateTime(2026, 9, 5, 23), now: now), 'Yesterday');
    });

    test('drops the year within the current year', () {
      expect(formatShortDate(DateTime(2026, 7, 10), now: now), '10 Jul');
      expect(formatShortDate(DateTime(2026, 1, 1), now: now), '1 Jan');
    });

    test('keeps the year for older throws', () {
      expect(
          formatShortDate(DateTime(2024, 12, 31), now: now), '31 Dec 2024');
    });

    test('future dates still read as a date, not "Yesterday"', () {
      expect(formatShortDate(DateTime(2026, 9, 7), now: now), '7 Sep');
    });
  });

  group('weekdayName', () {
    test('names the day', () {
      expect(weekdayName(DateTime(2026, 9, 6)), 'Sunday');
      expect(weekdayName(DateTime(2026, 9, 7)), 'Monday');
      expect(weekdayName(DateTime(2026, 9, 12)), 'Saturday');
    });
  });

  group('monthAbbreviation', () {
    test('names every month', () {
      expect(monthAbbreviation(DateTime(2026, 1, 5)), 'Jan');
      expect(monthAbbreviation(DateTime(2026, 7, 5)), 'Jul');
      expect(monthAbbreviation(DateTime(2026, 12, 5)), 'Dec');
    });
  });
}
