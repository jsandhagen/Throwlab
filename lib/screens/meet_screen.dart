import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meet.dart';
import '../models/throw_video.dart';
import '../services/meet_library.dart';
import '../services/results_sheet.dart';
import '../services/video_library.dart';
import '../widgets/conditions_sheet.dart';
import '../widgets/entry_dialog.dart';
import '../widgets/event_glyph.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'heat_sheet_import_screen.dart';
import 'meet_event_screen.dart';

/// One meet: the events being contested at it, and the state each of them
/// is in.
///
/// A meet is a day, not a competition — a coach at a county champs has a
/// discus at eleven and a javelin at two, and the two have separate fields,
/// separate orders and separate cuts. So the meet lists its events, and the
/// throwing happens one event down, on [MeetEventScreen].
/// Writes a meet's results out and hands them to the phone. Injected so a
/// test can drive the button without a file system under it.
typedef ResultsSharer = Future<String?> Function(
    Meet meet, MeetCompetition? only, Iterable<ThrowResult> results);

/// The results sheet as the app writes it, saved and opened.
Future<String?> shareResultsSheet(
        Meet meet, MeetCompetition? only, Iterable<ThrowResult> results) =>
    ResultsSheet.share(meet, results, only: only);

/// Saves the sheet, and says so — the file lands in the app's storage and
/// the phone opens it, which is where printing and sharing live.
Future<void> offerResultsSheet(
  BuildContext context, {
  required Meet meet,
  required Iterable<ThrowResult> results,
  MeetCompetition? only,
  ResultsSharer? sharer,
}) async {
  final saved = await (sharer ?? shareResultsSheet)(meet, only, results);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(saved == null
        ? "Couldn't write the results sheet."
        : 'Results sheet saved.'),
  ));
}

class MeetScreen extends StatelessWidget {
  const MeetScreen({super.key, required this.meetId, this.shareResults});

  final String meetId;

  /// Overrides how the sheet is written; the file system when null.
  final ResultsSharer? shareResults;

  @override
  Widget build(BuildContext context) {
    return Consumer2<MeetLibrary, VideoLibrary>(
      builder: (context, meets, library, _) {
        final meet = meets.byId(meetId);
        if (meet == null) {
          // Deleted from under us — nothing left to show.
          return const Scaffold(body: SizedBox.shrink());
        }
        final theme = Theme.of(context);
        final competitions = MeetCompetition.of(meet);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(meet.name.isEmpty ? 'Meet' : meet.name),
                Text(
                  '${shortThrowDate(meet.date)}'
                  '${meet.venue.isEmpty ? '' : ' · ${meet.venue}'}'
                  ' · ${_summary(meet)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Results sheet',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => offerResultsSheet(context,
                    meet: meet, results: library.results, sharer: shareResults),
              ),
              IconButton(
                tooltip: 'Import a heat sheet',
                icon: const Icon(Icons.upload_file_outlined),
                onPressed: () => _importSheet(context, meet),
              ),
              IconButton(
                tooltip: 'Meet settings',
                icon: const Icon(Icons.more_horiz),
                onPressed: () => _editMeet(context, meets, meet),
              ),
            ],
          ),
          body: Stack(
            children: [
              // The same sector that backs the library: a meet is a room in
              // the app, not a screen from another one.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                        SectorBackdropPainter(color: theme.colorScheme.primary),
                  ),
                ),
              ),
              Column(
                children: [
                  _ConditionsBar(
                    meet: meet,
                    onEdit: () => _editConditions(context, meets, meet),
                  ),
                  Expanded(
                    child: competitions.isEmpty
                        ? _empty(context, meet)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                            children: [
                              for (final competition in competitions)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _EventCard(
                                    meet: meet,
                                    standings: MeetStandings(
                                        competition, library.results,
                                        advancing: meet.advancing,
                                        prelimRounds: meet.prelimRounds),
                                    onOpen: () =>
                                        _openEvent(context, meet, competition),
                                    onRemove: () => _removeEvent(
                                        context, meets, meet, competition),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add athlete'),
            onPressed: () => _addEntry(context, meets, library, meet),
          ),
        );
      },
    );
  }

  String _summary(Meet meet) {
    final entries = meet.entries.length;
    if (entries == 0) return 'nobody entered yet';
    final events = MeetCompetition.of(meet).length;
    return '$events event${events == 1 ? '' : 's'} · '
        '$entries athlete${entries == 1 ? '' : 's'}';
  }

  Widget _empty(BuildContext context, Meet meet) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt,
                  size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Add the throwers you are watching today.\n'
                'The events they are entered in show up here, and the '
                'throwing happens inside one of them.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              // The whole field in one go, which is what the meet handed
              // out a program for.
              TextButton.icon(
                onPressed: () => _importSheet(context, meet),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import a heat sheet'),
              ),
            ],
          ),
        ),
      );

  void _importSheet(BuildContext context, Meet meet) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HeatSheetImportScreen(meetId: meet.id),
        ),
      );

  void _openEvent(
          BuildContext context, Meet meet, MeetCompetition competition) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetEventScreen(
            meetId: meet.id,
            event: competition.event,
            implementKg: competition.implementKg,
          ),
        ),
      );

  Future<void> _addEntry(BuildContext context, MeetLibrary meets,
      VideoLibrary library, Meet meet) async {
    final entry =
        await showMeetEntryDialog(context, known: library.knownAthletes);
    if (entry == null) return;
    // Onto the end of the flight: an athlete added mid-competition is one
    // the coach has just noticed, not one who throws first.
    entry.order = meet.entries.length;
    await meets.addEntry(meet.id, entry: entry);
    // Straight into the event they were entered in — an athlete is added
    // because they are about to throw.
    if (context.mounted) {
      _openEvent(context, meet,
          MeetCompetition(entry.event, entry.implementKg, [entry]));
    }
  }

  /// Takes a whole event out of the meet, once somebody has said so.
  ///
  /// The one thing worth spelling out is what does not go: a meet holds no
  /// results of its own, so the marks and the clips stay in the library
  /// exactly as they do when one athlete is taken out. Nobody loses a
  /// throw by tidying up a program that was read in wrong.
  Future<void> _removeEvent(BuildContext context, MeetLibrary meets, Meet meet,
      MeetCompetition competition) async {
    final field = competition.entries.length;
    final mine = competition.entries.where((entry) => entry.tracked).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${competition.label}?'),
        content: Text(
          'Takes the event and '
          '${field == 1 ? 'the one athlete' : 'all $field athletes'} in it '
          'out of this meet.'
          '${mine == 0 ? '' : ' The marks and clips already recorded stay '
              'in the library.'}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await meets.removeCompetition(meet.id,
        event: competition.event, implementKg: competition.implementKg);
  }

  Future<void> _editConditions(
      BuildContext context, MeetLibrary meets, Meet meet) async {
    final edited = await showConditionsSheet(context,
        conditions: meet.conditions, meetName: meet.name);
    if (edited == null) return;
    meet.conditions = edited;
    await meets.save(meet);
  }

  Future<void> _editMeet(
      BuildContext context, MeetLibrary meets, Meet meet) async {
    final edited = await showDialog<Meet>(
      context: context,
      builder: (context) => _MeetDialog(existing: meet),
    );
    if (edited != null) await meets.save(edited);
  }
}

/// What the day was like, across the top of the meet.
///
/// A prompt rather than a form: most meets are entered with nobody thinking
/// about the weather, and a line that says what it was — or offers to take
/// it down in one tap — is the only thing that gets it recorded at all. A
/// fixture still weeks off has no weather to record, so it says nothing.
class _ConditionsBar extends StatelessWidget {
  const _ConditionsBar({required this.meet, required this.onEdit});

  final Meet meet;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conditions = meet.conditions;
    // Nothing to say about a day that hasn't happened, and nothing worth
    // asking either.
    if (conditions.isEmpty && daysUntil(meet.date) > 0) {
      return const SizedBox.shrink();
    }
    final summary = conditions.summary;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Icon(
              conditions.isEmpty
                  ? Icons.wb_cloudy_outlined
                  : Icons.thermostat_outlined,
              size: 16,
              color:
                  conditions.isEmpty ? scheme.onSurfaceVariant : scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                conditions.isEmpty
                    ? 'What was it like out there?'
                    : [
                        if (summary.isNotEmpty) summary,
                        if (conditions.note.isNotEmpty) conditions.note,
                      ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: conditions.isEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, size: 15, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// One event at the meet: who is in it, how far through it is, and who is
/// leading it — enough for a coach to tell, from the top of the meet, which
/// ring to walk to.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.meet,
    required this.standings,
    required this.onOpen,
    required this.onRemove,
  });

  final Meet meet;
  final MeetStandings standings;
  final VoidCallback onOpen;

  /// Takes the whole event off the meet. Behind a menu rather than on the
  /// card: it is the one thing here that cannot be undone by tapping
  /// again, and the card's own job is to be tapped.
  final VoidCallback onRemove;

  MeetCompetition get competition => standings.competition;

  /// Which round the event is on, in the same words the event's own header
  /// uses — one answer, worked out in one place.
  String get _progress =>
      MeetFlight(competition, rounds: meet.rounds, standings: standings)
          .label
          .toLowerCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = eventColor(competition.event);
    final field = competition.entries.length;
    final mine = competition.entries.where((entry) => entry.tracked).length;
    // How big the field is, and — where it was too big to throw in one
    // order — how many flights it was cut into. That is the number a coach
    // reads this card for: which of them is up says nothing about how long
    // the event has left to run.
    final flights = competition.flights.length;
    final size =
        flights > 1 ? '$field in $flights flights' : '$field in the field';
    final leader = standings.places.isEmpty ? null : standings.places.first;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              EventGlyph(competition.event, size: 26, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      competition.label,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$size'
                      '${mine == field ? '' : ' · $mine of mine'} · '
                      '$_progress',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (leader != null && leader.best != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.emoji_events_outlined,
                              size: 14, color: accent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              leader.entry.athlete.isEmpty
                                  ? 'Unassigned'
                                  : leader.entry.athlete,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatDistance(
                                leader.best!,
                                leader.series.bestRound == null
                                    ? DistanceUnit.meters
                                    : leader.series
                                        .unitAt(leader.series.bestRound!)),
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600, color: accent),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Narrow on purpose: what this card is for is the line under
              // its name — the field, the round, who is leading — and a
              // full-sized tap target here takes enough width off that to
              // wrap it onto a second line.
              SizedBox(
                width: 32,
                child: PopupMenuButton<String>(
                  tooltip: 'Event',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onSelected: (_) => onRemove(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline, size: 18),
                            title: Text('Remove event'))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Names a meet, dates it, and says how many attempts it gives. Used to
/// start one and to fix it afterwards.
class _MeetDialog extends StatefulWidget {
  const _MeetDialog({this.existing, this.date});

  final Meet? existing;

  /// The day a new meet is being started for. Ignored when editing one.
  final DateTime? date;

  @override
  State<_MeetDialog> createState() => _MeetDialogState();
}

class _MeetDialogState extends State<_MeetDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _venue =
      TextEditingController(text: widget.existing?.venue ?? '');
  late DateTime _date = widget.existing?.date ?? widget.date ?? DateTime.now();

  /// A meet with no cut stores an advancing count past any real field, so
  /// it is not one of the choices below — fall back to the usual eight
  /// rather than handing the dropdown a value it has no item for.
  late int _advancing = _finals.contains(widget.existing?.advancing)
      ? widget.existing!.advancing
      : 8;

  /// The format, as (attempts, rounds before the cut). Equal parts mean
  /// the whole field throws the lot.
  late (int, int) _format = (
    widget.existing?.rounds ?? 6,
    widget.existing?.prelimRounds ?? 3,
  );

  bool get _hasFinal => _format.$2 < _format.$1;

  /// The formats a throws competition is actually run in. Both of the
  /// common ones are here in their own right — six throws for everybody,
  /// and three then a final — rather than one being an option hung off the
  /// other, because a coach reads them off a program as two formats.
  /// The cuts a final is drawn at.
  static const _finals = [6, 8, 9, 12];

  static const _known = [
    (6, 3),
    (5, 3),
    (6, 6),
    (5, 5),
    (4, 4),
    (3, 3),
  ];

  /// The choices, plus whatever this meet already is when that is
  /// something else — a stored format has to stay selectable.
  List<(int, int)> get _options =>
      _known.contains(_format) ? _known : [_format, ..._known];

  /// Derived rather than written down, so a label can't end up describing
  /// a format the meet isn't in: '3 + 3', '3 + 1', '4 throws'.
  static String _labelFor((int, int) format) {
    final (rounds, prelim) = format;
    if (prelim >= rounds) return '$rounds throws · everyone';
    return '$prelim + ${rounds - prelim} · cut after $prelim';
  }

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 25),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New meet' : 'Meet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Meet',
                hintText: 'e.g. "County Champs"',
              ),
            ),
            TextField(
              controller: _venue,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Where',
                hintText: 'e.g. "Sportcity"',
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(shortThrowDate(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            DropdownButtonFormField<(int, int)>(
              value: _format,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Format'),
              items: [
                for (final format in _options)
                  DropdownMenuItem(
                      value: format, child: Text(_labelFor(format))),
              ],
              onChanged: (format) =>
                  setState(() => _format = format ?? _format),
            ),
            if (_hasFinal) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _advancing,
                decoration: const InputDecoration(labelText: 'Final'),
                items: [
                  for (final advancing in _finals)
                    DropdownMenuItem(
                        value: advancing,
                        child: Text('Top $advancing advance')),
                ],
                onChanged: (advancing) =>
                    setState(() => _advancing = advancing ?? 8),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final existing = widget.existing;
            if (existing != null) {
              existing.name = _name.text.trim();
              existing.venue = _venue.text.trim();
              existing.date = _date;
              existing.rounds = _format.$1;
              existing.prelimRounds = _format.$2;
              // No cut means nobody is ever out of it.
              existing.advancing = _hasFinal ? _advancing : 99;
              Navigator.pop(context, existing);
              return;
            }
            Navigator.pop(
              context,
              Meet(
                id: MeetLibrary.newMeetId(),
                name: _name.text.trim(),
                date: _date,
                venue: _venue.text.trim(),
                rounds: _format.$1,
                prelimRounds: _format.$2,
                advancing: _hasFinal ? _advancing : 99,
              ),
            );
          },
          child: Text(widget.existing == null ? 'Start' : 'Save'),
        ),
      ],
    );
  }
}

/// Starts a meet from outside this screen — the list uses it too.
///
/// [date] is the day it is being started for, which the calendar knows and
/// today's list doesn't.
Future<Meet?> showNewMeetDialog(BuildContext context, {DateTime? date}) =>
    showDialog<Meet>(
      context: context,
      builder: (context) => _MeetDialog(date: date),
    );
