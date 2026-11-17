import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/notebook.dart';
import 'package:throwlab/models/research.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/training_note.dart';
import 'package:throwlab/screens/note_editor_screen.dart';
import 'package:throwlab/screens/notebook_screen.dart';
import 'package:throwlab/services/notebook_library.dart';
import 'package:throwlab/services/notes_library.dart';
import 'package:throwlab/widgets/notebook_embeds.dart';

import 'analysis_harness.dart';

NotebookPage _page({
  String id = 'p1',
  String title = '',
  String? sectionId,
  bool pinned = false,
  List<NoteBlock> blocks = const [],
  DateTime? updatedAt,
}) =>
    NotebookPage(
      id: id,
      title: title,
      sectionId: sectionId,
      pinned: pinned,
      createdAt: DateTime(2026, 5, 1),
      updatedAt: updatedAt ?? DateTime(2026, 5, 1),
      blocks: [for (final block in blocks) block.copy()],
    );

/// The coach's notebook: pages, sections, embeds, and the research tab.
void main() {
  group('a page', () {
    test('survives JSON, embeds and all', () {
      final page = _page(title: 'Drills', sectionId: 's1', pinned: true, blocks: [
        NoteBlock(id: 'b1', text: 'Stand throws first'),
        NoteBlock(id: 'b2', kind: NoteBlockKind.clip, ref: 'v9'),
        NoteBlock(
            id: 'b3',
            kind: NoteBlockKind.link,
            url: 'https://youtube.com/watch?v=x',
            text: 'Lecture'),
        NoteBlock(id: 'b4', kind: NoteBlockKind.divider),
      ]);
      final back = NotebookPage.fromJson(
          jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>);
      expect(back.title, 'Drills');
      expect(back.sectionId, 's1');
      expect(back.pinned, isTrue);
      expect(back.blocks.map((b) => b.kind), [
        NoteBlockKind.paragraph,
        NoteBlockKind.clip,
        NoteBlockKind.link,
        NoteBlockKind.divider,
      ]);
      expect(back.blocks[1].ref, 'v9');
      expect(back.blocks[2].url, 'https://youtube.com/watch?v=x');
    });

    test('a training note with no embeds stores no embed fields', () {
      final json = NoteBlock(id: 'b1', text: 'x').toJson();
      expect(json.containsKey('ref'), isFalse);
      expect(json.containsKey('url'), isFalse);
    });

    test('reads as its first line, and previews what it holds', () {
      final page = _page(blocks: [
        NoteBlock(id: 'b1', kind: NoteBlockKind.clip, ref: 'v1'),
        NoteBlock(id: 'b2', text: '**Block** drill'),
        NoteBlock(id: 'b3', kind: NoteBlockKind.link, url: 'https://a.org'),
      ]);
      expect(page.displayTitle, 'Block drill');
      expect(page.preview, 'A throw');
      expect(page.embedCounts,
          {NoteBlockKind.clip: 1, NoteBlockKind.link: 1});
    });

    test('a divider is never blank, an empty line always is', () {
      expect(NoteBlock(id: 'a', kind: NoteBlockKind.divider).isBlank, isFalse);
      expect(NoteBlock(id: 'b').isBlank, isTrue);
      expect(NoteBlock(id: 'c', kind: NoteBlockKind.clip, ref: 'v').isBlank,
          isFalse);
    });

    test('is found by its words, captions and links', () {
      final page = _page(title: 'Season', blocks: [
        NoteBlock(id: 'b1', text: 'Power **clean** day'),
        NoteBlock(
            id: 'b2', kind: NoteBlockKind.link, url: 'https://doi.org/10.1/x'),
      ]);
      expect(page.matches('clean'), isTrue);
      expect(page.matches('doi.org'), isTrue);
      expect(page.matches('season'), isTrue);
      expect(page.matches('hammer'), isFalse);
    });
  });

  group('the notebook library', () {
    late NotebookLibrary library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      library = NotebookLibrary();
      await library.load();
    });

    test('keeps pinned pages first, then the latest edited', () async {
      // Apart in time, since a save stamps the page with now.
      for (final id in ['a', 'b', 'c']) {
        await library.save(_page(id: id));
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      expect(library.pages.first.id, 'c');
      await library.setPinned('a', true);
      expect(library.pages.map((p) => p.id), ['a', 'c', 'b']);
    });

    test('files pages into sections, and keeps them when one goes',
        () async {
      final drills = await library.addSection('Drills');
      final cues = await library.addSection('Cues');
      await library.save(_page(id: 'a', sectionId: drills.id));
      await library.save(_page(id: 'b'));
      expect(library.pagesIn(drills.id).map((p) => p.id), ['a']);
      expect(library.pagesIn(null).map((p) => p.id), ['b']);

      await library.moveSection(cues.id, -1);
      expect(library.sections.map((s) => s.name), ['Cues', 'Drills']);

      await library.renameSection(drills.id, 'Throwing drills');
      expect(library.sectionById(drills.id)?.name, 'Throwing drills');

      await library.removeSection(drills.id);
      expect(library.pages, hasLength(2));
      expect(library.pagesIn(null), hasLength(2));
    });

    test('reads back what it wrote', () async {
      final section = await library.addSection('Cues');
      await library.save(_page(id: 'a', title: 'Hips', sectionId: section.id));
      final again = NotebookLibrary();
      await again.load();
      expect(again.pages.single.title, 'Hips');
      expect(again.sections.single.name, 'Cues');
    });

    test('a corrupt store opens as an empty notebook', () async {
      SharedPreferences.setMockInitialValues(
          {NotebookLibrary.pagesKey: 'not json'});
      final broken = NotebookLibrary();
      await broken.load();
      expect(broken.pages, isEmpty);
      expect(broken.isLoaded, isTrue);
    });
  });

  group('links', () {
    test('take the https nobody types', () {
      expect(normalizeUrl('youtube.com/watch?v=abc'),
          'https://youtube.com/watch?v=abc');
      expect(normalizeUrl('http://example.org'), 'http://example.org');
    });

    test('turn down what is not an address', () {
      expect(normalizeUrl(''), isNull);
      expect(normalizeUrl('two words'), isNull);
      expect(normalizeUrl('localhost'), isNull);
      expect(normalizeUrl('ftp://example.org'), isNull);
    });

    test('know a video when they see one', () {
      expect(isVideoLink('https://www.youtube.com/watch?v=a'), isTrue);
      expect(isVideoLink('https://youtu.be/a'), isTrue);
      expect(isVideoLink('https://doi.org/10.1/x'), isFalse);
    });
  });

  group('research', () {
    const entry = ResearchEntry(
      id: 'e1',
      title: 'A finding',
      topic: ResearchTopic.biomechanics,
      events: {ThrowEvent.shotPut},
      summary: 'Release speed mattered most.',
      takeaways: ['Speed first'],
      tips: ['Measure it'],
      citations: [
        Citation(
            authors: 'Doe, J.',
            year: 2000,
            title: 'A study',
            source: 'A journal',
            doi: '10.0/abc'),
      ],
    );

    test('an entry applies to its events, or to all when it names none',
        () {
      expect(entry.appliesTo(ThrowEvent.shotPut), isTrue);
      expect(entry.appliesTo(ThrowEvent.hammer), isFalse);
      expect(entry.appliesTo(null), isTrue);
    });

    test('a citation links through its DOI', () {
      final citation = entry.citations.single;
      expect(citation.link, 'https://doi.org/10.0/abc');
      expect(citation.reference, 'Doe, J. (2000). A study. A journal.');
    });

    test('a search reaches into the tips and the sources', () {
      expect(entry.matches('measure'), isTrue);
      expect(entry.matches('journal'), isTrue);
      expect(entry.matches('javelin'), isFalse);
    });
  });

  group('the notebook screen', () {
    late NotebookLibrary notebook;
    late NotesLibrary notes;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      notebook = NotebookLibrary();
      await notebook.load();
      notes = NotesLibrary();
      await notes.load();
    });

    Future<void> mount(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(500, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotebookLibrary>.value(value: notebook),
          ChangeNotifierProvider<NotesLibrary>.value(value: notes),
        ],
        child: MaterialApp(home: home),
      ));
      await pumpFrames(tester, 6);
    }

    testWidgets('opens empty with somewhere to start', (tester) async {
      await mount(tester, const NotebookScreen());
      expect(find.text('Your notebook'), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-new-page')), findsOneWidget);
    });

    testWidgets('lists pages by section', (tester) async {
      final drills = await notebook.addSection('Drills');
      await notebook.save(_page(id: 'a', title: 'Stand throws', sectionId: drills.id));
      await notebook.save(_page(id: 'b', title: 'Meet-day plan'));
      await mount(tester, const NotebookScreen());

      expect(find.text('Stand throws'), findsOneWidget);
      expect(find.text('Meet-day plan'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Drills'));
      await pumpFrames(tester);
      expect(find.text('Stand throws'), findsOneWidget);
      expect(find.text('Meet-day plan'), findsNothing);
    });

    testWidgets('the research tab lays out its topics', (tester) async {
      await mount(tester, const NotebookScreen());
      await tester.tap(find.byKey(const ValueKey('tab-research')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('research-coming')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-technique')), findsOneWidget);
    });

    testWidgets('a research entry saves to the notebook as a page',
        (tester) async {
      const entry = ResearchEntry(
        id: 'e1',
        title: 'A finding',
        topic: ResearchTopic.coaching,
        summary: 'Something found.',
        takeaways: ['One'],
        tips: ['Try it'],
        citations: [
          Citation(authors: 'Doe, J.', year: 2000, title: 'T', doi: '10.0/a'),
        ],
      );
      await mount(tester, const ResearchEntryScreen(entry: entry));
      await tester.tap(find.byKey(const ValueKey('research-save')));
      await pumpFrames(tester);
      final page = notebook.pages.single;
      expect(page.title, 'A finding');
      expect(page.blocks.first.kind, NoteBlockKind.callout);
      expect(page.blocks.last.kind, NoteBlockKind.link);
      expect(page.blocks.last.url, 'https://doi.org/10.0/a');
    });

    testWidgets('the editor puts a divider on a page and saves it there',
        (tester) async {
      await mount(tester, NoteEditorScreen(note: _page(id: 'p1')));
      expect(find.text("Coach's notebook"), findsOneWidget);
      await tester.tap(find.byTooltip('Add a throw, link, picture…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insert-divider')));
      await tester.pumpAndSettle();
      final stored = notebook.byId('p1');
      expect(stored, isNotNull);
      expect(stored!.blocks.any((b) => b.kind == NoteBlockKind.divider),
          isTrue);
      // Training notes never see it.
      expect(notes.notes, isEmpty);
    });
  });
}
