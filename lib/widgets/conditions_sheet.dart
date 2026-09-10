import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meet_conditions.dart';

/// Writes down what the day was like.
///
/// Chips rather than dropdowns, and a number pad rather than a form: this
/// is filled in standing at a fence between flights, with one hand, and
/// anything that takes two taps to open before it takes one to answer is
/// something a coach will stop bothering with by the third meet of the
/// season. Every field is optional and every chip deselects — half-filled
/// conditions are worth more than none, and a coach who only knows it was
/// into the wind should be able to say just that.
Future<MeetConditions?> showConditionsSheet(
  BuildContext context, {
  required MeetConditions conditions,
  String? meetName,
}) =>
    showModalBottomSheet<MeetConditions>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _ConditionsSheet(conditions: conditions, meetName: meetName),
    );

class _ConditionsSheet extends StatefulWidget {
  const _ConditionsSheet({required this.conditions, this.meetName});

  final MeetConditions conditions;
  final String? meetName;

  @override
  State<_ConditionsSheet> createState() => _ConditionsSheetState();
}

class _ConditionsSheetState extends State<_ConditionsSheet> {
  late MeetSky _sky = widget.conditions.sky;
  late MeetWind _wind = widget.conditions.wind;
  late TemperatureUnit _unit = widget.conditions.temperatureUnit;
  late final TextEditingController _temperature = TextEditingController(
      text: widget.conditions.temperature == null
          ? ''
          : '${widget.conditions.temperature!.round()}');
  late final TextEditingController _note =
      TextEditingController(text: widget.conditions.note);

  @override
  void dispose() {
    _temperature.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
        context,
        MeetConditions(
          sky: _sky,
          temperature: double.tryParse(_temperature.text.trim()),
          temperatureUnit: _unit,
          wind: _wind,
          note: _note.text.trim(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.meetName == null || widget.meetName!.isEmpty
                  ? 'Conditions'
                  : 'Conditions · ${widget.meetName}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            const _Label('Sky'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final sky in MeetSky.values)
                  if (sky != MeetSky.unknown)
                    ChoiceChip(
                      label: Text('${sky.glyph} ${sky.label}'),
                      selected: _sky == sky,
                      // Tapping the chosen one clears it: a coach who
                      // picked wrong should not have to leave it wrong.
                      onSelected: (on) => setState(
                          () => _sky = on ? sky : MeetSky.unknown),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            const _Label('Wind'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final wind in MeetWind.values)
                  if (wind != MeetWind.unknown)
                    ChoiceChip(
                      label: Text(wind.label),
                      selected: _wind == wind,
                      onSelected: (on) => setState(
                          () => _wind = on ? wind : MeetWind.unknown),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _temperature,
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Temperature',
                      hintText: 'e.g. 54',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // A toggle rather than a picker: there are two scales, and
                // a coach uses one of them all season.
                SegmentedButton<TemperatureUnit>(
                  showSelectedIcon: false,
                  segments: [
                    for (final unit in TemperatureUnit.values)
                      ButtonSegment(value: unit, label: Text(unit.symbol)),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (picked) =>
                      setState(() => _unit = picked.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Anything else',
                hintText: 'e.g. "wet ring, gusting down the runway"',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _save,
              child: const Text('Save conditions'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}
