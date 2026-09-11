import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/meet.dart';
import '../models/meet_board.dart';
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
import '../widgets/sector_board.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'analysis_screen.dart';
import 'meet_screen.dart';

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
    this.shareResults,
  });

  final String meetId;

  /// Which competition of the meet this is — the event and the weight
  /// together, since those are what put athletes in the same contest.
  final ThrowEvent event;
  final double implementKg;

  /// Overrides how a round is filmed; the camera when null.
  final AttemptFilmer? filmAttempt;

  /// Overrides how the results sheet is written; the file system when null.
  final ResultsSharer? shareResults;

  @override
  State<MeetEventScreen> createState() => _MeetEventScreenState();
}

/// Which way the event is being read: what is happening right now, the
/// order it is thrown in, or the table it all adds up to.
enum _MeetView { live, series, standings }

class _MeetEventScreenState extends State<MeetEventScreen> {
  /// Which view they last left an event on. A coach who works out of
  /// the series list all afternoon shouldn't be put back on the board every
  /// time they walk to the next ring.
  static const _viewKey = 'throwlab.meetView';

  _MeetView _view = _MeetView.live;

  @override
  void initState() {
    super.initState();
    _restoreView();
  }

  Future<void> _restoreView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final view = _MeetView.values.asNameMap()[prefs.getString(_viewKey)];
      if (view != null) setState(() => _view = view);
    } catch (_) {
      // Storage is allowed to fail; the live card is a fine place to land.
    }
  }

  Future<void> _setView(_MeetView view) async {
    setState(() => _view = view);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewKey, view.name);
    } catch (_) {
      // Not worth telling anyone about: the view still changed.
    }
  }

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
        final flight =
            MeetFlight(competition, rounds: meet.rounds, standings: standings);

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
            actions: [
              IconButton(
                tooltip: 'Results sheet',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                // This event's sheet, not the meet's: a coach standing at
                // the discus has no use for the javelin's pages.
                onPressed: () => offerResultsSheet(context,
                    meet: meet,
                    results: library.results,
                    only: competition,
                    sharer: widget.shareResults),
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
              if (competition.entries.isEmpty)
                _empty(context)
              else
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: AngularSegmentedBar<_MeetView>(
                        value: _view,
                        onChanged: _setView,
                        segments: [
                          AngularSegment(
                              value: _MeetView.live,
                              // Drawn rather than borrowed: the Material
                              // set has no mark for a throwing sector, and
                              // every other sector in the app is drawn too.
                              glyph: (color) => _SectorGlyph(color: color),
                              label: 'Live'),
                          const AngularSegment(
                              value: _MeetView.series,
                              icon: Icons.format_list_numbered,
                              label: 'Series'),
                          const AngularSegment(
                              value: _MeetView.standings,
                              icon: Icons.emoji_events_outlined,
                              label: 'Standings'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: switch (_view) {
                        _MeetView.series => _seriesList(meet, meets, library,
                            competition, standings, flight),
                        _MeetView.live => _liveView(meet, standings, flight),
                        _MeetView.standings => _standingsList(meet, standings),
                      },
                    ),
                  ],
                ),
            ],
          ),
          // Not on the live card: that card ends in the button for the
          // mark about to be called out, and a field is not what a coach is
          // adding to between attempts. The field lives one tab across.
          floatingActionButton: _view == _MeetView.live
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add athlete'),
                  onPressed: () => _addEntry(meets, library, meet),
                ),
        );
      },
    );
  }

  /// The field in the order it throws, which is the order a coach's eye
  /// goes down the list in as the round works through, under a bar saying
  /// where the round has got to.
  Widget _seriesList(Meet meet, MeetLibrary meets, VideoLibrary library,
      MeetCompetition competition, MeetStandings standings, MeetFlight flight) {
    final field = competition.entries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        _FlightBar(flight: flight, standings: standings),
        const SizedBox(height: 12),
        for (var i = 0; i < field.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EntryCard(
              meet: meet,
              entry: field[i],
              position: i + 1,
              place: standings.placeOf(field[i].id),
              upIn: flight.throwsUntil(field[i].id),
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

  /// The event as it stands right now: where the round has got to, the
  /// competition drawn on the sector, and the mark for whoever is in the
  /// circle, entered without leaving the screen.
  ///
  /// One card rather than three. Between attempts a coach looks down once,
  /// and everything they look down for is the same thing — who is up, what
  /// it will take, and the number they are about to write.
  Widget _liveView(Meet meet, MeetStandings standings, MeetFlight flight) {
    final board = MeetBoard(standings, inTheCircle: flight.inTheCircle);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final library = context.read<VideoLibrary>();
    final meets = context.read<MeetLibrary>();
    // Whoever throws next, named or not: a competition of one has no flight
    // to call, but it still has a mark to write down.
    final up = flight.next;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Card(
          // Opaque, unlike every other card in the app: the screen's own
          // sector art runs behind this one, and two sectors drawn over
          // each other at different angles is a picture of nothing.
          color: _opaque(theme),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _FlightBody(flight: flight, standings: standings),
                ),
                const SizedBox(height: 12),
                // The field itself, set into the card rather than run on
                // from the header: a picture of a sector and a list of
                // names are two different things to read, and the edge
                // between them is what says so.
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: scheme.outlineVariant.withOpacity(0.4)),
                  ),
                  child: board.isEmpty
                      ? _NothingOnTheBoard(event: widget.event)
                      : AspectRatio(
                          // Wider than it is tall, and that is geometry
                          // rather than taste: the sector opens at 34.92°,
                          // so a tall box runs the two lines together into
                          // a point inside the card — drawing a circle at
                          // the near edge of a band that starts forty
                          // meters out from one.
                          aspectRatio: 4 / 3,
                          child: SectorBoard(
                            board: board,
                            event: widget.event,
                            accent: eventColor(widget.event),
                            backdrop: scheme.surface,
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _BoardCaption(standings: standings, flight: flight),
                ),
                if (up != null) ...[
                  const SizedBox(height: 8),
                  Divider(
                      height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
                  // The athlete in the circle, on their own card from the
                  // series — same rounds, same two buttons, same place to
                  // put a thumb. A screen that enters a mark one way in one
                  // view and another way in another is two screens.
                  _EntryCard(
                    meet: meet,
                    entry: up,
                    position: standings.competition.entries.indexOf(up) + 1,
                    place: standings.placeOf(up.id),
                    // Not marked 'up': the row above the board has just
                    // said so, and this card is under it because of it.
                    upIn: null,
                    embedded: true,
                    closedFrom: !meet.hasFinal || standings.throwsInFinal(up.id)
                        ? null
                        : meet.prelimRounds,
                    series: MeetSeries(up, library.results),
                    library: library,
                    onEnter: (round) => _enter(meet, up, round),
                    onFilm: (round) => _film(meet, up, round),
                    onOpen: _openThrow,
                    onRemove: () => _removeEntry(meets, meet, up),
                    onMove: (by) => _move(meet, standings.competition.entries,
                        standings.competition.entries.indexOf(up), by),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The card color the rest of the app uses, flattened onto the surface.
  ///
  /// Every other card is translucent so the sector backdrop shows through
  /// it, which is the app's texture. Blending it here rather than picking a
  /// new color keeps this card exactly the tone of all the others while
  /// letting nothing through it.
  Color _opaque(ThemeData theme) => Color.alphaBlend(
      theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      theme.colorScheme.surface);

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
      // The rest of the field is recorded, not collected — the card offers
      // them no Film button, and neither should the sheet behind it.
      canFilm: entry.tracked,
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

/// The sector, small enough to sit in a segment: two lines opening from a
/// circle, with one distance arc across them.
class _SectorGlyph extends StatelessWidget {
  const _SectorGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(15, 15), painter: _SectorGlyphPainter(color));
}

class _SectorGlyphPainter extends CustomPainter {
  const _SectorGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Wider than the real 34.92° — at fifteen pixels an honest sector is a
    // pair of parallel lines, and the mark has to read as a wedge.
    const half = 0.52;
    final apex = Offset(size.width / 2, size.height * 0.94);
    final reach = size.height * 0.88;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final sign in [-1, 1]) {
      final angle = -math.pi / 2 + sign * half;
      canvas.drawLine(
          apex, apex + Offset(math.cos(angle), math.sin(angle)) * reach, paint);
    }
    canvas.drawArc(
      Rect.fromCircle(center: apex, radius: reach * 0.72),
      -math.pi / 2 - half,
      2 * half,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SectorGlyphPainter old) => old.color != color;
}

/// What the board adds up to for the athlete about to throw.
///
/// The lines say where the marks are; this says what to do about them — the
/// sentence a coach would shout across the infield if they could.
class _BoardCaption extends StatelessWidget {
  const _BoardCaption({required this.standings, required this.flight});

  final MeetStandings standings;
  final MeetFlight flight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = eventColor(standings.competition.event);
    final leader = standings.places.isEmpty ? null : standings.places.first;
    final up = flight.inTheCircle;
    final mine = up == null ? null : standings.placeOf(up.id);

    final lines = <(String, Color)>[];
    if (up == null || mine == null) {
      // Nobody in the circle: the round is over, or the competition is.
      if (leader != null && leader.best != null) {
        lines.add((
          '${_named(leader.entry)} '
              '${flight.finished ? 'won it on' : 'leads on'} '
              '${formatDistance(leader.best!, _unitOf(leader))}',
          scheme.onSurface,
        ));
      }
    } else {
      // The bar above has already said who is up. This says what the throw
      // has to do, which is the only thing the lines don't say themselves.
      // Nothing at all when they are already leading it: the row above
      // names them and the gold line on the board is theirs.
      final toLead = standings.neededFor(up.id, place: 1);
      if (toLead != null) {
        lines.add((
          '${formatDistance(toLead, _unitOf(mine))} takes the lead',
          accent,
        ));
      }
    }

    // And what the coach's own best-placed athlete is short of, which is
    // usually why the board was opened — said with their name on it, since
    // the athlete in the circle is as often as not somebody else's.
    if (!standings.cutMade) {
      for (final place in standings.places) {
        if (!place.entry.tracked) continue;
        final needed = standings.neededToQualify(place.entry.id);
        if (needed == null) continue;
        lines.add((
          '${_named(place.entry)} needs '
              '${formatDistance(needed, _unitOf(place))} to make the final',
          scheme.primary,
        ));
        break;
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 12 : 2),
            child: Text(
              lines[i].$1,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: lines[i].$2, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  static String _named(MeetEntry entry) =>
      entry.athlete.isEmpty ? 'Unassigned' : entry.athlete;

  /// The unit this athlete's competition is being measured in — theirs when
  /// they have a mark, meters until they do.
  static DistanceUnit _unitOf(MeetPlace place) => place.series.bestRound == null
      ? DistanceUnit.meters
      : place.series.unitAt(place.series.bestRound!);
}

/// Where the round has got to: how far through it the field is, and the
/// three athletes an infield calls out.
///
/// This is what a coach looks up for between attempts, and until now it had
/// to be counted off the cards by eye. It keeps itself right as marks go in
/// because it is worked out from the series rather than tracked alongside
/// them — nobody standing at a sector has a hand free to tell an app whose
/// turn it is.
class _FlightBody extends StatelessWidget {
  const _FlightBody({
    required this.flight,
    required this.standings,
    this.showLeader = false,
  });

  final MeetFlight flight;
  final MeetStandings standings;

  /// Whether to name whoever is winning. The live card draws them as the
  /// gold line across its sector instead, and saying it twice on one card
  /// is saying it once too often.
  final bool showLeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = eventColor(flight.competition.event);
    // The three an infield calls: up, on deck, in the hole.
    final calling = <(String, MeetEntry)>[
      if (flight.inTheCircle != null) ('up', flight.inTheCircle!),
      if (flight.onDeck != null) ('on deck', flight.onDeck!),
      if (flight.inTheHole != null) ('in the hole', flight.inTheHole!),
    ];
    final front = !flight.hasOrder || standings.places.isEmpty
        ? null
        : standings.places.first;
    // The leader is worth a line of their own only when they are not
    // already on one.
    final leader = !showLeader ||
            front == null ||
            calling.any((who) => who.$2.id == front.entry.id)
        ? null
        : front;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                flight.label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1),
              ),
            ),
            Text(
              flight.finished
                  ? 'all in'
                  : '${flight.thrown} of ${flight.fieldSize} thrown',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: flight.fieldSize == 0 ? 0 : flight.thrown / flight.fieldSize,
            minHeight: 5,
            color: accent,
            backgroundColor: scheme.outlineVariant.withOpacity(0.5),
          ),
        ),
        for (var i = 0; i < calling.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 10 : 4),
            child: _WhoRow(
              label: calling[i].$1,
              entry: calling[i].$2,
              place: standings.placeOf(calling[i].$2.id),
              color: i == 0 ? accent : scheme.onSurfaceVariant,
              lead: i == 0,
            ),
          ),
        if (leader != null) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.4)),
          const SizedBox(height: 8),
          _WhoRow(
            // A competition that is over has a winner; one still being
            // thrown has somebody in front, which is not the same thing and
            // shouldn't be written as though it were.
            label: flight.finished ? 'won by' : 'leading',
            entry: leader.entry,
            place: leader,
            color: scheme.onSurfaceVariant,
            lead: false,
            icon: Icons.emoji_events_outlined,
          ),
        ],
      ],
    );
  }
}

/// The same, on a card of its own, over the field in the series view.
///
/// It scrolls with the field rather than being pinned above it: the flight
/// order means a coach is scrolling to their own athlete anyway, and the
/// 'up' on the cards carries the same answer the whole way down.
class _FlightBar extends StatelessWidget {
  const _FlightBar({required this.flight, required this.standings});

  final MeetFlight flight;
  final MeetStandings standings;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.45),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: _FlightBody(
              flight: flight, standings: standings, showLeader: true),
        ),
      );
}

/// Nothing has been thrown yet, in the space the board will take.
class _NothingOnTheBoard extends StatelessWidget {
  const _NothingOnTheBoard({required this.event});

  final ThrowEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          EventGlyph(event, size: 26, color: eventColor(event)),
          const SizedBox(height: 12),
          Text(
            'Nothing on the board yet.\n'
            'The first mark of the competition draws the first line.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One named athlete in the bar: what they are to this round, who they are,
/// and what they are standing on.
class _WhoRow extends StatelessWidget {
  const _WhoRow({
    required this.label,
    required this.entry,
    required this.place,
    required this.color,
    required this.lead,
    this.icon,
  });

  final String label;
  final MeetEntry entry;
  final MeetPlace? place;
  final Color color;

  /// The one the coach is about to write a mark for, set in the event's
  /// color so it is found without reading.
  final bool lead;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = place?.best;
    final bestRound = place?.series.bestRound;
    return Row(
      children: [
        SizedBox(
          // Wide enough for 'in the hole', so the three names line up.
          width: 74,
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: lead ? FontWeight.w700 : FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Text(
            entry.athlete.isEmpty ? 'Unassigned' : entry.athlete,
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: lead ? FontWeight.w600 : FontWeight.w500,
                color: entry.tracked ? null : scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (best != null)
          Text(
            formatDistance(best, place!.series.unitAt(bestRound!)),
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: lead ? scheme.onSurface : scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// One athlete's competition: who they are, where they stand, and the two
/// buttons worth having on a phone held at chest height, over the series
/// underneath them.
///
/// Two rows, and the split is what each row is for. The top one answers
/// *who and how are they doing* — the name, the place, the mark they are
/// standing on — and carries the camera and the ruler, because those are
/// the only two things a coach does here. The bottom one is the series: six
/// boxes across the full width of the card, big enough to read at arm's
/// length and to hit without looking down.
///
/// It was three rows once, with the buttons on a line of their own, and one
/// row after that with no room for them. Two is where a field of a dozen
/// fits on a screen and nothing a coach reaches for has been taken away.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.meet,
    required this.entry,
    required this.position,
    required this.place,
    required this.upIn,
    this.embedded = false,
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

  /// Where they stand in the competition, or null before they have a mark
  /// on the board.
  final MeetPlace? place;

  /// How many throws until they are up: 0 in the circle, null otherwise —
  /// the card marks the athlete about to throw and leaves the rest of the
  /// order to the flight numbers and the bar above the field.
  final int? upIn;

  /// Drawn without its card, for somewhere that is already one — the live
  /// card puts the athlete in the circle at the bottom of itself, and a
  /// card inside a card reads as a mistake.
  final bool embedded;

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

  /// Whether there is a round left for the buttons to open.
  bool get _hasRoundLeft =>
      entry.nextRound < meet.rounds &&
      (closedFrom == null || entry.nextRound < closedFrom!);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = eventColor(entry.event);
    if (embedded) return _body(theme, accent);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      margin: EdgeInsets.zero,
      // The athlete in the circle is edged in the event's color, so a coach
      // looking down at the phone finds the row they are about to write on
      // without reading a name.
      shape: upIn == 0
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: accent.withOpacity(0.8), width: 1.5),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: _body(theme, accent),
    );
  }

  Widget _body(ThemeData theme, Color accent) => Padding(
        // Embedded, the card around it has already paid for the margin —
        // so it lines its name up with the header above rather than
        // stepping in from it.
        padding: embedded
            ? const EdgeInsets.fromLTRB(4, 6, 0, 0)
            : const EdgeInsets.fromLTRB(10, 4, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _position(theme),
                Expanded(child: _name(theme, accent)),
                _placeChip(theme),
                const SizedBox(width: 6),
                _placeAndBest(theme, accent),
                if (_hasRoundLeft) ...[
                  // Nothing is filmed for the rest of the field: a clip has
                  // to land in the library under somebody's name, and these
                  // are not the coach's athletes to keep.
                  if (entry.tracked)
                    _round(
                      theme,
                      icon: Icons.videocam_outlined,
                      tooltip: 'Film the next',
                      color: accent,
                      onPressed: () => onFilm(entry.nextRound),
                    ),
                  _round(
                    theme,
                    icon: Icons.straighten,
                    tooltip: 'Write the next mark down',
                    color: theme.colorScheme.onSurface,
                    filled: true,
                    onPressed: () => onEnter(entry.nextRound),
                  ),
                ] else
                  Padding(
                    // Cut, with nothing left to fill in behind them: there
                    // is no round for a button to open.
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'out',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                _menu(),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _boxes(accent),
            ),
          ],
        ),
      );

  /// Where they are in the flight: the number a coach counts down to work
  /// out how long they have before their athlete is in the circle.
  Widget _position(ThemeData theme) => SizedBox(
        width: 18,
        child: Text(
          '$position',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  /// Who they are. In the event's color when they are the one in the
  /// circle, which costs nothing across a crowded row — the word 'up'
  /// would have come off somebody's surname.
  Widget _name(ThemeData theme, Color accent) => Text(
        entry.athlete.isEmpty ? 'Unassigned' : entry.athlete,
        style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: upIn == 0
                ? accent
                // The rest of the field sits back a shade from the athletes
                // the coach is here for.
                : entry.tracked
                    ? null
                    : theme.colorScheme.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  /// Where they stand. Live on every card: a place that only exists on
  /// another tab is one a coach has to leave the competition to read.
  Widget _placeChip(ThemeData theme) {
    final standing = place?.best == null ? null : place!.place;
    if (standing == null) return const SizedBox.shrink();
    return Text(
      ordinalPlace(standing),
      style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: standing == 1 ? FontWeight.w700 : FontWeight.w500),
    );
  }

  /// What they are standing on, and whether it is the furthest they have
  /// ever thrown. No word for it: this is the only distance on the row, and
  /// the boxes underneath say which throw it came out of.
  Widget _placeAndBest(ThemeData theme, Color accent) {
    final best = series.best;
    if (best == null) return const SizedBox.shrink();
    final bestRound = series.bestRound!;
    // Null for the rest of the field, whose distances live on the attempt
    // and never reach the record book — so they hold no bests either.
    final bestResult = series.resultAt(bestRound);
    final isPb = bestResult != null && library.isPersonalBest(bestResult);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPb) ...[
          const FirstPlaceMedal(size: 13),
          const SizedBox(width: 4),
        ],
        Text(
          formatDistance(best, series.unitAt(bestRound)),
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700, color: accent),
        ),
      ],
    );
  }

  /// One of the two buttons: a target big enough to hit without looking
  /// down, and small enough that both fit beside a name.
  Widget _round(
    ThemeData theme, {
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
    bool filled = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 20),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
          // Tonal for the ruler, the way every other Mark button in the app
          // is; plain for the camera, so the pair reads as one action and
          // one shortcut rather than as two of equal weight.
          style: IconButton.styleFrom(
            foregroundColor: color,
            backgroundColor:
                filled ? theme.colorScheme.surfaceContainerHighest : null,
            shape: const CircleBorder(),
          ),
          onPressed: onPressed,
        ),
      );

  Widget _boxes(Color accent) => Row(
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
                unit: series.unitAt(round),
                filmed: series.filmedAt(round),
                isBest: round == series.bestRound,
                onTap: () => onEnter(round),
                onLongPress: () {
                  final result = series.resultAt(round);
                  if (result is ThrowVideo) onOpen(result);
                },
              ),
            ),
          ],
        ],
      );

  Widget _menu() => PopupMenuButton<String>(
        tooltip: 'Order and entry',
        icon: const Icon(Icons.more_horiz, size: 18),
        padding: EdgeInsets.zero,
        iconSize: 18,
        constraints: const BoxConstraints(minWidth: 180),
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
      );
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
            height: 36,
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
                  top: 7,
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
