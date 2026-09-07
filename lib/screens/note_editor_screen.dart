import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Where the coach last left the formatting bar. Remembered, because it
  /// is a preference about their hands rather than about this note.
  static const _dockKey = 'throwlab.noteToolbarTop';

  late final TrainingNote _note = widget.note.copy();
  late final TextEditingController _title =
      TextEditingController(text: _note.title);

  final Map<String, NoteTextController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  /// The block the toolbar acts on. Kept after focus is lost to the
  /// toolbar's own buttons, which is where the cursor goes when you tap one.
  String? _active;

  /// Toolbar under the app bar rather than above the keyboard. Either place
  /// stays on screen while typing; which one reads better depends on the
  /// phone, so it is a choice rather than a decision.
  bool _dockTop = false;

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
    unawaited(_loadDock());
  }

  Future<void> _loadDock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _dockTop = prefs.getBool(_dockKey) ?? false);
    } catch (_) {
      // Storage that will not answer just means the bar stays where it is.
    }
  }

  void _toggleDock() {
    setState(() => _dockTop = !_dockTop);
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_dockKey, _dockTop);
      } catch (_) {
        // The bar has already moved; it just won't be there next time.
      }
    }());
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

  /// The list kinds. A run of them, all the same kind, is what reads as one
  /// list on the screen — and so is what "delete the list" has to mean.
  static const _listKinds = {
    NoteBlockKind.bullet,
    NoteBlockKind.numbered,
    NoteBlockKind.checklist,
  };

  /// The whole list [block] belongs to: the lines either side of it that are
  /// the same kind, unbroken. Empty when [block] is not a list line.
  List<NoteBlock> _listRun(NoteBlock block) {
    if (!_listKinds.contains(block.kind)) return const [];
    final index = _note.blocks.indexOf(block);
    if (index == -1) return const [];
    var first = index;
    while (first > 0 && _note.blocks[first - 1].kind == block.kind) {
      first--;
    }
    var last = index;
    while (last < _note.blocks.length - 1 &&
        _note.blocks[last + 1].kind == block.kind) {
      last++;
    }
    return _note.blocks.sublist(first, last + 1);
  }

  /// Takes [doomed] out of the note, tidies up after them, and leaves the
  /// cursor somewhere sensible.
  ///
  /// A note is never left with nothing in it: emptying it out gives back one
  /// blank line, so the screen still has somewhere to type. That is also
  /// what deleting the only line means — the line clears rather than the
  /// editor going blank.
  void _removeBlocks(List<NoteBlock> doomed) {
    if (doomed.isEmpty) return;
    final typing = _focusNodes.values.any((node) => node.hasFocus);
    final at = _note.blocks.indexOf(doomed.first);
    setState(() {
      for (final block in doomed) {
        _note.blocks.remove(block);
      }
      if (_note.blocks.isEmpty) {
        _note.blocks.add(NoteBlock(id: NotesLibrary.newBlockId()));
      }
      // The line that slid up into the gap, or the last one if the gap was
      // at the end — the same place a cursor lands in any editor.
      final landing = _note.blocks[at.clamp(0, _note.blocks.length - 1)];
      _active = landing.id;
      if (typing && !landing.isImage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusFor(landing).requestFocus();
        });
      }
    });
    for (final block in doomed) {
      _controllers.remove(block.id)?.dispose();
      _focusNodes.remove(block.id)?.dispose();
      final path = block.imagePath;
      // The picture is a file of ours, not the gallery's copy — nothing else
      // will ever come back for it.
      if (path != null) {
        unawaited(_store?.deletePicture(path) ?? Future.value());
      }
    }
    _save();
  }

  void _deleteBlock() {
    final block = _activeBlock;
    if (block == null) return;
    _removeBlocks([block]);
  }

  Future<void> _deleteList() async {
    final block = _activeBlock;
    if (block == null) return;
    final run = _listRun(block);
    if (run.isEmpty) return;
    final lines = run.length == 1 ? '1 line' : '${run.length} lines';
    if (!await _confirm('Delete this list?', '$lines will go.')) return;
    _removeBlocks(run);
  }

  Future<void> _deletePicture(NoteBlock block) async {
    if (!await _confirm('Delete this picture?',
        'It goes from the note and from the phone. The rest of the note '
        'stays.')) {
      return;
    }
    _removeBlocks([block]);
  }

  /// The one confirmation shape this screen uses. Typing is undoable by
  /// retyping; deleting a picture or a whole list is not, so those ask.
  Future<bool> _confirm(String title, String detail) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
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
    return answer == true && mounted;
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
    if (!await _confirm('Delete this note?', _note.displayTitle)) return;
    _saveTimer?.cancel();
    // The held store rather than a fresh lookup: _confirm has already been
    // away and back, and the tree may not be here any more.
    await _store?.remove(_note.id);
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
              tooltip: _dockTop
                  ? 'Put the controls above the keyboard'
                  : 'Pin the controls to the top',
              icon: Icon(_dockTop
                  ? Icons.vertical_align_bottom
                  : Icons.vertical_align_top),
              onPressed: _toggleDock,
            ),
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteNote,
            ),
          ],
        ),
        // The toolbar rides in the body rather than in bottomNavigationBar:
        // the Scaffold shrinks its body to clear the keyboard but leaves a
        // bottom bar underneath it, which is how the tools used to disappear
        // exactly when there was text to format.
        body: Column(
          children: [
            if (_dockTop) _toolbar(),
            // With the bar at the top it is the text, not the bar, that
            // runs down to the system navigation — so the inset moves too.
            Expanded(
              child: SafeArea(top: false, bottom: _dockTop, child: _blocks()),
            ),
            if (!_dockTop) _toolbar(),
          ],
        ),
      ),
    );
  }

  Widget _blocks() {
    final theme = Theme.of(context);
    return ListView(
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
          Stack(
            children: [
              // Tapping the picture makes it the line the toolbar acts on.
              // Without this the only way to select one was its caption,
              // which nobody has to have written.
              GestureDetector(
                onTap: () => setState(() => _active = block.id),
                child: ConstrainedBox(
                  // A picture is drawn at its own size, so a small one would
                  // otherwise be smaller than the button sitting on it —
                  // which puts the button outside the picture, where taps
                  // never land.
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: ClipRRect(
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
                ),
              ),
              // On the picture itself, not in the toolbar: a picture has no
              // cursor in it, so a tool that acts on "the line you are in"
              // is no way to get rid of one.
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: theme.colorScheme.surface.withOpacity(0.72),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Delete this picture',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    onPressed: () => _deletePicture(block),
                  ),
                ),
              ),
            ],
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

  /// The formatting bar. Acts on whichever line the cursor is in, and stays
  /// put while the keyboard is up — pinned just above it, or under the app
  /// bar if that is where the coach put it.
  Widget _toolbar() {
    final block = _activeBlock;
    final theme = Theme.of(context);
    final divider = Divider(
        height: 1, thickness: 1, color: theme.colorScheme.outlineVariant);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        // Docked at the top there is no system inset beneath the bar to
        // clear — the body below it goes on for the rest of the screen.
        bottom: !_dockTop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_dockTop) divider,
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  // The formatting tools scroll: a dozen of them don't fit
                  // across a phone, and the ones that fall off the end are
                  // the rarer ones.
                  Expanded(
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
                      ],
                    ),
                  ),
                  // Deleting stays put at the end of the bar rather than
                  // scrolling away with the rest: a tool you cannot find is
                  // a tool you do not have.
                  const _ToolDivider(),
                  // Only where there is a list to delete — a run of one
                  // kind of list line goes in one tap rather than in nine.
                  if (block != null && _listRun(block).length > 1)
                    _tool(Icons.playlist_remove, 'Delete this list',
                        onTap: _deleteList),
                  _tool(Icons.backspace_outlined, 'Delete this line',
                      onTap: _deleteBlock),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            if (_dockTop) divider,
          ],
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
