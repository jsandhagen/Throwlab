import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/meet.dart';
import 'package:throwlab/screens/schedule_import_screen.dart';
import 'package:throwlab/services/meet_library.dart';

/// Importing a season: what the coach sees before anything reaches the
/// calendar, and what reaches it when they say so.
void main() {
  late MeetLibrary meets;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    meets = MeetLibrary();
    await meets.load();
  });

  const schedule = '''
Sat 13 March 2027 — Tiger Relays @ Auburn
Sat 10 April 2027 — County Champs @ Sportcity
''';

  /// A one-page PDF with a schedule laid out in two columns.
  Uint8List schedulePdf() {
    const content = 'BT /F1 12 Tf 72 700 Td (13 March 2027) Tj '
        '140 0 Td (Tiger Relays) Tj ET';
    final file = StringBuffer()
      ..write('%PDF-1.4\n')
      ..write('1 0 obj\n<< /Type /Font /Subtype /Type1 '
          '/BaseFont /Helvetica >>\nendobj\n')
      ..write('2 0 obj\n<< >>\nstream\n$content\nendstream\nendobj\n')
      ..write('3 0 obj\n<< /Type /Page /Resources << /Font << /F1 1 0 R >> >> '
          '/Contents 2 0 R >>\nendobj\n')
      ..write('%%EOF\n');
    return Uint8List.fromList(latin1.encode(file.toString()));
  }

  Future<void> open(WidgetTester tester,
      {Future<Uint8List?> Function()? readPdf}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<MeetLibrary>.value(value: meets)],
      child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    ));
    // Pushed rather than mounted, so adding can walk back the way it does
    // in the app.
    Navigator.push(
      tester.element(find.byType(Scaffold)),
      MaterialPageRoute(builder: (_) => ScheduleImportScreen(readPdf: readPdf)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Read it'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists what it read before anything is added', (tester) async {
    await open(tester);
    await paste(tester, schedule);
    expect(find.text('Tiger Relays'), findsOneWidget);
    expect(find.text('County Champs'), findsOneWidget);
    expect(find.text('Add 2 meets'), findsOneWidget);
    // Nothing has been written yet, whatever it found.
    expect(meets.meets, isEmpty);
  });

  testWidgets('adds the ticked meets, with their venues', (tester) async {
    await open(tester);
    await paste(tester, schedule);
    await tester.tap(find.text('Add 2 meets'));
    await tester.pumpAndSettle();

    expect(meets.meets.map((m) => m.name), ['County Champs', 'Tiger Relays']);
    final tigers = meets.meets.firstWhere((m) => m.name == 'Tiger Relays');
    expect(tigers.date, DateTime(2027, 3, 13));
    expect(tigers.venue, 'Auburn');
    // The format a schedule never states, defaulted to a 3 + 3.
    expect(tigers.rounds, 6);
    expect(tigers.prelimRounds, 3);
  });

  testWidgets('leaves out a meet that was unticked', (tester) async {
    await open(tester);
    await paste(tester, schedule);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 1 meet'));
    await tester.pumpAndSettle();
    expect(meets.meets.map((m) => m.name), ['County Champs']);
  });

  testWidgets('will not enter a meet the calendar already has',
      (tester) async {
    await meets.save(Meet(
        id: 'k1', name: 'Tiger Relays', date: DateTime(2027, 3, 13)));
    await open(tester);
    await paste(tester, schedule);

    expect(find.text('Already on the calendar'), findsOneWidget);
    expect(find.text('Add 1 meet'), findsOneWidget);
    await tester.tap(find.text('Add 1 meet'));
    await tester.pumpAndSettle();
    expect(meets.meets.length, 2);
  });

  testWidgets('shows what it had to guess', (tester) async {
    await open(tester);
    await paste(tester, '4/12/2027  Spring Open');
    expect(find.textContaining('month first'), findsOneWidget);
  });

  testWidgets('says so when it can read nothing', (tester) async {
    await open(tester);
    await paste(tester, 'Squad training\nBring your own implements');
    expect(find.textContaining('Nothing on that looked like a meet'),
        findsOneWidget);
    expect(find.text('Add 1 meet'), findsNothing);
  });

  group('a PDF', () {
    testWidgets('is read into the same review', (tester) async {
      await open(tester, readPdf: () async => schedulePdf());
      await tester.tap(find.text('Open a PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Tiger Relays'), findsOneWidget);
      expect(find.text('Add 1 meet'), findsOneWidget);
    });

    testWidgets('says so when it is a scan with no text in it',
        (tester) async {
      await open(tester,
          readPdf: () async =>
              Uint8List.fromList(latin1.encode('%PDF-1.4\nno text here\n')));
      await tester.tap(find.text('Open a PDF'));
      await tester.pumpAndSettle();
      expect(find.textContaining('it may be a scan'), findsOneWidget);
    });

    testWidgets('does nothing when nobody picked one', (tester) async {
      await open(tester, readPdf: () async => null);
      await tester.tap(find.text('Open a PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Open a PDF'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });
  });
}
