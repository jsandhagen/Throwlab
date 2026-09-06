// The stand-in library the preview renderers paint: a handful of throws
// across three athletes, and the "frames" they are stills of.
//
// Generated at run time rather than committed, so the previews need no
// fixtures and no image package — there is a minimal PNG encoder at the
// bottom of this file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Marks with no clip behind them: one athlete's competition results, and
/// a thrower who is only ever in a results sheet.
List<Map<String, dynamic>> sampleMarks() {
  final now = DateTime.now();
  String daysAgo(int days) =>
      DateTime(now.year, now.month, now.day - days, 14).toIso8601String();

  Map<String, dynamic> mark(
    String id,
    String athlete,
    String event,
    double implementKg,
    double distance,
    String achievedOn, {
    String note = '',
    String distanceUnit = 'metres',
  }) =>
      {
        'id': id,
        'athlete': athlete,
        'event': event,
        'implementKg': implementKg,
        'distance': distance,
        'distanceUnit': distanceUnit,
        'achievedOn': achievedOn,
        'note': note,
      };

  return [
    mark('m1', 'Anna Sofia', 'discus', 1, 54.02, daysAgo(16),
        note: 'County Champs, final'),
    mark('m2', 'Anna Sofia', 'discus', 1, 51.30, daysAgo(44),
        note: 'League match'),
    // Nothing of hers was ever filmed: the whole season is a results sheet.
    mark('m3', 'Priya Raman', 'hammer', 4, 58.44, daysAgo(11),
        note: 'Regional final'),
    mark('m4', 'Priya Raman', 'hammer', 4, 56.10, daysAgo(39)),
  ];
}

List<Map<String, dynamic>> sampleLibrary(List<String> thumbs) {
  Map<String, dynamic> video(
    String id,
    String athlete,
    String event,
    double implementKg,
    String recordedAt, {
    double captureFps = 30,
    String note = '',
    double? distance,
    String distanceUnit = 'metres',
    String? thumbnail,
  }) =>
      {
        'id': id,
        'path': '/videos/$id.mp4',
        'event': event,
        'implementKg': implementKg,
        'importedAt': recordedAt,
        'recordedAt': recordedAt,
        'fps': 30.0,
        'captureFps': captureFps,
        'note': note,
        'athlete': athlete,
        'distance': distance,
        'distanceUnit': distanceUnit,
        'thumbnailPath': thumbnail,
      };

  final now = DateTime.now();
  String daysAgo(int days, int hour) =>
      DateTime(now.year, now.month, now.day - days, hour).toIso8601String();

  return [
    video('1', 'Anna Sofia', 'discus', 1, daysAgo(2, 15),
        captureFps: 240, note: 'PB attempt, slight headwind',
        distance: 52.18, thumbnail: thumbs[0]),
    video('2', 'Anna Sofia', 'discus', 1, daysAgo(2, 14),
        distance: 49.80, thumbnail: thumbs[2]),
    video('3', 'Anna Sofia', 'discus', 1, daysAgo(9, 11),
        captureFps: 120, note: 'Standing throws', distance: 47.05,
        thumbnail: thumbs[0]),
    video('4', 'Jakob', 'javelin', 0.8, daysAgo(21, 12),
        captureFps: 240, note: 'Full approach', distance: 61.44,
        distanceUnit: 'feet', thumbnail: thumbs[1]),
    video('5', 'Jakob', 'javelin', 0.8, daysAgo(22, 12),
        note: '~2.5 m/s tailwind', distance: 58.9, thumbnail: thumbs[1]),
    video('6', 'Adam', 'shotPut', 7.26, daysAgo(30, 9),
        distance: 18.90, thumbnail: thumbs[2]),
    // The same athlete on two weights, which is a training week rather than
    // an oddity — and two marks that must not be rolled into one.
    video('8', 'Adam', 'shotPut', 6, daysAgo(31, 10),
        note: 'Light implement day', distance: 20.44, thumbnail: thumbs[1]),
    video('7', '', 'hammer', 4, daysAgo(120, 9),
        note: 'Imported before thumbnails existed'),
  ];
}

/// Writes three stand-in "frames" (sky/grass, track, indoor) to a temp dir
/// and returns their paths.
List<String> sampleThumbnails() {
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
