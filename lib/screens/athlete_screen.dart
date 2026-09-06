import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/athlete_profile.dart';
import '../models/throw_video.dart';
import '../services/video_library.dart';
import '../widgets/angular.dart';
import '../widgets/event_glyph.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_actions.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'analysis_screen.dart';

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
  /// what you are looking at before scrolling.
  String _summary(AthleteProfile profile) {
    final count =
        '${profile.throws.length} throw${profile.throws.length == 1 ? '' : 's'}';
    if (profile.isEmpty) return count;
    final events = profile.events.length;
    final since = shortThrowDate(profile.firstThrewOn!);
    return '$count · $events event${events == 1 ? '' : 's'} · since $since';
  }

  Widget _body(
      BuildContext context, VideoLibrary library, AthleteProfile profile) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _SectionHeading('Personal bests')),
        if (profile.bests.isEmpty)
          const SliverToBoxAdapter(child: _NoMarks())
        else
          SliverList.separated(
            itemCount: profile.bests.length,
            separatorBuilder: (context, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _BestTile(
                best: profile.bests[index],
                onTap: () => _openThrow(
                    context, profile.bests[index].video, profile.throws),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: _SectionHeading(
              'Throws', '${profile.throws.length}'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
      ],
    );
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
              ThrowThumbnail(best.video, width: 76, height: 50),
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
                        Expanded(
                          child: Text(best.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
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

class _NoMarks extends StatelessWidget {
  const _NoMarks();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        'No distances recorded yet. Long-press a throw and add how far it '
        'went — the furthest at each implement becomes a best, and its clip '
        'wears the medal.',
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
