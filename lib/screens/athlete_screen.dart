import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/athlete_profile.dart';
import '../models/athlete_record.dart';
import '../models/meet.dart';
import '../models/meet_history.dart';
import '../models/throw_event.dart';
import '../models/throw_mark.dart';
import '../models/throw_video.dart';
import '../models/training_note.dart';
import '../services/athlete_library.dart';
import '../services/meet_library.dart';
import '../services/notes_library.dart';
import '../services/video_library.dart';
import '../widgets/angular.dart';
import '../widgets/event_glyph.dart';
import '../widgets/gold.dart';
import '../widgets/mark_editor.dart';
import '../widgets/note_text.dart';
import '../widgets/progression.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_actions.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'analysis_screen.dart';
import 'meet_event_screen.dart';
import 'note_editor_screen.dart';

/// One athlete: what they have thrown, what their best mark is at each of
/// it, and every clip of theirs.
///
/// The library's other headings are buckets — an event, a date — and a grid
/// of stills says everything there is to say about those. An athlete is a
/// person you are coaching over a season, so their heading opens this
/// instead: the marks first, because that is the question a coach opens an
/// athlete to answer, then the throws those marks came out of.
class AthleteScreen extends StatelessWidget {
  const AthleteScreen({
    super.key,
    required this.name,
    required this.titleFor,
  });

  /// Who this is. Looked up by name on every build rather than held as a
  /// list of ids, so a throw tagged to them from anywhere in the app turns
  /// up here — and a mark recorded on it counts straight away.
  final String name;

  /// How to label a card here — under an athlete their name is redundant.
  final String Function(ThrowVideo video) titleFor;

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoLibrary>(
      builder: (context, library, _) {
        final profile = library.profileFor(name);
        final theme = Theme.of(context);
        // The nickname is what to show; the profile's own spelling stays the
        // identity every throw is tagged with.
        final record = athleteRecordsOf(context)?.recordFor(profile.name);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(record?.displayName ?? profile.name),
                Text(
                  _summary(profile),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Edit athlete',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editAthlete(context, profile.name, record),
              ),
              IconButton(
                tooltip: 'Record a mark',
                icon: const Icon(Icons.emoji_events_outlined),
                onPressed: () => _addMark(context, library, profile.name),
              ),
            ],
          ),
          body: Stack(
            children: [
              // The same sector that backs the library, so a profile reads
              // as a room in it rather than a screen from another app.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                        SectorBackdropPainter(color: theme.colorScheme.primary),
                  ),
                ),
              ),
              profile.isEmpty
                  ? const _NoThrows()
                  : _body(context, library, profile),
            ],
          ),
        );
      },
    );
  }

  /// "12 throws · 3 events · since 4 Aug" — enough of a profile to know
  /// what you are looking at before scrolling. Marks count as throws: from
  /// out here there is no difference between one that was filmed and one
  /// that wasn't.
  String _summary(AthleteProfile profile) {
    final total = profile.throws.length + profile.marks.length;
    final count = '$total throw${total == 1 ? '' : 's'}';
    if (profile.isEmpty) return count;
    final events = profile.events.length;
    final since = shortThrowDate(profile.firstThrewOn!);
    return '$count · $events event${events == 1 ? '' : 's'} · since $since';
  }

  Future<void> _addMark(
      BuildContext context, VideoLibrary library, String athlete) async {
    final mark = await showMarkEditor(context, athlete: athlete);
    if (mark != null) await library.addMark(mark);
  }

  /// Opens the record editor and stores whatever comes back. The library
  /// spelling stays the athlete's identity — only the nickname, full name
  /// and school are the coach's to set.
  Future<void> _editAthlete(
      BuildContext context, String athlete, AthleteRecord? existing) async {
    final records = athleteRecordsOf(context, listen: false);
    if (records == null) return;
    final edited = await showDialog<AthleteRecord>(
      context: context,
      builder: (context) => _AthleteEditDialog(
        record: existing ?? AthleteRecord(name: athlete),
      ),
    );
    if (edited != null) await records.save(edited);
  }

  Widget _body(
      BuildContext context, VideoLibrary library, AthleteProfile profile) {
    final record = athleteRecordsOf(context)?.recordFor(profile.name);
    final atMeet = _meetResultIds(context);
    return CustomScrollView(
      slivers: [
        if (record != null && !record.isEmpty)
          SliverToBoxAdapter(
            child: _IdentityLine(record: record, filedAs: profile.name),
          ),
        const SliverToBoxAdapter(child: _SectionHeading('Personal bests')),
        if (profile.bests.isEmpty)
          SliverToBoxAdapter(
            child: _NoMarks(
                onRecord: () => _addMark(context, library, profile.name)),
          )
        else
          SliverList.separated(
            itemCount: profile.bests.length,
            separatorBuilder: (context, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final best = profile.bests[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _BestTile(
                  best: best,
                  season: _progressionFor(profile, best, atMeet),
                  // A filmed best opens its clip; one that was only ever
                  // written down opens the thing it actually is, the entry.
                  onTap: () => best.isFilmed
                      ? _openThrow(context, best.video!, profile.throws)
                      : _editMark(context, library, best.result as ThrowMark),
                ),
              );
            },
          ),
        ..._meetsSection(context, profile),
        _notesSection(context, profile.name),
        if (profile.marks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeading('Marks', '${profile.marks.length}'),
          ),
          SliverList.separated(
            itemCount: profile.marks.length,
            separatorBuilder: (context, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final mark = profile.marks[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _MarkTile(
                  mark: mark,
                  isPersonalBest: library.isPersonalBest(mark),
                  onTap: () => _editMark(context, library, mark),
                  onLongPress: () => _deleteMark(context, library, mark),
                ),
              );
            },
          ),
        ],
        SliverToBoxAdapter(
          child: _SectionHeading('Throws', '${profile.throws.length}'),
        ),
        if (profile.throws.isEmpty)
          const SliverToBoxAdapter(child: _NoClips())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemCount: profile.throws.length,
              itemBuilder: (context, index) {
                final video = profile.throws[index];
                return ThrowCard(
                  video: video,
                  title: titleFor(video),
                  isPersonalBest: library.isPersonalBest(video),
                  onTap: () => _openThrow(context, video, profile.throws),
                  onLongPress: () => showThrowActions(context, video),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Every measured throw of theirs at one event and weight, oldest first.
  /// Training marks included: an athlete throwing further on a Tuesday than
  /// they manage on a Saturday is exactly what a coach wants to see, and a
  /// chart of competition days alone would hide it.
  List<ProgressionPoint> _progressionFor(
      AthleteProfile profile, PersonalBest best, Set<String> atMeet) {
    final points = [
      for (final result in profile.results)
        if (result.event == best.event &&
            result.implementKg == best.implementKg &&
            result.distance != null)
          ProgressionPoint(
            on: result.displayDate,
            meters: result.distance!,
            atMeet: atMeet.contains(result.id),
          ),
    ]..sort((a, b) => a.on.compareTo(b.on));
    return points;
  }

  /// The ids of every mark and clip a meet has an attempt pointing at.
  Set<String> _meetResultIds(BuildContext context) => {
        for (final meet in meetsOf(context)?.meets ?? const <Meet>[])
          for (final entry in meet.entries)
            for (final attempt in entry.attempts)
              if (attempt?.resultId != null) attempt!.resultId!,
      };

  /// Their meets, most recent first: the series, where it placed, and what
  /// the day was like.
  ///
  /// The record book already holds the marks. What it does not hold is the
  /// afternoon they came out of — whether the big throw was the opener or
  /// the last one, what the field was, and whether it was into a headwind.
  /// A coach going into a championship is asking about that half of it.
  List<Widget> _meetsSection(BuildContext context, AthleteProfile profile) {
    final outings = MeetOuting.forAthlete(
      profile.name,
      meetsOf(context)?.meets ?? const <Meet>[],
      Provider.of<VideoLibrary>(context, listen: false).results,
    );
    if (outings.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeading('Meets', _tally(outings)),
      ),
      SliverList.separated(
        itemCount: outings.length,
        separatorBuilder: (context, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _OutingTile(
            outing: outings[index],
            onTap: () => _openCompetition(context, outings[index]),
          ),
        ),
      ),
    ];
  }

  /// '4' on its own, or '4 · 2 wins' for an athlete who has been winning
  /// them. The one number a coach says out loud about a season, and the
  /// only one worth putting in a heading.
  String _tally(List<MeetOuting> outings) {
    final record = MeetRecord(outings);
    if (record.wins == 0) return '${record.outings}';
    return '${record.outings} · ${record.wins} '
        'win${record.wins == 1 ? '' : 's'}';
  }

  /// Opens the competition this series was thrown in — the rest of the
  /// field, and the rounds as they were entered.
  void _openCompetition(BuildContext context, MeetOuting outing) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetEventScreen(
            meetId: outing.meet.id,
            event: outing.event,
            implementKg: outing.implementKg,
          ),
        ),
      );

  /// The athlete's training notes, most recently edited first. Lives off
  /// its own store, so a note keeps working whatever happens to the clips.
  Widget _notesSection(BuildContext context, String athlete) {
    return SliverToBoxAdapter(
      child: Consumer<NotesLibrary>(
        builder: (context, notes, _) {
          final mine = notes.notesFor(athlete);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeading(
                  'Training notes', mine.isEmpty ? null : '${mine.length}'),
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(
                    'Nothing written down yet. Notes are the place for '
                    'session plans, cues that worked, and pictures of a '
                    'position worth remembering.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              else
                for (final note in mine)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _NoteTile(
                      note: note,
                      onTap: () => _openNote(context, note),
                      onLongPress: () => _deleteNote(context, notes, note),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openNote(
                      context,
                      TrainingNote(
                        id: NotesLibrary.newNoteId(),
                        athlete: athlete,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    ),
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('New note'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Long-pressing a note deletes it, the way long-pressing a mark does —
  /// so a note written on the wrong athlete doesn't have to be opened to be
  /// got rid of.
  Future<void> _deleteNote(
      BuildContext context, NotesLibrary notes, TrainingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text(note.displayTitle),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await notes.remove(note.id);
  }

  void _openNote(BuildContext context, TrainingNote note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
  }

  Future<void> _editMark(
      BuildContext context, VideoLibrary library, ThrowMark mark) async {
    final edited = await showMarkEditor(context, existing: mark);
    if (edited != null) await library.updateMark(edited);
  }

  Future<void> _deleteMark(
      BuildContext context, VideoLibrary library, ThrowMark mark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this mark?'),
        content: Text('${formatDistance(mark.distance, mark.distanceUnit)} '
            '· ${shortThrowDate(mark.achievedOn)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await library.removeMark(mark.id);
  }

  void _openThrow(
      BuildContext context, ThrowVideo video, List<ThrowVideo> siblings) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(video: video, siblings: siblings),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label, [this.trailing]);

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// One meet they threw at: the series, where it placed them, and what the
/// day was like.
class _OutingTile extends StatelessWidget {
  const _OutingTile({required this.outing, required this.onTap});

  final MeetOuting outing;
  final VoidCallback onTap;

  /// '2nd of 12', or what happened instead. A field of one is not a
  /// competition, so it is not a placing either.
  String get _placing {
    final place = outing.place?.place;
    if (place == null) return outing.taken == 0 ? 'not thrown' : 'no mark';
    if (outing.fieldSize <= 1) return 'unopposed';
    return '${ordinalPlace(place)} of ${outing.fieldSize}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = eventColor(outing.event);
    final best = outing.best;
    final conditions = outing.meet.conditions;
    return Card(
      color: scheme.surfaceContainerHighest.withOpacity(0.45),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      outing.meet.name.isEmpty ? 'Meet' : outing.meet.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (outing.won) ...[
                    const FirstPlaceMedal(size: 13),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    _placing,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: outing.won ? accent : scheme.onSurfaceVariant,
                        fontWeight:
                            outing.won ? FontWeight.w700 : FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${shortThrowDate(outing.date)} · '
                      '${outing.event.label} · '
                      '${outing.implementSpec.weightLabel}'
                      '${outing.meet.venue.isEmpty ? '' : ' · ${outing.meet.venue}'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (best != null)
                    Text(
                      formatDistance(
                          best, outing.series.unitAt(outing.series.bestRound!)),
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600, color: accent),
                    ),
                ],
              ),
              if (outing.taken > 0) ...[
                const SizedBox(height: 8),
                _SeriesLine(outing: outing, accent: accent),
              ],
              if (conditions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (conditions.summary.isNotEmpty) conditions.summary,
                    if (conditions.note.isNotEmpty) conditions.note,
                  ].join(' · '),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The series as a results sheet writes it: every round in order, X for a
/// foul, – for a pass, and the one that counted in the event's color.
///
/// Written out rather than drawn as boxes: on a profile the question is
/// what the shape of the afternoon was, and six numbers in a row answer it
/// in a fraction of the space the competition screen needs for something
/// you also have to be able to hit with a thumb.
class _SeriesLine extends StatelessWidget {
  const _SeriesLine({required this.outing, required this.accent});

  final MeetOuting outing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = outing.entry;
    final rounds = <Widget>[];
    for (var round = 0; round < entry.attempts.length; round++) {
      final attempt = entry.attemptAt(round);
      final distance = outing.series.distanceAt(round);
      final (text, color) = switch (attempt?.kind) {
        null => ('·', scheme.onSurfaceVariant),
        AttemptKind.foul => ('X', scheme.error),
        AttemptKind.pass => ('–', scheme.onSurfaceVariant),
        AttemptKind.mark => distance == null
            ? ('?', scheme.onSurfaceVariant)
            : (
                formatDistance(distance, outing.series.unitAt(round))
                    .split(' ')
                    .first,
                round == outing.series.bestRound
                    ? accent
                    : scheme.onSurface.withOpacity(0.85)
              ),
      };
      if (rounds.isNotEmpty) {
        rounds.add(Text('  ·  ',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.outlineVariant)));
      }
      rounds.add(Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: round == outing.series.bestRound
                ? FontWeight.w700
                : FontWeight.w500),
      ));
    }
    return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center, children: rounds);
  }
}

/// One mark: what it was thrown with, how far it went, and the clip it came
/// out of — tapping opens that throw, which is the point of keeping the
/// video and the number together in the first place.
class _BestTile extends StatelessWidget {
  const _BestTile({
    required this.best,
    required this.season,
    required this.onTap,
  });

  final PersonalBest best;

  /// Every measured throw at this event and weight, oldest first. Drawn
  /// under the mark once there are two of them: a best is the high-water
  /// line and says nothing about the direction of travel, and an athlete
  /// two meters off theirs in June is either building or falling away.
  final List<ProgressionPoint> season;

  final VoidCallback onTap;

  /// What the season has moved, first mark to last. Not best to best: a
  /// best only ever goes up, so measuring against it would draw every
  /// athlete as improving.
  double get _moved => season.last.meters - season.first.meters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
      clipBehavior: Clip.antiAlias,
      shape: angularShape(14, side: const BorderSide(color: Color(0x66FFC94D))),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // A filmed best leads with the frame it came out of; one that
                  // was only written down leads with the medal, so the row
                  // still reads as an achievement rather than a missing image.
                  SizedBox(
                    width: 76,
                    height: 50,
                    child: best.isFilmed
                        ? ThrowThumbnail(best.video!, width: 76, height: 50)
                        : const Center(child: FirstPlaceMedal(size: 28)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            EventGlyph(best.event,
                                size: 16, color: eventColor(best.event)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(best.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                            // Said here rather than in the line below, which a
                            // long meet name and a big number leave no room in.
                            if (!best.isFilmed) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Not filmed',
                                child: Icon(Icons.videocam_off_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _footnote(best),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // No medal here: everything under this heading is one, and
                  // the icon only crowded the mark it was pointing at.
                  Text(
                    formatDistance(best.distance, best.unit),
                    style: const TextStyle(
                      color: personalBestGold,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (season.length > 1) ...[
                const SizedBox(height: 6),
                ProgressionChart(
                    points: season,
                    color: eventColor(best.event),
                    // The card's own unit: a best written '200-02.25' over
                    // a chart labeled in meters is one throw in two
                    // notations.
                    unit: best.unit,
                    height: 78),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    // Signed both ways, because a season that went
                    // backwards should say so.
                    '${_moved >= 0 ? '+' : '−'}'
                    '${formatDistance(_moved.abs(), best.unit)} '
                    'since ${shortThrowDate(season.first.on)} · '
                    '${season.length} measured',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// When it was thrown, and out of how many — a mark with one throw behind
  /// it is a first measurement rather than a season's work, and saying so
  /// is more honest than letting it read like one.
  String _footnote(PersonalBest best) {
    final when = shortThrowDate(best.setOn);
    return best.attempts == 1
        ? '$when · first mark'
        : '$when · best of ${best.attempts}';
  }
}

/// One mark, in the list of everything that was thrown but not filmed.
class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.mark,
    required this.isPersonalBest,
    required this.onTap,
    required this.onLongPress,
  });

  final ThrowMark mark;
  final bool isPersonalBest;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = mark.note.isEmpty
        ? shortThrowDate(mark.achievedOn)
        : '${shortThrowDate(mark.achievedOn)} · ${mark.note}';
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      clipBehavior: Clip.antiAlias,
      shape: angularShape(10),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              EventGlyph(mark.event, size: 18, color: eventColor(mark.event)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${mark.implementSpec.weightLabel} '
                      '${mark.event.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isPersonalBest) const FirstPlaceMedal(size: 16),
              const SizedBox(width: 6),
              Text(
                formatDistance(mark.distance, mark.distanceUnit),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isPersonalBest
                      ? personalBestGold
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One note in the list: what it is called, what it says next, and what is
/// in it — a picture count and a checklist tally, which are the two things
/// you want to know before opening it.
class _NoteTile extends StatelessWidget {
  const _NoteTile(
      {required this.note, required this.onTap, required this.onLongPress});

  final TrainingNote note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checklist = note.checklist;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      clipBehavior: Clip.antiAlias,
      shape: angularShape(10),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: Icon(Icons.sticky_note_2_outlined,
                    size: 18, color: theme.colorScheme.primary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      note.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (note.preview.isNotEmpty)
                      NoteRichText(
                        note.preview,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          shortThrowDate(note.updatedAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (note.pictureCount > 0) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.image_outlined,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('${note.pictureCount}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                        if (checklist.total > 0) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.checklist,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('${checklist.done}/${checklist.total}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMarks extends StatelessWidget {
  const _NoMarks({required this.onRecord});

  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No distances yet. Add how far a throw went from its long-press '
            'menu, or record a mark from a meet nobody filmed — the furthest '
            'at each implement becomes a best either way.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onRecord,
            icon: const Icon(Icons.emoji_events_outlined, size: 18),
            label: const Text('Record a mark'),
          ),
        ],
      ),
    );
  }
}

/// An athlete whose season is on a results sheet rather than a phone.
class _NoClips extends StatelessWidget {
  const _NoClips();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        'Nothing filmed yet. Import a clip from the library to break one '
        'down frame by frame.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _NoThrows extends StatelessWidget {
  const _NoThrows();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Nothing here any more — these throws have been deleted or '
          'tagged to someone else.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// The record under the name: the full name and school a coach filled in,
/// shown when they gave one so the heading's nickname still says who it is.
class _IdentityLine extends StatelessWidget {
  const _IdentityLine({required this.record, required this.filedAs});

  final AthleteRecord record;

  /// The library spelling, worth showing beside a nickname so the person
  /// tagging a clip knows which name the throws carry.
  final String filedAs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The full name is only news when it isn't already what the heading
    // shows; the same goes for a nickname sitting over the filed spelling.
    final shown = record.displayName;
    final parts = <String>[
      if (record.fullName.isNotEmpty && record.fullName != shown)
        record.fullName,
      if (record.school.isNotEmpty) record.school,
      if (record.nickname.trim().isNotEmpty && filedAs != shown)
        'filed as $filedAs',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(Icons.badge_outlined,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editing what a coach knows about an athlete that no throw records: a
/// nickname to show them by, and the full name and school a heat sheet is
/// matched against.
class _AthleteEditDialog extends StatefulWidget {
  const _AthleteEditDialog({required this.record});

  final AthleteRecord record;

  @override
  State<_AthleteEditDialog> createState() => _AthleteEditDialogState();
}

class _AthleteEditDialogState extends State<_AthleteEditDialog> {
  late final TextEditingController _nickname =
      TextEditingController(text: widget.record.nickname);
  late final TextEditingController _fullName =
      TextEditingController(text: widget.record.fullName);
  late final TextEditingController _school =
      TextEditingController(text: widget.record.school);

  @override
  void dispose() {
    _nickname.dispose();
    _fullName.dispose();
    _school.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit athlete'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filed as ${widget.record.name}. The throws stay tagged with '
              'that; a nickname only changes what is shown.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nickname,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                helperText: 'Shown instead of the filed name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                helperText: 'How a meet program prints them',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _school,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'School or club',
                helperText: 'Used to find them on a heat sheet',
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
          onPressed: () => Navigator.pop(
            context,
            widget.record.copyWith(
              nickname: _nickname.text.trim(),
              fullName: _fullName.text.trim(),
              school: _school.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
