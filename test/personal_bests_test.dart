import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:throwlab/models/athlete_profile.dart';
import 'package:throwlab/models/throw_event.dart';
import 'package:throwlab/models/throw_video.dart';
import 'package:throwlab/services/video_library.dart';

ThrowVideo _throw(
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

/// Who holds a personal best, and what an athlete's profile makes of it.
void main() {
  group('personalBestIds', () {
    test('the furthest throw at an event and weight holds the mark', () {
      final ids = personalBestIds([
        _throw('near', distance: 14.10),
        _throw('far', distance: 15.02),
        _throw('middle', distance: 14.88),
      ]);
      expect(ids, {'far'});
    });

    test('a weight keeps its own mark rather than the heavier one\'s', () {
      // 12.90 with the 4 kg does not touch what she has done with the 3 kg,
      // and a lighter implement must not erase the heavy mark either.
      final ids = personalBestIds([
        _throw('heavy', implementKg: 4, distance: 12.90),
        _throw('light', implementKg: 3, distance: 14.40),
      ]);
      expect(ids, {'heavy', 'light'});
    });

    test('each event is scored on its own', () {
      final ids = personalBestIds([
        _throw('shot', event: ThrowEvent.shotPut, distance: 14.10),
        _throw('disc',
            event: ThrowEvent.discus, implementKg: 1, distance: 44.60),
      ]);
      expect(ids, {'shot', 'disc'});
    });

    test('one athlete never takes another\'s mark', () {
      final ids = personalBestIds([
        _throw('ana', athlete: 'Ana Diaz', distance: 14.10),
        _throw('bea', athlete: 'Bea Cole', distance: 13.02),
      ]);
      expect(ids, {'ana', 'bea'});
    });

    test('a name spelled differently is still the same athlete', () {
      final ids = personalBestIds([
        _throw('one', athlete: 'Ana Diaz', distance: 14.10),
        _throw('two', athlete: ' ana diaz ', distance: 13.02),
      ]);
      expect(ids, {'one'});
    });

    test('an unmeasured throw can never be a best', () {
      final ids = personalBestIds([
        _throw('measured', distance: 11.20),
        _throw('unmeasured'),
      ]);
      expect(ids, {'measured'});
    });

    test('untagged throws hold no marks at all', () {
      // Otherwise "Unassigned" becomes one fictional thrower whose record
      // is whatever the longest loose clip in the library happens to be.
      final ids = personalBestIds([
        _throw('loose', athlete: '', distance: 21.30),
        _throw('other', athlete: '  ', distance: 19.80),
      ]);
      expect(ids, isEmpty);
    });

    test('the earlier throw keeps a mark that is only equalled', () {
      final ids = personalBestIds([
        _throw('later', distance: 14.10, on: DateTime(2026, 6, 2)),
        _throw('first', distance: 14.10, on: DateTime(2026, 4, 9)),
      ]);
      expect(ids, {'first'});
    });

    test('a single measured throw is already a best', () {
      expect(personalBestIds([_throw('only', distance: 9.44)]), {'only'});
    });
  });

  group('AthleteProfile', () {
    test('collects one best per event and weight, in event order', () {
      final profile = AthleteProfile.of('Ana Diaz', [
        _throw('shot-4', distance: 14.10),
        _throw('shot-4b', distance: 13.20),
        _throw('shot-3', implementKg: 3, distance: 15.60),
        _throw('disc',
            event: ThrowEvent.discus, implementKg: 1, distance: 44.60),
        _throw('elsewhere', athlete: 'Bea Cole', distance: 99),
      ]);

      expect([for (final best in profile.bests) best.video.id],
          ['shot-4', 'shot-3', 'disc']);
      expect(profile.bests.first.distance, 14.10);
      // Two 4 kg throws behind the mark, one 3 kg throw behind that one.
      expect(profile.bests.first.attempts, 2);
      expect(profile.bests[1].attempts, 1);
      expect(profile.bestAt(ThrowEvent.shotPut, 4)?.video.id, 'shot-4');
      expect(profile.bestAt(ThrowEvent.hammer, 4), isNull);
    });

    test('holds only that athlete\'s throws, newest first', () {
      final profile = AthleteProfile.of('ana diaz', [
        _throw('old', on: DateTime(2026, 1, 5)),
        _throw('new', on: DateTime(2026, 3, 5)),
        _throw('theirs', athlete: 'Bea Cole', on: DateTime(2026, 4, 5)),
      ]);
      expect([for (final video in profile.throws) video.id], ['new', 'old']);
      expect(profile.name, 'Ana Diaz'); // the newest throw's spelling wins
      expect(profile.lastThrewOn, DateTime(2026, 3, 5));
      expect(profile.firstThrewOn, DateTime(2026, 1, 5));
      expect(profile.events, [ThrowEvent.shotPut]);
    });

    test('counts what is measured and lists no bests without a distance', () {
      final profile = AthleteProfile.of('Ana Diaz', [
        _throw('a', distance: 12.4),
        _throw('b'),
        _throw('c'),
      ]);
      expect(profile.throws, hasLength(3));
      expect(profile.measured, 1);
      expect(profile.bests, hasLength(1));
    });

    test('an athlete with nothing left reads as empty', () {
      final profile = AthleteProfile.of('Ana Diaz', []);
      expect(profile.isEmpty, isTrue);
      expect(profile.name, 'Ana Diaz');
      expect(profile.lastThrewOn, isNull);
    });
  });

  group('VideoLibrary', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('marks the best throw and re-marks it when one is beaten', () async {
      final library = VideoLibrary();
      await library.load();
      final first = _throw('first', distance: 14.10);
      final second = _throw('second', distance: 13.00);
      await library.add(first);
      await library.add(second);

      expect(library.isPersonalBest(first), isTrue);
      expect(library.isPersonalBest(second), isFalse);

      // The distance a coach types in later counts the moment it is saved.
      second.distance = 15.44;
      await library.update(second);
      expect(library.isPersonalBest(second), isTrue);
      expect(library.isPersonalBest(first), isFalse);
    });

    test('deleting the record holder hands the mark back', () async {
      final library = VideoLibrary();
      await library.load();
      final holder = _throw('holder', distance: 14.10);
      final runnerUp = _throw('runner-up', distance: 13.00);
      await library.add(holder);
      await library.add(runnerUp);

      await library.remove(holder.id);
      expect(library.isPersonalBest(runnerUp), isTrue);
    });

    test('reads the marks back from storage', () async {
      final saved = VideoLibrary();
      await saved.load();
      await saved.add(_throw('near', distance: 12.00));
      await saved.add(_throw('far', distance: 16.00));

      final reloaded = VideoLibrary();
      await reloaded.load();
      final far = reloaded.videos.firstWhere((video) => video.id == 'far');
      expect(reloaded.isPersonalBest(far), isTrue);
      expect(reloaded.profileFor('Ana Diaz').bests.single.distance, 16.00);
    });

    test('tagging a loose clip gives it a mark to hold', () async {
      final library = VideoLibrary();
      await library.load();
      final loose = _throw('loose', athlete: '', distance: 18.20);
      await library.add(loose);
      expect(library.isPersonalBest(loose), isFalse);

      loose.athlete = 'Ana Diaz';
      await library.update(loose);
      expect(library.isPersonalBest(loose), isTrue);
    });
  });
}
