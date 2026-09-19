import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/athlete_profile.dart';
import '../models/athlete_record.dart';
import '../models/meet.dart';
import '../models/meet_history.dart';
import '../models/season_averages.dart';
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
    // Read once and handed to both sections below: the averages are a
    // reading of the same meets the list underneath spells out.
    final outings = MeetOuting.forAthlete(
      profile.name,
      meetsOf(context)?.meets ?? const <Meet>[],
      library.results,
    );
    // The marks a meet hasn't already written out. A competition series is
    // spelled round by round in the section above, and the same throw
    // listed again underneath is the same throw twice — what is left is
    // what was thrown where no meet was keeping score.
    final loose = [
      for (final mark in profile.marks)
        if (!atMeet.contains(mark.id)) mark,
    ];
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
                  record: _progressionFor(profile, best, atMeet),
                  // A filmed best opens its clip; one that was only ever
                  // written down opens the thing it actually is, the entry.
                  onTap: () => best.isFilmed
                      ? _openThrow(context, best.video!, profile.throws)
                      : _editMark(context, library, best.result as ThrowMark),
                ),
              );
            },
          ),
        ..._averagesSection(context, outings),
        ..._meetsSection(context, outings),
        _notesSection(context, profile.name),
        if (loose.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeading('Marks', '${loose.length}'),
          ),
          SliverList.separated(
            itemCount: loose.length,
            separatorBuilder: (context, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final mark = loose[index];
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

  /// The record as it was set and reset: every throw of theirs that stood
  /// as the best at this event and weight on the day it was taken, oldest
  /// first, ending on the one that holds it now.
  ///
  /// Only those. A card under a heading that says PERSONAL BESTS is about
  /// the mark, and a scatter of every throw behind it was answering a
  /// different question — how the throwing is going — which the averages
  /// below answer properly, meet by meet and season by season. Here the
  /// line climbs, because that is what a record does.
  ///
  /// A mark that equals the best does not reset it, the way a record
  /// stands until it is beaten rather than matched — the same rule
  /// `personalBestIds` scores by.
  List<ProgressionPoint> _progressionFor(
      AthleteProfile profile, PersonalBest best, Set<String> atMeet) {
    final measured = [
      for (final result in profile.results)
        if (result.event == best.event &&
            result.implementKg == best.implementKg &&
            result.distance != null)
          result,
    ]..sort((a, b) {
        final byDate = a.displayDate.compareTo(b.displayDate);
        // Two on one day is a series, and nothing says which came first;
        // the id settles it so the staircase is drawn the same way twice.
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    final points = <ProgressionPoint>[];
    double? standing;
    for (final result in measured) {
      if (standing != null && result.distance! <= standing) continue;
      standing = result.distance;
      points.add(ProgressionPoint(
        on: result.displayDate,
        meters: result.distance!,
        // Still worth saying where it was set: a best thrown on a Tuesday
        // is a best nobody else saw.
        atMeet: atMeet.contains(result.id),
      ));
    }
    return points;
  }

  /// The ids of every mark and clip a meet has an attempt pointing at.
  Set<String> _meetResultIds(BuildContext context) => {
        for (final meet in meetsOf(context)?.meets ?? const <Meet>[])
          for (final entry in meet.entries)
            for (final attempt in entry.attempts)
              if (attempt?.resultId != null) attempt!.resultId!,
      };

  /// What the season averages, one card per thing they throw.
  ///
  /// A best says how far an athlete has thrown once. These say where the
  /// middle of their throwing sits and how much of it counts, which is the
  /// half of a season a coach can actually work on — and the half that
  /// moves first, in both directions.
  ///
  /// Read over everything on record rather than over a date range: the app
  /// has no season boundary anywhere else either, and the progression
  /// drawn under each best is the same span. A coach who wants last year
  /// left out is asking a different question than this answers.
  List<Widget> _averagesSection(
      BuildContext context, List<MeetOuting> outings) {
    // Nothing worth averaging anywhere in their history means no section at
    // all — rather than a heading and a season picker over an empty space.
    final ever = SeasonAverages.forSeason(outings);
    if (ever.every((reading) => reading.isEmpty)) return const [];
    return [
      SliverToBoxAdapter(
        child: _AveragesSection(
          outings: outings,
          seasons: SeasonAverages.seasonsOf(outings),
        ),
      ),
    ];
  }

  /// Their meets, most recent first: the series, where it placed, and what
  /// the day was like.
  ///
  /// The record book already holds the marks. What it does not hold is the
  /// afternoon they came out of — whether the big throw was the opener or
  /// the last one, what the field was, and whether it was into a headwind.
  /// A coach going into a championship is asking about that half of it.
  List<Widget> _meetsSection(BuildContext context, List<MeetOuting> outings) {
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
  const _SectionHeading(this.label, [this.trailing, this.action]);

  final String label;
  final String? trailing;

  /// A control belonging to the section, sat at the end of its heading —
  /// where it reads as governing everything under it rather than as part
  /// of the first card.
  final Widget? action;

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
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// The averages, the season they are taken over, and which way a meet is
/// read.
///
/// A career average is not what anybody means by one: two seasons ago
/// pulls this spring's number down, and a coach reading it in June is
/// asking about this spring. So the section opens on the most recent
/// season there is a competition in, and the picker in its heading reaches
/// the others — an athlete with only one season on record is not asked to
/// choose between a year and itself, and never sees it.
///
/// The season is not remembered between athletes on purpose: the default
/// is already the season being coached, and a picker left on 2025 from the
/// last profile would quietly answer a question about this one with last
/// year's numbers. Which way a meet is read *is* remembered, in
/// [_lineKey] — that is a preference about how a coach thinks rather than
/// about one athlete, and flipping it on every profile would be a chore.
class _AveragesSection extends StatefulWidget {
  const _AveragesSection({required this.outings, required this.seasons});

  final List<MeetOuting> outings;

  /// Every season there is a competition on record for, most recent first.
  final List<int> seasons;

  @override
  State<_AveragesSection> createState() => _AveragesSectionState();
}

class _AveragesSectionState extends State<_AveragesSection> {
  /// Whether a meet counts as its average or as its best, remembered
  /// across athletes the way the other view choices are.
  static const _lineKey = 'throwlab.meetLine';

  /// The season being shown, or null for every one of them.
  int? _season;

  MeetLine _line = MeetLine.average;

  @override
  void initState() {
    super.initState();
    _season = widget.seasons.length > 1 ? widget.seasons.first : null;
    _restoreLine();
  }

  Future<void> _restoreLine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final line = MeetLine.values.asNameMap()[prefs.getString(_lineKey)];
      if (line != null) setState(() => _line = line);
    } catch (_) {
      // Storage is allowed to fail; the average is a fine place to land.
    }
  }

  Future<void> _setLine(MeetLine line) async {
    setState(() => _line = line);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lineKey, line.name);
    } catch (_) {
      // Not worth telling anyone about: the card still changed.
    }
  }

  @override
  void didUpdateWidget(_AveragesSection old) {
    super.didUpdateWidget(old);
    // A mark recorded while this is open can add a season, or take the last
    // competition out of the one being shown. Fall back to the newest
    // rather than leave the picker naming a season with nothing in it.
    if (_season != null && !widget.seasons.contains(_season)) {
      _season = widget.seasons.isEmpty ? null : widget.seasons.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final averages = [
      for (final reading
          in SeasonAverages.forSeason(widget.outings, season: _season))
        if (!reading.isEmpty) reading,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          'Averages',
          null,
          widget.seasons.length < 2
              ? null
              : _SeasonPicker(
                  seasons: widget.seasons,
                  season: _season,
                  onChanged: (season) => setState(() => _season = season),
                ),
        ),
        if (averages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              // Said rather than shown as an empty card: the season has an
              // answer, and the answer is that there is not enough in it.
              'Nothing to average in $_season — an average wants two '
              'measured throws behind it.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final reading in averages)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _AveragesTile(
                averages: reading,
                line: _line,
                onLine: _setLine,
                // The seasons before this one, so the card can say what
                // the meets averaged then as well as now. Read whole
                // rather than through the picker — the comparison is the
                // one thing on the card the filter must not narrow.
                history: SeasonAverages.history(
                    widget.outings, reading.event, reading.implementKg),
              ),
            ),
      ],
    );
  }
}

/// Which season the averages are over: a year, or all of them.
///
/// A year rather than a season proper, which is the simplification
/// [SeasonAverages.seasonsOf] explains — it is exactly right for an outdoor
/// season and wrong for an indoor winter, and this is where it would be put
/// right.
class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.seasons,
    required this.season,
    required this.onChanged,
  });

  final List<int> seasons;
  final int? season;
  final ValueChanged<int?> onChanged;

  /// Stands in for 'every season' in the menu. A popup menu cannot carry a
  /// null value — it is what a dismissed menu returns — and no throw was
  /// ever taken in year nought.
  static const _every = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<int>(
      tooltip: 'Season',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      onSelected: (picked) => onChanged(picked == _every ? null : picked),
      itemBuilder: (context) => [
        for (final year in seasons)
          PopupMenuItem(
            value: year,
            child: Text('$year',
                style: TextStyle(
                    color: year == season ? scheme.primary : null,
                    fontWeight: year == season ? FontWeight.w700 : null)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _every,
          child: Text('Every season',
              style: TextStyle(
                  color: season == null ? scheme.primary : null,
                  fontWeight: season == null ? FontWeight.w700 : null)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 3, 2, 3),
        decoration: ShapeDecoration(
          shape: angularShape(8),
          color: scheme.surfaceContainerHighest.withOpacity(0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              season == null ? 'Every season' : '$season',
              style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w600),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// What a season of competitions averages at one event and weight.
///
/// One number, said once and said large, and a switch for which number it
/// is: what an athlete averages across every throw of a meet, or what the
/// best of each meet averages. Both are worth asking and they answer
/// different questions — see [MeetLine] — but set side by side as equals
/// they read as two answers to one, near enough alike that nothing about
/// them says which is which. So one leads, the line under it is the same
/// number meet by meet, the seasons under that are the same number year by
/// year, and the other is an aside.
class _AveragesTile extends StatelessWidget {
  const _AveragesTile({
    required this.averages,
    required this.line,
    required this.onLine,
    this.history = const [],
  });

  final SeasonAverages averages;

  /// Which way a meet is being read, and how to change it.
  final MeetLine line;
  final ValueChanged<MeetLine> onLine;

  /// The same reading for every season on record, most recent first.
  final List<SeasonAverages> history;

  bool get _byBest => line == MeetLine.best;

  /// What the big number was taken over, in the words a coach would use
  /// saying it out loud — and what it cost, which is half of what an
  /// average at a meet is worth knowing.
  String get _over {
    final meets = averages.meetsScored;
    final at = '$meets meet${meets == 1 ? '' : 's'}';
    // Kept short: the fouls and the passes are written on the same line,
    // and a phrase that reads well on its own ellipsizes beside them.
    return _byBest
        ? 'best of each of $at'
        : 'over ${averages.marks} throws at $at';
  }

  /// 'nothing fouled', or '3 of 10 fouled'. Null before anything has been
  /// thrown at a meet at all.
  String? get _fouled {
    if (averages.attempts == 0) return null;
    if (averages.fouls == 0) return 'nothing fouled';
    return '${averages.fouls} of ${averages.attempts} fouled';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = eventColor(averages.event);
    final season = averages.scoredMeets;
    final moved = averages.movement(line);
    final fouled = _fouled;
    final seasons = _seasons;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(0.45),
      clipBehavior: Clip.antiAlias,
      shape: angularShape(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EventGlyph(averages.event, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(averages.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                _LineToggle(line: line, onChanged: onLine, accent: accent),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _byBest ? 'AVERAGE BEST AT A MEET' : 'AVERAGE AT A MEET',
              style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 1),
            Text(
              formatDistance(averages.on(line)!, averages.unit),
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: accent),
            ),
            Row(
              children: [
                Flexible(
                  child: Text(
                    _over,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (fouled != null)
                  Text(
                    '  ·  $fouled',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: averages.fouls == 0
                            ? scheme.onSurfaceVariant
                            : scheme.error),
                  ),
                // A pass is not a foul and does not wear its color: it is
                // a round given up on purpose, usually by somebody whose
                // place is already safe.
                if (averages.passes > 0)
                  Text(
                    '  ·  ${averages.passes} passed',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            if (season.length > 1) ...[
              const SizedBox(height: 8),
              ProgressionChart(
                points: [
                  for (final meet in season)
                    ProgressionPoint(
                        on: meet.date,
                        meters: meetValue(meet, line)!,
                        atMeet: true),
                ],
                color: accent,
                unit: averages.unit,
                height: 70,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                  // The same number the figure above is, taken one meet at
                  // a time — which the switch in the header has named, so
                  // this only has to say what it did.
                  '${moved! >= 0 ? '+' : '−'}'
                  '${formatDistance(moved.abs(), averages.unit)} '
                  'since ${shortThrowDate(season.first.date)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            ..._asides(theme, scheme),
            if (seasons.length > 1) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
              const SizedBox(height: 8),
              Text(
                'SEASON BY SEASON',
                style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              _SeasonRows(
                seasons: seasons,
                showing: averages.season,
                line: line,
                accent: accent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The rest of the competition, set small and named in full.
  ///
  /// The other reading of the same meets, and the one throw a season is
  /// remembered by. They are the same kind of number as the figure above —
  /// a mean of throws in meters — so what keeps them from reading as rival
  /// answers is that they are plainly subordinate and say, in words, what
  /// they were taken over.
  List<Widget> _asides(ThemeData theme, ColorScheme scheme) {
    final other = averages
        .on(_byBest ? MeetLine.average : MeetLine.best);
    final best = averages.best;
    return [
      const SizedBox(height: 10),
      Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
      const SizedBox(height: 6),
      if (other != null)
        _Aside(
          label: _byBest ? 'Every throw averaged' : 'Best of each meet',
          value: formatDistance(other, averages.unit),
          over: _byBest
              ? '${averages.marks} throws'
              : '${averages.meetsScored} meets',
        ),
      if (best != null)
        _Aside(
          // The furthest of the season at a meet — not the personal best,
          // which is all-time and counts the training days too.
          label: 'Furthest at a meet',
          value: formatDistance(best, averages.unit),
          over: shortThrowDate(averages.bestOn!),
        ),
    ];
  }

  /// The seasons there is a competition average for, most recent first.
  List<SeasonAverages> get _seasons => [
        for (final season in history)
          if (season.averageMark != null) season,
      ];
}

/// Which way a meet is read on this card: as its average, or as its best.
///
/// Two words rather than an icon, because neither reading has a picture
/// anybody would recognize, and a card whose numbers change under a symbol
/// nobody can name is a card that looks broken.
class _LineToggle extends StatelessWidget {
  const _LineToggle({
    required this.line,
    required this.onChanged,
    required this.accent,
  });

  final MeetLine line;
  final ValueChanged<MeetLine> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: ShapeDecoration(
        shape: angularShape(8),
        color: scheme.surfaceContainerHighest.withOpacity(0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in MeetLine.values)
            _half(context, option, option == MeetLine.average ? 'Avg' : 'Best'),
        ],
      ),
    );
  }

  Widget _half(BuildContext context, MeetLine option, String label) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = option == line;
    return Material(
      color: on ? accent.withOpacity(0.22) : Colors.transparent,
      shape: angularShape(8),
      child: InkWell(
        onTap: on ? null : () => onChanged(option),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: on ? accent : scheme.onSurfaceVariant,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

/// One of the numbers the card does not lead with: what it is in words,
/// what it comes to, and what it was taken over.
class _Aside extends StatelessWidget {
  const _Aside({
    required this.label,
    required this.value,
    required this.over,
  });

  final String label;
  final String value;
  final String over;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          // Wide enough for a date carrying its year — '20 Sep 2025' —
          // since a season on record long enough to be worth comparing is
          // one whose dates need saying in full.
          SizedBox(
            width: 88,
            child: Text(
              over,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the meets came to, a season at a time — the card's chart carried
/// up a level, and read the same way it is.
///
/// The chart above it draws the meets inside one season, which is the
/// question a coach asks in June. This is the one they ask in January: is
/// the whole thing further along than it was last year. Rows rather than a
/// line, because a season is one number and there are rarely more than
/// three or four of them — a line drawn through four points a year apart
/// invents a shape between them that nobody threw.
///
/// What is drawn is the *change*, not the mark. A bar for a 48 m average
/// beside one for a 52 m average has to start somewhere, and anywhere but
/// zero draws a seven per cent season as a fivefold one — while zero draws
/// two bars of near enough the same length, which says nothing at all. The
/// difference between the seasons has a real zero, so that is what gets the
/// bar: how far it moved, and which way.
class _SeasonRows extends StatelessWidget {
  const _SeasonRows({
    required this.seasons,
    required this.showing,
    required this.line,
    required this.accent,
  });

  /// Most recent first, each with a competition average.
  final List<SeasonAverages> seasons;

  /// The season the rest of the card is filtered to, picked out here so the
  /// figures above can be found in the history they came from. Null when
  /// the card is showing every season at once, and then no row is the one
  /// being shown.
  final int? showing;

  /// Which way a meet is read, the same as everything above.
  final MeetLine line;

  final Color accent;

  /// What each season moved from the one before it. The list runs newest
  /// first, so a season's predecessor is the row underneath; the oldest has
  /// nothing behind it and moved from nothing.
  List<double?> get _moves => [
        for (var i = 0; i < seasons.length; i++)
          i + 1 < seasons.length
              ? seasons[i].on(line)! - seasons[i + 1].on(line)!
              : null,
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final moves = _moves;
    // The biggest move sets the scale, so the bars are read against each
    // other and a season that barely moved draws as barely moving.
    final widest = moves.fold<double>(
        0, (most, move) => math.max(most, move == null ? 0 : move.abs()));

    return Column(
      children: [
        for (var i = 0; i < seasons.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _row(theme, scheme, seasons[i], moves[i], widest),
          ),
      ],
    );
  }

  Widget _row(ThemeData theme, ColorScheme scheme, SeasonAverages season,
      double? moved, double widest) {
    final mine = season.season == showing;
    final unit = season.unit;
    // Down is the app's one red: the same one a foul wears, for the same
    // reason — it is the thing a coach is looking for.
    final tint = moved == null || moved >= 0 ? accent : scheme.error;
    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(
            '${season.season}',
            style: theme.textTheme.labelMedium?.copyWith(
                color: mine ? accent : scheme.onSurfaceVariant,
                fontWeight: mine ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
        SizedBox(
          width: 82,
          child: Text(
            formatDistance(season.on(line)!, unit),
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: mine ? scheme.onSurface : scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: moved == null || widest == 0
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    // Never nothing: a season that moved a centimeter
                    // moved, and a bar of no width says it didn't.
                    widthFactor: (moved.abs() / widest).clamp(0.05, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: tint.withOpacity(mine ? 0.9 : 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            moved == null
                ? ''
                : '${moved >= 0 ? '+' : '−'}${formatDistance(moved.abs(), unit)}',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
                color: moved == null || moved >= 0
                    ? scheme.onSurfaceVariant
                    : scheme.error),
          ),
        ),
      ],
    );
  }
}

/// One meet they threw at: the series, where it placed them, and what the
/// day was like.
class _OutingTile extends StatelessWidget {
  const _OutingTile({required this.outing, required this.onTap});

  final MeetOuting outing;
  final VoidCallback onTap;

  /// What the afternoon came to under the series it came out of —
  /// 'averaged 52.44 m from 4 · 2 fouls'.
  ///
  /// The number above is the throw they were placed on, which is the one
  /// the meet cared about. This is the one the next meet is worked on:
  /// six throws around 52 is a different competition from one 54 and five
  /// nowhere, and the series alone makes that a thing to be read off rather
  /// than a thing that is said.
  String? get _averaged {
    final average = outing.average;
    // Nothing to average until there are two of them: the series is
    // written out directly above, so one mark and its fouls would be the
    // same line twice.
    if (average == null || outing.legalMarks < 2) return null;
    final fouls = outing.fouls;
    return [
      'averaged ${formatDistance(average, outing.unit)} '
          'from ${outing.legalMarks}',
      if (fouls > 0) '$fouls foul${fouls == 1 ? '' : 's'}',
    ].join(' · ');
  }

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
                    const PersonalBestMedal(size: 13),
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
              if (_averaged != null) ...[
                const SizedBox(height: 4),
                Text(
                  _averaged!,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
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
    required this.record,
    required this.onTap,
  });

  final PersonalBest best;

  /// The mark's own history, oldest first: every throw that stood as the
  /// best when it was taken. Drawn under it once there are two of them —
  /// one is a first measurement, and a line needs somewhere to have come
  /// from.
  final List<ProgressionPoint> record;

  final VoidCallback onTap;

  /// How far the mark has come since the first one they had. It only ever
  /// goes up, which is what a record does; how the throwing is *going* is
  /// the averages' question, and they answer it meet by meet.
  double get _moved => record.last.meters - record.first.meters;

  /// How many times it was beaten to get here.
  String get _broken {
    final times = record.length - 1;
    return times == 1 ? 'broken once' : 'broken $times times';
  }

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
                        : const Center(child: PersonalBestMedal(size: 28)),
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
              if (record.length > 1) ...[
                const SizedBox(height: 6),
                ProgressionChart(
                    points: record,
                    color: eventColor(best.event),
                    // The card's own unit: a best written '200-02.25' over
                    // a chart labeled in meters is one throw in two
                    // notations.
                    unit: best.unit,
                    height: 78),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    // Never signed: this line is the record's own climb,
                    // and a record that came down is one nobody kept.
                    '+${formatDistance(_moved, best.unit)} '
                    'since ${shortThrowDate(record.first.on)} · $_broken',
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
              if (isPersonalBest) const PersonalBestMedal(size: 16),
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
  late final TextEditingController _firstName =
      TextEditingController(text: widget.record.firstName);
  late final TextEditingController _lastName =
      TextEditingController(text: widget.record.lastName);
  late final TextEditingController _school =
      TextEditingController(text: widget.record.school);

  @override
  void dispose() {
    _nickname.dispose();
    _firstName.dispose();
    _lastName.dispose();
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
            // Two fields, because which half is the family name is not
            // something to be worked out from one. 'Anna Sofia' is two
            // given names, and everything that shortens a name to what a
            // board has room for was drawing her across the sector as
            // 'Sofia'.
            TextField(
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'First name',
                helperText: 'As a meet program prints it',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Last name',
                helperText: 'What a board and a sector call them',
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
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              school: _school.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
