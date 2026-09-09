import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/screens/athlete_screen.dart';
import 'package:throwlab/services/athlete_library.dart';
import 'package:throwlab/services/notes_library.dart';
import 'package:throwlab/services/video_library.dart';

/// Editing the record a profile can't derive: the nickname it goes by, and
/// the full name and school a heat sheet is matched against.
void main() {
  late VideoLibrary library;
  late NotesLibrary notes;
  late AthleteLibrary athletes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    library = VideoLibrary();
    await library.load();
    notes = NotesLibrary();
    await notes.load();
    athletes = AthleteLibrary();
    await athletes.load();
    // A mark gives the athlete a profile to open.
    await library.addMark(ThrowMark(
      id: 'm1',
      athlete: 'Robert Fischer',
      event: ThrowEvent.shotPut,
      implementKg: 5.44,
      distance: 15.2,
      achievedOn: DateTime(2026, 5, 1),
    ));
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoLibrary>.value(value: library),
        ChangeNotifierProvider<NotesLibrary>.value(value: notes),
        ChangeNotifierProvider<AthleteLibrary>.value(value: athletes),
      ],
      child: MaterialApp(
        home: AthleteScreen(
            name: 'Robert Fischer', titleFor: (video) => video.event.label),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a nickname becomes the display name', (tester) async {
    await open(tester);
    expect(find.text('Robert Fischer'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Nickname'), 'Bud');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The heading is the nickname now, with the filed name kept underneath.
    expect(find.text('Bud'), findsWidgets);
    expect(athletes.recordFor('Robert Fischer')?.nickname, 'Bud');
    expect(find.textContaining('filed as Robert Fischer'), findsOneWidget);
  });

  testWidgets('a full name and school are kept for a heat sheet match',
      (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'School or club'), 'Central HS');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(athletes.recordFor('Robert Fischer')?.school, 'Central HS');
    expect(find.textContaining('Central HS'), findsOneWidget);
  });
}
