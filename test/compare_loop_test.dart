import 'package:flutter_test/flutter_test.dart';
import 'package:throwlab/utils/compare_loop.dart';
import 'package:throwlab/utils/scrub_frames.dart';

void main() {
  // The releases sit at different points of their own clips, which is the
  // whole reason the loop normalizes on them. Both clips are long enough to
  // hold the full lead-in and follow-through.
  const syncA = Duration(seconds: 3);
  const syncB = Duration(seconds: 5);
  const length = Duration(seconds: 10);

  CompareLoop build({CompareRoutine routine = CompareRoutine.together}) {
    // The frame directories need not exist: the loop only asks ScrubFrames
    // which still a position lands on, which is arithmetic.
    final loop = CompareLoop(
      framesA: ScrubFrames(dir: '/none', count: 300, stride: 1, fps: 30),
      framesB: ScrubFrames(dir: '/none', count: 300, stride: 1, fps: 30),
      vsync: const TestVSync(),
    )
      ..speed = 1
      ..routine = routine
      ..setClips(
          syncA: syncA, syncB: syncB, durationA: length, durationB: length);
    addTearDown(loop.dispose);
    return loop;
  }

  /// Runs the loop for [total], sampling where both clips sit every 50 ms.
  Future<List<({Duration a, Duration b})>> sample(
      WidgetTester tester, CompareLoop loop, Duration total) async {
    const step = Duration(milliseconds: 50);
    final poses = <({Duration a, Duration b})>[];
    loop.start();
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
      poses.add(loop.poses);
    }
    loop.stop();
    return poses;
  }

  group('the window', () {
    test('the lead-in is whichever clip has less run-up before its release',
        () {
      final loop = build();
      // A has 3 s before its release and B has 5, but the ceiling is 2 s.
      expect(loop.leadIn, const Duration(seconds: 2));

      loop.setClips(
          syncA: const Duration(milliseconds: 800),
          syncB: syncB,
          durationA: length,
          durationB: length);
      // A only holds 0.8 s of run-up, so that is what both show.
      expect(loop.leadIn, const Duration(milliseconds: 800));
    });

    test('the follow-through is likewise the shorter of the two', () {
      final loop = build()
        ..setClips(
            syncA: syncA,
            syncB: const Duration(milliseconds: 9600),
            durationA: length,
            durationB: length);
      expect(loop.followThrough, const Duration(milliseconds: 400));
    });

    test('there is nothing to play until both releases are marked', () {
      final loop = build()
        ..setClips(
            syncA: syncA,
            syncB: Duration.zero,
            durationA: length,
            durationB: length);
      expect(loop.hasWindow, isFalse);

      loop.setClips(
          syncA: syncA, syncB: syncB, durationA: length, durationB: length);
      expect(loop.hasWindow, isTrue);
    });
  });

  group('played together', () {
    testWidgets('the two stay the same distance from their own releases',
        (tester) async {
      final loop = build();
      final poses = await sample(tester, loop, const Duration(seconds: 3));

      // The invariant the whole comparison rests on: whatever moment of the
      // window is on screen, both clips are at the same point of their own
      // throw. They cannot drift, because neither is being played — both are
      // indexed off one clock.
      for (final pose in poses) {
        expect(syncA - pose.a, syncB - pose.b,
            reason: 'the clips came apart at ${pose.a} / ${pose.b}');
      }
    });

    testWidgets('it starts a lead-in before each release and runs past them',
        (tester) async {
      final loop = build();
      final poses = await sample(tester, loop, const Duration(seconds: 3));

      expect(poses.first.a, lessThan(syncA));
      expect(poses.first.b, lessThan(syncB));
      // 3 s at 1x covers the 3.5 s window's releases and then some.
      expect(poses.last.a, greaterThan(syncA));
      expect(poses.last.b, greaterThan(syncB));
    });

    testWidgets('it comes back round rather than running off the end',
        (tester) async {
      final loop = build();
      // The window is 3.5 s, so five seconds is one full pass and part of
      // the next.
      final poses = await sample(tester, loop, const Duration(seconds: 5));

      expect(poses.last.a, lessThan(syncA),
          reason: 'the second pass should be back before the release');
      for (final pose in poses) {
        expect(pose.a, greaterThanOrEqualTo(Duration.zero));
        expect(pose.a, lessThanOrEqualTo(length));
        expect(pose.b, greaterThanOrEqualTo(Duration.zero));
        expect(pose.b, lessThanOrEqualTo(length));
      }
    });
  });

  group('taken in turn', () {
    testWidgets('both run together, then A throws alone, then B does',
        (tester) async {
      final loop = build(routine: CompareRoutine.inTurn);
      final poses =
          await sample(tester, loop, const Duration(milliseconds: 7300));

      /// Whether each clip moved between one sample and the next.
      List<({bool a, bool b})> moves() => [
            for (var i = 1; i < poses.length; i++)
              (a: poses[i].a != poses[i - 1].a, b: poses[i].b != poses[i - 1].b)
          ];
      final motion = moves();

      // Together first: a stretch where both are moving.
      expect(motion.take(15).where((m) => m.a && m.b), isNotEmpty);
      // Then a stretch where A is finishing its throw and B is held.
      expect(motion.where((m) => m.a && !m.b), isNotEmpty,
          reason: 'A never threw on its own');
      // And then the other way round.
      expect(motion.where((m) => !m.a && m.b), isNotEmpty,
          reason: 'B never followed');
      // The two are never both throwing after they split up.
      final aAlone = motion.indexWhere((m) => m.a && !m.b);
      final bAlone = motion.indexWhere((m) => !m.a && m.b);
      expect(aAlone, lessThan(bAlone), reason: 'B went before A');
    });

    testWidgets('they stop together a beat before the release', (tester) async {
      final loop = build(routine: CompareRoutine.inTurn);
      final poses =
          await sample(tester, loop, const Duration(milliseconds: 7300));

      // The freeze: a run of samples where neither clip moves, with both
      // sitting [hold] short of their own release.
      var held = false;
      for (var i = 1; i < poses.length; i++) {
        if (poses[i].a != poses[i - 1].a || poses[i].b != poses[i - 1].b) {
          continue;
        }
        if (poses[i].a == syncA - CompareLoop.hold &&
            poses[i].b == syncB - CompareLoop.hold) {
          held = true;
          break;
        }
      }
      expect(held, isTrue,
          reason: 'the two never stopped together before the release');
    });

    testWidgets('each clip finishes its own follow-through', (tester) async {
      final loop = build(routine: CompareRoutine.inTurn);
      final poses =
          await sample(tester, loop, const Duration(milliseconds: 7300));

      final furthestA = poses.map((p) => p.a).reduce((a, b) => a > b ? a : b);
      final furthestB = poses.map((p) => p.b).reduce((a, b) => a > b ? a : b);
      expect(furthestA, greaterThan(syncA));
      expect(furthestB, greaterThan(syncB));
    });
  });

  testWidgets('a speed change keeps the routine where it had got to',
      (tester) async {
    final loop = build();
    loop.start();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final before = loop.poses;

    loop.speed = 0.25;
    // The picture does not jump: the legs are re-timed, not restarted.
    expect(loop.poses.a, before.a);
    expect(loop.poses.b, before.b);
    loop.stop();
  });
}
