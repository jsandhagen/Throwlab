import 'package:flutter/material.dart';

import '../models/throw_video.dart';
import 'throw_picker.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2 Sep", or "2 Sep 2025" once the year stops being obvious. A card has
/// room for when a throw happened, not for a timestamp — the full one is
/// still on the throw itself.
String shortThrowDate(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final date = '${local.day} ${_months[local.month - 1]}';
  return local.year == today.year ? date : '$date ${local.year}';
}

/// A throw as a card: the still first, the words under it.
///
/// The library used to be text rows with a 72×48 stamp on the left, which
/// asked a coach to tell two throws apart by reading "Shot Put · Men ·
/// 2026-09-02 14:31" twice. A throw is something you recognise by looking
/// at it, so the still leads and gets enough room to be recognised.
class ThrowCard extends StatelessWidget {
  const ThrowCard({
    super.key,
    required this.video,
    required this.title,
    this.onTap,
    this.onLongPress,
  });

  final ThrowVideo video;

  /// What this throw is, in the context it's shown in: under an athlete the
  /// name is redundant, in a search result it is the useful half.
  final String title;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = video.note.isEmpty
        ? shortThrowDate(video.displayDate)
        : '${shortThrowDate(video.displayDate)} · ${video.note}';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      // The card fills whatever slot it is given — a fixed-width cell on a
      // shelf, a grid cell inside a group — so one card serves both.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThrowThumbnail(video, width: width, height: width / 1.6),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}
