import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/meet.dart';
import '../models/throw_event.dart';
import '../models/throw_video.dart';
import '../models/training_note.dart';
import '../screens/analysis_screen.dart';
import '../screens/athlete_screen.dart';
import '../screens/meet_screen.dart';
import '../services/athlete_library.dart';
import '../services/meet_library.dart';
import '../services/video_library.dart';
import 'throw_card.dart';
import 'throw_picker.dart';

/// What the notebook's + button can put on a page.
enum InsertChoice {
  clip('A throw from the library', Icons.videocam_outlined),
  athlete('An athlete', Icons.person_outline),
  meet('A meet', Icons.emoji_events_outlined),
  link('A link — a video, an article, a paper', Icons.link),
  picture('A picture', Icons.image_outlined),
  callout('A callout', Icons.lightbulb_outline),
  divider('A divider', Icons.horizontal_rule);

  const InsertChoice(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The + menu: everything a notebook page can hold besides words.
Future<InsertChoice?> showInsertSheet(BuildContext context) =>
    showModalBottomSheet<InsertChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Add to the page',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final choice in InsertChoice.values)
              ListTile(
                key: ValueKey('insert-${choice.name}'),
                leading: Icon(choice.icon),
                title: Text(choice.label),
                onTap: () => Navigator.pop(context, choice),
              ),
          ],
        ),
      ),
    );

/// Picks one throw out of the library, newest first, with a search over
/// who threw it, the event and the throw's own note.
Future<ThrowVideo?> pickThrow(BuildContext context) {
  final videos = [...context.read<VideoLibrary>().videos]
    ..sort((a, b) => b.displayDate.compareTo(a.displayDate));
  return _pickFrom<ThrowVideo>(
    context,
    title: 'Add a throw',
    empty: 'No throws in the library yet. Film or import one first.',
    items: videos,
    matches: (video, query) => [
      video.athlete,
      displayNameOf(context, video.athlete, listen: false),
      video.event.label,
      video.note,
    ].any((text) => text.toLowerCase().contains(query)),
    tile: (context, video) => ListTile(
      leading: ThrowThumbnail(video, width: 64, height: 44),
      title: Text(_throwTitle(context, video)),
      subtitle: Text(_throwDetail(video)),
    ),
  );
}

/// Picks one of the athletes the library knows.
Future<String?> pickAthlete(BuildContext context) {
  final names = context.read<VideoLibrary>().knownAthletes;
  return _pickFrom<String>(
    context,
    title: 'Add an athlete',
    empty: 'No athletes yet. Tag a throw with a name and they turn up here.',
    items: names,
    matches: (name, query) => [
      name,
      displayNameOf(context, name, listen: false),
    ].any((text) => text.toLowerCase().contains(query)),
    tile: (context, name) => ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(displayNameOf(context, name)),
    ),
  );
}

/// Picks one meet, the most recent first.
Future<Meet?> pickMeet(BuildContext context) {
  final meets = [...context.read<MeetLibrary>().meets]
    ..sort((a, b) => b.date.compareTo(a.date));
  return _pickFrom<Meet>(
    context,
    title: 'Add a meet',
    empty: 'No meets yet. Add one from the trophy on the library.',
    items: meets,
    matches: (meet, query) => meet.name.toLowerCase().contains(query),
    tile: (context, meet) => ListTile(
      leading: const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
      title: Text(meet.name),
      subtitle: Text(longThrowDate(meet.date)),
    ),
  );
}

/// The one picker shape: a tall sheet, a search over it, a tap to choose.
Future<T?> _pickFrom<T>(
  BuildContext context, {
  required String title,
  required String empty,
  required List<T> items,
  required bool Function(T item, String query) matches,
  required Widget Function(BuildContext context, T item) tile,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PickerSheet<T>(
        title: title,
        empty: empty,
        items: items,
        matches: matches,
        tile: tile,
      ),
    );

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.empty,
    required this.items,
    required this.matches,
    required this.tile,
  });

  final String title;
  final String empty;
  final List<T> items;
  final bool Function(T item, String query) matches;
  final Widget Function(BuildContext context, T item) tile;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final item in widget.items)
        if (query.isEmpty || widget.matches(item, query)) item,
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                    child: Text(widget.title,
                        style: theme.textTheme.titleLarge)),
              ],
            ),
          ),
          if (widget.items.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          Expanded(
            child: widget.items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(widget.empty,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: shown.length,
                    itemBuilder: (context, index) => InkWell(
                      onTap: () => Navigator.pop(context, shown[index]),
                      child: IgnorePointer(
                          child: widget.tile(context, shown[index])),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a link's address and what to call it.
Future<({String url, String label})?> askForLink(BuildContext context) =>
    showDialog<({String url, String label})>(
      context: context,
      builder: (context) => const _LinkDialog(),
    );

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _url = TextEditingController();
  final _label = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A coach adding a link has nearly always just copied it, so offer what
    // is on the clipboard when it looks like an address.
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text?.trim() ?? '';
      if (mounted && _url.text.isEmpty && normalizeUrl(text) != null) {
        setState(() => _url.text = text);
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = normalizeUrl(_url.text);
    return AlertDialog(
      title: const Text('Add a link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('link-url'),
            controller: _url,
            autofocus: _url.text.isEmpty,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'youtube.com/watch?v=…',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('link-label'),
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What it is (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('link-add'),
          onPressed: url == null
              ? null
              : () => Navigator.pop(
                  context, (url: url, label: _label.text.trim())),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// [text] as a web address to open, or null when it is not one. A bare
/// "youtube.com/…" gets its https, because nobody types that part.
String? normalizeUrl(String text) {
  var value = text.trim();
  if (value.isEmpty || value.contains(' ')) return null;
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  if (!uri.host.contains('.')) return null;
  return uri.toString();
}

/// Whether [url] is a video somewhere — which is drawn as one, with a play
/// mark, rather than as a page.
bool isVideoLink(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host.endsWith('youtube.com') ||
      host == 'youtu.be' ||
      host.endsWith('vimeo.com') ||
      host.endsWith('instagram.com') ||
      host.endsWith('tiktok.com');
}

/// Opens [url] in whatever the phone opens links in, or puts it on the
/// clipboard when nothing will.
Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  await Clipboard.setData(ClipboardData(text: url));
  messenger?.showSnackBar(const SnackBar(
      content: Text("Couldn't open the link — it's copied instead.")));
}

String _throwTitle(BuildContext context, ThrowVideo video) {
  final who = video.athlete.trim().isEmpty
      ? 'No athlete'
      : displayNameOf(context, video.athlete);
  return '$who · ${video.event.label}';
}

String _throwDetail(ThrowVideo video) => [
      video.implementSpec.weightLabel,
      if (video.distance != null)
        formatDistance(video.distance!, video.distanceUnit),
      shortThrowDate(video.displayDate),
    ].join(' · ');

/// An embedded throw, athlete, meet or link, drawn as a card that opens
/// what it points at. What it points at is looked up on every build, so a
/// throw re-tagged or a meet renamed elsewhere is right here too — and one
/// deleted says so rather than leaving a hole.
class NotebookEmbedCard extends StatelessWidget {
  const NotebookEmbedCard({
    super.key,
    required this.block,
    this.selected = false,
    this.onSelect,
    this.onRemove,
  });

  final NoteBlock block;

  /// Whether this is the block the editor's toolbar acts on.
  final bool selected;

  /// Called on a long press, which selects the block without opening it.
  final VoidCallback? onSelect;

  /// Shows the remove button when set — in the editor, never in a preview.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      children: [
        Card(
          key: ValueKey('embed-${block.id}'),
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: 1.5),
          ),
          child: InkWell(
            onTap: resolved.open == null
                ? onSelect
                : () {
                    onSelect?.call();
                    resolved.open!(context);
                  },
            onLongPress: onSelect,
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 10, onRemove == null ? 10 : 44, 10),
              child: Row(
                children: [
                  resolved.leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(resolved.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (resolved.detail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(resolved.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  if (resolved.open != null)
                    Icon(resolved.openIcon,
                        size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Remove from the page',
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
            ),
          ),
      ],
    );
  }

  _Resolved _resolve(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget badge(IconData icon) => Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: scheme.primary),
        );
    final ref = block.ref ?? '';
    switch (block.kind) {
      case NoteBlockKind.clip:
        ThrowVideo? video;
        for (final candidate in context.watch<VideoLibrary>().videos) {
          if (candidate.id == ref) video = candidate;
        }
        if (video == null) {
          return _Resolved(
              leading: badge(Icons.videocam_off_outlined),
              title: 'Throw no longer in the library',
              detail: 'It was deleted after it was added here.');
        }
        final found = video;
        return _Resolved(
          leading: ThrowThumbnail(found, width: 64, height: 44),
          title: _throwTitle(context, found),
          detail: _throwDetail(found),
          openIcon: Icons.play_circle_outline,
          open: (context) => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      AnalysisScreen(video: found, siblings: [found]))),
        );
      case NoteBlockKind.athlete:
        final library = context.watch<VideoLibrary>();
        final last = library.lastThrewOn(ref);
        final count = library.results
            .where((r) => r.athlete.trim().toLowerCase() == ref.toLowerCase())
            .length;
        return _Resolved(
          leading: badge(Icons.person_outline),
          title: displayNameOf(context, ref),
          detail: [
            count == 1 ? '1 throw' : '$count throws',
            if (last != null) 'last threw ${shortThrowDate(last)}',
          ].join(' · '),
          open: (context) => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AthleteScreen(
                      name: ref,
                      titleFor: (video) => '${video.event.label} · '
                          '${video.implementSpec.weightLabel}'))),
        );
      case NoteBlockKind.meet:
        final meet = context.watch<MeetLibrary>().byId(ref);
        if (meet == null) {
          return _Resolved(
              leading: badge(Icons.event_busy_outlined),
              title: 'Meet no longer on the calendar',
              detail: 'It was deleted after it was added here.');
        }
        return _Resolved(
          leading: badge(Icons.emoji_events_outlined),
          title: meet.name,
          detail: longThrowDate(meet.date),
          open: (context) => Navigator.push(context,
              MaterialPageRoute(builder: (_) => MeetScreen(meetId: meet.id))),
        );
      case NoteBlockKind.link:
        final url = block.url ?? '';
        final uri = Uri.tryParse(url);
        final host = (uri?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');
        final video = isVideoLink(url);
        return _Resolved(
          leading: badge(video ? Icons.smart_display_outlined : Icons.public),
          title: host.isEmpty ? url : host,
          detail: url,
          openIcon: Icons.open_in_new,
          open: url.isEmpty ? null : (context) => openLink(context, url),
        );
      default:
        return _Resolved(leading: badge(Icons.help_outline), title: '');
    }
  }
}

class _Resolved {
  _Resolved({
    required this.leading,
    required this.title,
    this.detail = '',
    this.open,
    this.openIcon = Icons.chevron_right,
  });

  final Widget leading;
  final String title;
  final String detail;
  final void Function(BuildContext context)? open;
  final IconData openIcon;
}

/// The icon a notebook list shows for a kind of block a page holds.
IconData embedIcon(NoteBlockKind kind) => switch (kind) {
      NoteBlockKind.clip => Icons.videocam_outlined,
      NoteBlockKind.athlete => Icons.person_outline,
      NoteBlockKind.meet => Icons.emoji_events_outlined,
      NoteBlockKind.link => Icons.link,
      NoteBlockKind.image => Icons.image_outlined,
      _ => Icons.notes,
    };
