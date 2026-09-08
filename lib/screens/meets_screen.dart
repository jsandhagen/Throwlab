import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/meet_library.dart';
import '../services/video_library.dart';
import '../widgets/angular.dart';
import '../widgets/event_glyph.dart';
import '../widgets/mark_editor.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'meet_screen.dart';
import 'schedule_import_screen.dart';

/// Which way the season is being read: the meets one after another, or the
/// months they fall in.
enum _MeetsView { list, calendar }

/// The competitions, and the way into the one happening now.
///
/// Today's meet opens straight from the trophy rather than making the coach
/// pick it out of a list: between attempts there is time for one tap. The
/// list is what the season looks like from behind; the calendar is what it
/// looks like from in front, which is the half of it a coach plans against.
class MeetsScreen extends StatefulWidget {
  const MeetsScreen({super.key});

  @override
  State<MeetsScreen> createState() => _MeetsScreenState();
}

class _MeetsScreenState extends State<MeetsScreen> {
  /// Which view the coach last left this on. Remembered because it is a
  /// preference about how they think about a season, not about one meet.
  static const _viewKey = 'throwlab.meetsCalendar';

  /// Which headings the coach has folded away. Remembered for the same
  /// reason the view is: a season somebody reads forwards only wants what
  /// has already been thrown when they go looking for it.
  static const _foldedKey = 'throwlab.meetsFolded';

  _MeetsView _view = _MeetsView.list;
  final Set<String> _folded = {};

  @override
  void initState() {
    super.initState();
    _restoreView();
  }

  Future<void> _restoreView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final folded = prefs.getStringList(_foldedKey) ?? const <String>[];
      setState(() {
        if (prefs.getBool(_viewKey) ?? false) _view = _MeetsView.calendar;
        _folded
          ..clear()
          ..addAll(folded);
      });
    } catch (_) {
      // Storage is allowed to fail; the list is a fine place to land, with
      // everything open.
    }
  }

  Future<void> _fold(String heading) async {
    setState(() {
      if (!_folded.remove(heading)) _folded.add(heading);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_foldedKey, _folded.toList());
    } catch (_) {
      // Not worth telling anyone about: the section still folded.
    }
  }

  Future<void> _setView(_MeetsView view) async {
    setState(() => _view = view);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_viewKey, view == _MeetsView.calendar);
    } catch (_) {
      // Not worth telling anyone about: the view still changed.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MeetLibrary, VideoLibrary>(
      builder: (context, meets, library, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Meets'),
            actions: [
              IconButton(
                tooltip: 'Import a schedule',
                icon: const Icon(Icons.upload_file_outlined),
                onPressed: () => _import(context),
              ),
              IconButton(
                tooltip: 'Record a mark',
                icon: const Icon(Icons.straighten),
                onPressed: () async {
                  final mark = await showMarkEditor(context);
                  if (mark != null) await library.addMark(mark);
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                        SectorBackdropPainter(color: theme.colorScheme.primary),
                  ),
                ),
              ),
              // The bar stays up with nothing on the books: a season is
              // planned forwards, and an empty calendar is where the first
              // meet of it gets a date.
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: AngularSegmentedBar<_MeetsView>(
                      value: _view,
                      onChanged: _setView,
                      segments: const [
                        AngularSegment(
                            value: _MeetsView.list,
                            icon: Icons.view_agenda_outlined,
                            label: 'List'),
                        AngularSegment(
                            value: _MeetsView.calendar,
                            icon: Icons.calendar_month_outlined,
                            label: 'Calendar'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _view == _MeetsView.list
                        ? (meets.meets.isEmpty
                            ? _empty(context)
                            : _list(context, meets, library))
                        : _MeetCalendar(
                            meets: meets.meets,
                            onOpen: (meet) => _open(context, meet),
                            onDelete: (meet) =>
                                _confirmDelete(context, meets, meet),
                            onAdd: (day) => _start(context, meets, date: day),
                          ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('New meet'),
            onPressed: () => _start(context, meets),
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, MeetLibrary meets, VideoLibrary library) {
    final season = MeetSeason(meets.meets);
    // The next fixture, which the hero layout puts at full size: today's
    // meet if there is one, otherwise the soonest one coming.
    final next = season.today.isNotEmpty
        ? season.today.first
        : (season.upcoming.isNotEmpty ? season.upcoming.first : null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: [
        // Today first, then what is coming, then the season behind you.
        ..._section(context, meets, library, 'Today', season.today,
            live: true, next: next),
        ..._section(context, meets, library, 'Upcoming', season.upcoming,
            next: next, fold: true),
        ..._section(context, meets, library, 'Past', season.past, fold: true),
      ],
    );
  }

  /// One heading and the meets under it, or nothing at all when there are
  /// none — an empty 'Today' is not news.
  List<Widget> _section(
    BuildContext context,
    MeetLibrary meets,
    VideoLibrary library,
    String heading,
    List<Meet> section, {
    bool live = false,
    Meet? next,
    bool fold = false,
  }) {
    if (section.isEmpty) return const [];
    if (fold && _folded.contains(heading)) {
      return [
        _SectionHeading(heading,
            count: section.length,
            live: live,
            folded: true,
            onFold: () => _fold(heading)),
      ];
    }
    // The next fixture is the one being asked about, so it is the size of
    // the question. Everything else in its section carries on below it.
    final hero = section.contains(next) ? next : null;
    final rest = [
      for (final meet in section)
        if (meet != hero) meet,
    ];
    return [
      _SectionHeading(heading,
          count: section.length,
          live: live,
          onFold: fold ? () => _fold(heading) : null),
      if (hero != null) ...[
        _MeetHero(
          meet: hero,
          library: library,
          onOpen: () => _open(context, hero),
          onDelete: () => _confirmDelete(context, meets, hero),
        ),
        if (rest.isNotEmpty) const SizedBox(height: 10),
      ],
      // One surface with the meets ruled off inside it, rather than a card
      // each floating on the sector: a season is a list of one thing, and
      // cutting it into separate boxes said it wasn't.
      if (rest.isNotEmpty)
        _Grouped([
          for (final meet in rest)
            _MeetRailRow(
              meet: meet,
              library: library,
              onOpen: () => _open(context, meet),
              onDelete: () => _confirmDelete(context, meets, meet),
            ),
        ]),
    ];
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThrowsGlyph(size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text('No meets yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Start one when you get to the track. Enter your throwers, '
              'then film an attempt or write down the mark — whichever you '
              'managed to catch.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _import(context),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import a schedule'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, MeetLibrary meets,
      {DateTime? date}) async {
    final meet = await showNewMeetDialog(context, date: date);
    if (meet == null || !context.mounted) return;
    await meets.save(meet);
    if (context.mounted) _open(context, meet);
  }

  void _import(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScheduleImportScreen()),
      );

  void _open(BuildContext context, Meet meet) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MeetScreen(meetId: meet.id)),
      );

  Future<void> _confirmDelete(
      BuildContext context, MeetLibrary meets, Meet meet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${meet.name.isEmpty ? 'this meet' : meet.name}?'),
        content: const Text(
            'The series goes; the marks and clips it recorded stay in the '
            'library.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await meets.remove(meet.id);
  }
}

/// A season as a month at a time: which days had a competition on them, and
/// what was contested.
///
/// Drawn rather than pulled in, like the rest of the app's chrome — and a
/// throws calendar wants little of what a calendar package brings: no
/// times, no overlaps, one meet a day almost always.
class _MeetCalendar extends StatefulWidget {
  const _MeetCalendar({
    required this.meets,
    required this.onOpen,
    required this.onDelete,
    required this.onAdd,
  });

  final List<Meet> meets;
  final ValueChanged<Meet> onOpen;
  final ValueChanged<Meet> onDelete;

  /// Starts a meet on a day that hasn't got one — the thing a calendar is
  /// for that a list isn't.
  final ValueChanged<DateTime> onAdd;

  @override
  State<_MeetCalendar> createState() => _MeetCalendarState();
}

class _MeetCalendarState extends State<_MeetCalendar> {
  late DateTime _month = _openingMonth();
  DateTime? _selected;

  /// The month worth opening on: this one if anything is on in it, and
  /// otherwise whichever month the latest meet was in. A coach who last
  /// competed in August should not be shown an empty January.
  DateTime _openingMonth() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    for (final meet in widget.meets) {
      if (_sameMonth(meet.date, thisMonth)) return thisMonth;
    }
    if (widget.meets.isEmpty) return thisMonth;
    final latest = widget.meets.first.date;
    return DateTime(latest.year, latest.month);
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Meet> _on(DateTime day) => [
        for (final meet in widget.meets)
          if (_sameDay(meet.date, day)) meet
      ];

  void _step(int months) => setState(() {
        _month = DateTime(_month.year, _month.month + months);
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final showing = selected == null
        ? [
            for (final meet in widget.meets)
              if (_sameMonth(meet.date, _month)) meet,
          ]
        : _on(selected);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
              onPressed: () => _step(-1),
            ),
            Expanded(
              child: Text(
                _monthLabel(_month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
              onPressed: () => _step(1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _grid(context),
        const SizedBox(height: 12),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shortThrowDate(selected),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (showing.isEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Meet here'),
                    onPressed: () => widget.onAdd(selected),
                  ),
              ],
            ),
          ),
        if (showing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              selected == null
                  ? 'Nothing on in ${_monthLabel(_month)}.'
                  : 'Nothing on this day.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final meet in showing)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MeetCard(
                meet: meet,
                onOpen: () => widget.onOpen(meet),
                onDelete: () => widget.onDelete(meet),
              ),
            ),
      ],
    );
  }

  /// The month, as six rows of seven. Leading and trailing days from the
  /// neighbouring months are drawn faintly rather than left blank, so the
  /// grid keeps its shape as the season moves through it.
  Widget _grid(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final first = DateTime(_month.year, _month.month);
    // DateTime.weekday is 1..7 from Monday; the locale's first day is 0..6
    // from Sunday, so both come back to the same 0..6 before subtracting.
    final offset =
        (first.weekday % 7 - localizations.firstDayOfWeekIndex + 7) % 7;
    final start = first.subtract(Duration(days: offset));
    final today = DateTime.now();
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  localizations.narrowWeekdays[
                      (localizations.firstDayOfWeekIndex + i) % 7],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var day = 0; day < 7; day++)
                Expanded(
                  child: _day(
                    context,
                    // Days, not hours: adding 24 h across a daylight-saving
                    // change would land on the same date twice.
                    DateTime(
                        start.year, start.month, start.day + week * 7 + day),
                    today,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _day(BuildContext context, DateTime day, DateTime today) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final here = _on(day);
    final thisMonth = _sameMonth(day, _month);
    final isSelected = _selected != null && _sameDay(day, _selected!);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          _selected = isSelected ? null : day;
          // Tapping into a neighbouring month's day follows it there,
          // rather than selecting a day the grid is about to stop showing.
          if (!thisMonth) _month = DateTime(day.year, day.month);
        }),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected
                ? scheme.primary.withOpacity(0.18)
                : here.isEmpty
                    ? null
                    : scheme.surfaceContainerHighest.withOpacity(0.5),
            border: _sameDay(day, today)
                ? Border.all(color: scheme.primary.withOpacity(0.7))
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: thisMonth
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withOpacity(0.4),
                  fontWeight: here.isEmpty ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              // One mark per event on the day, in the event's own colour —
              // a Saturday with a discus and a javelin on it reads as two
              // competitions rather than as one busy square.
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final event in _events(here))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: eventColor(event),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The events on a day, at most four so a busy day still fits its square.
  List<ThrowEvent> _events(List<Meet> here) {
    final events = <ThrowEvent>{};
    for (final meet in here) {
      for (final entry in meet.entries) {
        events.add(entry.event);
      }
    }
    // A meet with nobody entered yet is still a day with something on it.
    if (events.isEmpty && here.isNotEmpty) return const [];
    return events.take(4).toList();
  }

  String _monthLabel(DateTime month) =>
      '${_months[month.month - 1]} ${month.year}';

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

/// Month names for the date rail, which has room for three letters.
const _monthShort = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// What a meet has to say for itself.
///
/// A fixture and a meet already thrown are two different rows: one is a
/// date and a place, the other is what happened. Both are read off the same
/// meet, so the layouts ask this rather than each working it out again.
class _Facts {
  _Facts(this.meet, VideoLibrary? library)
      : events = {for (final entry in meet.entries) entry.event}.toList(),
        athletes = meet.entries.length {
    var attempts = 0;
    double? best;
    final results = library == null
        ? const <String, ThrowResult>{}
        : {for (final result in library.results) result.id: result};
    for (final entry in meet.entries) {
      for (final attempt in entry.attempts) {
        if (attempt == null) continue;
        attempts++;
        if (attempt.kind != AttemptKind.mark) continue;
        final distance =
            results[attempt.resultId ?? '']?.distance ?? attempt.distance;
        if (distance != null && (best == null || distance > best)) {
          best = distance;
        }
      }
    }
    this.attempts = attempts;
    this.best = best;
  }

  final Meet meet;
  final List<ThrowEvent> events;
  final int athletes;
  late final int attempts;

  /// The furthest thrown at it, by anybody — the one number a season list
  /// can say about a meet that is over.
  late final double? best;

  bool get thrown => attempts > 0;

  /// The line under the name: where and when for a fixture, what happened
  /// for a meet already thrown.
  String get line {
    final away = countdownTo(meet.date);
    return [
      if (meet.venue.isNotEmpty) meet.venue,
      if (away != null) away,
      if (thrown) ...[
        '$athletes athlete${athletes == 1 ? '' : 's'}',
        if (best != null) 'best ${formatDistance(best!)}',
      ] else if (athletes > 0)
        '$athletes entered',
    ].join(' · ');
  }
}

/// A heading over one part of the season.
///
/// Set in capitals and tracked out rather than written as a sentence: it is
/// a label on a group, not a line of the list, and the two read as the same
/// weight when both are sentence case.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
    this.heading, {
    required this.count,
    this.live = false,
    this.folded = false,
    this.onFold,
  });

  final String heading;
  final int count;
  final bool live;
  final bool folded;

  /// Null for a heading that doesn't fold. Today's is one meet and the
  /// reason the screen was opened; there is nothing there to get out of
  /// the way.
  final VoidCallback? onFold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        live ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    final row = Padding(
      padding: EdgeInsets.fromLTRB(6, 18, onFold == null ? 6 : 2, 8),
      child: Row(
        children: [
          if (live) ...[
            Icon(Icons.circle, size: 7, color: color),
            const SizedBox(width: 7),
          ],
          Text(
            heading.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700, letterSpacing: 1.4, color: color),
          ),
          const SizedBox(width: 8),
          // The count stays up when the section is folded away, so what is
          // behind the heading is still known without opening it.
          Text('$count',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: color.withOpacity(0.6))),
          if (onFold != null) ...[
            const Spacer(),
            AnimatedRotation(
              turns: folded ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.expand_more, size: 20, color: color),
            ),
          ],
        ],
      ),
    );
    if (onFold == null) return row;
    return InkWell(
      onTap: onFold,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

/// The meets of one section on a single surface, ruled off from each other.
class _Grouped extends StatelessWidget {
  const _Grouped(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// The date, stacked, at a fixed width so a column of them lines up.
class _DateRail extends StatelessWidget {
  const _DateRail(this.date);

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = date.toLocal();
    final color = theme.colorScheme.onSurface;
    return SizedBox(
      width: 42,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${local.day}',
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, height: 1.1, color: color)),
          Text(
            // The year only when it isn't this one, which is most of a
            // fixture list read in September.
            local.year == DateTime.now().year
                ? _monthShort[local.month - 1]
                : "${_monthShort[local.month - 1]} '${local.year % 100}",
            style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Event glyphs for a meet, at most a handful.
class _EventDots extends StatelessWidget {
  const _EventDots(this.events, {this.size = 16});

  final List<ThrowEvent> events;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final event in events.take(4))
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: EventGlyph(event, size: size, color: eventColor(event)),
            ),
        ],
      );
}

/// One meet as a row with the date down the left edge.
class _MeetRailRow extends StatelessWidget {
  const _MeetRailRow({
    required this.meet,
    required this.library,
    required this.onOpen,
    required this.onDelete,
  });

  final Meet meet;
  final VideoLibrary library;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = _Facts(meet, library);
    return InkWell(
      onTap: onOpen,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            _DateRail(meet.date),
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 30,
              color: theme.colorScheme.outlineVariant.withOpacity(0.35),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(meet.name.isEmpty ? 'Meet' : meet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (facts.line.isNotEmpty)
                    Text(facts.line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            _EventDots(facts.events),
            Icon(Icons.chevron_right,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The next fixture, at the size of the thing you are actually asking
/// about.
class _MeetHero extends StatelessWidget {
  const _MeetHero({
    required this.meet,
    required this.library,
    required this.onOpen,
    required this.onDelete,
  });

  final Meet meet;
  final VideoLibrary library;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = _Facts(meet, library);
    final local = meet.date.toLocal();
    // Counted in days rather than rounded to weeks: this is the meet being
    // planned for, and 'in 23 days' is what a coach is actually counting.
    // Nothing at all on the day itself — the heading above already says
    // TODAY, and saying it twice is not saying it louder.
    final days = daysUntil(meet.date);
    final away = switch (days) {
      <= 0 => null,
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.35), width: 1),
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (away != null) ...[
                Text(away.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: theme.colorScheme.primary)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(meet.name.isEmpty ? 'Meet' : meet.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  _EventDots(facts.events, size: 20),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '${_weekdayShort[local.weekday - 1]} '
                      '${shortThrowDate(meet.date)}',
                  if (meet.venue.isNotEmpty) meet.venue,
                  if (facts.athletes > 0)
                    '${facts.athletes} entered'
                  else
                    'nobody entered yet',
                ].join(' · '),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One meet in a list: when it was, how big it was, and what was thrown at
/// it. Shared by the list and the calendar's day.
class MeetCard extends StatelessWidget {
  const MeetCard(
      {super.key,
      required this.meet,
      required this.onOpen,
      required this.onDelete,
      this.library});

  final Meet meet;

  /// Where the distances are, for a card that says what was thrown at the
  /// meet. Null from the calendar, which only has room for the name.
  final VideoLibrary? library;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = _Facts(meet, library);
    final events = facts.events;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        onTap: onOpen,
        onLongPress: onDelete,
        title: Text(
          meet.name.isEmpty ? 'Meet' : meet.name,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            shortThrowDate(meet.date),
            // A meet with nobody in it yet is one on the calendar, not one
            // that went badly: counting its nothing reads as the latter.
            if (_Facts(meet, library).line case final line when line.isNotEmpty)
              line,
          ].join(' · '),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: EventGlyph(event, size: 18, color: eventColor(event)),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
