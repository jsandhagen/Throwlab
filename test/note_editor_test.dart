import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/training_note.dart';
import 'package:throwlab/screens/note_editor_screen.dart';
import 'package:throwlab/services/notes_library.dart';

import 'analysis_harness.dart';

/// Writing a note: typing, lists, emphasis, pictures, and the fact that it
/// saves itself.
void main() {
  late NotesLibrary notes;
  late Directory temp;
  late File picture;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notes = NotesLibrary();
    await notes.load();
    // Made here rather than inside a testWidgets body: real file I/O never
    // completes inside the test binding's fake async, and awaiting it there
    // hangs the test rather than failing it.
    temp = await Directory.systemTemp.createTemp('throwlab_note');
    picture = File('${temp.path}/p.png')..writeAsBytesSync(_onePixelPng);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  TrainingNote note({List<NoteBlock> blocks = const [], String title = ''}) =>
      TrainingNote(
        id: 'n1',
        athlete: 'Ana Diaz',
        title: title,
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
        blocks: blocks,
      );

  Future<void> mountEditor(WidgetTester tester, TrainingNote which) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<NotesLibrary>.value(
      value: notes,
      child: MaterialApp(home: NoteEditorScreen(note: which)),
    ));
    await pumpFrames(tester, 6);
  }

  /// The block fields, in order. The title is a field too, and leads.
  Finder blockField(int index) => find.byType(TextField).at(index + 1);

  /// The toolbar scrolls on a phone; its last few tools need reaching.
  Future<void> scrollToolbar(WidgetTester tester) async {
    await tester.drag(
        find.byKey(const Key('note-toolbar')), const Offset(-320, 0));
    await pumpFrames(tester, 6);
  }

  Future<void> settleSave(WidgetTester tester) async {
    // Typing saves on a short debounce.
    await tester.pump(const Duration(milliseconds: 500));
    await pumpFrames(tester, 4);
  }

  testWidgets('a new note opens with one line to type in', (tester) async {
    await mountEditor(tester, note());
    expect(find.byType(TextField), findsNWidgets(2)); // title + one block
    expect(find.text('What happened, and what to work on'), findsOneWidget);
  });

  testWidgets('typing is saved without being asked to', (tester) async {
    await mountEditor(tester, note());
    await tester.enterText(find.byType(TextField).first, 'Throws day');
    await tester.enterText(blockField(0), 'Left side stayed long');
    await settleSave(tester);

    final saved = notes.notesFor('Ana Diaz').single;
    expect(saved.title, 'Throws day');
    expect(saved.blocks.single.text, 'Left side stayed long');
  });

  testWidgets('Enter ends a line and starts another of the same kind',
      (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', kind: NoteBlockKind.bullet, text: 'Block earlier'),
    ]));
    await tester.enterText(blockField(0), 'Block earlier\nStay tall');
    await pumpFrames(tester, 8);

    final saved = notes.notesFor('Ana Diaz').single;
    expect(saved.blocks.map((b) => b.text), ['Block earlier', 'Stay tall']);
    // A bulleted list carries on being one.
    expect(saved.blocks.map((b) => b.kind),
        [NoteBlockKind.bullet, NoteBlockKind.bullet]);
  });

  testWidgets('a heading gives way to body text on the next line',
      (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', kind: NoteBlockKind.heading, text: 'Session 3'),
    ]));
    await tester.enterText(blockField(0), 'Session 3\nWindy');
    await pumpFrames(tester, 8);

    expect(notes.notesFor('Ana Diaz').single.blocks.map((b) => b.kind),
        [NoteBlockKind.heading, NoteBlockKind.paragraph]);
  });

  testWidgets('the toolbar bolds the selection', (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', text: 'left side long'),
    ]));
    await tester.tap(blockField(0));
    await pumpFrames(tester, 4);
    // Select "left side".
    final field = tester.widget<TextField>(blockField(0));
    field.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 9);
    await pumpFrames(tester, 2);

    await tester.tap(find.byTooltip('Bold'));
    await settleSave(tester);

    expect(notes.notesFor('Ana Diaz').single.blocks.single.text,
        '**left side** long');
  });

  testWidgets('the toolbar turns a line into a list and back',
      (tester) async {
    await mountEditor(tester, note(blocks: [NoteBlock(id: 'b1', text: 'Cue')]));
    await tester.tap(blockField(0));
    await pumpFrames(tester, 4);

    await tester.tap(find.byTooltip('Numbered list'));
    await pumpFrames(tester, 6);
    expect(notes.notesFor('Ana Diaz').single.blocks.single.kind,
        NoteBlockKind.numbered);
    expect(find.text('1.'), findsOneWidget);

    // Tapping the kind it already is puts it back to a paragraph.
    await tester.tap(find.byTooltip('Numbered list'));
    await pumpFrames(tester, 6);
    expect(notes.notesFor('Ana Diaz').single.blocks.single.kind,
        NoteBlockKind.paragraph);
  });

  testWidgets('numbering restarts after a line that is not in the list',
      (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', kind: NoteBlockKind.numbered, text: 'One'),
      NoteBlock(id: 'b2', kind: NoteBlockKind.numbered, text: 'Two'),
      NoteBlock(id: 'b3', text: 'Then a thought'),
      NoteBlock(id: 'b4', kind: NoteBlockKind.numbered, text: 'One again'),
    ]));
    expect(find.text('1.'), findsNWidgets(2));
    expect(find.text('2.'), findsOneWidget);
  });

  testWidgets('a checklist item ticks, and stays ticked', (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', kind: NoteBlockKind.checklist, text: 'Warm up'),
    ]));
    await tester.tap(find.byType(Checkbox));
    await pumpFrames(tester, 6);

    expect(notes.notesFor('Ana Diaz').single.blocks.single.checked, isTrue);
  });

  testWidgets('a line can be moved and deleted', (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', text: 'First'),
      NoteBlock(id: 'b2', text: 'Second'),
    ]));
    await tester.tap(blockField(1));
    await pumpFrames(tester, 4);

    await scrollToolbar(tester);
    await tester.tap(find.byTooltip('Move up'));
    await pumpFrames(tester, 6);
    expect(notes.notesFor('Ana Diaz').single.blocks.map((b) => b.text),
        ['Second', 'First']);

    await tester.tap(find.byTooltip('Delete this line'));
    await pumpFrames(tester, 6);
    expect(notes.notesFor('Ana Diaz').single.blocks.map((b) => b.text),
        ['First']);
  });

  testWidgets('deleting the only line clears it rather than the editor',
      (tester) async {
    await mountEditor(tester, note(blocks: [NoteBlock(id: 'b1', text: 'Only')]));
    await tester.tap(blockField(0));
    await pumpFrames(tester, 4);
    await scrollToolbar(tester);
    await tester.tap(find.byTooltip('Delete this line'));
    await pumpFrames(tester, 6);

    // There is always somewhere to type — but the line itself does go.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Only'), findsNothing);
    expect(notes.notesFor('Ana Diaz').single.blocks.single.text, '');
  });

  testWidgets('a whole list goes in one tap', (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(id: 'b1', kind: NoteBlockKind.heading, text: 'Session 3'),
      NoteBlock(id: 'b2', kind: NoteBlockKind.bullet, text: 'Stay tall'),
      NoteBlock(id: 'b3', kind: NoteBlockKind.bullet, text: 'Block the left'),
      NoteBlock(id: 'b4', kind: NoteBlockKind.bullet, text: 'Finish through'),
    ]));
    // Nothing to delete until the cursor is in a list.
    expect(find.byTooltip('Delete this list'), findsNothing);
    await tester.tap(blockField(1));
    await pumpFrames(tester, 4);

    await scrollToolbar(tester);
    await tester.tap(find.byTooltip('Delete this list'));
    await pumpFrames(tester, 20);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, 20);

    // The heading above it is not part of the list, and stays.
    expect(notes.notesFor('Ana Diaz').single.blocks.map((b) => b.text),
        ['Session 3']);
  });

  testWidgets('a picture carries a caption', (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(
          id: 'b1', kind: NoteBlockKind.image, imagePath: picture.path),
    ]));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Caption this picture'), findsOneWidget);

    await tester.enterText(blockField(0), 'Release, from behind');
    await settleSave(tester);
    final saved = notes.notesFor('Ana Diaz').single.blocks.single;
    expect(saved.text, 'Release, from behind');
    expect(saved.kind, NoteBlockKind.image);
  });

  testWidgets('a picture that has gone missing says so', (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(
          id: 'b1', kind: NoteBlockKind.image, imagePath: '/gone.png'),
    ]));
    expect(find.text('Picture missing'), findsOneWidget);
  });

  testWidgets('a picture can be deleted from the picture itself',
      (tester) async {
    await mountEditor(tester, note(blocks: [
      NoteBlock(
          id: 'b1', kind: NoteBlockKind.image, imagePath: picture.path),
      NoteBlock(id: 'b2', text: 'What it should look like'),
    ]));

    await tester.tap(find.byTooltip('Delete this picture'));
    await pumpFrames(tester, 20);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, 20);

    expect(find.byType(Image), findsNothing);
    expect(notes.notesFor('Ana Diaz').single.blocks.map((b) => b.text),
        ['What it should look like']);
  });

  testWidgets('the toolbar stays above the keyboard', (tester) async {
    await mountEditor(tester, note(blocks: [NoteBlock(id: 'b1', text: 'Cue')]));
    final bar = find.byKey(const Key('note-toolbar'));

    // Up comes the keyboard, over the bottom third of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await pumpFrames(tester, 6);

    // Above the keyboard, and against it — not under it, which is where a
    // bottomNavigationBar would have gone.
    expect(tester.getBottomLeft(bar).dy, lessThanOrEqualTo(800));
    expect(tester.getBottomLeft(bar).dy, greaterThan(700));
  });

  testWidgets('the controls can be pinned to the top, and stay pinned',
      (tester) async {
    await mountEditor(tester, note(blocks: [NoteBlock(id: 'b1', text: 'Cue')]));
    final bar = find.byKey(const Key('note-toolbar'));
    expect(tester.getTopLeft(bar).dy, greaterThan(600));

    await tester.tap(find.byTooltip('Pin the controls to the top'));
    await pumpFrames(tester, 6);
    expect(tester.getTopLeft(bar).dy, lessThan(200));

    // The next note opens with the bar where it was left.
    await mountEditor(tester, note(blocks: [NoteBlock(id: 'b1', text: 'Cue')]));
    expect(tester.getTopLeft(bar).dy, lessThan(200));
    expect(find.byTooltip('Put the controls above the keyboard'),
        findsOneWidget);
  });

  testWidgets('deleting the note asks, then takes it away', (tester) async {
    await notes.save(note(title: 'Throws day'));
    await mountEditor(tester, notes.byId('n1')!);

    await tester.tap(find.byTooltip('Delete note'));
    await pumpFrames(tester, 20);
    expect(find.text('Delete this note?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, 20);

    expect(notes.notes, isEmpty);
  });
}

/// The smallest valid PNG: one transparent pixel.
final _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
