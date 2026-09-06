import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/athlete_profile.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_mark.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/video_library.dart';

ThrowVideo _clip(
  String id, {
  String athlete = 'Ana Diaz',
  ThrowEvent event = ThrowEvent.shotPut,
  double implementKg = 4,
  double? distance,
  DateTime? on,
}) =>
    ThrowVideo(
      id: id,
      path: '/$id.mp4',
      event: event,
      implementKg: implementKg,
      importedAt: on ?? DateTime(2026, 5, 1),
      athlete: athlete,
      distance: distance,
    );

ThrowMark _mark(
  String id, {
  String athlete = 'Ana Diaz',
  ThrowEvent event = ThrowEvent.shotPut,
  double implementKg = 4,
  double distance = 15,
  DateTime? on,
  String note = '',
}) =>
    ThrowMark(
      id: id,
      athlete: athlete,
      event: event,
      implementKg: implementKg,
      distance: distance,
      achievedOn: on ?? DateTime(2026, 5, 1),
      note: note,
    );

/// Marks: the throws that were measured but never filmed, which is most of
/// what an athlete actually does.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('records', () {
    test('a mark that went further takes the best off a clip', () {
      final ids = personalBestIds([
        _clip('filmed', distance: 14.10),
        _mark('meet', distance: 15.02),
      ]);
      expect(ids, {'meet'});
    });

    test('a clip that went further keeps it', () {
      final ids = personalBestIds([
        _clip('filmed', distance: 15.02),
        _mark('meet', distance: 14.10),
      ]);
      expect(ids, {'filmed'});
    });

    test('a mark is still scored per event and weight', () {
      final ids = personalBestIds([
        _mark('shot-4', implementKg: 4, distance: 12.90),
        _mark('shot-3', implementKg: 3, distance: 14.40),
        _mark('disc',
            event: ThrowEvent.discus, implementKg: 1, distance: 44.60),
      ]);
      expect(ids, {'shot-4', 'shot-3', 'disc'});
    });
  });

  group('AthleteProfile', () {
    test('keeps clips and marks apart but scores them together', () {
      final profile = AthleteProfile.of(
        'Ana Diaz',
        [_clip('filmed', distance: 14.10)],
        [
          _mark('meet', distance: 15.02, on: DateTime(2026, 6, 1)),
          _mark('other', athlete: 'Bea Cole', distance: 21),
        ],
      );

      expect(profile.throws.single.id, 'filmed');
      expect(profile.marks.single.id, 'meet');
      // One best, out of two throws, held by the one nobody filmed.
      expect(profile.bests.single.result.id, 'meet');
      expect(profile.bests.single.attempts, 2);
      expect(profile.bests.single.isFilmed, isFalse);
      expect(profile.bests.single.video, isNull);
      expect(profile.measured, 2);
    });

    test('an athlete with only marks still has a profile', () {
      final profile = AthleteProfile.of('Ana Diaz', [], [
        _mark('one', distance: 15.02, on: DateTime(2026, 6, 1)),
        _mark('two', distance: 14.10, on: DateTime(2026, 4, 1)),
      ]);

      expect(profile.isEmpty, isFalse);
      expect(profile.throws, isEmpty);
      expect(profile.marks, hasLength(2));
      expect(profile.bests.single.distance, 15.02);
      expect(profile.firstThrewOn, DateTime(2026, 4, 1));
      expect(profile.lastThrewOn, DateTime(2026, 6, 1));
      expect(profile.events, [ThrowEvent.shotPut]);
    });
  });

  group('VideoLibrary', () {
    late VideoLibrary library;

    setUp(() async {
      library = VideoLibrary();
      await library.load();
    });

    test('records, edits and deletes a mark', () async {
      final mark = _mark('m1', distance: 15.02);
      await library.addMark(mark);
      expect(library.marks.single.distance, 15.02);
      expect(library.isPersonalBest(mark), isTrue);

      mark.distance = 16.44;
      await library.updateMark(mark);
      expect(library.marks.single.distance, 16.44);

      await library.removeMark(mark.id);
      expect(library.marks, isEmpty);
    });

    test('a mark takes the medal off a clip, and gives it back', () async {
      final clip = _clip('filmed', distance: 14.10);
      await library.add(clip);
      expect(library.isPersonalBest(clip), isTrue);

      final mark = _mark('m1', distance: 15.02);
      await library.addMark(mark);
      expect(library.isPersonalBest(clip), isFalse);
      expect(library.isPersonalBest(mark), isTrue);

      await library.removeMark(mark.id);
      expect(library.isPersonalBest(clip), isTrue);
    });

    test('marks survive a reload, and clips are untouched by them',
        () async {
      await library.add(_clip('filmed', distance: 14.10));
      await library.addMark(_mark('m1', distance: 15.02, note: 'County'));

      final reloaded = VideoLibrary();
      await reloaded.load();
      expect(reloaded.videos.single.id, 'filmed');
      expect(reloaded.marks.single.note, 'County');
      expect(reloaded.profileFor('Ana Diaz').bests.single.result.id, 'm1');
    });

    test('a corrupt mark list costs the marks, never the clips', () async {
      await library.add(_clip('filmed', distance: 14.10));
      SharedPreferences.setMockInitialValues({
        'flutter.throwlab.videos':
            (await SharedPreferences.getInstance())
                .getString('throwlab.videos')!,
        'flutter.throwlab.marks': '{not json',
      });

      final reloaded = VideoLibrary();
      await reloaded.load();
      expect(reloaded.videos, hasLength(1));
      expect(reloaded.marks, isEmpty);
    });

    test('an athlete known only from a mark is offered by name', () async {
      await library.addMark(_mark('m1', athlete: 'Bea Cole'));
      expect(library.knownAthletes, ['Bea Cole']);
      expect(library.athletesWithoutClips, ['Bea Cole']);
    });

    test('an athlete with a clip is not counted as clipless', () async {
      await library.add(_clip('filmed', athlete: 'Ana Diaz'));
      await library.addMark(_mark('m1', athlete: 'ana diaz'));
      expect(library.athletesWithoutClips, isEmpty);
      expect(library.knownAthletes, ['Ana Diaz']);
    });

    test('knows when someone last threw, filmed or not', () async {
      await library.add(_clip('filmed', on: DateTime(2026, 3, 1)));
      await library.addMark(_mark('m1', on: DateTime(2026, 7, 4)));
      expect(library.lastThrewOn('ANA DIAZ'), DateTime(2026, 7, 4));
      expect(library.lastThrewOn('nobody'), isNull);
    });
  });
}
