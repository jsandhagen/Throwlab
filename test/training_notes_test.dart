import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/training_note.dart';
import 'package:throwlab/services/notes_library.dart';

TrainingNote _note({
  String id = 'n1',
  String athlete = 'Ana Diaz',
  String title = '',
  List<NoteBlock> blocks = const [],
  DateTime? updatedAt,
}) =>
    TrainingNote(
      id: id,
      athlete: athlete,
      title: title,
      createdAt: DateTime(2026, 5, 1),
      updatedAt: updatedAt ?? DateTime(2026, 5, 1),
      blocks: [for (final block in blocks) block.copy()],
    );

NoteBlock _block(String id, String text,
        [NoteBlockKind kind = NoteBlockKind.paragraph]) =>
    NoteBlock(id: id, kind: kind, text: text);

/// Training notes: how they read, and how they are stored.
void main() {
  group('emphasis', () {
    List<String> texts(String source) =>
        [for (final run in inlineRuns(source)) run.text];

    test('marks a bold run and drops its markers', () {
      final runs = inlineRuns('keep the **left side** long');
      expect(texts('keep the **left side** long'),
          ['keep the ', 'left side', ' long']);
      expect(runs[1].bold, isTrue);
      expect(runs[0].bold, isFalse);
    });

    test('nests, because the markers only ever toggle', () {
      final runs = inlineRuns('**bold and *both* back**');
      expect(runs.map((r) => r.text), ['bold and ', 'both', ' back']);
      expect(runs.every((run) => run.bold), isTrue);
      expect(runs[1].italic, isTrue);
      expect(runs[0].italic, isFalse);
    });

    test('an unclosed marker styles the rest of the line', () {
      // Which is what someone halfway through typing one has written.
      final runs = inlineRuns('block the __left');
      expect(runs.last.underline, isTrue);
      expect(stripMarkers('block the __left'), 'block the left');
    });

    test('keeps the markers when the editor asks for them', () {
      final runs = inlineRuns('a **b**', keepMarkers: true);
      expect(runs.map((r) => r.text), ['a ', '**', 'b', '**']);
      expect(runs.where((run) => run.isMarker), hasLength(2));
      // Rebuilt exactly, or the cursor would land in the wrong place.
      expect(runs.map((r) => r.text).join(), 'a **b**');
    });

    test('spans carry the styling a reader sees', () {
      final spans = inlineSpans('plain **loud**',
          base: const TextStyle(fontSize: 12));
      expect(spans, hasLength(2));
      expect((spans.last as TextSpan).style?.fontWeight, FontWeight.w700);
      expect((spans.first as TextSpan).style?.fontWeight, isNull);
    });
  });

  group('a note reads as', () {
    test('its title, or its first line when it has none', () {
      expect(_note(title: 'Throws day').displayTitle, 'Throws day');
      expect(
        _note(blocks: [_block('b1', '**Left side** stayed long')])
            .displayTitle,
        'Left side stayed long',
      );
      expect(_note().displayTitle, 'Untitled note');
    });

    test('a preview of what it says next', () {
      final note = _note(title: 'Throws day', blocks: [
        _block('b1', 'Block earlier', NoteBlockKind.bullet),
        _block('b2', 'Second line'),
      ]);
      expect(note.preview, 'Block earlier');
    });

    test('skipping the line that stood in for a missing title', () {
      final note = _note(blocks: [
        _block('b1', 'Standing throws'),
        _block('b2', 'Felt rushed'),
      ]);
      expect(note.displayTitle, 'Standing throws');
      expect(note.preview, 'Felt rushed');
    });

    test('counting its pictures and its checklist', () {
      final note = _note(blocks: [
        NoteBlock(
            id: 'b1',
            kind: NoteBlockKind.image,
            imagePath: '/p.jpg',
            text: 'Release'),
        _block('b2', 'Warm up', NoteBlockKind.checklist)..checked = true,
        _block('b3', 'Six full throws', NoteBlockKind.checklist),
      ]);
      expect(note.pictureCount, 1);
      expect(note.checklist.done, 1);
      expect(note.checklist.total, 2);
    });
  });

  group('NotesLibrary', () {
    late NotesLibrary notes;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      notes = NotesLibrary();
      await notes.load();
    });

    test('keeps one athlete\'s notes apart from another\'s', () async {
      await notes.save(_note(id: 'n1', athlete: 'Ana Diaz'));
      await notes.save(_note(id: 'n2', athlete: 'Bea Cole'));
      expect(notes.notesFor('ana diaz').single.id, 'n1');
      expect(notes.notesFor('  Bea Cole ').single.id, 'n2');
      expect(notes.notesFor('Nobody'), isEmpty);
    });

    test('stores a copy, so an unsaved edit stays unsaved', () async {
      final note = _note(blocks: [_block('b1', 'First')]);
      await notes.save(note);

      note.blocks.first.text = 'Changed my mind';
      expect(notes.byId('n1')!.blocks.first.text, 'First');

      await notes.save(note);
      expect(notes.byId('n1')!.blocks.first.text, 'Changed my mind');
    });

    test('lists the most recently edited first', () async {
      await notes.save(_note(id: 'old'));
      await notes.save(_note(id: 'new'));
      // save() stamps updatedAt, so the second one leads.
      expect([for (final note in notes.notesFor('Ana Diaz')) note.id],
          ['new', 'old']);
    });

    test('survives a reload, blocks and all', () async {
      await notes.save(_note(title: 'Throws day', blocks: [
        _block('b1', 'Six full throws', NoteBlockKind.numbered),
        NoteBlock(
            id: 'b2',
            kind: NoteBlockKind.image,
            imagePath: '/p.jpg',
            text: 'Release'),
        _block('b3', 'Warm up', NoteBlockKind.checklist)..checked = true,
      ]));

      final reloaded = NotesLibrary();
      await reloaded.load();
      final note = reloaded.notesFor('Ana Diaz').single;
      expect(note.title, 'Throws day');
      expect(note.blocks.map((b) => b.kind), [
        NoteBlockKind.numbered,
        NoteBlockKind.image,
        NoteBlockKind.checklist,
      ]);
      expect(note.blocks[1].imagePath, '/p.jpg');
      expect(note.blocks[2].checked, isTrue);
    });

    test('a block kind it has never heard of reads as a paragraph', () {
      // A note written by a newer version should lose the styling of one
      // line, not the whole note.
      final block = NoteBlock.fromJson({'id': 'b1', 'kind': 'quote', 'text': 'x'});
      expect(block.kind, NoteBlockKind.paragraph);
      expect(block.text, 'x');
    });

    test('a corrupt store recovers with no notes rather than no app',
        () async {
      SharedPreferences.setMockInitialValues(
          {'flutter.throwlab.notes': '{not json'});
      final broken = NotesLibrary();
      await broken.load();
      expect(broken.isLoaded, isTrue);
      expect(broken.notes, isEmpty);
    });

    test('deleting one picture leaves the file gone and the note alone',
        () async {
      final temp = await Directory.systemTemp.createTemp('throwlab_pic');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/p.png')..writeAsStringSync('x');

      await notes.deletePicture(file.path);
      expect(file.existsSync(), isFalse);
      // A picture that has already gone is not an error worth having.
      await notes.deletePicture(file.path);
    });

    test('deleting one leaves the rest', () async {
      await notes.save(_note(id: 'n1'));
      await notes.save(_note(id: 'n2'));
      await notes.remove('n1');
      expect([for (final note in notes.notes) note.id], ['n2']);
    });
  });
}
