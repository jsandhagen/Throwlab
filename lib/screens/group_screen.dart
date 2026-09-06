import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/throw_video.dart';
import '../services/video_library.dart';
import '../widgets/throw_actions.dart';
import '../widgets/throw_card.dart';
import 'analysis_screen.dart';

/// Everything under one library heading — an athlete, or an event — as a
/// grid of stills.
///
/// The home shelf shows the newest few and stops, which is what keeps it
/// short enough to scan; this is where the rest of them live, so nothing is
/// hidden by that.
class GroupScreen extends StatelessWidget {
  const GroupScreen({
    super.key,
    required this.title,
    required this.videoIds,
    required this.titleFor,
  });

  final String title;

  /// Ids rather than the throws themselves: a delete or a re-tag made from
  /// inside this screen then shows up here, instead of leaving a stale copy
  /// of the group on screen.
  final List<String> videoIds;

  /// How to label a card here — under an athlete their name is redundant.
  final String Function(ThrowVideo video) titleFor;

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoLibrary>(
      builder: (context, library, _) {
        final byId = {for (final video in library.videos) video.id: video};
        final videos = [
          for (final id in videoIds)
            if (byId.containsKey(id)) byId[id]!,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                Text(
                  '${videos.length} throw${videos.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          body: videos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nothing here any more — these throws have been '
                      'deleted or tagged to someone else.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    // Wider than tall like the frame itself, but with enough
                    // height left for the two lines that now sit on it.
                    childAspectRatio: 1.25,
                  ),
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return ThrowCard(
                      video: video,
                      title: titleFor(video),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnalysisScreen(
                              video: video, siblings: videos),
                        ),
                      ),
                      onLongPress: () => showThrowActions(context, video),
                    );
                  },
                ),
        );
      },
    );
  }
}
