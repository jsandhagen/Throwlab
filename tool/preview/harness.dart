// Shared plumbing for the preview renderers in this directory.
//
// A widget test paints nothing useful by default: the test engine ships no
// fonts, and its fake async never lets an image finish decoding. These two
// helpers deal with both. See CLAUDE.md.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers the app's own Barlow (bundled in pubspec.yaml) plus the
/// Material icon font from the SDK. Without them every glyph paints as a
/// filled box.
Future<void> loadPreviewFonts() async {
  final barlow = FontLoader('Barlow');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    barlow.addFont(rootBundle.load('assets/fonts/Barlow-$weight.ttf'));
  }
  await barlow.load();

  // Icons come from the SDK cache, which is only there when a `flutter`
  // command is what launched us.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.view(
      File('${dir.path}/MaterialIcons-Regular.otf').readAsBytesSync().buffer)));
  await icons.load();
}

/// Decodes [paths] into the image cache before the widget tree asks for
/// them. Test bindings fake out async work, so an image first resolved
/// inside a pump never finishes decoding and paints as an empty box;
/// warming the cache here — under [WidgetTester.runAsync], where async work
/// is real — means the widgets get a finished image right away.
Future<void> warmImages(WidgetTester tester, List<String> paths) async {
  await tester.runAsync(() async {
    for (final path in paths) {
      final done = Completer<void>();
      final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener((_, __) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      }, onError: (error, _) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      });
      stream.addListener(listener);
      await done.future.timeout(const Duration(seconds: 5),
          onTimeout: () => stderr.writeln('preview: $path failed to decode'));
    }
  });
}

/// Pumps until the tree is idle.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}
