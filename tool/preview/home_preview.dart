// Renders the home screen to PNGs so library UI changes can be reviewed
// without an emulator — useful when working headless (CI, containers, an
// agent session). It is not a test: it asserts nothing, it just paints.
//
//   flutter test --update-goldens tool/preview/home_preview.dart
//
// Images land in build/preview/ (gitignored). Sample throws and their
// thumbnails are generated at run time, so no fixtures are committed.
//
// Living outside test/ keeps `flutter test` — and therefore CI — clear of it.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:throwlab/main.dart';

import 'harness.dart';

/// Where the generated PNGs go, relative to this file.
const _out = '../../build/preview';

void main() {
  testWidgets('home screen', (tester) async {
    await loadPreviewFonts();
    final thumbs = _sampleThumbnails();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'flutter.throwlab.videos': jsonEncode(_sampleLibrary(thumbs)),
    });

    // A tall phone, the way the app is actually held.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await warmImages(tester, thumbs);
    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);
    await _shoot(tester, 'home_by_athlete');

    await tester.tap(find.text('Event'));
    await settle(tester);
    await _shoot(tester, 'home_by_event');

    await tester.tap(find.text('Date'));
    await settle(tester);
    await _shoot(tester, 'home_by_date');

    await tester.enterText(find.byType(TextField).first, 'javelin');
    await settle(tester);
    await _shoot(tester, 'home_search');
  });

  testWidgets('empty library', (tester) async {
    await loadPreviewFonts();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ThrowLabApp());
    await settle(tester);
    await _shoot(tester, 'home_empty');
  });
}

Future<void> _shoot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$_out/$name.png'));

List<Map<String, dynamic>> _sampleLibrary(List<String> thumbs) {
  Map<String, dynamic> video(
    String id,
    String athlete,
    String event,
    String gender,
    String recordedAt, {
    double captureFps = 30,
    String note = '',
    double? distance,
    String? thumbnail,
  }) =>
      {
        'id': id,
        'path': '/videos/$id.mp4',
        'event': event,
        'gender': gender,
        'importedAt': recordedAt,
        'recordedAt': recordedAt,
        'fps': 30.0,
        'captureFps': captureFps,
        'note': note,
        'athlete': athlete,
        'distance': distance,
        'thumbnailPath': thumbnail,
      };

  final now = DateTime.now();
  String daysAgo(int days, int hour) =>
      DateTime(now.year, now.month, now.day - days, hour).toIso8601String();

  return [
    video('1', 'Anna Sofia', 'discus', 'women', daysAgo(2, 15),
        captureFps: 240, note: 'PB attempt, slight headwind',
        distance: 52.18, thumbnail: thumbs[0]),
    video('2', 'Anna Sofia', 'discus', 'women', daysAgo(2, 14),
        thumbnail: thumbs[2]),
    video('3', 'Anna Sofia', 'discus', 'women', daysAgo(9, 11),
        captureFps: 120, note: 'Standing throws', thumbnail: thumbs[0]),
    video('4', 'Jakob', 'javelin', 'men', daysAgo(21, 12),
        captureFps: 240, note: 'Full approach', distance: 61.44,
        thumbnail: thumbs[1]),
    video('5', 'Jakob', 'javelin', 'men', daysAgo(22, 12),
        note: '~2.5 m/s tailwind', distance: 58.9, thumbnail: thumbs[1]),
    video('6', 'Adam', 'shotPut', 'men', daysAgo(30, 9),
        thumbnail: thumbs[2]),
    video('7', '', 'hammer', 'women', daysAgo(120, 9),
        note: 'Imported before thumbnails existed'),
  ];
}

/// Writes three stand-in "frames" (sky/grass, track, indoor) to a temp dir
/// and returns their paths.
List<String> _sampleThumbnails() {
  final dir = Directory.systemTemp.createTempSync('throwlab_preview');
  int channel(double v) => v.clamp(0, 255).round();

  List<int> field(double x, double y) => y < 0.55
      ? [channel(120 + 70 * y), channel(170 + 60 * y), channel(215 + 30 * y)]
      : [channel(70 - 30 * y), channel(120 - 30 * y), channel(60 - 20 * y)];

  List<int> track(double x, double y) {
    if (y < 0.38) return [140, 175, 205];
    final lane = (y - 0.38) / 0.62 * 6;
    if ((lane - lane.roundToDouble()).abs() < 0.05) return [235, 235, 235];
    return lane.floor().isEven ? [172, 74, 58] : [188, 88, 68];
  }

  List<int> indoor(double x, double y) =>
      [channel(60 + 50 * x * (1 - y)), channel(58 + 40 * x), channel(70 + 55 * x)];

  return [
    _writePng('${dir.path}/field.png', field),
    _writePng('${dir.path}/track.png', track),
    _writePng('${dir.path}/indoor.png', indoor),
  ];
}

/// Minimal PNG encoder — enough to paint a 640x360 gradient, so the preview
/// needs no image package and no committed fixtures.
String _writePng(String path, List<int> Function(double x, double y) shade) {
  const width = 640;
  const height = 360;
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < width; x++) {
      raw.add(shade(x / width, y / height));
    }
  }

  final png = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = <int>[...ascii.encode(type), ...data];
    png
      ..add(_be32(data.length))
      ..add(body)
      ..add(_be32(_crc32(body)));
  }

  chunk('IHDR', [
    ..._be32(width),
    ..._be32(height),
    8, // bit depth
    2, // color type: truecolor
    0, 0, 0,
  ]);
  chunk('IDAT', zlib.encode(raw.takeBytes()));
  chunk('IEND', const []);
  File(path).writeAsBytesSync(png.takeBytes());
  return path;
}

List<int> _be32(int value) =>
    [value >> 24 & 0xff, value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
