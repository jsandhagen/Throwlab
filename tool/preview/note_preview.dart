// Renders the training note editor to PNGs, so the block editor and its
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

/// A phone-sized keyboard, in physical pixels. Nothing paints one in a test,
/// so the preview both insets the screen by it and draws a stand-in — the
/// point of the shot is where the toolbar sits relative to it.
const _keyboard = 780.0;

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

    Future<void> shoot(String name) async {
      await settle(tester);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));
    }

    await tester.pumpWidget(
      ChangeNotifierProvider<NotesLibrary>.value(
        value: notes,
        child: MaterialApp(
          theme: ThrowLabApp.theme,
          builder: (context, child) => Stack(
            children: [
              child!,
              // The stand-in: whatever the screen has been inset by is what
              // the keyboard would be covering.
              if (MediaQuery.viewInsetsOf(context).bottom > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: MediaQuery.viewInsetsOf(context).bottom,
                  child: const ColoredBox(
                    color: Color(0xFF202124),
                    child: Center(
                      // Styled outright: this sits outside the app's own
                      // theme, so it would otherwise paint as boxes.
                      child: Text(
                        'the keyboard is here',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 13,
                          color: Color(0xFF9AA0A6),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          home: NoteEditorScreen(note: notes.byId('note-1')!),
        ),
      ),
    );
    await shoot('note');

    // Typing in it: the keyboard takes the bottom of the screen, and the
    // formatting bar has to end up above it rather than under it.
    await tester.tap(find.byType(TextField).at(2));
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await shoot('note-keyboard');

    // The same, with the bar pinned under the app bar instead.
    await tester.tap(find.byTooltip('Pin the controls to the top'));
    await shoot('note-keyboard-top');
  });
}
