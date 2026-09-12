import 'dart:io';

import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../services/athlete_library.dart';
import '../services/video_library.dart';
import 'angular.dart';
import 'event_glyph.dart';
import 'gold.dart';
import 'throw_card.dart';

/// The color each event is tagged with across the app.
Color eventColor(ThrowEvent event) => switch (event) {
      ThrowEvent.shotPut => Colors.orangeAccent,
      ThrowEvent.discus => Colors.greenAccent,
      ThrowEvent.hammer => Colors.purpleAccent,
      ThrowEvent.javelin => Colors.lightBlueAccent,
    };

/// A throw's still frame, falling back to the implement glyph for clips
/// imported before thumbnails existed (or whose still went missing).
class ThrowThumbnail extends StatelessWidget {
  const ThrowThumbnail(this.video,
      {super.key, this.width = 72, this.height = 48});

  final ThrowVideo video;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = eventColor(video.event);
    final path = video.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(path),
            width: width, height: height, fit: BoxFit.cover),
      );
    }
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: EventGlyph(video.event, color: color),
    );
  }
}

/// One line about a throw: when it was recorded, how far it went, and the
/// note if any.
///
/// The date is written the way a card writes one, with the clock kept on
/// it: a session is a dozen throws on one afternoon, and the minute is the
/// only thing that tells two of them apart.
String throwSubtitle(ThrowVideo video) {
  final distance = video.distance;
  final when = video.displayDate.toLocal();
  final clock = '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
  return [
    '${shortThrowDate(video.displayDate)}, $clock',
    if (distance != null) formatDistance(distance, video.distanceUnit),
    if (video.note.isNotEmpty) video.note,
  ].join(' · ');
}

/// Who threw it and what they threw. [context] resolves the athlete through
/// the records when it is given, so a throw filed under a spelling nobody
/// uses still reads as the name every other screen shows.
String throwTitle(ThrowVideo video, {BuildContext? context}) {
  final athlete = context == null
      ? video.athlete
      : displayNameOf(context, video.athlete, listen: false);
  return '${athlete.isEmpty ? '' : '$athlete · '}'
      '${video.event.label} · ${video.implementSpec.weightLabel}';
}

/// Picks the two throws a comparison opens with — A, then B, in the order
/// the comparison screen lays them out (A on the left in landscape, on top
/// in portrait).
///
/// One sheet for both ways in. Opened from a throw ([against]), that throw
/// is fixed as A and a tap on a candidate opens the pair: the clip being
/// watched is what the question is about, so a confirm step would be a tap
/// spent on something already on screen. Opened from the library both
/// halves are still to be chosen, so the picks land in slots that say what
/// is chosen and what is still missing before anything opens.
Future<(ThrowVideo, ThrowVideo)?> pickThrowsToCompare(
  BuildContext context, {
  required VideoLibrary library,
  ThrowVideo? against,
}) {
  final videos = library.videos;
  return showModalBottomSheet<(ThrowVideo, ThrowVideo)>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ComparePickerSheet(
      candidates: [
        for (final video in videos)
          if (video.id != against?.id) video,
      ],
      bests: {
        for (final video in videos)
          if (library.isPersonalBest(video)) video.id,
      },
      anchor: against,
    ),
  );
}

class _ComparePickerSheet extends StatefulWidget {
  const _ComparePickerSheet({
    required this.candidates,
    required this.bests,
    this.anchor,
  });

  /// Everything that can be picked: the library, less the throw the
  /// comparison is already fixed on.
  final List<ThrowVideo> candidates;

  /// The clips standing as a personal best, badged in the list — "compare
  /// this with her best" is the comparison a coach asks for most, and
  /// hunting for which row that is defeats the sheet.
  final Set<String> bests;

  /// The throw already fixed as A, when the sheet was opened from one.
  final ThrowVideo? anchor;

  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Narrowing to the reference throw's own event and athlete.
  ///
  /// Chips rather than a rule the sheet enforces. The library's dialog used
  /// to lock the event outright and the throw's sheet let you off it, which
  /// is the same question answered two ways; a chip is the answer a coach
  /// can argue with, and a filter that shows itself is one they can get
  /// back out of.
  bool _sameEvent = false;
  bool _sameAthlete = false;

  /// Set once either chip has been touched, after which the sheet leaves
  /// them alone: somebody who turned the event filter off does not want the
  /// next pick turning it back on.
  bool _filtersTouched = false;

  /// What is in the slots, A first. Empty when the sheet is anchored — the
  /// anchor is A there, and a tap on a candidate is the whole interaction.
  final List<ThrowVideo> _picks = [];

  @override
  void initState() {
    super.initState();
    _openOnReferenceEvent();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The throw the chips narrow against: the anchor, else whatever is in
  /// slot A.
  ThrowVideo? get _reference =>
      widget.anchor ?? (_picks.isEmpty ? null : _picks.first);

  ThrowVideo? get _slotA => widget.anchor ?? _picks.elementAtOrNull(0);
  ThrowVideo? get _slotB =>
      widget.anchor == null ? _picks.elementAtOrNull(1) : null;

  /// Opens narrowed to the reference's event — comparing a javelin release
  /// with a shot put says nothing — but never onto an empty list: with no
  /// second throw of that event the filter would hide everything behind a
  /// chip nobody knows to turn off.
  void _openOnReferenceEvent() {
    final reference = _reference;
    _sameEvent = reference != null &&
        widget.candidates.any((video) =>
            video.id != reference.id && video.event == reference.event);
  }

  void _pick(ThrowVideo video) {
    final anchor = widget.anchor;
    if (anchor != null) {
      Navigator.pop(context, (anchor, video));
      return;
    }
    setState(() {
      if (_picks.contains(video)) {
        _picks.remove(video);
      } else if (_picks.length < 2) {
        _picks.add(video);
      } else {
        // Both slots are full, so the tap means "not that one, this one".
        // The checkbox list this replaced swallowed it instead, which left
        // a coach tapping a row that never took and no hint as to why.
        _picks[1] = video;
      }
      if (!_filtersTouched) _openOnReferenceEvent();
    });
  }

  void _clear(int slot) => setState(() {
        _picks.removeAt(slot);
        if (!_filtersTouched) _openOnReferenceEvent();
      });

  /// A and B trade places. Which is which is not cosmetic — A is the pane
  /// the linked scrub is driven from, and the one on the left.
  void _swap() => setState(() => _picks.insert(0, _picks.removeAt(1)));

  void _setFilter(void Function() change) => setState(() {
        _filtersTouched = true;
        change();
      });

  /// What the search box is matched against: who threw it, what they threw,
  /// how far, and the note. The mark is in there because a coach looking
  /// for one throw out of a season often remembers the number.
  bool _matches(ThrowVideo video, String query) {
    final distance = video.distance;
    final haystack = [
      video.athlete,
      displayNameOf(context, video.athlete, listen: false),
      video.event.label,
      video.implementSpec.weightLabel,
      if (distance != null) formatDistance(distance, video.distanceUnit),
      video.note,
    ].join(' ');
    return haystack.toLowerCase().contains(query);
  }

  List<ThrowVideo> get _shown {
    final reference = _reference;
    final query = _query.trim().toLowerCase();
    return [
      for (final video in widget.candidates)
        if ((reference == null || !_sameEvent || video.event == reference.event) &&
            (reference == null ||
                !_sameAthlete ||
                video.athlete == reference.athlete) &&
            (query.isEmpty || _matches(video, query)))
          video,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anchor = widget.anchor;
    final shown = _shown;
    return Padding(
      // The search box is no use under the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(anchor == null ? 'Pick two throws' : 'Compare with',
                        style: theme.textTheme.titleMedium),
                  ),
                  if (anchor == null)
                    IconButton(
                      tooltip: 'Swap A and B',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: _picks.length == 2 ? _swap : null,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _SlotRow(
                    letter: 'A',
                    video: _slotA,
                    hint: 'Tap a throw below',
                    // The anchor is what the sheet was opened from: there is
                    // nothing to clear it to.
                    onClear: anchor == null && _picks.isNotEmpty
                        ? () => _clear(0)
                        : null,
                  ),
                  if (anchor == null) ...[
                    const SizedBox(height: 6),
                    _SlotRow(
                      letter: 'B',
                      video: _slotB,
                      hint: _picks.isEmpty
                          ? 'Then a second one'
                          : 'Tap another throw',
                      onClear: _picks.length == 2 ? () => _clear(1) : null,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AngularSearchField(
                controller: _search,
                hintText: 'Search athlete, event, mark, note',
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
            ),
            _filterChips(),
            if (shown.isEmpty)
              _emptyState()
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: shown.length,
                  itemBuilder: (context, index) => _candidate(shown[index]),
                ),
              ),
            if (anchor == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton.icon(
                  onPressed: _picks.length == 2
                      ? () => Navigator.pop(context, (_picks[0], _picks[1]))
                      : null,
                  icon: const Icon(Icons.compare),
                  label: Text(switch (_picks.length) {
                    0 => 'Pick two throws to compare',
                    1 => 'Pick one more throw',
                    _ => 'Compare',
                  }),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// The two narrowings, named after the throw they narrow to. Nothing to
  /// narrow against until a reference exists, so the row is not there at
  /// all on an empty pair — an inert chip is worse than no chip.
  Widget _filterChips() {
    final reference = _reference;
    if (reference == null) return const SizedBox(height: 12);
    final athlete = reference.athlete.isEmpty
        ? null
        : displayNameOf(context, reference.athlete, listen: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          FilterChip(
            label: Text(reference.event.label),
            tooltip: '${reference.event.label} throws only',
            avatar: EventGlyph(reference.event,
                size: 18, color: eventColor(reference.event)),
            showCheckmark: false,
            selected: _sameEvent,
            onSelected: (on) => _setFilter(() => _sameEvent = on),
          ),
          if (athlete != null) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text(athlete),
              tooltip: 'Throws by $athlete only',
              avatar: const Icon(Icons.person_outline, size: 18),
              showCheckmark: false,
              selected: _sameAthlete,
              onSelected: (on) => _setFilter(() => _sameAthlete = on),
            ),
          ],
        ],
      ),
    );
  }

  /// Why the list is empty, and the one tap that fills it back up. A
  /// filter is dropped one at a time, so a sheet narrowed twice explains
  /// itself twice rather than throwing everything open at once.
  Widget _emptyState() {
    final theme = Theme.of(context);
    final reference = _reference;
    final query = _query.trim();

    String message;
    String? action;
    VoidCallback? undo;
    if (widget.candidates.isEmpty) {
      message = widget.anchor == null
          ? 'Import a second throw — a comparison takes two.'
          : 'Import another throw to compare against this one.';
    } else if (query.isNotEmpty) {
      message = 'Nothing matches "$query".';
      action = 'Clear search';
      undo = () {
        _search.clear();
        setState(() => _query = '');
      };
    } else if (_sameAthlete && reference != null) {
      message = 'No other throws by '
          '${displayNameOf(context, reference.athlete, listen: false)}.';
      action = 'Show everyone';
      undo = () => _setFilter(() => _sameAthlete = false);
    } else if (_sameEvent && reference != null) {
      message = 'No other ${reference.event.label.toLowerCase()} throws yet.';
      action = 'Show all events';
      undo = () => _setFilter(() => _sameEvent = false);
    } else {
      message = 'Nothing to compare with.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      child: Column(
        children: [
          Text(message,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          if (action != null && undo != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: undo, child: Text(action)),
          ],
        ],
      ),
    );
  }

  /// Which side a row is on, or — for a row on neither — the side a tap
  /// would put it: the first pick fills A, and once both are full the next
  /// tap lands in B. A list that offered 'B' to every row while A stood
  /// empty was describing a rule the sheet does not follow.
  String _letterFor(int slot) => switch (slot) {
        0 => 'A',
        1 => 'B',
        _ => _picks.isEmpty ? 'A' : 'B',
      };

  Widget _candidate(ThrowVideo video) {
    final theme = Theme.of(context);
    final slot = _picks.indexOf(video);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      selected: slot >= 0,
      selectedTileColor: theme.colorScheme.primary.withOpacity(0.10),
      leading: ThrowThumbnail(video),
      title: Row(
        children: [
          Expanded(
            child: Text(throwTitle(video, context: context),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (widget.bests.contains(video.id))
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: FirstPlaceMedal(size: 14),
            ),
        ],
      ),
      subtitle: Text(throwSubtitle(video),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: widget.anchor != null
          ? Icon(Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7))
          : _SlotBadge(_letterFor(slot), filled: slot >= 0),
      onTap: () => _pick(video),
    );
  }
}

/// One half of the pair: which side it is, what is on it, and how to take
/// it back off.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.letter,
    required this.video,
    required this.hint,
    this.onClear,
  });

  final String letter;
  final ThrowVideo? video;

  /// What the side says while it is still empty.
  final String hint;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final video = this.video;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: angularShape(
          12,
          side: BorderSide(
            color: video == null
                ? scheme.outlineVariant.withOpacity(0.45)
                : scheme.primary.withOpacity(0.55),
          ),
        ),
        color: video == null
            ? null
            : scheme.surfaceContainerHighest.withOpacity(0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            _SlotBadge(letter, filled: video != null),
            const SizedBox(width: 8),
            if (video == null)
              Expanded(
                child: Text(hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withOpacity(0.8))),
              )
            else ...[
              ThrowThumbnail(video, width: 44, height: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(throwTitle(video, context: context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                    Text(throwSubtitle(video),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant.withOpacity(0.8))),
                  ],
                ),
              ),
            ],
            if (onClear != null)
              IconButton(
                tooltip: 'Clear $letter',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// The A/B marker: filled once that side is settled, an outline while it is
/// still a question.
class _SlotBadge extends StatelessWidget {
  const _SlotBadge(this.letter, {required this.filled});

  final String letter;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? scheme.primary : null,
        border: filled
            ? null
            : Border.all(color: scheme.outlineVariant.withOpacity(0.7)),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: filled
              ? scheme.onPrimary
              : scheme.onSurfaceVariant.withOpacity(0.7),
        ),
      ),
    );
  }
}
