import 'dart:io';

import 'package:flutter/material.dart';

import '../models/throw_video.dart';
import 'event_glyph.dart';
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

/// "58.42 m" — centimetres are how a throw is measured, and the trailing
/// zeros of "58.40" carry meaning, so they stay.
String formatDistance(double metres) => '${metres.toStringAsFixed(2)} m';

/// A typed distance, or null when it isn't one. Accepts a comma decimal
/// mark, since a phone keyboard hands over whatever the locale uses, and
/// rejects negatives — a throw can be zero-length, never less.
double? parseDistance(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value.isNaN || value < 0) return null;
  return value;
}

/// A throw as a card: the still, with what it is written over it.
///
/// The library used to be text rows with a 72×48 stamp on the left, which
/// asked a coach to tell two throws apart by reading "Shot Put · Men ·
/// 2026-09-02 14:31" twice. A throw is something you recognise by looking
/// at it, so the frame is the whole card and the words sit on it — which
/// buys the still every pixel of the cell instead of the two thirds left
/// over after a caption.
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
    final accent = eventColor(video.event);
    final subtitle = video.note.isEmpty
        ? shortThrowDate(video.displayDate)
        : '${shortThrowDate(video.displayDate)} · ${video.note}';
    final distance = video.distance;

    return Material(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        // The card fills whatever slot it is given — a fixed-width cell on
        // a shelf, a grid cell inside a group — so one card serves both.
        child: LayoutBuilder(builder: (context, constraints) {
          // A grid cell is half a shelf card; at that size the badges eat
          // the frame they are supposed to sit on, so they step aside.
          final roomy = constraints.maxHeight >= 120;
          return Stack(
            fit: StackFit.expand,
            children: [
            _still(accent),
            // Scrims: keep the overlaid text and badges readable whatever
            // the frame is — bright sky at the top, grass or runway below.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.3],
                  colors: [Color(0x73000000), Colors.transparent],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.3, 1],
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            // A wash of the event's colour across the bottom corner —
            // texture, and a second read on which event this is.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  stops: const [0, 0.55],
                  colors: [accent.withOpacity(0.26), Colors.transparent],
                ),
              ),
            ),
            if (roomy)
              Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0x59000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            if (distance != null && roomy)
              Positioned(
                left: 8,
                top: 8,
                child: _Badge(label: formatDistance(distance)),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            ],
          );
        }),
      ),
    );
  }

  Widget _still(Color accent) {
    final path = video.thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    // No still (an older import, or extraction failed): an event-tinted
    // panel keeps the shelf's rhythm rather than leaving a hole.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.35), accent.withOpacity(0.08)],
        ),
      ),
      child: Center(
        child: EventGlyph(video.event,
            size: 34, color: Colors.white.withOpacity(0.75)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x8A000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.straighten, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
