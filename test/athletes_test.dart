import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/video_library.dart';

ThrowVideo _video(String id, String athlete) => ThrowVideo(
      id: id,
      path: '/v$id.mp4',
      event: ThrowEvent.discus,
      gender: Gender.women,
      importedAt: DateTime.parse('2026-06-11T10:30:00'),
      fps: 60,
      athlete: athlete,
    );

Future<VideoLibrary> _libraryOf(List<ThrowVideo> videos) async {
  final library = VideoLibrary();
  await library.load();
  // add() inserts at the front, so add oldest first to end up with the
  // real newest-first ordering.
  for (final video in videos.reversed) {
    await library.add(video);
  }
  return library;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('VideoLibrary.knownAthletes', () {
    test('is empty when nothing is tagged', () async {
      final library = await _libraryOf([_video('1', ''), _video('2', '  ')]);
      expect(library.knownAthletes, isEmpty);
    });

    test('lists each athlete once, most recent first', () async {
      final library = await _libraryOf([
        _video('3', 'Riley'),
        _video('2', 'Sam'),
        _video('1', 'Riley'),
      ]);
      expect(library.knownAthletes, ['Riley', 'Sam']);
    });

    test('treats differently-cased spellings as one athlete, newest wins',
        () async {
      final library = await _libraryOf([
        _video('2', 'Sam'),
        _video('1', 'sam'),
      ]);
      expect(library.knownAthletes, ['Sam']);
    });

    test('trims stored names and skips untagged clips', () async {
      final library = await _libraryOf([
        _video('3', '  Riley  '),
        _video('2', ''),
        _video('1', 'Sam'),
      ]);
      expect(library.knownAthletes, ['Riley', 'Sam']);
    });

    test('picks up a name the moment a clip is tagged', () async {
      final library = await _libraryOf([_video('1', '')]);
      expect(library.knownAthletes, isEmpty);

      final video = library.videos.single;
      video.athlete = 'Riley';
      await library.update(video);
      expect(library.knownAthletes, ['Riley']);
    });
  });
}
