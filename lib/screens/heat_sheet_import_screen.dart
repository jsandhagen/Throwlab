import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../services/athlete_library.dart';
import '../services/meet_library.dart';
import '../services/video_library.dart';
import '../utils/heat_sheet_parser.dart';
import '../utils/pdf_text.dart';
import '../widgets/event_glyph.dart';
import '../widgets/import_source.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_picker.dart';

/// Reading a heat sheet into a meet: which events to keep, and who in them
/// is one of yours.
///
/// A program lists the whole afternoon and the whole field, and typing
/// that in a name at a time is the reason a coach ends up tracking three
/// athletes instead of the section they are placed against. So the sheet is
/// read whole and the choosing happens here.
///
/// The important column is the one the sheet doesn't have: whether a name
/// is somebody the library already knows. Those come in tracked — their
/// throws reach their record book — and everybody else comes in as the rest
/// of the field, which is what they are.
class HeatSheetImportScreen extends StatefulWidget {
  const HeatSheetImportScreen({super.key, required this.meetId, this.readPdf});

  final String meetId;

  /// Injected by the previews and the tests, which have no file picker.
  final PdfReader? readPdf;

  @override
  State<HeatSheetImportScreen> createState() => _HeatSheetImportScreenState();
}

class _HeatSheetImportScreenState extends State<HeatSheetImportScreen> {
  final TextEditingController _text = TextEditingController();
  final List<_EventRow> _rows = [];

  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _openPdf() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final bytes = await (widget.readPdf ?? _pickPdf)();
      if (!mounted || bytes == null) return;
      final text = pdfText(bytes);
      if (text == null) {
        setState(() => _problem =
            'No text in that PDF — it may be a scan or a photo of one. '
                'Paste the heat sheet in instead.');
        return;
      }
      _text.text = text;
      _read();
    } catch (e) {
      if (mounted) setState(() => _problem = 'Could not open that file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<Uint8List?> _pickPdf() async {
    const pdf = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [pdf]);
    return file == null ? null : await file.readAsBytes();
  }

  void _read() {
    // The coach's athletes, each with whatever full name and school their
    // record holds — so a program that prints someone's full name links
    // them even when the library knows them by a nickname no sheet would use.
    final records = athleteRecordsOf(context, listen: false);
    final known = [
      for (final name in context.read<VideoLibrary>().knownAthletes)
        KnownAthlete(
          name: name,
          fullName: records?.recordFor(name)?.fullName ?? '',
          school: records?.recordFor(name)?.school ?? '',
        ),
    ];
    final found = parseHeatSheet(_text.text);
    final rows = [
      for (final event in found)
        _EventRow(
          event,
          [
            for (final athlete in event.athletes)
              _AthleteRow(
                  athlete, matchAthlete(athlete.name, athlete.team, known)),
          ],
        ),
    ];
    // Start on the events one of your athletes is in — that is what a coach
    // came to the sheet for. Where none of them is anybody's yet, which is
    // every first meet, start on all of them rather than on nothing.
    final mine = rows.where((row) => row.mine > 0).toList();
    for (final row in rows) {
      row.chosen = mine.isEmpty || row.mine > 0;
    }
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _problem = rows.isEmpty
          ? 'No throwing events on that. A heat sheet needs a heading naming '
              'the event — "Event 15 Boys Shot Put" — with the field under it.'
          : null;
    });
  }

  /// Everything ticked, as entries ready to go into the meet.
  List<MeetEntry> _going(Meet meet) {
    // An athlete already down for this event at this weight is not entered
    // twice: a sheet read again after a scratch should not double the field.
    bool already(String name, ThrowEvent event, double kg) =>
        meet.entries.any((entry) =>
            entry.event == event &&
            entry.implementKg == kg &&
            sameAthlete(entry.athlete, name));

    final entries = <MeetEntry>[];
    var order = meet.entries.length;
    for (final row in _rows) {
      if (!row.chosen) continue;
      for (final athlete in row.athletes) {
        if (!athlete.chosen) continue;
        final name = athlete.known ?? athlete.athlete.name;
        if (already(name, row.event.event, row.event.implementKg)) continue;
        entries.add(MeetEntry(
          id: '${MeetLibrary.newEntryId()}_${entries.length}',
          // The library's spelling wins, so a season doesn't split between
          // 'J Sandhagen' and 'Jakob Sandhagen'.
          athlete: name,
          event: row.event.event,
          implementKg: row.event.implementKg,
          // Only your own athletes reach the record book. The rest of the
          // field is here to be placed against, not to be kept.
          tracked: athlete.known != null,
          order: order++,
        ));
      }
    }
    return entries;
  }

  Future<void> _add(MeetLibrary meets, Meet meet) async {
    final entries = _going(meet);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await meets.addEntries(meet.id, entries);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(entries.length == 1
          ? 'Entered 1 athlete'
          : 'Entered ${entries.length} athletes'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meets = context.watch<MeetLibrary>();
    final meet = meets.byId(widget.meetId);
    if (meet == null) return const Scaffold(body: SizedBox.shrink());
    final going = _rows.isEmpty ? const <MeetEntry>[] : _going(meet);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import a heat sheet'),
        actions: [
          if (_rows.isNotEmpty)
            IconButton(
              tooltip: 'Start again',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => setState(_rows.clear),
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
          _rows.isEmpty ? _source() : _review(context),
        ],
      ),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: going.isEmpty ? null : () => _add(meets, meet),
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(going.length == 1
                      ? 'Enter 1 athlete'
                      : 'Enter ${going.length} athletes'),
                ),
              ),
            ),
    );
  }

  Widget _source() => ImportSource(
        controller: _text,
        busy: _busy,
        problem: _problem,
        onRead: _read,
        onOpenPdf: _openPdf,
        blurb: 'Paste the program, or open the PDF the meet sent. The '
            'throwing events are picked out of it — everything else on the '
            'afternoon is left alone.',
        hint: 'Event 15  Boys Shot Put 12lb\n'
            '  1 Smith, John        12 Central HS      44-06.00',
      );

  Widget _review(BuildContext context) {
    final theme = Theme.of(context);
    final mine = _rows.fold<int>(0, (sum, row) => sum + row.mine);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            mine == 0
                ? 'None of these names is in your library yet, so they all '
                    'come in as the rest of the field. Tap an event to see '
                    'who is in it.'
                : '$mine of these names ${mine == 1 ? 'is an athlete' : 'are '
                        'athletes'} you already have. They come in tracked, so '
                    'their throws reach their record book; everybody else is '
                    'the rest of the field. Tap an event to see who is in it.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        for (final row in _rows)
          _EventCard(
            row: row,
            onToggle: (chosen) => setState(() => row.chosen = chosen),
            onWeight: (kg) =>
                setState(() => row.event = row.event.withWeight(kg)),
            onAthlete: (athlete, chosen) =>
                setState(() => athlete.chosen = chosen),
          ),
      ],
    );
  }
}

/// One event off the sheet and whether it is being kept.
class _EventRow {
  _EventRow(this.event, this.athletes);

  HeatSheetEvent event;
  final List<_AthleteRow> athletes;
  bool chosen = true;

  /// How many of the field the library already knows.
  int get mine => athletes.where((a) => a.known != null).length;

  int get taking => athletes.where((a) => a.chosen).length;
}

class _AthleteRow {
  _AthleteRow(this.athlete, this.known);

  final HeatSheetAthlete athlete;

  /// The library's spelling of this person, when it is one of theirs.
  final String? known;
  bool chosen = true;
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.row,
    required this.onToggle,
    required this.onWeight,
    required this.onAthlete,
  });

  final _EventRow row;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onWeight;
  final void Function(_AthleteRow, bool) onAthlete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = row.event;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Checkbox(
          value: row.chosen,
          onChanged: (value) => onToggle(value ?? false),
        ),
        title: Row(
          children: [
            EventGlyph(event.event, size: 18, color: eventColor(event.event)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // The implement's own name for itself, so a 12 lb shot
                // reads as one rather than as 5.44 kg.
                '${event.event.label} · '
                '${event.event.specFor(event.implementKg).weightLabel}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Text(
          [
            '${row.athletes.length} entered',
            if (row.mine > 0) '${row.mine} of mine',
            if (event.weightGuessed) 'weight guessed',
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
              color: event.weightGuessed
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    // The heading as printed, so a weight that had to be
                    // guessed can be checked against what the sheet said.
                    event.title,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<double>(
                  value: event.implementKg,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final spec in event.event.implements)
                      DropdownMenuItem(
                          value: spec.weightKg, child: Text(spec.weightLabel)),
                  ],
                  onChanged: (kg) => kg == null ? null : onWeight(kg),
                ),
              ],
            ),
          ),
          for (final athlete in row.athletes)
            // One of the coach's own is tinted and struck down its leading
            // edge, so a long field can be skimmed for them without reading
            // every name — which is the whole reason a heat sheet is imported.
            //
            // The tint and the edge are the tile's own `tileColor` and
            // `shape` rather than a box wrapped around it: a ListTile paints
            // its background on the nearest Material ancestor, so a
            // decorated box in between would cover both that and the ink
            // splash — which Flutter asserts on.
            CheckboxListTile(
              dense: true,
              tileColor: athlete.known == null
                  ? null
                  : theme.colorScheme.primary.withOpacity(0.12),
              shape: athlete.known == null
                  ? null
                  : Border(
                      left: BorderSide(
                          color: theme.colorScheme.primary, width: 3),
                    ),
              value: athlete.chosen,
              onChanged: (value) => onAthlete(athlete, value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(athlete.known ?? athlete.athlete.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: athlete.known != null
                          ? FontWeight.w600
                          : FontWeight.w400)),
              subtitle: Text(
                [
                  if (athlete.known != null) 'Your athlete',
                  if (athlete.athlete.team.isNotEmpty) athlete.athlete.team,
                  if (athlete.athlete.seed.isNotEmpty)
                    'seed ${athlete.athlete.seed}',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: athlete.known != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant),
              ),
              secondary: athlete.known == null
                  ? null
                  : Tooltip(
                      message: 'One of your athletes',
                      child: Icon(Icons.person,
                          size: 18, color: theme.colorScheme.primary),
                    ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
