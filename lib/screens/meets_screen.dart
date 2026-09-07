import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meet.dart';
import '../services/meet_library.dart';
import '../services/video_library.dart';
import '../widgets/event_glyph.dart';
import '../widgets/mark_editor.dart';
import '../widgets/sector_art.dart';
import '../widgets/throw_card.dart';
import '../widgets/throw_picker.dart';
import 'meet_screen.dart';

/// The competitions, most recent first, and the way into the one happening
/// now.
///
/// Today's meet opens straight from the trophy rather than making the coach
/// pick it out of a list: between attempts there is time for one tap.
class MeetsScreen extends StatelessWidget {
  const MeetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MeetLibrary, VideoLibrary>(
      builder: (context, meets, library, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Meets'),
            actions: [
              IconButton(
                tooltip: 'Record a mark',
                icon: const Icon(Icons.straighten),
                onPressed: () async {
                  final mark = await showMarkEditor(context);
                  if (mark != null) await library.addMark(mark);
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: SectorBackdropPainter(
                        color: theme.colorScheme.primary),
                  ),
                ),
              ),
              if (meets.meets.isEmpty)
                _empty(context)
              else
                ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    for (final meet in meets.meets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MeetCard(
                          meet: meet,
                          onOpen: () => _open(context, meet),
                          onDelete: () => _confirmDelete(context, meets, meet),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('New meet'),
            onPressed: () => _start(context, meets),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThrowsGlyph(size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text('No meets yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Start one when you get to the track. Enter your throwers, '
              'then film an attempt or write down the mark — whichever you '
              'managed to catch.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, MeetLibrary meets) async {
    final meet = await showNewMeetDialog(context);
    if (meet == null || !context.mounted) return;
    await meets.save(meet);
    if (context.mounted) _open(context, meet);
  }

  void _open(BuildContext context, Meet meet) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MeetScreen(meetId: meet.id)),
      );

  Future<void> _confirmDelete(
      BuildContext context, MeetLibrary meets, Meet meet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${meet.name.isEmpty ? 'this meet' : meet.name}?'),
        content: const Text(
            'The series goes; the marks and clips it recorded stay in the '
            'library.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await meets.remove(meet.id);
  }
}

class _MeetCard extends StatelessWidget {
  const _MeetCard(
      {required this.meet, required this.onOpen, required this.onDelete});

  final Meet meet;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = {for (final entry in meet.entries) entry.event}.toList();
    final attempts =
        meet.entries.fold<int>(0, (sum, entry) => sum + entry.taken);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        onTap: onOpen,
        onLongPress: onDelete,
        title: Text(
          meet.name.isEmpty ? 'Meet' : meet.name,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${shortThrowDate(meet.date)} · '
          '${meet.entries.length} athlete${meet.entries.length == 1 ? '' : 's'}'
          ' · $attempts attempt${attempts == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: EventGlyph(event, size: 18, color: eventColor(event)),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
