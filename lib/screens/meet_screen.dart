import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_mark.dart';
import '../models/throw_video.dart';
import '../services/meet_library.dart';
import '../services/video_library.dart';
import '../services/video_optimizer.dart';
import '../widgets/athlete_picker.dart';
import '../widgets/attempt_entry.dart';
import '../widgets/event_glyph.dart';
import '../widgets/gold.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'analysis_screen.dart';

/// Films the round that is about to be thrown. Injected so a test can drive
/// the screen without a camera.
typedef AttemptFilmer = Future<ThrowVideo?> Function(
    MeetEntry entry, String meetName);

/// One competition as it happens: every athlete the coach has entered, the
/// series each of them is putting together, and the two things there is
/// time to do between attempts — film the throw, and write down the mark.
///
/// The screen holds no results of its own. A measured attempt is a mark or
/// a clip in the library the moment it is entered, so by the time the coach
/// is off the infield the meet is already in each athlete's record book,
/// personal bests and all.
class MeetScreen extends StatefulWidget {
  const MeetScreen({super.key, required this.meetId, this.filmAttempt});

  final String meetId;

  /// Overrides how a round is filmed; the camera when null.
  final AttemptFilmer? filmAttempt;

  @override
  State<MeetScreen> createState() => _MeetScreenState();
}

class _MeetScreenState extends State<MeetScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<MeetLibrary, VideoLibrary>(
      builder: (context, meets, library, _) {
        final meet = meets.byId(widget.meetId);
        if (meet == null) {
          // Deleted from under us — nothing left to show.
          return const Scaffold(body: SizedBox.shrink());
        }
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(meet.name.isEmpty ? 'Meet' : meet.name),
                Text(
                  '${shortThrowDate(meet.date)} · ${_summary(meet)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Meet settings',
                icon: const Icon(Icons.more_horiz),
                onPressed: () => _editMeet(meets, meet),
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
              if (meet.entries.isEmpty)
                _empty(context)
              else
                ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    for (final entry in meet.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EntryCard(
                          meet: meet,
                          entry: entry,
                          series: MeetSeries(entry, library.results),
                          library: library,
                          onEnter: (round) => _enter(meet, entry, round),
                          onFilm: (round) => _film(meet, entry, round),
                          onOpen: _openThrow,
                          onRemove: () => _removeEntry(meets, meet, entry),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add athlete'),
            onPressed: () => _addEntry(meets, library, meet),
          ),
        );
      },
    );
  }

  String _summary(Meet meet) {
    final entries = meet.entries.length;
    if (entries == 0) return 'nobody entered yet';
    final attempts =
        meet.entries.fold<int>(0, (sum, entry) => sum + entry.taken);
    return '$entries athlete${entries == 1 ? '' : 's'} · '
        '$attempts attempt${attempts == 1 ? '' : 's'}';
  }

  Widget _empty(BuildContext context) => Center(
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
                'Film an attempt, or just write the mark down when you '
                "didn't have the camera up.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  /// Enters one round: the sheet, then whatever it came back with.
  Future<void> _enter(Meet meet, MeetEntry entry, int round) async {
    final meets = context.read<MeetLibrary>();
    final library = context.read<VideoLibrary>();
    final series = MeetSeries(entry, library.results);
    final attempt = entry.attemptAt(round);
    final result = series.resultAt(round);
    final outcome = await showAttemptSheet(
      context,
      athlete: entry.athlete,
      round: round,
      filmed: result is ThrowVideo,
      existing: attempt?.kind,
      metres: series.distanceAt(round),
      unit: result?.distanceUnit ?? DistanceUnit.metres,
    );
    if (outcome == null || !mounted) return;

    switch (outcome.action) {
      case AttemptAction.film:
        await _film(meet, entry, round);
      case AttemptAction.save:
        await _saveMark(meet, entry, round,
            metres: outcome.metres!, unit: outcome.unit!);
      case AttemptAction.foul:
      case AttemptAction.pass:
        final kind = outcome.action == AttemptAction.foul
            ? AttemptKind.foul
            : AttemptKind.pass;
        // A foul is not a result: whatever distance was recorded for this
        // round has to leave the record book with it, or the athlete keeps
        // a personal best for a throw that didn't count.
        final clip = await _unmeasure(library, result);
        await meets.setAttempt(meet.id, entry.id, round,
            MeetAttempt(kind: kind, resultId: clip?.id));
      case AttemptAction.clear:
        // The clip stays in the library — it is footage of a real throw,
        // and deleting it is a bigger thing than taking a round back.
        await _unmeasure(library, result);
        await meets.setAttempt(meet.id, entry.id, round, null);
    }
  }

  /// Strips the distance from a round being taken back: a typed mark is
  /// deleted outright, while a filmed one keeps its clip and loses only the
  /// number. Returns the clip, when there was one.
  Future<ThrowVideo?> _unmeasure(
      VideoLibrary library, ThrowResult? result) async {
    if (result is ThrowMark) {
      await library.removeMark(result.id);
      return null;
    }
    if (result is ThrowVideo) {
      if (result.distance != null) {
        result.distance = null;
        await library.update(result);
      }
      return result;
    }
    return null;
  }

  /// Writes the distance into the record book, then points the round at it.
  Future<void> _saveMark(
    Meet meet,
    MeetEntry entry,
    int round, {
    required double metres,
    required DistanceUnit unit,
  }) async {
    final meets = context.read<MeetLibrary>();
    final library = context.read<VideoLibrary>();
    final existing = MeetSeries(entry, library.results).resultAt(round);

    // Filmed: the clip is the throw, so the mark belongs on it rather than
    // beside it as a second record of the same attempt.
    if (existing is ThrowVideo) {
      existing.distance = metres;
      existing.distanceUnit = unit;
      await library.update(existing);
      await meets.setAttempt(meet.id, entry.id, round,
          MeetAttempt.mark(existing.id));
      return;
    }

    if (existing is ThrowMark) {
      existing.distance = metres;
      existing.distanceUnit = unit;
      await library.updateMark(existing);
      await meets.setAttempt(
          meet.id, entry.id, round, MeetAttempt.mark(existing.id));
      return;
    }

    final mark = ThrowMark(
      id: VideoLibrary.newMarkId(),
      athlete: entry.athlete,
      event: entry.event,
      implementKg: entry.implementKg,
      distance: metres,
      distanceUnit: unit,
      achievedOn: meet.date,
      note: meet.name,
    );
    await library.addMark(mark);
    await meets.setAttempt(meet.id, entry.id, round, MeetAttempt.mark(mark.id));
  }

  /// Films a round and hangs the clip on it, then asks for the distance —
  /// which is announced a few seconds after the throw, by which time the
  /// coach is looking at this sheet anyway.
  Future<void> _film(Meet meet, MeetEntry entry, int round) async {
    final meets = context.read<MeetLibrary>();
    final filmer = widget.filmAttempt ?? _capture;
    final video = await filmer(entry, meet.name);
    if (video == null || !mounted) return;
    await meets.setAttempt(
        meet.id, entry.id, round, MeetAttempt.mark(video.id));
    if (!mounted) return;
    await _enter(meet, entry, round);
  }

  /// Records a throw with the phone's camera and files it as it was shot.
  ///
  /// Deliberately not the import's re-encode: that runs for minutes, and
  /// the next athlete is up. The clip is stamped as owing one instead, and
  /// the analyzer does it the first time the throw is opened.
  Future<ThrowVideo?> _capture(MeetEntry entry, String meetName) async {
    final library = context.read<VideoLibrary>();
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null || !mounted) return null;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final rates = await VideoOptimizer.probeFrameRates(picked.path);
    final path = await VideoOptimizer.stashCapture(picked.path, id);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't save the recording.")));
      }
      return null;
    }
    final thumbnail = await VideoOptimizer.extractThumbnail(path, id);
    final now = DateTime.now();
    final video = ThrowVideo(
      id: id,
      path: path,
      event: entry.event,
      implementKg: entry.implementKg,
      importedAt: now,
      recordedAt: now,
      fps: rates?.playback ?? 30,
      captureFps: rates?.capture,
      athlete: entry.athlete,
      note: meetName,
      thumbnailPath: thumbnail,
      optimizePending: true,
    );
    await library.add(video);
    return video;
  }

  void _openThrow(ThrowVideo video) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisScreen(video: video, siblings: [video]),
        ),
      );

  Future<void> _addEntry(
      MeetLibrary meets, VideoLibrary library, Meet meet) async {
    final entry = await showDialog<MeetEntry>(
      context: context,
      builder: (context) => _EntryDialog(known: library.knownAthletes),
    );
    if (entry != null) await meets.addEntry(meet.id, entry: entry);
  }

  Future<void> _removeEntry(
      MeetLibrary meets, Meet meet, MeetEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${entry.athlete}?'),
        content: const Text(
            'Takes them out of this meet. The marks and clips already '
            'recorded stay in the library.'),
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
    if (confirmed == true) await meets.removeEntry(meet.id, entry.id);
  }

  Future<void> _editMeet(MeetLibrary meets, Meet meet) async {
    final edited = await showDialog<Meet>(
      context: context,
      builder: (context) => _MeetDialog(existing: meet),
    );
    if (edited != null) await meets.save(edited);
  }
}

/// One athlete's competition: who they are, the series so far, and the two
/// buttons that are worth having on a phone held at chest height.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.meet,
    required this.entry,
    required this.series,
    required this.library,
    required this.onEnter,
    required this.onFilm,
    required this.onOpen,
    required this.onRemove,
  });

  final Meet meet;
  final MeetEntry entry;
  final MeetSeries series;
  final VideoLibrary library;
  final ValueChanged<int> onEnter;
  final ValueChanged<int> onFilm;
  final ValueChanged<ThrowVideo> onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = eventColor(entry.event);
    final best = series.best;
    final bestRound = series.bestRound;
    final bestResult = bestRound == null ? null : series.resultAt(bestRound);
    final isBest =
        bestResult != null && library.isPersonalBest(bestResult);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EventGlyph(entry.event, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.athlete.isEmpty ? 'Unassigned' : entry.athlete,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${entry.event.label} · '
                        '${entry.implementSpec.weightLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove from meet',
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var round = 0; round < meet.rounds; round++) ...[
                  if (round > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _AttemptBox(
                      key: ValueKey('round-$round'),
                      round: round,
                      accent: accent,
                      attempt: entry.attemptAt(round),
                      distance: series.distanceAt(round),
                      unit: series.resultAt(round)?.distanceUnit ??
                          DistanceUnit.metres,
                      filmed: series.filmedAt(round),
                      isBest: round == bestRound,
                      onTap: () => onEnter(round),
                      onLongPress: () {
                        final result = series.resultAt(round);
                        if (result is ThrowVideo) onOpen(result);
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // The two buttons keep their full size whatever the best
                // reads: they are what a coach aims a thumb at without
                // looking down, and a long mark in feet would otherwise
                // squeeze them off the card.
                Expanded(
                  child: best == null
                      ? const SizedBox.shrink()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isBest) ...[
                                const FirstPlaceMedal(size: 13),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isBest ? 'PB' : 'Best',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                formatDistance(
                                    best,
                                    series.resultAt(bestRound!)?.distanceUnit ??
                                        DistanceUnit.metres),
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600, color: accent),
                              ),
                            ],
                          ),
                        ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.videocam_outlined, size: 20),
                  label: const Text('Film'),
                  onPressed: () => onFilm(entry.nextRound),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.straighten, size: 20),
                  label: const Text('Mark'),
                  onPressed: () => onEnter(entry.nextRound),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One round of a series, the way it is written on a results sheet: the
/// distance, X for a foul, – for a pass, and nothing at all for a round
/// that has not been thrown.
class _AttemptBox extends StatelessWidget {
  const _AttemptBox({
    super.key,
    required this.round,
    required this.accent,
    required this.attempt,
    required this.distance,
    required this.unit,
    required this.filmed,
    required this.isBest,
    required this.onTap,
    required this.onLongPress,
  });

  final int round;

  /// The event's colour, so the leading attempt reads as part of the card
  /// rather than as the app's own accent landing on it.
  final Color accent;

  final MeetAttempt? attempt;
  final double? distance;
  final DistanceUnit unit;
  final bool filmed;
  final bool isBest;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (attempt?.kind) {
      null => ('', scheme.onSurfaceVariant),
      AttemptKind.foul => ('X', scheme.error),
      AttemptKind.pass => ('–', scheme.onSurfaceVariant),
      AttemptKind.mark => distance == null
          // The mark behind this round has been deleted from the library.
          ? ('?', scheme.onSurfaceVariant)
          : (
              formatDistance(distance!, unit).split(' ').first,
              isBest ? accent : scheme.onSurface
            ),
    };
    return Semantics(
      label: 'Round ${round + 1}',
      button: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: attempt == null
                ? null
                : scheme.surfaceContainerHighest.withOpacity(0.6),
            border: Border.all(
              color: isBest ? accent : scheme.outlineVariant,
              width: isBest ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 2,
                left: 4,
                child: Text(
                  '${round + 1}',
                  style: TextStyle(
                      fontSize: 9,
                      height: 1,
                      color: scheme.onSurfaceVariant),
                ),
              ),
              if (filmed)
                Positioned(
                  top: 2,
                  right: 3,
                  child: Icon(Icons.videocam,
                      size: 10, color: scheme.primary),
                ),
              Positioned.fill(
                top: 8,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enters an athlete in an event. The weight is asked for here rather than
/// per attempt because it does not change through a competition — and a
/// best is per weight, so guessing it would put the mark in the wrong book.
class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.known});

  final List<String> known;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  String _athlete = '';
  ThrowEvent _event = ThrowEvent.shotPut;
  late ImplementSpec _implement = _event.defaultImplement;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add athlete'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AthletePicker(
              known: widget.known,
              value: _athlete,
              onChanged: (name) => setState(() => _athlete = name),
            ),
            const SizedBox(height: 12),
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
                    ),
                  ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Names a meet, dates it, and says how many attempts it gives. Used to
/// start one and to fix it afterwards.
class _MeetDialog extends StatefulWidget {
  const _MeetDialog({this.existing});

  final Meet? existing;

  @override
  State<_MeetDialog> createState() => _MeetDialogState();
}

class _MeetDialogState extends State<_MeetDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late int _rounds = widget.existing?.rounds ?? 6;

  @override
  void dispose() {
    _name.dispose();
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
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(shortThrowDate(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            DropdownButtonFormField<int>(
              value: _rounds,
              decoration: const InputDecoration(labelText: 'Attempts'),
              items: [
                for (final rounds in const [3, 4, 5, 6])
                  DropdownMenuItem(
                      value: rounds, child: Text('$rounds per athlete')),
              ],
              onChanged: (rounds) => setState(() => _rounds = rounds ?? 6),
            ),
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
              existing.date = _date;
              existing.rounds = _rounds;
              Navigator.pop(context, existing);
              return;
            }
            Navigator.pop(
              context,
              Meet(
                id: MeetLibrary.newMeetId(),
                name: _name.text.trim(),
                date: _date,
                rounds: _rounds,
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
Future<Meet?> showNewMeetDialog(BuildContext context) => showDialog<Meet>(
      context: context,
      builder: (context) => const _MeetDialog(),
    );
