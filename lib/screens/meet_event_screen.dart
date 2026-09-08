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
import '../widgets/angular.dart';
import '../widgets/attempt_entry.dart';
import '../widgets/entry_dialog.dart';
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

/// One event at a meet, as it happens: the field in the order it throws,
/// the series each of them is putting together, and the two things there is
/// time to do between attempts — film the throw, and write down the mark.
///
/// An event, not a meet, because that is the unit a competition is actually
/// run in: everyone here is throwing the same implement, in one order,
/// against one cut. A coach standing at the discus cage has no use for the
/// javelin's flight two rings away.
///
/// The screen holds no results of its own. A measured attempt is a mark or
/// a clip in the library the moment it is entered, so by the time the coach
/// is off the infield the meet is already in each athlete's record book,
/// personal bests and all.
class MeetEventScreen extends StatefulWidget {
  const MeetEventScreen({
    super.key,
    required this.meetId,
    required this.event,
    required this.implementKg,
    this.filmAttempt,
  });

  final String meetId;

  /// Which competition of the meet this is — the event and the weight
  /// together, since those are what put athletes in the same contest.
  final ThrowEvent event;
  final double implementKg;

  /// Overrides how a round is filmed; the camera when null.
  final AttemptFilmer? filmAttempt;

  @override
  State<MeetEventScreen> createState() => _MeetEventScreenState();
}

/// Which way the event is being read: the order it is thrown in, or where
/// everyone stands in it.
enum _MeetView { series, standings }

class _MeetEventScreenState extends State<MeetEventScreen> {
  _MeetView _view = _MeetView.series;

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
        final accent = eventColor(widget.event);
        final spec = widget.event.specFor(widget.implementKg);
        // Empty once the last entry is removed: the competition stops
        // existing, but the screen stays so somebody can be put back in it.
        final competition = MeetCompetition.of(meet).firstWhere(
          (c) => c.event == widget.event && c.implementKg == widget.implementKg,
          orElse: () =>
              MeetCompetition(widget.event, widget.implementKg, const []),
        );
        final standings = MeetStandings(competition, library.results,
            advancing: meet.advancing, prelimRounds: meet.prelimRounds);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                EventGlyph(widget.event, size: 20, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${widget.event.label} · ${spec.weightLabel}'),
                      Text(
                        meet.name.isEmpty ? 'Meet' : meet.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
              if (competition.entries.isEmpty)
                _empty(context)
              else
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: AngularSegmentedBar<_MeetView>(
                        value: _view,
                        onChanged: (view) => setState(() => _view = view),
                        segments: const [
                          AngularSegment(
                              value: _MeetView.series,
                              icon: Icons.format_list_numbered,
                              label: 'Series'),
                          AngularSegment(
                              value: _MeetView.standings,
                              icon: Icons.emoji_events_outlined,
                              label: 'Standings'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _view == _MeetView.series
                          ? _seriesList(
                              meet, meets, library, competition, standings)
                          : _standingsList(meet, standings),
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

  /// The field in the order it throws, which is the order a coach's eye
  /// goes down the list in as the round works through.
  Widget _seriesList(Meet meet, MeetLibrary meets, VideoLibrary library,
      MeetCompetition competition, MeetStandings standings) {
    final field = competition.entries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        for (var i = 0; i < field.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EntryCard(
              meet: meet,
              entry: field[i],
              position: i + 1,
              // Null when nothing is closed: no final, or they made it. A
              // 3 + 3 only closes the last rounds once the whole field has
              // had its three, which is what throwsInFinal waits for.
              closedFrom: !meet.hasFinal || standings.throwsInFinal(field[i].id)
                  ? null
                  : meet.prelimRounds,
              series: MeetSeries(field[i], library.results),
              library: library,
              onEnter: (round) => _enter(meet, field[i], round),
              onFilm: (round) => _film(meet, field[i], round),
              onOpen: _openThrow,
              onRemove: () => _removeEntry(meets, meet, field[i]),
              onMove: (by) => _move(meet, field, i, by),
            ),
          ),
      ],
    );
  }

  /// Where the competition stands — one table, because everyone on this
  /// screen is in the one an athlete is actually placed in.
  Widget _standingsList(Meet meet, MeetStandings standings) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          _StandingsCard(
            standings: standings,
            onSetFinalOrder: () => _setFinalOrder(meet, standings),
          ),
        ],
      );

  /// Moves one athlete up or down the flight.
  ///
  /// Only within this event: the meet's order runs across every competition
  /// in it, and the javelin has no business shuffling because the discus
  /// did.
  Future<void> _move(
      Meet meet, List<MeetEntry> field, int index, int by) async {
    final target = index + by;
    if (target < 0 || target >= field.length) return;
    _number(meet);
    final was = field[index].order;
    field[index].order = field[target].order;
    field[target].order = was;
    await context.read<MeetLibrary>().save(meet);
  }

  /// Redraws the order for the final: the qualifiers, worst-placed first,
  /// with everyone who missed the cut left where they are behind them.
  Future<void> _setFinalOrder(Meet meet, MeetStandings standings) async {
    final field = standings.competition.entries;
    final qualifiers = standings.finalOrder;
    final resequenced = [
      ...qualifiers,
      for (final entry in field)
        if (!qualifiers.contains(entry)) entry,
    ];
    _number(meet);
    // The places this event already holds in the meet's order, refilled in
    // the new sequence — so a second event on the same card keeps its own.
    final slots = [for (final entry in field) entry.order]..sort();
    for (var i = 0; i < resequenced.length; i++) {
      resequenced[i].order = slots[i];
    }
    await context.read<MeetLibrary>().save(meet);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The final throws in reverse order, leader last.')));
    }
  }

  /// Numbers the whole field off, so no two entries share a position.
  ///
  /// Positions can start out equal — everyone added at once sits on the
  /// same one, and a stable sort keeps them in the order they arrived — and
  /// swapping two equal numbers would move nobody.
  void _number(Meet meet) {
    final all = meet.inOrder;
    for (var i = 0; i < all.length; i++) {
      all[i].order = i;
    }
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
                'Nobody in this event yet.\n'
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
      meters: series.distanceAt(round),
      unit: result?.distanceUnit ?? DistanceUnit.meters,
    );
    if (outcome == null || !mounted) return;

    switch (outcome.action) {
      case AttemptAction.film:
        await _film(meet, entry, round);
      case AttemptAction.save:
        await _saveMark(meet, entry, round,
            meters: outcome.meters!, unit: outcome.unit!);
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

  /// Reorders the field, and saves it.

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
    required double meters,
    required DistanceUnit unit,
  }) async {
    final meets = context.read<MeetLibrary>();
    final library = context.read<VideoLibrary>();

    // The rest of the field is recorded, not collected: their throw is a
    // number on the attempt and nothing else. It has to be, or a rival's
    // 60 m would turn up in the library as somebody's personal best.
    if (!entry.tracked) {
      await meets.setAttempt(meet.id, entry.id, round,
          MeetAttempt.untracked(meters, distanceUnit: unit));
      return;
    }

    final existing = MeetSeries(entry, library.results).resultAt(round);

    // Filmed: the clip is the throw, so the mark belongs on it rather than
    // beside it as a second record of the same attempt.
    if (existing is ThrowVideo) {
      existing.distance = meters;
      existing.distanceUnit = unit;
      await library.update(existing);
      await meets.setAttempt(
          meet.id, entry.id, round, MeetAttempt.mark(existing.id));
      return;
    }

    if (existing is ThrowMark) {
      existing.distance = meters;
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
      distance: meters,
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't save the recording.")));
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

  /// Adds somebody to this event — already in it, since that is the one
  /// the coach is standing at.
  Future<void> _addEntry(
      MeetLibrary meets, VideoLibrary library, Meet meet) async {
    final entry = await showMeetEntryDialog(
      context,
      known: library.knownAthletes,
      event: widget.event,
      implementKg: widget.implementKg,
    );
    if (entry != null) {
      // Onto the end of the flight: an athlete added mid-competition is
      // one the coach has just noticed, not one who throws first.
      entry.order = meet.entries.length;
      await meets.addEntry(meet.id, entry: entry);
    }
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
}

/// One athlete's competition: who they are, the series so far, and the two
/// buttons that are worth having on a phone held at chest height.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.meet,
    required this.entry,
    required this.position,
    required this.closedFrom,
    required this.series,
    required this.library,
    required this.onEnter,
    required this.onFilm,
    required this.onOpen,
    required this.onRemove,
    required this.onMove,
  });

  final Meet meet;
  final MeetEntry entry;

  /// Where they throw in the flight, from 1.
  final int position;

  /// The first round they no longer have — the cut, for an athlete who
  /// missed it. Null while everyone still has throws coming.
  final int? closedFrom;

  final MeetSeries series;
  final VideoLibrary library;
  final ValueChanged<int> onEnter;
  final ValueChanged<int> onFilm;
  final ValueChanged<ThrowVideo> onOpen;
  final VoidCallback onRemove;

  /// Moves them one place up (-1) or down (1) the order.
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = eventColor(entry.event);
    final best = series.best;
    final bestRound = series.bestRound;
    final bestResult = bestRound == null ? null : series.resultAt(bestRound);
    final isBest = bestResult != null && library.isPersonalBest(bestResult);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Where they are in the flight: the number a coach counts
                // down to work out how long they have before their athlete
                // is in the circle.
                SizedBox(
                  width: 22,
                  child: Text(
                    '$position',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                // No event on the card: everyone on this screen is in the
                // same one, and the app bar has already said which.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.athlete.isEmpty ? 'Unassigned' : entry.athlete,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              // The rest of the field sits back a shade from
                              // the athletes the coach is here for.
                              color: entry.tracked
                                  ? null
                                  : theme.colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!entry.tracked) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.groups_outlined,
                            size: 15,
                            color: theme.colorScheme.onSurfaceVariant),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Order and entry',
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (choice) => switch (choice) {
                    'up' => onMove(-1),
                    'down' => onMove(1),
                    _ => onRemove(),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'up',
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.arrow_upward, size: 18),
                            title: Text('Throw earlier'))),
                    PopupMenuItem(
                        value: 'down',
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.arrow_downward, size: 18),
                            title: Text('Throw later'))),
                    PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline, size: 18),
                            title: Text('Remove'))),
                  ],
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
                      closed: closedFrom != null && round >= closedFrom!,
                      attempt: entry.attemptAt(round),
                      distance: series.distanceAt(round),
                      unit: series.resultAt(round)?.distanceUnit ??
                          DistanceUnit.meters,
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
                                        DistanceUnit.meters),
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600, color: accent),
                              ),
                            ],
                          ),
                        ),
                ),
                // Cut, with nothing left to fill in behind them: there is
                // no round for these buttons to open.
                if (closedFrom != null && entry.nextRound >= closedFrom!)
                  Text(
                    'out of the final',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                else ...[
                  // Nothing is filmed for the rest of the field: a clip has
                  // to land in the library under somebody's name, and these
                  // are not the coach's athletes to keep.
                  if (entry.tracked) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.videocam_outlined, size: 20),
                      label: const Text('Film'),
                      onPressed: () => onFilm(entry.nextRound),
                    ),
                    const SizedBox(width: 4),
                  ],
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.straighten, size: 20),
                    label: const Text('Mark'),
                    onPressed: () => onEnter(entry.nextRound),
                  ),
                ],
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
    required this.closed,
    required this.attempt,
    required this.distance,
    required this.unit,
    required this.filmed,
    required this.isBest,
    required this.onTap,
    required this.onLongPress,
  });

  final int round;

  /// The event's color, so the leading attempt reads as part of the card
  /// rather than as the app's own accent landing on it.
  final Color accent;

  /// A round this athlete doesn't get: they were cut before it. Shown, not
  /// hidden — a series is six boxes, and the empty ones say why.
  final bool closed;

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
      label: closed && attempt == null
          ? 'Round ${round + 1}, out of the final'
          : 'Round ${round + 1}',
      button: !closed,
      child: InkWell(
        // A round they were cut before is not theirs to enter.
        onTap: closed ? null : onTap,
        onLongPress: closed ? null : onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          // Grayed rather than gone, so the series still reads as six.
          opacity: closed && attempt == null ? 0.35 : 1,
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
                        fontSize: 9, height: 1, color: scheme.onSurfaceVariant),
                  ),
                ),
                if (filmed)
                  Positioned(
                    top: 2,
                    right: 3,
                    child:
                        Icon(Icons.videocam, size: 10, color: scheme.primary),
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
      ),
    );
  }
}

/// One competition's table: who is where, where the cut falls, and what a
/// coach's own athlete has to throw to get past it.
class _StandingsCard extends StatelessWidget {
  const _StandingsCard(
      {required this.standings, required this.onSetFinalOrder});

  final MeetStandings standings;
  final VoidCallback onSetFinalOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = eventColor(standings.competition.event);
    final places = standings.places;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No event heading: the app bar has said which competition
            // this is, and there is only ever the one table under it.
            if (standings.hasCut) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  standings.cutMade
                      ? 'the final'
                      : 'top ${standings.advancing} advance',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: standings.cutMade
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
            ],
            for (var i = 0; i < places.length; i++) ...[
              // The cut, drawn where it falls: everything under this line
              // is out of the final as things stand.
              if (standings.hasCut &&
                  i > 0 &&
                  places[i - 1].advancing &&
                  !places[i].advancing)
                _CutLine(advancing: standings.advancing),
              _PlaceRow(
                place: places[i],
                accent: accent,
                // Once the cut is made there is nothing left to need: the
                // closed rounds on their card say it better than a number.
                needed: standings.cutMade
                    ? null
                    : standings.neededToQualify(places[i].entry.id),
              ),
            ],
            if (standings.hasCut) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: const Text('Order the final'),
                  onPressed: onSetFinalOrder,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CutLine extends StatelessWidget {
  const _CutLine({required this.advancing});

  final int advancing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: scheme.primary.withOpacity(0.5))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'the cut',
              style: TextStyle(fontSize: 10, color: scheme.primary),
            ),
          ),
          Expanded(child: Divider(color: scheme.primary.withOpacity(0.5))),
        ],
      ),
    );
  }
}

/// One line of the table. A coach's own athlete is the one the eye should
/// find first, so the rest of the field is set back rather than dressed up.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.accent,
    required this.needed,
  });

  final MeetPlace place;
  final Color accent;

  /// What it would take to make the final, for an athlete who is out of it.
  final double? needed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = place.entry.tracked;
    final best = place.best;
    final unit = place.series.bestRound == null
        ? DistanceUnit.meters
        : place.series.unitAt(place.series.bestRound!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  best == null ? '–' : '${place.place}',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: mine ? accent : scheme.onSurfaceVariant,
                      fontWeight: mine ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              Expanded(
                child: Text(
                  place.entry.athlete.isEmpty
                      ? 'Unassigned'
                      : place.entry.athlete,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: mine ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontWeight: mine ? FontWeight.w600 : FontWeight.w400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                best == null ? '—' : formatDistance(best, unit),
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: mine ? accent : scheme.onSurfaceVariant),
              ),
            ],
          ),
          // Only for the coach's own: what the rest of the field needs is
          // not their problem.
          if (mine && needed != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                'needs ${formatDistance(needed!, unit)} to make the final',
                style:
                    theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}
