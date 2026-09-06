import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/training_note.dart';
import '../services/notes_library.dart';
import '../widgets/note_text.dart';

/// Writes one training note.
///
/// Always editable — there is no read mode to switch out of, the way a
/// notes app works — and it saves itself, so a coach who backs out of the
/// screen mid-sentence keeps the sentence.
///
/// Emphasis is written with markers in the text and drawn as you type: the
/// bold word is bold in the field, and its `**` sit either side of it in a
/// faint grey. That is what buys real formatting without a document model,
/// and it means a note is still readable text wherever it ends up.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.note});

  /// The note to edit. A copy is taken, so nothing reaches the store until
  /// it is saved.
  final TrainingNote note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TrainingNote _note = widget.note.copy();
  late final TextEditingController _title =
      TextEditingController(text: _note.title);

  final Map<String, NoteTextController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  /// The block the toolbar acts on. Kept after focus is lost to the
  /// toolbar's own buttons, which is where the cursor goes when you tap one.
  String? _active;

  Timer? _saveTimer;

  /// Held rather than read from context on demand: the last save happens in
  /// dispose(), where the tree is already coming down and a lookup would
  /// throw. A half-typed line is exactly what must not be lost.
  NotesLibrary? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = context.read<NotesLibrary>();
  }

  @override
  void initState() {
    super.initState();
    // A brand new note opens with somewhere to type rather than a wall of
    // buttons and nothing to press them on.
    if (_note.blocks.isEmpty) {
      _note.blocks.add(NoteBlock(id: NotesLibrary.newBlockId()));
    }
  }

  @override
  void dispose() {
    // Anything typed inside the debounce window would otherwise go down
    // with the screen.
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _store?.save(_note);
    }
    _saveTimer?.cancel();
    _title.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  NoteTextController _controllerFor(NoteBlock block) =>
      _controllers.putIfAbsent(
        block.id,
        () => NoteTextController(
          text: block.text,
          // Faint enough to read as punctuation rather than as syntax —
          // the words between them are already bold, which is the part
          // that matters.
          markerColor:
              Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
        ),
      );

  FocusNode _focusFor(NoteBlock block) => _focusNodes.putIfAbsent(
        block.id,
        () => FocusNode()
          ..addListener(() {
            if (_focusNodes[block.id]?.hasFocus ?? false) {
              setState(() => _active = block.id);
            }
          }),
      );

  NoteBlock? get _activeBlock {
    for (final block in _note.blocks) {
      if (block.id == _active) return block;
    }
    return null;
  }

  /// Saves shortly after typing stops. Structural edits — a new block, a
  /// kind change, a tick — go straight through, since those are the ones
  /// worth not losing.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  void _save() {
    _saveTimer?.cancel();
    _store?.save(_note);
  }

  void _typed(NoteBlock block, String value) {
    // Enter ends a block and starts the next one, carrying the kind with
    // it — which is what makes a bulleted list feel like a list rather than
    // like six separate decisions.
    final newline = value.indexOf('\n');
    if (newline != -1 && !block.isImage) {
      final head = value.substring(0, newline);
      final tail = value.substring(newline + 1);
      block.text = head;
      _controllerFor(block).text = head;
      // A heading's continuation is body text, never another heading.
      final kind = block.kind == NoteBlockKind.heading
          ? NoteBlockKind.paragraph
          : block.kind;
      _insertAfter(block, NoteBlock(
        id: NotesLibrary.newBlockId(),
        kind: kind,
        text: tail,
      ));
      _save();
      return;
    }
    block.text = value.replaceAll('\n', ' ');
    _scheduleSave();
  }

  void _insertAfter(NoteBlock block, NoteBlock fresh) {
    final index = _note.blocks.indexOf(block);
    setState(() => _note.blocks.insert(index + 1, fresh));
    // Focus lands after the frame that builds the new field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFor(fresh).requestFocus();
    });
  }

  void _addBlock(NoteBlockKind kind) {
    final fresh = NoteBlock(id: NotesLibrary.newBlockId(), kind: kind);
    final active = _activeBlock;
    if (active == null) {
      setState(() => _note.blocks.add(fresh));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusFor(fresh).requestFocus();
      });
    } else {
      _insertAfter(active, fresh);
    }
    _save();
  }

  void _setKind(NoteBlockKind kind) {
    final block = _activeBlock;
    if (block == null || block.isImage) return;
    setState(() => block.kind = block.kind == kind
        // Tapping the kind a block already is turns it back into a
        // paragraph, so the buttons toggle rather than trap.
        ? NoteBlockKind.paragraph
        : kind);
    _save();
  }

  void _move(int by) {
    final block = _activeBlock;
    if (block == null) return;
    final from = _note.blocks.indexOf(block);
    final to = from + by;
    if (to < 0 || to >= _note.blocks.length) return;
    setState(() {
      _note.blocks.removeAt(from);
      _note.blocks.insert(to, block);
    });
    _save();
  }

  void _deleteBlock() {
    final block = _activeBlock;
    if (block == null || _note.blocks.length == 1) return;
    setState(() {
      _note.blocks.remove(block);
      _active = null;
    });
    _controllers.remove(block.id)?.dispose();
    _focusNodes.remove(block.id)?.dispose();
    _save();
  }

  /// Wraps the selection in [marker], or opens an empty pair to type into.
  void _emphasise(String marker) {
    final block = _activeBlock;
    if (block == null) return;
    final controller = _controllerFor(block);
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final inner = text.substring(start, end);
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '$marker$inner$marker'),
      selection: TextSelection(
        baseOffset: start + marker.length,
        extentOffset: end + marker.length,
      ),
    );
    block.text = controller.text;
    _focusFor(block).requestFocus();
    _scheduleSave();
  }

  Future<void> _addPicture() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final id = NotesLibrary.newBlockId();
    final stored = await context
        .read<NotesLibrary>()
        .adoptPicture(_note.id, id, picked.path);
    if (stored == null || !mounted) return;
    final fresh = NoteBlock(
        id: id, kind: NoteBlockKind.image, imagePath: stored);
    final active = _activeBlock;
    if (active == null) {
      setState(() => _note.blocks.add(fresh));
    } else {
      _insertAfter(active, fresh);
    }
    _save();
  }

  Future<void> _deleteNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text(_note.displayTitle),
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
    if (confirmed != true || !mounted) return;
    _saveTimer?.cancel();
    await context.read<NotesLibrary>().remove(_note.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Leaving is saving: there is no discard, because a coach backing out
      // of a note means they are done with it, not that they never wrote it.
      onPopInvokedWithResult: (didPop, _) => _save(),
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Training note'),
              Text(
                _note.athlete,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteNote,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.headlineSmall,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Note title',
                isDense: true,
              ),
              onChanged: (value) {
                _note.title = value;
                _scheduleSave();
              },
            ),
            const SizedBox(height: 4),
            for (final block in _note.blocks) _blockRow(block),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addBlock(NoteBlockKind.paragraph),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add a line'),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _toolbar(),
      ),
    );
  }

  Widget _blockRow(NoteBlock block) {
    if (block.isImage) return _pictureBlock(block);

    final theme = Theme.of(context);
    final style = switch (block.kind) {
      NoteBlockKind.heading => theme.textTheme.titleLarge,
      _ => theme.textTheme.bodyLarge,
    };
    return Padding(
      padding: EdgeInsets.only(
          top: block.kind == NoteBlockKind.heading ? 14 : 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _leading(block, style),
          Expanded(
            child: TextField(
              controller: _controllerFor(block),
              focusNode: _focusFor(block),
              style: style?.copyWith(
                decoration: block.kind == NoteBlockKind.checklist &&
                        block.checked
                    ? TextDecoration.lineThrough
                    : null,
                color: block.kind == NoteBlockKind.checklist && block.checked
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                hintText: _hintFor(block),
              ),
              onChanged: (value) => _typed(block, value),
            ),
          ),
        ],
      ),
    );
  }

  String? _hintFor(NoteBlock block) {
    if (_note.blocks.first.id != block.id) return null;
    return switch (block.kind) {
      NoteBlockKind.heading => 'Heading',
      NoteBlockKind.checklist => 'Something to do next session',
      NoteBlockKind.bullet ||
      NoteBlockKind.numbered =>
        'A cue, a drill, a number',
      _ => 'What happened, and what to work on',
    };
  }

  /// The bullet, the number or the checkbox — what says which kind of line
  /// this is without a label saying so.
  Widget _leading(NoteBlock block, TextStyle? style) {
    final theme = Theme.of(context);
    switch (block.kind) {
      case NoteBlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(top: 10, right: 10, left: 2),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: theme.colorScheme.primary, shape: BoxShape.circle),
          ),
        );
      case NoteBlockKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(top: 4, right: 8),
          child: SizedBox(
            width: 20,
            child: Text('${_numberOf(block)}.',
                style: style?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
        );
      case NoteBlockKind.checklist:
        return SizedBox(
          width: 34,
          child: Checkbox(
            value: block.checked,
            visualDensity: VisualDensity.compact,
            onChanged: (value) {
              setState(() => block.checked = value ?? false);
              _save();
            },
          ),
        );
      default:
        return const SizedBox(width: 2);
    }
  }

  /// Numbering restarts wherever a run of numbered lines does, so two lists
  /// separated by a paragraph are two lists.
  int _numberOf(NoteBlock block) {
    var number = 0;
    for (final candidate in _note.blocks) {
      if (candidate.kind == NoteBlockKind.numbered) {
        number++;
      } else {
        number = 0;
      }
      if (candidate.id == block.id) break;
    }
    return number;
  }

  Widget _pictureBlock(NoteBlock block) {
    final theme = Theme.of(context);
    final path = block.imagePath;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: path != null && File(path).existsSync()
                ? Image.file(File(path), fit: BoxFit.cover)
                : Container(
                    height: 120,
                    alignment: Alignment.center,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Text('Picture missing'),
                  ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controllerFor(block),
            focusNode: _focusFor(block),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              hintText: 'Caption this picture',
            ),
            onChanged: (value) => _typed(block, value),
          ),
        ],
      ),
    );
  }

  /// The formatting bar. Sits above the keyboard, and acts on whichever
  /// line the cursor is in.
  Widget _toolbar() {
    final block = _activeBlock;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          // Scrolls: eleven tools don't fit across a phone, and the ones
          // that fall off the end are the rarer ones.
          child: ListView(
            key: const Key('note-toolbar'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              _tool(Icons.format_bold, 'Bold',
                  onTap: () => _emphasise('**')),
              _tool(Icons.format_italic, 'Italic',
                  onTap: () => _emphasise('*')),
              _tool(Icons.format_underlined, 'Underline',
                  onTap: () => _emphasise('__')),
              const _ToolDivider(),
              _tool(Icons.title, 'Heading',
                  on: block?.kind == NoteBlockKind.heading,
                  onTap: () => _setKind(NoteBlockKind.heading)),
              _tool(Icons.format_list_bulleted, 'Bulleted list',
                  on: block?.kind == NoteBlockKind.bullet,
                  onTap: () => _setKind(NoteBlockKind.bullet)),
              _tool(Icons.format_list_numbered, 'Numbered list',
                  on: block?.kind == NoteBlockKind.numbered,
                  onTap: () => _setKind(NoteBlockKind.numbered)),
              _tool(Icons.checklist, 'Checklist',
                  on: block?.kind == NoteBlockKind.checklist,
                  onTap: () => _setKind(NoteBlockKind.checklist)),
              const _ToolDivider(),
              _tool(Icons.image_outlined, 'Add a picture',
                  onTap: _addPicture),
              const _ToolDivider(),
              _tool(Icons.arrow_upward, 'Move up',
                  onTap: () => _move(-1)),
              _tool(Icons.arrow_downward, 'Move down',
                  onTap: () => _move(1)),
              _tool(Icons.backspace_outlined, 'Delete this line',
                  onTap: _deleteBlock),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String tooltip,
      {required VoidCallback onTap, bool on = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      isSelected: on,
      // Compact, so as much of the bar as possible is reachable without
      // scrolling it.
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      color: on ? scheme.primary : scheme.onSurface,
      onPressed: onTap,
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: VerticalDivider(
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant),
      );
}
