import 'dart:io';

import 'package:flutter/material.dart';

import '../models/throw_event.dart';
import '../models/throw_video.dart';
import 'event_glyph.dart';

/// The colour each event is tagged with across the app.
Color eventColor(ThrowEvent event) => switch (event) {
      ThrowEvent.shotPut => Colors.orangeAccent,
      ThrowEvent.discus => Colors.greenAccent,
      ThrowEvent.hammer => Colors.purpleAccent,
      ThrowEvent.javelin => Colors.lightBlueAccent,
    };

/// A throw's still frame, falling back to the implement glyph for clips
/// imported before thumbnails existed (or whose still went missing).
class ThrowThumbnail extends StatelessWidget {
  const ThrowThumbnail(this.video, {super.key, this.width = 72, this.height = 48});

  final ThrowVideo video;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = eventColor(video.event);
    final path = video.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(path),
            width: width, height: height, fit: BoxFit.cover),
      );
    }
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: EventGlyph(video.event, color: color),
    );
  }
}

/// One line about a throw: when it was recorded, and the note if any.
String throwSubtitle(ThrowVideo video) {
  final date = video.displayDate.toLocal().toString().substring(0, 16);
  return video.note.isEmpty ? date : '$date · ${video.note}';
}

String throwTitle(ThrowVideo video) =>
    '${video.athlete.isEmpty ? '' : '${video.athlete} · '}'
    '${video.event.label} · ${video.gender.label}';

/// Picks a throw to compare [against] with. Opens on that throw's own event
/// — comparing a javelin release with a shot put says nothing — and offers
/// the rest of the library behind a second chip.
Future<ThrowVideo?> pickThrowToCompare(
  BuildContext context, {
  required List<ThrowVideo> videos,
  required ThrowVideo against,
}) {
  final candidates =
      videos.where((video) => video.id != against.id).toList();
  return showModalBottomSheet<ThrowVideo>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ComparePickerSheet(
      candidates: candidates,
      event: against.event,
    ),
  );
}

class _ComparePickerSheet extends StatefulWidget {
  const _ComparePickerSheet({required this.candidates, required this.event});

  final List<ThrowVideo> candidates;
  final ThrowEvent event;

  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet> {
  bool _sameEventOnly = true;

  @override
  void initState() {
    super.initState();
    // Nothing to narrow to: open on the whole library rather than an empty
    // list the user has to work out how to escape.
    _sameEventOnly =
        widget.candidates.any((video) => video.event == widget.event);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _sameEventOnly
        ? widget.candidates
            .where((video) => video.event == widget.event)
            .toList()
        : widget.candidates;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compare with',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: Text(widget.event.label),
                  avatar: EventGlyph(widget.event,
                      size: 18, color: eventColor(widget.event)),
                  selected: _sameEventOnly,
                  onSelected: (_) => setState(() => _sameEventOnly = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All events'),
                  selected: !_sameEventOnly,
                  onSelected: (_) => setState(() => _sameEventOnly = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  widget.candidates.isEmpty
                      ? 'Import another throw to compare against this one.'
                      : 'No other ${widget.event.label.toLowerCase()} throws '
                          'yet — switch to All events to compare across '
                          'implements.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final video = shown[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ThrowThumbnail(video),
                      title: Text(throwTitle(video)),
                      subtitle: Text(throwSubtitle(video),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, video),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
