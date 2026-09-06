import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/throw_event.dart';
import '../models/throw_mark.dart';
import '../models/throw_video.dart';
import '../services/video_library.dart';
import 'athlete_picker.dart';
import 'distance_field.dart';
import 'throw_card.dart';

/// Records a throw that was never filmed, or edits one already recorded.
///
/// Returns the mark to save, or null if it was cancelled. The caller saves
/// it, so the same sheet serves "add" from an athlete's profile — where the
/// name is already known — and "add" from the library, where it isn't.
Future<ThrowMark?> showMarkEditor(
  BuildContext context, {
  String? athlete,
  ThrowMark? existing,
}) =>
    showDialog<ThrowMark>(
      context: context,
      builder: (context) => _MarkDialog(athlete: athlete, existing: existing),
    );

class _MarkDialog extends StatefulWidget {
  const _MarkDialog({this.athlete, this.existing});

  /// Fixed when the mark is being added from inside someone's profile;
  /// null when the sheet has to ask who threw it.
  final String? athlete;
  final ThrowMark? existing;

  @override
  State<_MarkDialog> createState() => _MarkDialogState();
}

class _MarkDialogState extends State<_MarkDialog> {
  late String _athlete =
      widget.existing?.athlete ?? widget.athlete ?? '';
  late ThrowEvent _event = widget.existing?.event ?? ThrowEvent.shotPut;
  late ImplementSpec _implement = widget.existing == null
      ? _event.defaultImplement
      : _event.specFor(widget.existing!.implementKg);
  late double? _distance = widget.existing?.distance;
  late DistanceUnit _unit =
      widget.existing?.distanceUnit ?? DistanceUnit.metres;
  late DateTime _achievedOn = widget.existing?.achievedOn ?? DateTime.now();
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');

  /// A mark is its distance; without one there is nothing to record.
  bool get _canSave => (_distance ?? 0) > 0 && _athlete.trim().isNotEmpty;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _achievedOn,
      // A season either side: these are typed in from a results sheet, not
      // scrolled to from scratch.
      firstDate: DateTime(now.year - 25),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _achievedOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.athlete != null && widget.existing == null;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Record a mark' : 'Edit mark'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!fixed) ...[
              AthletePicker(
                known: context.read<VideoLibrary>().knownAthletes,
                value: _athlete,
                onChanged: (name) => setState(() => _athlete = name),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<ThrowEvent>(
              value: _event,
              decoration: const InputDecoration(labelText: 'Event'),
              items: [
                for (final event in ThrowEvent.values)
                  DropdownMenuItem(value: event, child: Text(event.label)),
              ],
              onChanged: (event) => setState(() {
                _event = event ?? _event;
                // Weights don't carry across events: 4 kg is a shot or a
                // hammer, never a discus.
                _implement = _event.defaultImplement;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              value: _implement.weightKg,
              // Without this the '7.26 kg · Men, M35–M49' row is laid out
              // at its natural width and runs off a narrow phone.
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
            const SizedBox(height: 12),
            DistanceField(
              metres: _distance,
              unit: _unit,
              onChanged: (metres, entered) => setState(() {
                _distance = metres;
                _unit = entered;
              }),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(shortThrowDate(_achievedOn)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Meet or note',
                hintText: 'e.g. "County Champs, final"',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: _canSave
              ? () => Navigator.pop(
                    context,
                    ThrowMark(
                      // Editing keeps the id, so the mark is updated rather
                      // than duplicated.
                      id: widget.existing?.id ?? VideoLibrary.newMarkId(),
                      athlete: _athlete.trim(),
                      event: _event,
                      implementKg: _implement.weightKg,
                      distance: _distance!,
                      distanceUnit: _unit,
                      achievedOn: _achievedOn,
                      note: _note.text.trim(),
                    ),
                  )
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
