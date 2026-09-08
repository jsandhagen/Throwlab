import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meet.dart';
import '../services/meet_library.dart';
import '../utils/pdf_text.dart';
import '../utils/schedule_parser.dart';
import '../widgets/import_source.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_card.dart';

/// Reading a season off a schedule and putting it on the calendar.
///
/// The parser is allowed to be wrong — a fixture list is a page written for
/// a person to read — so nothing it finds goes anywhere until a coach has
/// looked down the list and said so. Every row can be edited or dropped
/// here, and a row the parser had to guess at says what it guessed.
class ScheduleImportScreen extends StatefulWidget {
  const ScheduleImportScreen({super.key, this.readPdf});

  /// Hands back the bytes of a PDF, or null if nobody picked one. Injected
  /// by the previews and the tests, which have no file picker to open.
  final Future<Uint8List?> Function()? readPdf;

  @override
  State<ScheduleImportScreen> createState() => _ScheduleImportScreenState();
}

class _ScheduleImportScreenState extends State<ScheduleImportScreen> {
  final TextEditingController _text = TextEditingController();
  final List<_Row> _rows = [];

  /// What went wrong with the last thing they handed over, in the words a
  /// coach can act on: paste it instead, or type it in.
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
                'Paste the schedule in instead.');
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
    final found = parseSchedule(_text.text);
    setState(() {
      _rows
        ..clear()
        ..addAll(found.map(_Row.new));
      _problem = found.isEmpty
          ? 'Nothing on that looked like a meet. A row needs a date on it — '
              '"12 April — Spring Open" or "4/12 Spring Open".'
          : null;
    });
  }

  Future<void> _edit(_Row row) async {
    final edited = await showDialog<ScheduleCandidate>(
      context: context,
      builder: (context) => _RowDialog(row.candidate),
    );
    if (edited != null) setState(() => row.candidate = edited);
  }

  /// The rows that are actually going in: ticked, and not already on the
  /// calendar. One list, so the count on the button and what the button
  /// does can't drift apart.
  List<ScheduleCandidate> _going(MeetLibrary meets) => [
        for (final row in _rows)
          if (row.chosen && !_already(meets, row.candidate)) row.candidate,
      ];

  Future<void> _add(MeetLibrary meets) async {
    final chosen = _going(meets);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    for (final candidate in chosen) {
      await meets.save(Meet(
        id: MeetLibrary.newMeetId(),
        name: candidate.name,
        date: candidate.date,
        venue: candidate.venue,
        // The format a schedule never states, defaulted the way the New
        // meet dialog defaults it. It is one dropdown on the meet itself.
        rounds: 6,
        prelimRounds: 3,
      ));
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(chosen.length == 1
          ? 'Added ${chosen.first.name}'
          : 'Added ${chosen.length} meets'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meets = context.watch<MeetLibrary>();
    final chosen = _going(meets).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import a schedule'),
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
          _rows.isEmpty ? _source(context) : _review(context, meets),
        ],
      ),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: chosen == 0 ? null : () => _add(meets),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(chosen == 1 ? 'Add 1 meet' : 'Add $chosen meets'),
                ),
              ),
            ),
    );
  }

  /// Where a schedule comes in: pasted, or out of a PDF.
  Widget _source(BuildContext context) => ImportSource(
        controller: _text,
        busy: _busy,
        problem: _problem,
        onRead: _read,
        onOpenPdf: _openPdf,
        blurb: 'Paste a fixture list — an email, a page off the league '
            'site, a PDF the association put out. Anything with a date at '
            'the start of the row.',
        hint: '3/13   Tiger Relays          Auburn, AL\n'
            '3/27   Spring Invitational   Home',
      );

  /// What it made of the page, a row at a time.
  Widget _review(BuildContext context, MeetLibrary meets) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            'Check the dates before you add them — a schedule is written for '
            'a person to read. Tap a meet to change it.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        for (final row in _rows)
          _CandidateCard(
            row: row,
            already: _already(meets, row.candidate),
            onToggle: (chosen) => setState(() => row.chosen = chosen),
            onEdit: () => _edit(row),
          ),
      ],
    );
  }

  /// Whether the calendar already has this one — a schedule read twice, or
  /// a meet the coach entered by hand before the fixture list turned up.
  bool _already(MeetLibrary meets, ScheduleCandidate candidate) =>
      meets.meets.any((meet) =>
          meet.name.toLowerCase().trim() ==
              candidate.name.toLowerCase().trim() &&
          meet.date.year == candidate.date.year &&
          meet.date.month == candidate.date.month &&
          meet.date.day == candidate.date.day);
}

/// One found meet and whether it is going in. Mutable, because the point of
/// the screen is changing both.
class _Row {
  _Row(this.candidate);

  ScheduleCandidate candidate;
  bool chosen = true;
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.row,
    required this.already,
    required this.onToggle,
    required this.onEdit,
  });

  final _Row row;

  /// Already on the calendar. Shown, and left off by default, rather than
  /// hidden — a coach re-importing a schedule wants to see it was read.
  final bool already;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidate = row.candidate;
    final notes = [
      if (already) 'Already on the calendar',
      ...candidate.notes,
    ];
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: Column(
        children: [
          CheckboxListTile(
            value: row.chosen && !already,
            onChanged: already ? null : (value) => onToggle(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(candidate.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                shortThrowDate(candidate.date),
                if (candidate.venue.isNotEmpty) candidate.venue,
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            secondary: IconButton(
              tooltip: 'Change',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          ),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(note,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.tertiary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Correcting one row before it becomes a meet.
class _RowDialog extends StatefulWidget {
  const _RowDialog(this.candidate);

  final ScheduleCandidate candidate;

  @override
  State<_RowDialog> createState() => _RowDialogState();
}

class _RowDialogState extends State<_RowDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.candidate.name);
  late final TextEditingController _venue =
      TextEditingController(text: widget.candidate.venue);
  late DateTime _date = widget.candidate.date;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 5),
      lastDate: DateTime(_date.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Meet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Meet'),
            ),
            TextField(
              controller: _venue,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Where'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(shortThrowDate(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            // The line it was read off, so a correction can be checked
            // against what the schedule actually said.
            const SizedBox(height: 8),
            Text('On the schedule',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(
              widget.candidate.source,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            widget.candidate.copyWith(
              name: _name.text.trim(),
              venue: _venue.text.trim(),
              date: _date,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
