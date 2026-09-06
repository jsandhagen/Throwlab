import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/video_library.dart';

void main() {
  runApp(const ThrowLabApp());
}

class ThrowLabApp extends StatelessWidget {
  const ThrowLabApp({super.key});

  /// The one place the app's look is decided — screens don't restyle it.
  /// Named so the preview renderers in tool/ can paint a single screen
  /// under the real theme instead of a default one.
  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Barlow',
        colorScheme: ColorScheme.fromSeed(
          // Matches the light blue of the flask-and-javelin logo.
          seedColor: const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          titleSpacing: 16,
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
    return ChangeNotifierProvider(
      create: (_) => VideoLibrary()..load(),
      child: MaterialApp(
        title: 'ThrowLab',
        theme: theme,
        home: const HomeScreen(),
      ),
    );
  }
}
