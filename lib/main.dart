import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/athlete_library.dart';
import 'services/meet_library.dart';
import 'services/meet_relay.dart';
import 'services/meet_server.dart';
import 'services/notes_library.dart';
import 'services/video_library.dart';
import 'widgets/distance_field.dart';

void main() {
  // Read before anything opens a sheet, so the first one is already in
  // the unit the coach works in.
  DistanceField.loadPreference();
  runApp(const ThrowLabApp());
}

class ThrowLabApp extends StatelessWidget {
  const ThrowLabApp({super.key});

  /// The one place the app's look is decided — screens don't restyle it.
  /// Named so the preview renderers in tool/ can paint a single screen
  /// under the real theme instead of a default one.
  static ThemeData get theme => _themeFor(ColorScheme.fromSeed(
        // Matches the light blue of the flask-and-javelin logo.
        seedColor: const Color(0xFF4FC3F7),
        brightness: Brightness.dark,
      ));

  static ThemeData _themeFor(ColorScheme scheme) => ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Barlow',
        colorScheme: scheme,
        useMaterial3: true,
        // The bar keeps its color when a list scrolls under it. Material 3
        // swaps it for surfaceContainer there — a lighter gray, which on
        // this dark theme read as the header changing under the thumb, and
        // left it a different gray from the header bands laid on the plain
        // surface beneath it. Only a color named here stops the swap.
        appBarTheme: AppBarTheme(
          centerTitle: false,
          titleSpacing: 16,
          backgroundColor: scheme.surface,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        sliderTheme: const SliderThemeData(
          showValueIndicator: ShowValueIndicator.never,
          trackHeight: 6,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VideoLibrary()..load()),
        ChangeNotifierProvider(create: (_) => NotesLibrary()..load()),
        ChangeNotifierProvider(create: (_) => MeetLibrary()..load()),
        ChangeNotifierProvider(create: (_) => AthleteLibrary()..load()),
        // Nothing is listening and no socket is open until a coach asks to
        // share a meet, so this costs nothing to have around.
        ChangeNotifierProvider(create: (_) => MeetServer()),
        ChangeNotifierProvider(create: (_) => MeetRelay()),
      ],
      child: MaterialApp(
        title: 'ThrowLab',
        theme: theme,
        home: const HomeScreen(),
      ),
    );
  }
}
