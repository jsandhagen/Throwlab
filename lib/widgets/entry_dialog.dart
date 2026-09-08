import 'package:flutter/material.dart';

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../services/meet_library.dart';
import 'athlete_picker.dart';
import 'event_glyph.dart';
import 'throw_picker.dart';

/// Enters an athlete in a meet, in an event, at a weight.
///
/// Lives here rather than on the meet screen because both ways into a meet
/// need it: the meet itself, where the event is still being chosen, and one
/// event's own screen, where it is already known.
Future<MeetEntry?> showMeetEntryDialog(
  BuildContext context, {
  required List<String> known,
  ThrowEvent? event,
  double? implementKg,
}) =>
    showDialog<MeetEntry>(
      context: context,
      builder: (context) =>
          _EntryDialog(known: known, event: event, implementKg: implementKg),
    );

/// The weight is asked for here rather than per attempt because it does not
/// change through a competition — and a best is per weight, so guessing it
/// would put the mark in the wrong book.
class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.known, this.event, this.implementKg});

  final List<String> known;

  /// What the athlete is being entered in, when that is already settled —
  /// added from inside an event, where asking again would only be a way to
  /// enter them in the wrong one.
  final ThrowEvent? event;
  final double? implementKg;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  String _athlete = '';
  late ThrowEvent _event = widget.event ?? ThrowEvent.shotPut;
  late ImplementSpec _implement = widget.implementKg == null
      ? _event.defaultImplement
      : _event.specFor(widget.implementKg!);
  bool _tracked = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add athlete'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A rival is a name off a start list, not somebody the library
            // has met, so typing is the only sensible way in.
            if (_tracked)
              AthletePicker(
                known: widget.known,
                value: _athlete,
                onChanged: (name) => setState(() => _athlete = name),
              )
            else
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Athlete', hintText: 'Name or club'),
                onChanged: (name) => setState(() => _athlete = name),
              ),
            const SizedBox(height: 12),
            if (widget.event != null)
              // Settled already: this is the field of one competition, and
              // a dropdown here would only be a way out of it.
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading:
                    EventGlyph(_event, size: 20, color: eventColor(_event)),
                title: Text('${_event.label} · ${_implement.weightLabel}'),
              )
            else ...[
              DropdownButtonFormField<ThrowEvent>(
                value: _event,
                decoration: const InputDecoration(labelText: 'Event'),
                items: [
                  for (final event in ThrowEvent.values)
                    DropdownMenuItem(value: event, child: Text(event.label)),
                ],
                onChanged: (event) => setState(() {
                  _event = event ?? _event;
                  _implement = _event.defaultImplement;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                value: _implement.weightKg,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Implement'),
                items: [
                  for (final spec in _event.implements)
                    DropdownMenuItem(
                      value: spec.weightKg,
                      child: Text('${spec.weightLabel}  ·  ${spec.usedBy}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (weight) => setState(() =>
                    _implement = _event.specFor(weight ?? _implement.weightKg)),
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              value: _tracked,
              contentPadding: EdgeInsets.zero,
              title: const Text('One of mine'),
              subtitle: Text(
                _tracked
                    ? 'Marks and clips go into the library, and count '
                        'toward their bests.'
                    : 'Tracked for the standings only — nothing is written '
                        'to your library.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onChanged: (value) => setState(() => _tracked = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _athlete.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    MeetEntry(
                      id: MeetLibrary.newEntryId(),
                      athlete: _athlete.trim(),
                      event: _event,
                      implementKg: _implement.weightKg,
                      tracked: _tracked,
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
