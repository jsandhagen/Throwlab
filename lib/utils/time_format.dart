/// Formats a position as `m:ss.mmm` for the scrubber readout.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = position.inSeconds % 60;
  final millis = position.inMilliseconds % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${millis.toString().padLeft(3, '0')}';
}

/// Frame index at [position] for footage recorded at [fps].
int frameAt(Duration position, double fps) =>
    (position.inMicroseconds * fps / Duration.microsecondsPerSecond).round();

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a library date the way the home screen shows it: `Today`,
/// `Yesterday`, `10 Jul` within the current year, and `10 Jul 2024`
/// otherwise. [date] and [now] are compared as local calendar days.
String formatShortDate(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  // Compare as UTC midnights so a daylight-saving shift can't turn
  // yesterday into a 23-hour, zero-day difference.
  final days = DateTime.utc(today.year, today.month, today.day)
      .difference(DateTime.utc(date.year, date.month, date.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  final label = '${date.day} ${_months[date.month - 1]}';
  return date.year == today.year ? label : '$label ${date.year}';
}
