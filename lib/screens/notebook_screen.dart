import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/research_library.dart';
import '../models/notebook.dart';
import '../models/research.dart';
import '../models/throw_event.dart';
import '../models/training_note.dart';
import '../services/notebook_library.dart';
import '../services/notes_library.dart';
import '../widgets/note_text.dart';
import '../widgets/notebook_embeds.dart';
import '../widgets/throw_card.dart';
import 'note_editor_screen.dart';

/// The coach's notebook: the coach's own pages on one tab, and what the
/// research says about coaching the throws on the other.
///
/// The pages are the coach's to organize — sections they name and order,
/// pages pinned to the top — and a page holds more than words: a throw from
/// the library, an athlete, a meet, a link to a video or a paper. The
/// research is the app's, each entry with its sources, and any of it can be
/// copied into the notebook to be written on.
class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key, this.research = researchLibrary});

  /// The research tab's entries — the shipped library, unless a test hands
  /// it others.
  final List<ResearchEntry> research;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Coach's notebook"),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(
                key: ValueKey('tab-notebook'),
                icon: Icon(Icons.edit_note),
                text: 'My notes'),
            Tab(
                key: ValueKey('tab-research'),
                icon: Icon(Icons.school_outlined),
                text: 'Research'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _NotesTab(),
          _ResearchTab(entries: widget.research),
        ],
      ),
    );
  }
}

/// Which pages the list is showing.
sealed class _Filter {
  const _Filter();
}

class _All extends _Filter {
  const _All();
}

class _Pinned extends _Filter {
  const _Pinned();
}

/// Pages filed in no section — shown only once there are sections, since
/// before that every page is in none.
class _Unfiled extends _Filter {
  const _Unfiled();
}

class _InSection extends _Filter {
  const _InSection(this.id);
  final String id;
}

class _NotesTab extends StatefulWidget {
  const _NotesTab();

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab>
    with AutomaticKeepAliveClientMixin {
  _Filter _filter = const _All();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  List<NotebookPage> _shown(NotebookLibrary library) {
    final pages = switch (_filter) {
      _All() => library.pages,
      _Pinned() => [
          for (final page in library.pages)
            if (page.pinned) page
        ],
      _Unfiled() => library.pagesIn(null),
      _InSection(:final id) => library.pagesIn(id),
    };
    return [
      for (final page in pages)
        if (page.matches(_query)) page
    ];
  }

  Future<void> _open(NotebookPage page) async {
    final library = context.read<NotebookLibrary>();
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NoteEditorScreen(note: page)));
    // A page opened and left with nothing on it was never really written:
    // tidy it away rather than leave "Untitled page" in the list.
    final stored = library.byId(page.id);
    if (stored != null &&
        stored.title.trim().isEmpty &&
        stored.blocks.every((block) => block.isBlank)) {
      await library.remove(stored.id);
    }
  }

  void _newPage() {
    final library = context.read<NotebookLibrary>();
    final filter = _filter;
    _open(library.draft(
        sectionId: filter is _InSection ? filter.id : null));
  }

  Future<void> _addSection() async {
    final name = await _askName(context, title: 'New section');
    if (name == null || !mounted) return;
    final section = await context.read<NotebookLibrary>().addSection(name);
    if (mounted) setState(() => _filter = _InSection(section.id));
  }

  Future<void> _sectionMenu(NotebookSection section) async {
    final library = context.read<NotebookLibrary>();
    final index = library.sections.indexWhere((s) => s.id == section.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(section.name,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: const Text('Move left'),
                onTap: () => Navigator.pop(context, 'left'),
              ),
            if (index < library.sections.length - 1)
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: const Text('Move right'),
                onTap: () => Navigator.pop(context, 'right'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete section'),
              subtitle: const Text('Its pages are kept, in no section'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'rename':
        final name = await _askName(context,
            title: 'Rename section', initial: section.name);
        if (name != null) await library.renameSection(section.id, name);
      case 'left':
        await library.moveSection(section.id, -1);
      case 'right':
        await library.moveSection(section.id, 1);
      case 'delete':
        await library.removeSection(section.id);
        if (mounted) setState(() => _filter = const _All());
    }
  }

  Future<void> _pageMenu(NotebookPage page, String action) async {
    final library = context.read<NotebookLibrary>();
    switch (action) {
      case 'pin':
        await library.setPinned(page.id, !page.pinned);
      case 'move':
        final target = await _pickSection(context, library, page.sectionId);
        if (target == null) return;
        await library.moveTo(page.id, target.isEmpty ? null : target);
      case 'delete':
        final go = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this page?'),
            content: Text(page.displayTitle),
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
        if (go == true) await library.remove(page.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final library = context.watch<NotebookLibrary>();
    final filter = _filter;
    // A section deleted out from under the filter falls back to everything.
    if (filter is _InSection && library.sectionById(filter.id) == null) {
      _filter = const _All();
    }
    final shown = _shown(library);
    final hasPinned = library.pages.any((page) => page.pinned);
    final hasUnfiled =
        library.sections.isNotEmpty && library.pagesIn(null).isNotEmpty;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('notebook-new-page'),
        onPressed: _newPage,
        icon: const Icon(Icons.add),
        label: const Text('New page'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView(
                key: const ValueKey('notebook-sections'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                children: [
                  _chip('All', _filter is _All,
                      () => setState(() => _filter = const _All())),
                  if (hasPinned)
                    _chip('Pinned', _filter is _Pinned,
                        () => setState(() => _filter = const _Pinned()),
                        icon: Icons.push_pin_outlined),
                  for (final section in library.sections)
                    _chip(
                      section.name,
                      _filter is _InSection &&
                          (_filter as _InSection).id == section.id,
                      () => setState(() => _filter = _InSection(section.id)),
                      onLongPress: () => _sectionMenu(section),
                    ),
                  if (hasUnfiled)
                    _chip('No section', _filter is _Unfiled,
                        () => setState(() => _filter = const _Unfiled())),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      key: const ValueKey('notebook-add-section'),
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Section'),
                      onPressed: _addSection,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (library.pages.length > 5)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  key: const ValueKey('notebook-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search the notebook',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
          if (filter is _InSection)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Text(
                  'Hold a section to rename, move or delete it',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          if (library.pages.isEmpty)
            const SliverFillRemaining(
                hasScrollBody: false, child: _EmptyNotebook())
          else if (shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _query.trim().isNotEmpty
                        ? 'Nothing in the notebook says "${_query.trim()}".'
                        : 'No pages here yet. "New page" puts one in.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              sliver: SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) => _PageCard(
                  page: shown[index],
                  section: library.sectionById(shown[index].sectionId),
                  onOpen: () => _open(shown[index]),
                  onAction: (action) => _pageMenu(shown[index], action),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap,
          {IconData? icon, VoidCallback? onLongPress}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: FilterChip(
            label: Text(label),
            avatar: icon == null ? null : Icon(icon, size: 16),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
          ),
        ),
      );
}

class _EmptyNotebook extends StatelessWidget {
  const _EmptyNotebook();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Your notebook', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Keep whatever is worth keeping: drill progressions, the cue '
            'that finally worked, a season plan. Put a throw from the '
            'library on a page, or an athlete, a meet, a picture, or a link '
            'to a video or a paper.',
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 8),
          Text(
            'Sections keep it in order: Drills, Cues, Season plan — '
            'whatever you need.',
            textAlign: TextAlign.center,
            style: muted,
          ),
        ],
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.page,
    required this.section,
    required this.onOpen,
    required this.onAction,
  });

  final NotebookPage page;
  final NotebookSection? section;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = page.preview;
    final counts = page.embedCounts;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Card(
      key: ValueKey('notebook-page-${page.id}'),
      color: scheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (page.pinned) ...[
                          Icon(Icons.push_pin, size: 16, color: scheme.primary),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(page.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      NoteRichText(preview,
                          maxLines: 2,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (section != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(section!.name,
                                style: muted?.copyWith(color: scheme.primary)),
                          ),
                        Text(shortThrowDate(page.updatedAt), style: muted),
                        for (final entry in counts.entries)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(embedIcon(entry.key),
                                  size: 14, color: scheme.onSurfaceVariant),
                              if (entry.value > 1) ...[
                                const SizedBox(width: 2),
                                Text('${entry.value}', style: muted),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Page options',
                onSelected: onAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'pin',
                    child: ListTile(
                      leading: Icon(page.pinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                      title: Text(page.pinned ? 'Unpin' : 'Pin to the top'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'move',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_move_outline),
                      title: Text('Move to section'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a section's name. Null when the coach backs out or leaves it
/// blank.
Future<String?> _askName(BuildContext context,
    {required String title, String initial = ''}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, initial: initial),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Its own widget so the field's controller lives exactly as long as the
/// dialog does — disposed by the caller, it would go while the dialog was
/// still animating away with it.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const ValueKey('section-name'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration:
              const InputDecoration(hintText: 'Drills, Cues, Season plan…'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('section-save'),
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('Save')),
        ],
      );
}

/// Picks the section to move a page to. An empty string is "no section";
/// null is backing out.
Future<String?> _pickSection(
        BuildContext context, NotebookLibrary library, String? current) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('Move to', style: TextStyle(fontSize: 18))),
            ListTile(
              leading: Icon(current == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: const Text('No section'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final section in library.sections)
              ListTile(
                leading: Icon(section.id == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(section.name),
                onTap: () => Navigator.pop(context, section.id),
              ),
            if (library.sections.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text('No sections yet — "+ Section" on the notebook '
                    'makes one.'),
              ),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Research
// ---------------------------------------------------------------------------

class _ResearchTab extends StatefulWidget {
  const _ResearchTab({required this.entries});

  final List<ResearchEntry> entries;

  @override
  State<_ResearchTab> createState() => _ResearchTabState();
}

class _ResearchTabState extends State<_ResearchTab>
    with AutomaticKeepAliveClientMixin {
  ResearchTopic? _topic;
  ThrowEvent? _event;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  int _countIn(ResearchTopic topic) =>
      widget.entries.where((entry) => entry.topic == topic).length;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;
    final shown = [
      for (final entry in widget.entries)
        if ((_topic == null || entry.topic == _topic) &&
            entry.appliesTo(_event) &&
            entry.matches(_query))
          entry,
    ];
    final browsing = _topic == null && !searching;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const ValueKey('research-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search the research',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                for (final event in [null, ...ThrowEvent.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(event?.label ?? 'All events'),
                      selected: _event == event,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _event = event),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.entries.isEmpty)
          SliverToBoxAdapter(
            child: Card(
              key: const ValueKey('research-coming'),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: scheme.primary.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_stories_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Research is on its way: coaching tips drawn from '
                        'published studies on the throws, each with its '
                        'sources, and any of it saved to your notebook in '
                        'a tap.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (browsing)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 116,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: ResearchTopic.values.length,
              itemBuilder: (context, index) {
                final topic = ResearchTopic.values[index];
                final count = _countIn(topic);
                return Card(
                  key: ValueKey('topic-${topic.name}'),
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainer,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _topic = topic),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(topic.label,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(topic.blurb,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant)),
                          ),
                          Text(
                            count == 0
                                ? 'Coming soon'
                                : count == 1
                                    ? '1 entry'
                                    : '$count entries',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else ...[
          if (_topic != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'All topics',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _topic = null),
                    ),
                    Expanded(
                      child: Text(_topic!.label,
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
              ),
            ),
          if (shown.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    widget.entries.isEmpty
                        ? 'Nothing here yet — entries are on their way.'
                        : 'Nothing matches that.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) =>
                    _ResearchCard(entry: shown[index]),
              ),
            ),
        ],
      ],
    );
  }
}

class _ResearchCard extends StatelessWidget {
  const _ResearchCard({required this.entry});

  final ResearchEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey('research-${entry.id}'),
      color: scheme.surfaceContainer,
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ResearchEntryScreen(entry: entry))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(entry.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              _EntryTags(entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTags extends StatelessWidget {
  const _EntryTags({required this.entry});

  final ResearchEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tag(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text,
              style: theme.textTheme.labelSmall?.copyWith(color: color)),
        );
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        tag(entry.topic.label, scheme.primary),
        tag(entry.evidence.label, scheme.tertiary),
        for (final event in entry.events) tag(event.label, scheme.secondary),
      ],
    );
  }
}

/// One research entry, read in full: the finding, what to do with it, and
/// the sources — each one a tap from the paper itself.
class ResearchEntryScreen extends StatelessWidget {
  const ResearchEntryScreen({super.key, required this.entry});

  final ResearchEntry entry;

  /// Copies the entry into a new notebook page — the coach's to write on,
  /// with the sources kept on it as links.
  Future<void> _saveToNotebook(BuildContext context) async {
    final library = context.read<NotebookLibrary>();
    final messenger = ScaffoldMessenger.of(context);
    var n = 0;
    NoteBlock block(NoteBlockKind kind, String text, {String? url}) =>
        NoteBlock(
            id: '${NotesLibrary.newBlockId()}_${n++}',
            kind: kind,
            text: text,
            url: url);
    final page = library.draft()
      ..title = entry.title
      ..blocks.addAll([
        block(NoteBlockKind.callout, entry.summary),
        block(NoteBlockKind.heading, 'What the research found'),
        for (final line in entry.takeaways) block(NoteBlockKind.bullet, line),
        block(NoteBlockKind.heading, 'At practice'),
        for (final line in entry.tips) block(NoteBlockKind.checklist, line),
        block(NoteBlockKind.heading, 'Sources'),
        for (final citation in entry.citations)
          if (citation.link != null)
            block(NoteBlockKind.link, citation.reference, url: citation.link)
          else
            block(NoteBlockKind.bullet, citation.reference),
      ]);
    await library.save(page);
    messenger.showSnackBar(
        const SnackBar(content: Text("Saved to your notebook's My notes.")));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(text,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        );
    Widget line(String text, IconData icon) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(entry.topic.label)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('research-save'),
        onPressed: () => _saveToNotebook(context),
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Save to notebook'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          Text(entry.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          _EntryTags(entry: entry),
          const SizedBox(height: 16),
          Text(entry.summary, style: theme.textTheme.bodyLarge),
          if (entry.takeaways.isNotEmpty) ...[
            heading('What the research found'),
            for (final text in entry.takeaways) line(text, Icons.science_outlined),
          ],
          if (entry.tips.isNotEmpty) ...[
            heading('At practice'),
            for (final text in entry.tips) line(text, Icons.sports_outlined),
          ],
          if (entry.citations.isNotEmpty) ...[
            heading('Sources'),
            for (final citation in entry.citations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(citation.reference,
                    style: theme.textTheme.bodyMedium),
                trailing: citation.link == null
                    ? null
                    : const Icon(Icons.open_in_new, size: 18),
                onTap: citation.link == null
                    ? null
                    : () => openLink(context, citation.link!),
              ),
          ],
        ],
      ),
    );
  }
}
