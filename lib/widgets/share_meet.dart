import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';

import '../models/meet.dart';
import '../services/meet_library.dart';
import '../services/meet_relay.dart';
import '../services/video_library.dart';
import 'throw_picker.dart';

/// Handing one competition to the people standing at it.
///
/// One ring, one link. The link is handed over at a sector by somebody
/// standing at it, and what the people there are watching is the discus —
/// not the javelin two hours later, and not the rest of the day's field,
/// who are other people's athletes and never agreed to be on anybody's
/// phone. A coach with two rings going shares each and gets a link for
/// each.
///
/// The link is a public one now, so the sheet has one less thing to
/// explain: it is not about which network anybody is on. What it has to
/// say instead is that the phone has to keep signal, because the phone is
/// still the only thing that knows what was thrown — it pushes, and a
/// board nobody can reach is a board that stopped.
///
/// A QR because nobody is typing a hostname off a screen in sunlight, and
/// the link in full underneath because sometimes they have to.
Future<void> showShareCompetition(
  BuildContext context, {
  required Meet meet,
  required MeetCompetition competition,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Insets the top and leaves the bottom to the sheet, which is why the
    // body adds the navigation bar's own padding itself.
    useSafeArea: true,
    builder: (context) => _ShareSheet(meet: meet, competition: competition),
  );
}

/// The relay, looked up softly the way the meets are: a screen that offers
/// to share still paints in a test — or on a phone where the service never
/// came up — with nothing but the meet.
MeetRelay? meetRelayOf(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<MeetRelay>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.meet, required this.competition});

  final Meet meet;
  final MeetCompetition competition;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _working = false;

  Future<void> _start(MeetRelay relay) async {
    final meets = context.read<MeetLibrary>();
    final library = context.read<VideoLibrary>();
    // The app's own colors, handed over so the page paints in them rather
    // than in ones matched by eye. The theme stays main.dart's to decide.
    final scheme = Theme.of(context).colorScheme;
    setState(() => _working = true);
    await relay.start(
      meetId: widget.meet.id,
      event: widget.competition.event,
      implementKg: widget.competition.implementKg,
      scheme: scheme,
      // Read live, at every push. The relay holds the answers and never a
      // copy of the competition, so a mark entered a moment ago is in the
      // next one.
      meet: () => meets.byId(widget.meet.id),
      results: () => library.results,
      isPersonalBest: library.isPersonalBest,
      // What says the competition has moved. The meet and the record book
      // together, because a mark lands in both.
      changes: Listenable.merge([meets, library]),
    );
    if (mounted) setState(() => _working = false);
  }

  Future<void> _stop(MeetRelay relay) async {
    setState(() => _working = true);
    await relay.stop(widget.meet.id, widget.competition.event,
        widget.competition.implementKg);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final relay = meetRelayOf(context);
    final sharing = relay != null &&
        relay.sharing(widget.meet.id, widget.competition.event,
            widget.competition.implementKg);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Follow along', style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          // Which ring this link is for. A coach with two going has two
          // links, and the sheet has to say which one is in their hand.
          Text(widget.competition.label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: eventColor(widget.competition.event))),
          const SizedBox(height: 8),
          Text(
            sharing
                ? 'Scan this, or send it to anybody. Keep this phone on '
                    'signal — it is what the board is being fed from.'
                : 'Puts this event on a page anyone can open, here or at '
                    'home: the board, the field and the results sheet, '
                    'updating as you enter it. This phone works the '
                    'competition out and sends it on, so it needs signal.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          if (relay == null)
            Text('Sharing is not available.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error))
          else if (sharing) ...[
            _Sharing(
                relay: relay,
                meet: widget.meet,
                competition: widget.competition),
            // The one thing the LAN never had to say. The relay goes on
            // answering with whatever it last heard, so a phone that has
            // lost signal leaves a board on a stand that looks live and is
            // an hour old, and the coach is the only one who can be told.
            if (!relay.reaching) ...[
              const SizedBox(height: 12),
              Text(
                relay.error ?? 'Not reaching the page — it is showing what '
                    'it last had.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ] else ...[
            if (relay.error != null) ...[
              Text(relay.error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _working ? null : () => _start(relay),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Start sharing'),
            ),
          ],
          if (relay != null && sharing) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _working ? null : () => _stop(relay),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop sharing'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Sharing extends StatelessWidget {
  const _Sharing({
    required this.relay,
    required this.meet,
    required this.competition,
  });

  final MeetRelay relay;
  final Meet meet;
  final MeetCompetition competition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url =
        relay.urlFor(meet.id, competition.event, competition.implementKg) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            // The one place the app breaks its own dark theme, on purpose:
            // a code has to be dark on light with a quiet zone round it, and
            // a dark-on-dark QR is one no camera will read.
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
              size: const Size.square(232),
              painter: QrPainter(
                  relay.qrFor(meet.id, competition.event,
                          competition.implementKg) ??
                      url),
            ),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied.')),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    url,
                    // Read out loud and typed into somebody else's phone, so
                    // it is set at a size that survives both.
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy_outlined,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A QR code, painted from the encoder's own matrix.
///
/// Public so the same matrix can be drawn somewhere else later without a
/// second encoder — a sheet to tape to the fence by the sector is the
/// obvious one, since a phone screen in direct sun is the thing QR is worst
/// at and paper is best at.
class QrPainter extends CustomPainter {
  QrPainter(this.data) : _image = _encode(data);

  final String data;
  final QrImage? _image;

  static QrImage? _encode(String data) {
    if (data.isEmpty) return null;
    try {
      // Level M: enough redundancy for a fingerprint on the glass without
      // spending modules a sunlit screen needs to keep fat.
      return QrImage(
          QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    } catch (_) {
      // A link too long to encode is not worth taking the sheet down for;
      // the link itself is printed underneath either way.
      return null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final image = _image;
    if (image == null) return;
    // Modules are snapped to whole pixels: a QR drawn on fractional
    // boundaries comes out with seams a camera reads as noise.
    final count = image.moduleCount;
    final scale = (size.width / count).floorToDouble();
    final drawn = scale * count;
    final offset = ((size.width - drawn) / 2).floorToDouble();
    final paint = Paint()..color = const Color(0xFF000000);
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
              offset + col * scale, offset + row * scale, scale, scale),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(QrPainter old) => old.data != data;
}
