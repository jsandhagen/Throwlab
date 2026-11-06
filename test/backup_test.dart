import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/services/backup.dart';

/// The library in one file and back: what goes in, where it lands on a phone
/// that gives the app another directory, and that a restore only ever adds.
void main() {
  late Directory temp;
  late String oldDocs;
  late String newDocs;
  late String external;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('throwlab_backup');
    oldDocs = '${temp.path}/old/app_flutter';
    newDocs = '${temp.path}/new/app_flutter';
    external = '${temp.path}/gallery/VID_0001.mp4';
    for (final (path, body) in [
      ('$oldDocs/throws/a.mp4', 'clip a'),
      ('$oldDocs/throws/a.jpg', 'thumb a'),
      ('$oldDocs/throws/b.mp4', 'clip b'),
      ('$oldDocs/notes/n1/block1.jpg', 'picture'),
      // A clip whose encode failed still plays off the file it came from.
      (external, 'gallery clip'),
      // Stills are cut again on the first open, so they stay behind.
      ('$oldDocs/throws/a_frames/f00001.jpg', 'still'),
    ]) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
    }
    Directory(newDocs).createSync(recursive: true);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Map<String, dynamic> video(String id, String path, {String? thumb}) => {
        'id': id,
        'path': path,
        'thumbnailPath': thumb,
        'scrubFramesDir': '$oldDocs/throws/${id}_frames',
        'scrubFrameCount': 120,
        'scrubFramesVersion': 6,
      };

  Map<String, Object> phone() => {
        'throwlab.videos': jsonEncode([
          video('a', '$oldDocs/throws/a.mp4', thumb: '$oldDocs/throws/a.jpg'),
          video('b', '$oldDocs/throws/b.mp4'),
          video('c', external),
        ]),
        'throwlab.marks': jsonEncode([
          {'id': 'm1', 'distance': 14.2},
        ]),
        'throwlab.notes': jsonEncode([
          {
            'id': 'n1',
            'blocks': [
              {'id': 'block1', 'imagePath': '$oldDocs/notes/n1/block1.jpg'},
            ],
          },
        ]),
        'throwlab.athletes': jsonEncode([
          {'name': 'Ana Diaz', 'nickname': 'Ana'},
        ]),
        'throwlab.distanceUnit': 'feet',
        'throwlab.meetsCalendar': true,
      };

  Future<String> backUp() async {
    final out = '${temp.path}/backup.zip';
    await LibraryBackup.write(prefs: phone(), docs: oldDocs, outPath: out);
    return out;
  }

  test('carries every file the library points at, and not the stills',
      () async {
    final zip = await backUp();
    final input = InputFileStream(zip);
    final names =
        ZipDecoder().decodeStream(input).files.map((file) => file.name).toSet();
    await input.close();
    expect(names, {
      LibraryBackup.manifestName,
      'files/throws/a.mp4',
      'files/throws/a.jpg',
      'files/throws/b.mp4',
      'files/notes/n1/block1.jpg',
      'external/0_VID_0001.mp4',
    });
    expect(File('$zip.part').existsSync(), isFalse);
  });

  test('says what it holds before anything is restored', () async {
    final info = await LibraryBackup.inspect(await backUp());
    expect(info.createdAt, isNotNull);
    expect(info.summary.contents, '3 clips · 1 mark · 0 meets · 1 note');
    expect(info.summary.files, 5);
  });

  test('restores onto a phone that keeps the app somewhere else', () async {
    final result = await LibraryBackup.restore(
      await backUp(),
      current: const {},
      docs: newDocs,
    );
    final videos =
        (jsonDecode(result.values['throwlab.videos'] as String) as List)
            .cast<Map<String, dynamic>>();
    final a = videos.firstWhere((v) => v['id'] == 'a');
    expect(a['path'], '$newDocs/throws/a.mp4');
    expect(a['thumbnailPath'], '$newDocs/throws/a.jpg');
    expect(File(a['path'] as String).readAsStringSync(), 'clip a');
    // The stills come back as owed, under the new directory.
    expect(a['scrubFramesDir'], '$newDocs/throws/a_frames');
    expect(a['scrubFrameCount'], 0);
    expect(a['scrubFramesVersion'], 0);

    final c = videos.firstWhere((v) => v['id'] == 'c');
    expect(c['path'], '$newDocs/restored/0_VID_0001.mp4');
    expect(File(c['path'] as String).readAsStringSync(), 'gallery clip');

    final note = (jsonDecode(result.values['throwlab.notes'] as String) as List)
        .single as Map<String, dynamic>;
    final picture =
        ((note['blocks'] as List).single as Map)['imagePath'] as String;
    expect(picture, '$newDocs/notes/n1/block1.jpg');
    expect(File(picture).readAsStringSync(), 'picture');

    expect(result.values['throwlab.distanceUnit'], 'feet');
    expect(result.values['throwlab.meetsCalendar'], true);
    expect(result.addedTo('throwlab.videos'), 3);
    expect(result.addedTo('throwlab.marks'), 1);
    expect(result.addedTo('throwlab.athletes'), 1);
    expect(File('$newDocs/throws/a_frames/f00001.jpg').existsSync(), isFalse);
  });

  test('only adds: what is on the phone stays as it is', () async {
    // The phone already has its own throw 'a', a renamed athlete and a
    // setting of its own, and a clip the backup never saw.
    File('$newDocs/throws/a.mp4')
      ..createSync(recursive: true)
      ..writeAsStringSync('the phone\'s own a');
    final current = <String, Object>{
      'throwlab.videos': jsonEncode([
        {'id': 'a', 'path': '$newDocs/throws/a.mp4', 'note': 'edited here'},
        {'id': 'z', 'path': '$newDocs/throws/z.mp4'},
      ]),
      'throwlab.athletes': jsonEncode([
        {'name': 'ana diaz', 'nickname': 'Annie'},
      ]),
      'throwlab.distanceUnit': 'meters',
    };
    final result = await LibraryBackup.restore(await backUp(),
        current: current, docs: newDocs);
    final videos =
        (jsonDecode(result.values['throwlab.videos'] as String) as List)
            .cast<Map<String, dynamic>>();
    expect(videos.map((v) => v['id']), ['a', 'z', 'b', 'c']);
    expect(videos.first['note'], 'edited here');
    expect(
        File('$newDocs/throws/a.mp4').readAsStringSync(), 'the phone\'s own a');
    final athletes =
        jsonDecode(result.values['throwlab.athletes'] as String) as List;
    expect(athletes.single['nickname'], 'Annie');
    expect(result.values['throwlab.distanceUnit'], 'meters');
    expect(result.addedTo('throwlab.videos'), 2);
    expect(result.addedTo('throwlab.athletes'), 0);
  });

  test('restoring the same backup twice adds nothing the second time',
      () async {
    final zip = await backUp();
    final first =
        await LibraryBackup.restore(zip, current: const {}, docs: newDocs);
    final second =
        await LibraryBackup.restore(zip, current: first.values, docs: newDocs);
    expect(second.addedAnything, isFalse);
    expect(second.values['throwlab.videos'], first.values['throwlab.videos']);
  });

  test('turns away a zip that is not a backup', () async {
    final zip = '${temp.path}/other.zip';
    final encoder = ZipFileEncoder()..create(zip);
    encoder.addArchiveFile(ArchiveFile.bytes('hello.txt', utf8.encode('hi')));
    await encoder.close();
    expect(LibraryBackup.inspect(zip), throwsFormatException);
  });

  test('never writes outside the app\'s own directory', () async {
    final zip = '${temp.path}/hostile.zip';
    final manifest = {
      'format': LibraryBackup.format,
      'version': LibraryBackup.version,
      'docs': oldDocs,
      'files': {'/x': 'files/../../escaped.txt'},
      'prefs': <String, dynamic>{},
    };
    final encoder = ZipFileEncoder()..create(zip);
    encoder.addArchiveFile(ArchiveFile.bytes(
        LibraryBackup.manifestName, utf8.encode(jsonEncode(manifest))));
    encoder.addArchiveFile(
        ArchiveFile.bytes('files/../../escaped.txt', utf8.encode('x')));
    await encoder.close();
    await expectLater(
        LibraryBackup.restore(zip, current: const {}, docs: newDocs),
        throwsFormatException);
    expect(File('${temp.path}/new/escaped.txt').existsSync(), isFalse);
    expect(File('${temp.path}/escaped.txt').existsSync(), isFalse);
  });

  test('a backup made by a newer app says so', () async {
    final zip = '${temp.path}/newer.zip';
    final encoder = ZipFileEncoder()..create(zip);
    encoder.addArchiveFile(ArchiveFile.bytes(
        LibraryBackup.manifestName,
        utf8.encode(jsonEncode({
          'format': LibraryBackup.format,
          'version': LibraryBackup.version + 1,
        }))));
    await encoder.close();
    expect(
        LibraryBackup.inspect(zip),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('newer ThrowLab'))));
  });

  test('sizes read the way a phone states them', () {
    expect(formatBytes(512), '1 KB');
    expect(formatBytes(820 * 1000 * 1000), '820 MB');
    expect(formatBytes(1400 * 1000 * 1000), '1.4 GB');
  });
}
