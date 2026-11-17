// Renders the coach's notebook to PNGs: the pages by section, a page with
// every kind of embed on it, the + menu, and the research tab.
//
//   flutter test --update-goldens tool/preview/notebook_preview.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';

import 'harness.dart';
import 'sample_library.dart';

const _out = '../../build/preview';

Map<String, dynamic> _block(String id, String kind,
        {String text = '', String? ref, String? url, bool checked = false}) =>
    {
      'id': id,
      'kind': kind,
      'text': text,
      'checked': checked,
      if (ref != null) 'ref': ref,
      if (url != null) 'url': url,
    };

List<Map<String, dynamic>> _sections() => [
      {'id': 's1', 'name': 'Drills'},
      {'id': 's2', 'name': 'Cues'},
      {'id': 's3', 'name': 'Season plan'},
    ];

List<Map<String, dynamic>> _pages() {
  final now = DateTime.now();
  String daysAgo(int days) =>
      DateTime(now.year, now.month, now.day - days, 10).toIso8601String();
  Map<String, dynamic> page(String id, String title, String? section,
          int age, List<Map<String, dynamic>> blocks, {bool pinned = false}) =>
      {
        'id': id,
        'title': title,
        'sectionId': section,
        'pinned': pinned,
        'createdAt': daysAgo(age + 3),
        'updatedAt': daysAgo(age),
        'blocks': blocks,
      };
  return [
    page('p1', 'Discus: south African drill', 's1', 1, [
      _block('a1', 'callout',
          text: 'Sweep wide, land **narrow** — the right foot turns on '
              'the ball before it lands.'),
      _block('a2', 'paragraph',
          text: 'Anna finally got it on Tuesday. Her best stand throw '
              'after six of these:'),
      _block('a3', 'clip', ref: '1', text: 'Watch the right heel at 0:02'),
      _block('a4', 'heading', text: 'Progression'),
      _block('a5', 'numbered', text: 'Walk-through, no implement'),
      _block('a6', 'numbered', text: 'Half turn with a towel'),
      _block('a7', 'numbered', text: 'Full South African, 1 kg'),
      _block('a8', 'divider'),
      _block('a9', 'link',
          url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          text: 'The clinic video the drill came from'),
      _block('a10', 'athlete', ref: 'Anna Sofia', text: 'Who it was for'),
      _block('a11', 'checklist', text: 'Film it from behind next week'),
      _block('a12', 'checklist',
          text: 'Try it with the 1.6 kg', checked: true),
    ], pinned: true),
    page('p2', 'Words that worked', 's2', 4, [
      _block('b1', 'bullet', text: '"Long left side" — Adam, shot'),
      _block('b2', 'bullet', text: '"Hit the wall" for the block'),
      _block('b3', 'bullet', text: '"Quiet head" in the turn'),
    ]),
    page('p3', 'County Champs plan', 's3', 6, [
      _block('c1', 'meet', ref: 'k1'),
      _block('c2', 'checklist', text: 'Two warm-up throws, then sit'),
      _block('c3', 'checklist', text: 'Spikes, tape, the 1 kg'),
    ]),
    page('p4', 'Overweight implements', null, 12, [
      _block('d1', 'paragraph',
          text: 'Reading on heavy-light throwing for the winter block.'),
      _block('d2', 'link', url: 'https://doi.org/10.1080/02640414.2010.000000'),
    ]),
  ];
}

void main() {
  testWidgets('coach notebook', (tester) async {
    await loadPreviewFonts();
    final thumbs = sampleThumbnails();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.videos': jsonEncode(sampleLibrary(thumbs)),
      'flutter.throwlab.marks': jsonEncode(sampleMarks()),
      'flutter.throwlab.meets': jsonEncode(sampleMeets()),
      'flutter.throwlab.notebook': jsonEncode(_pages()),
      'flutter.throwlab.notebookSections': jsonEncode(_sections()),
    });
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> shoot(String name) async {
      await settle(tester);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
    }

    await warmImages(tester, thumbs);
    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);
    await shoot('notebook_home_bar');

    await tester.tap(find.byKey(const ValueKey('open-notebook')));
    await shoot('notebook_pages');

    await tester.tap(find.widgetWithText(FilterChip, 'Drills'));
    await shoot('notebook_section');
    await tester.tap(find.widgetWithText(FilterChip, 'All'));
    await settle(tester);

    await tester.tap(find.text('Discus: south African drill'));
    await shoot('notebook_page');

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await shoot('notebook_page_scrolled');

    await tester.tap(find.byTooltip('Add a throw, link, picture…'));
    await shoot('notebook_insert');
    await tester.tapAt(const Offset(180, 80));
    await settle(tester);

    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('tab-research')));
    await shoot('notebook_research');
  });

  testWidgets('empty notebook', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('open-notebook')));
    await settle(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$_out/notebook_empty.png'));
  });
}
