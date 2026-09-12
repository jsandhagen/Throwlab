import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:throwlab/services/app_updater.dart';

/// Serves [body] in chunks, and can be told to die part-way through — which
/// is what leaving the app, or losing the track's wifi, looks like from
/// here.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.body, {this.cutAfter});

  final List<int> body;

  /// Bytes to hand over before the stream fails, or null to serve the lot.
  final int? cutAfter;

  /// Every range asked for, in order.
  final ranges = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final range = request.headers['range'];
    ranges.add(range);
    final from = range == null
        ? 0
        : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    final rest = body.sublist(from);
    final serve = cutAfter == null ? rest : rest.take(cutAfter!).toList();

    Stream<List<int>> chunks() async* {
      for (var at = 0; at < serve.length; at += 8) {
        yield Uint8List.fromList(
            serve.sublist(at, (at + 8).clamp(0, serve.length)));
      }
      if (cutAfter != null) throw const SocketException('connection lost');
    }

    return http.StreamedResponse(
      chunks(),
      from == 0 ? 200 : 206,
      contentLength: rest.length,
    );
  }
}

void main() {
  late Directory staging;
  final apk = List<int>.generate(200, (i) => i % 251);

  setUp(() async {
    staging = await Directory.systemTemp.createTemp('throwlab-update');
    AppUpdater.stagingDirectory = () async => staging;
    AppUpdater.status.value = UpdateStatus.idle;
  });

  tearDown(() async {
    AppUpdater.openClient = http.Client.new;
    AppUpdater.stagingDirectory = () async => staging;
    await staging.delete(recursive: true);
  });

  test('picks a cut-off download up where it stopped', () async {
    final died = _FakeClient(apk, cutAfter: 64);
    AppUpdater.openClient = () => died;
    await AppUpdater.download(7);

    // Held rather than lost: the bytes that made it are still on the phone.
    expect(AppUpdater.status.value.stage, UpdateStage.held);
    final part = File('${staging.path}/ThrowLab.apk.part');
    expect(await part.length(), 64);

    final rest = _FakeClient(apk);
    AppUpdater.openClient = () => rest;
    await AppUpdater.download(7);

    // It asked for the rest of the file, not the whole of it again.
    expect(rest.ranges.single, 'bytes=64-');
    expect(AppUpdater.status.value.stage, UpdateStage.ready);
    expect(AppUpdater.status.value.progress, 1);
    expect(await File('${staging.path}/ThrowLab.apk').readAsBytes(), apk);
    expect(await part.exists(), isFalse);
  });

  test('throws away a part file left over from an older build', () async {
    AppUpdater.openClient = () => _FakeClient(apk, cutAfter: 64);
    await AppUpdater.download(7);
    expect(await File('${staging.path}/ThrowLab.apk.part').length(), 64);

    // A newer build is a different APK; resuming into it would build a file
    // that is half one release and half the next.
    final fresh = _FakeClient(apk);
    AppUpdater.openClient = () => fresh;
    AppUpdater.status.value = UpdateStatus.idle;
    await AppUpdater.download(8);

    expect(fresh.ranges.single, isNull);
    expect(await File('${staging.path}/ThrowLab.apk').readAsBytes(), apk);
  });

  test('resumes what belongs to the build being offered', () async {
    AppUpdater.openClient = () => _FakeClient(apk, cutAfter: 64);
    await AppUpdater.download(7);

    final rest = _FakeClient(apk);
    AppUpdater.openClient = () => rest;
    AppUpdater.status.value = UpdateStatus.idle;
    await AppUpdater.resume(7);

    expect(rest.ranges.single, 'bytes=64-');
    expect(AppUpdater.status.value.stage, UpdateStage.ready);
  });

  group('a build that has been overtaken', () {
    test('is thrown away rather than resumed', () async {
      AppUpdater.openClient = () => _FakeClient(apk, cutAfter: 64);
      await AppUpdater.download(7);
      expect(await File('${staging.path}/ThrowLab.apk.part').exists(), isTrue);

      // Build 9 is out now. Half of build 7 is half of a file nobody is
      // being offered, and resuming into it would finish a release that is
      // already the one before last.
      final other = _FakeClient(apk);
      AppUpdater.openClient = () => other;
      await AppUpdater.resume(9);

      expect(other.ranges, isEmpty);
      expect(await File('${staging.path}/ThrowLab.apk.part').exists(), isFalse);
      expect(await File('${staging.path}/ThrowLab.apk.build').exists(),
          isFalse);
      expect(AppUpdater.status.value.stage, UpdateStage.idle);
    });

    test('is never installed, however finished it is', () async {
      AppUpdater.openClient = () => _FakeClient(apk);
      await AppUpdater.download(7);
      expect(AppUpdater.status.value.stage, UpdateStage.ready);

      // The whole APK is on the phone and the banner is offering to
      // install it — and then build 9 goes out. Opening the installer now
      // would put somebody on 7, restart them, and offer 9 all over again:
      // the update walking up one release at a time instead of landing on
      // the newest.
      await AppUpdater.resume(9);

      expect(AppUpdater.status.value.stage, UpdateStage.idle);
      expect(await File('${staging.path}/ThrowLab.apk').exists(), isFalse);
    });

    test('is not handed to the installer by a stale banner', () async {
      AppUpdater.openClient = () => _FakeClient(apk);
      await AppUpdater.download(7);
      // The APK on disk belongs to a build nobody is offering any more,
      // whatever the status says.
      await File('${staging.path}/ThrowLab.apk.build').writeAsString('9');

      await AppUpdater.install();

      expect(AppUpdater.status.value.stage, UpdateStage.idle);
      expect(await File('${staging.path}/ThrowLab.apk').exists(), isFalse);
    });
  });
}
