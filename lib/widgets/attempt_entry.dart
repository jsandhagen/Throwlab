import 'package:flutter/material.dart';

import '../models/meet.dart';
import '../models/throw_video.dart';
import 'distance_field.dart';

/// What the coach chose to do with one attempt.
enum AttemptAction {
  /// Record the distance typed into the sheet.
  save,
  foul,
  pass,

  /// Take the round back out of the series.
  clear,

  /// Open the camera for this round, then come back for the distance.
  film,
}

class AttemptOutcome {
  const AttemptOutcome(this.action, {this.metres, this.unit});

  final AttemptAction action;

  /// Metres, for [AttemptAction.save].
  final double? metres;
  final DistanceUnit? unit;
}

/// Enters one round of one athlete's series.
///
/// A sheet rather than a dialog, and the distance field is focused as it
/// opens: this is used standing at the sector with a mark just called out
/// over a tannoy, so the keyboard has to be up by the time the coach's
/// thumb gets there. Foul and pass are one tap each and save on the spot —
/// they have no number to type, and asking for one anyway is what makes a
/// coach stop bothering to record them.
Future<AttemptOutcome?> showAttemptSheet(
  BuildContext context, {
  required String athlete,
  required int round,
  required bool filmed,
  AttemptKind? existing,
  double? metres,
  DistanceUnit unit = DistanceUnit.metres,
  bool canFilm = true,
}) =>
    showModalBottomSheet<AttemptOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AttemptSheet(
        athlete: athlete,
        round: round,
        filmed: filmed,
        existing: existing,
        metres: metres,
        unit: unit,
        canFilm: canFilm,
      ),
    );

class _AttemptSheet extends StatefulWidget {
  const _AttemptSheet({
    required this.athlete,
    required this.round,
    required this.filmed,
    required this.existing,
    required this.metres,
    required this.unit,
    required this.canFilm,
  });

  final String athlete;
  final int round;
  final bool filmed;
  final AttemptKind? existing;
  final double? metres;
  final DistanceUnit unit;
  final bool canFilm;

  @override
  State<_AttemptSheet> createState() => _AttemptSheetState();
}

class _AttemptSheetState extends State<_AttemptSheet> {
  late double? _metres = widget.metres;
  late DistanceUnit _unit = widget.unit;

  void _close(AttemptOutcome outcome) => Navigator.pop(context, outcome);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Lifts the sheet clear of the keyboard it opens with.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.athlete} · round ${widget.round + 1}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.filmed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('Filmed',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          DistanceField(
            metres: _metres,
            unit: _unit,
            autofocus: true,
            onChanged: (metres, entered) => setState(() {
              _metres = metres;
              _unit = entered;
            }),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _WideButton(
                  label: 'Foul',
                  icon: Icons.close_rounded,
                  selected: widget.existing == AttemptKind.foul,
                  onPressed: () =>
                      _close(const AttemptOutcome(AttemptAction.foul)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WideButton(
                  label: 'Pass',
                  icon: Icons.arrow_right_alt,
                  selected: widget.existing == AttemptKind.pass,
                  onPressed: () =>
                      _close(const AttemptOutcome(AttemptAction.pass)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Full width, because this is the one the thumb goes for with a
          // competition carrying on in front of the coach.
          FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: (_metres ?? 0) > 0
                ? () => _close(AttemptOutcome(AttemptAction.save,
                    metres: _metres, unit: _unit))
                : null,
            child: const Text('Save mark'),
          ),
          // Wrapped rather than a Row: three buttons across don't fit a
          // phone, and one of them running off the edge is one a coach
          // can't reach.
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              // Filming is offered here as well as on the athlete's card,
              // because the coach often opens the round while the athlete
              // is still walking into the circle.
              if (widget.canFilm && !widget.filmed)
                TextButton.icon(
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Film it'),
                  onPressed: () =>
                      _close(const AttemptOutcome(AttemptAction.film)),
                ),
              if (widget.existing != null)
                TextButton.icon(
                  icon: const Icon(Icons.backspace_outlined),
                  label: const Text('Clear'),
                  onPressed: () =>
                      _close(const AttemptOutcome(AttemptAction.clear)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A target big enough to hit without looking away from the circle.
class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        foregroundColor: selected ? scheme.primary : scheme.onSurface,
        side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant),
      ),
    );
  }
}
