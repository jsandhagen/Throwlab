// Renders the training note editor to a PNG, so the block editor and its
// formatting bar can be reviewed without a device.
//
//   flutter test --update-goldens tool/preview/note_preview.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';
import 'package:throwlab/screens/note_editor_screen.dart';
import 'package:throwlab/services/notes_library.dart';

import 'harness.dart';
import 'sample_library.dart';

const _out = '../../build/preview';

void main() {
  testWidgets('training note', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.notes': jsonEncode(sampleNotes()),
    });

    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final notes = NotesLibrary();
    await notes.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<NotesLibrary>.value(
        value: notes,
        child: MaterialApp(
          theme: ThrowLabApp.theme,
          home: NoteEditorScreen(note: notes.byId('note-1')!),
        ),
      ),
    );
    await settle(tester);
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('$_out/note.png'));
  });
}
