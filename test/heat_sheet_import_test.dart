import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/screens/heat_sheet_import_screen.dart';
import 'package:throwlab/services/meet_library.dart';
import 'package:throwlab/services/video_library.dart';

/// Reading a meet's programme into the meet: which events are kept, and
/// which of the names belong to the coach.
void main() {
  late MeetLibrary meets;
  late VideoLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    meets = MeetLibrary();
    await meets.load();
    library = VideoLibrary();
    await library.load();
    await meets.save(Meet(
        id: 'k1', name: 'County Champs', date: DateTime(2026, 6, 13)));
    // One of the coach's own, known to the library from a mark.
    await library.addMark(ThrowMark(
      id: 'm1',
      athlete: 'Jakob Sandhagen',
      event: ThrowEvent.shotPut,
      implementKg: 5,
      distance: 14.2,
      achievedOn: DateTime(2026, 5, 1),
    ));
  });

  const sheet = '''
Event 15  Boys Shot Put 12lb
=======================================================================
  1 Smith, John                 12 Central HS            44-06.00
  2 SANDHAGEN, J                12 Central HS            48-02.50

Event 16  Girls Discus
=======================================================================
  1 Diaz, Ana                   11 Central HS            41.20m
''';

  Future<void> open(WidgetTester tester,
      {Future<Uint8List?> Function()? readPdf}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeetLibrary>.value(value: meets),
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
      ],
      child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    ));
    Navigator.push(
      tester.element(find.byType(Scaffold)),
      MaterialPageRoute(
        builder: (_) =>
            HeatSheetImportScreen(meetId: 'k1', readPdf: readPdf),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Read it'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the throwing events and how big each field is',
      (tester) async {
    await open(tester);
    await paste(tester, sheet);
    expect(find.textContaining('Shot Put'), findsOneWidget);
    expect(find.textContaining('Discus'), findsOneWidget);
    expect(find.textContaining('2 entered · 1 of mine'), findsOneWidget);
    // Nothing is entered until it is asked for.
    expect(meets.byId('k1')!.entries, isEmpty);
  });

  testWidgets('starts on the events one of your athletes is in',
      (tester) async {
    await open(tester);
    await paste(tester, sheet);
    // The shot put has Jakob in it; the girls' discus has nobody of theirs.
    expect(find.text('Enter 2 athletes'), findsOneWidget);
  });

  testWidgets('enters your athlete tracked and the rest of the field not',
      (tester) async {
    await open(tester);
    await paste(tester, sheet);
    await tester.tap(find.text('Enter 2 athletes'));
    await tester.pumpAndSettle();

    final entries = meets.byId('k1')!.entries;
    expect(entries.length, 2);
    final jakob =
        entries.firstWhere((e) => e.athlete == 'Jakob Sandhagen');
    // The library's spelling wins over the sheet's 'SANDHAGEN, J', or the
    // season splits between two spellings of one person.
    expect(jakob.tracked, isTrue);
    expect(jakob.event, ThrowEvent.shotPut);
    // A 12 lb shot is thrown as the 5 kg shell.
    expect(jakob.implementKg, 5);
    expect(entries.firstWhere((e) => e.athlete == 'John Smith').tracked,
        isFalse);
  });

  testWidgets('takes an event the coach ticks on as well', (tester) async {
    await open(tester);
    await paste(tester, sheet);
    // The girls' discus, which nobody of theirs is in.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter 3 athletes'));
    await tester.pumpAndSettle();
    expect(meets.byId('k1')!.entries.length, 3);
  });

  testWidgets('leaves out an athlete who is unticked', (tester) async {
    await open(tester);
    await paste(tester, sheet);
    // Open the shot put and drop the rival out of it.
    await tester.tap(find.textContaining('Shot Put'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('John Smith'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter 1 athlete'));
    await tester.pumpAndSettle();
    expect(meets.byId('k1')!.entries.single.athlete, 'Jakob Sandhagen');
  });

  testWidgets('will not enter the same athlete twice', (tester) async {
    await meets.addEntry('k1',
        entry: MeetEntry(
          id: 'e1',
          athlete: 'Jakob Sandhagen',
          event: ThrowEvent.shotPut,
          implementKg: 5,
        ));
    await open(tester);
    await paste(tester, sheet);
    // Jakob is already down for it, so only the rival is left to enter.
    expect(find.text('Enter 1 athlete'), findsOneWidget);
  });

  testWidgets('says when a weight had to be guessed', (tester) async {
    await open(tester);
    await paste(tester, sheet);
    // The girls' discus never said what weight, so the division decided.
    expect(find.textContaining('weight guessed'), findsOneWidget);
  });

  testWidgets('reads a heat sheet out of a PDF', (tester) async {
    const content = 'BT /F1 12 Tf 72 720 Td (Event 15 Boys Shot Put 12lb) Tj '
        '0 -20 Td (1 Smith, John) Tj 160 0 Td (Central HS) Tj ET';
    final file = StringBuffer()
      ..write('%PDF-1.4\n')
      ..write('1 0 obj\n<< /Type /Font /Subtype /Type1 '
          '/BaseFont /Helvetica >>\nendobj\n')
      ..write('2 0 obj\n<< >>\nstream\n$content\nendstream\nendobj\n')
      ..write('3 0 obj\n<< /Type /Page /Resources << /Font << /F1 1 0 R >> >> '
          '/Contents 2 0 R >>\nendobj\n')
      ..write('%%EOF\n');
    await open(tester,
        readPdf: () async =>
            Uint8List.fromList(latin1.encode(file.toString())));
    await tester.tap(find.text('Open a PDF'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Shot Put'), findsOneWidget);
    expect(find.text('Enter 1 athlete'), findsOneWidget);
  });

  testWidgets('says so when there is no throwing on the page',
      (tester) async {
    await open(tester);
    await paste(tester, 'Event 3 Boys 100 Meter Dash\n 1 Smith, John  11.20');
    expect(find.textContaining('No throwing events'), findsOneWidget);
  });
}
