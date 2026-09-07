import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/athlete_profile.dart';
import '../models/throw_event.dart';
import '../models/throw_mark.dart';
import '../models/throw_video.dart';
import '../models/training_note.dart';
import '../services/notes_library.dart';
import '../services/video_library.dart';
import '../widgets/angular.dart';
import '../widgets/event_glyph.dart';
import '../widgets/gold.dart';
import '../widgets/mark_editor.dart';
import '../widgets/note_text.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_actions.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'analysis_screen.dart';
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
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name),
                Text(
                  _summary(profile),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: [
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

  Widget _body(
      BuildContext context, VideoLibrary library, AthleteProfile profile) {
    return CustomScrollView(
      slivers: [
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
                  // A filmed best opens its clip; one that was only ever
                  // written down opens the thing it actually is, the entry.
                  onTap: () => best.isFilmed
                      ? _openThrow(context, best.video!, profile.throws)
                      : _editMark(
                          context, library, best.result as ThrowMark),
                ),
              );
            },
          ),
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
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              else
                for (final note in mine)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _NoteTile(
                      note: note,
                      onTap: () => _openNote(context, note),
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

/// One mark: what it was thrown with, how far it went, and the clip it came
/// out of — tapping opens that throw, which is the point of keeping the
/// video and the number together in the first place.
class _BestTile extends StatelessWidget {
  const _BestTile({required this.best, required this.onTap});

  final PersonalBest best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
      clipBehavior: Clip.antiAlias,
      shape: angularShape(14,
          side: const BorderSide(color: Color(0x66FFC94D))),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
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
              EventGlyph(mark.event,
                  size: 18, color: eventColor(mark.event)),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
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
  const _NoteTile({required this.note, required this.onTap});

  final TrainingNote note;
  final VoidCallback onTap;

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
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
                        ],
                        if (checklist.total > 0) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.checklist,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('${checklist.done}/${checklist.total}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
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
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
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
