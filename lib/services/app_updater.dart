import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _releaseBase =
    'https://github.com/jsandhagen/Throwlab/releases/download/latest';
const _versionUrl = '$_releaseBase/version.txt';
const _apkUrl = '$_releaseBase/ThrowLab.apk';

/// Where an update has got to.
enum UpdateStage {
  /// Nothing going on, or nothing offered.
  idle,

  /// Coming down now.
  downloading,

  /// Part of it is on the phone and nothing is moving it: the network went,
  /// or the app was killed mid-download. Whatever came down is kept, and
  /// picking it up again starts from there.
  held,

  /// The whole APK is on the phone, waiting to be handed to the installer.
  ready,

  /// It went wrong, and [UpdateStatus.error] says how.
  failed,
}

/// An update as it stands: what is happening, to which build, and how far
/// through it is.
@immutable
class UpdateStatus {
  const UpdateStatus({
    required this.stage,
    this.build,
    this.progress,
    this.error,
  });

  static const idle = UpdateStatus(stage: UpdateStage.idle);

  final UpdateStage stage;

  /// The build being fetched.
  final int? build;

  /// 0..1, or null while the size is unknown.
  final double? progress;

  final String? error;

  bool get isBusy => stage == UpdateStage.downloading;
}

/// Checks the rolling GitHub "latest" release for a newer build and installs
/// it in-app. CI stamps every APK with the workflow run number as its build
/// number and publishes the same number as version.txt next to the APK.
///
/// The download outlives whatever started it. It is held here rather than in
/// a screen's state, and it writes into a part file it can resume from, so
/// walking away from the app — to the camera, to the meet, to a locked
/// phone — doesn't cost the bytes already fetched. Android will keep a
/// backgrounded app running until it needs the memory; when it does take
/// it, the next launch picks the download up where the axe fell instead of
/// starting the APK again.
class AppUpdater {
  /// What the download is doing, for anything that wants to show it. A
  /// notifier rather than a callback: the progress has to reach whichever
  /// screen happens to be up when it finishes, which is not necessarily the
  /// one that started it.
  static final ValueNotifier<UpdateStatus> status =
      ValueNotifier<UpdateStatus>(UpdateStatus.idle);

  /// A rolling release re-uploads the same asset URLs, so GitHub's CDN/edge
  /// happily serves a stale copy — the reason a freshly published build often
  /// isn't seen. Ask every layer not to cache, and vary the URL per request
  /// so nothing can key a hit against a previous fetch.
  static const _noCacheHeaders = {
    'Cache-Control': 'no-cache, no-store, max-age=0',
    'Pragma': 'no-cache',
  };

  /// How the download talks to the network and to the disk. Both are here
  /// so a test can hand over a fake of each; nothing else should touch
  /// them.
  @visibleForTesting
  static http.Client Function() openClient = http.Client.new;

  @visibleForTesting
  static Future<Directory> Function() stagingDirectory = getTemporaryDirectory;

  static Uri _fresh(String url) =>
      Uri.parse('$url?t=${DateTime.now().microsecondsSinceEpoch}');

  /// Returns the newer build number, or null if up to date / offline.
  static Future<int?> checkForUpdate() async {
    if (kDebugMode) return null; // dev builds aren't numbered by CI
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      final latest = await _fetchLatestBuild();
      if (latest == null) return null;
      return latest > current ? latest : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the published build number, retrying a few times so a not-yet-
  /// ready network at cold start doesn't leave the app stuck on an old build
  /// until the next restart. Returns null only after every attempt fails.
  static Future<int?> _fetchLatestBuild() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await openClient()
            .get(_fresh(_versionUrl), headers: _noCacheHeaders)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final latest = int.tryParse(response.body.trim());
          if (latest != null) return latest;
        }
      } catch (_) {
        // Transient failure — fall through and retry.
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    return null;
  }

  /// Starts, or picks back up, the download of [build].
  ///
  /// Safe to call again at any point: a download already running is left
  /// alone, and one that stopped resumes from the bytes already on the
  /// phone. Returns when the APK is down, not when it is installed —
  /// handing it to the installer is [install], which has to happen with the
  /// app in front of somebody.
  static Future<void> download(int build) async {
    if (status.value.isBusy) return;
    final dir = await stagingDirectory();
    final apk = File('${dir.path}/ThrowLab.apk');
    final part = File('${dir.path}/ThrowLab.apk.part');
    final stamp = File('${dir.path}/ThrowLab.apk.build');

    // A part file from an older build is a different APK: keep nothing.
    if (await _stampedBuild(stamp) != build) {
      if (await part.exists()) await part.delete();
      if (await apk.exists()) await apk.delete();
      await stamp.writeAsString('$build');
    }
    if (await apk.exists()) {
      status.value =
          UpdateStatus(stage: UpdateStage.ready, build: build, progress: 1);
      return;
    }

    status.value = UpdateStatus(
      stage: UpdateStage.downloading,
      build: build,
      progress: await _fraction(part),
    );

    final client = openClient();
    try {
      var have = await part.exists() ? await part.length() : 0;
      final request = http.Request('GET', _fresh(_apkUrl))
        ..headers.addAll({
          ..._noCacheHeaders,
          // What makes leaving the app cheap rather than free: the server
          // is asked for the rest of the file, not the whole of it again.
          if (have > 0) 'range': 'bytes=$have-',
        });
      final response = await client.send(request);
      if (response.statusCode != 206 && response.statusCode != 200) {
        throw HttpException('download failed (HTTP ${response.statusCode})');
      }
      // 200 to a range request means the server sent the lot anyway, so
      // what is on disk is no use — GitHub's asset storage does honor
      // ranges, but nothing here depends on it.
      final resuming = response.statusCode == 206 && have > 0;
      if (!resuming) have = 0;

      final total = response.contentLength == null
          ? null
          : have + response.contentLength!;
      final sink =
          part.openWrite(mode: resuming ? FileMode.append : FileMode.writeOnly);
      var received = have;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          status.value = UpdateStatus(
            stage: UpdateStage.downloading,
            build: build,
            progress: total == null ? null : received / total,
          );
        }
      } finally {
        await sink.close();
      }
      if (total != null && received < total) {
        throw const HttpException('download ended early');
      }
      await part.rename(apk.path);
      status.value =
          UpdateStatus(stage: UpdateStage.ready, build: build, progress: 1);
    } catch (e) {
      // Held, not lost: the part file stays where it is and the next call
      // asks for the rest of it.
      status.value = UpdateStatus(
        stage: UpdateStage.held,
        build: build,
        progress: await _fraction(part),
        error: '$e',
      );
    } finally {
      client.close();
    }
  }

  /// Hands the downloaded APK to the system installer. Android will not put
  /// the installer up for an app that isn't in front of somebody, so this is
  /// called when the app is resumed rather than the moment the bytes land.
  ///
  /// Only ever the build being offered. An APK that came down before
  /// another release went out is the update before last, and installing it
  /// would put somebody one version behind and then ask them to do the
  /// whole thing again — see [resume].
  static Future<void> install() async {
    if (status.value.stage != UpdateStage.ready) return;
    final dir = await stagingDirectory();
    final apk = File('${dir.path}/ThrowLab.apk');
    if (!await apk.exists()) {
      status.value = UpdateStatus.idle;
      return;
    }
    if (await _stampedBuild(File('${dir.path}/ThrowLab.apk.build')) !=
        status.value.build) {
      await _discard(dir);
      status.value = UpdateStatus.idle;
      return;
    }
    final result = await OpenFilex.open(apk.path);
    if (result.type != ResultType.done) {
      status.value = UpdateStatus(
        stage: UpdateStage.failed,
        build: status.value.build,
        error: result.message,
      );
    }
  }

  /// Picks up whatever was going on before the app was last put down: a
  /// part file for [build] means a download to finish, a whole APK means an
  /// installer to open. Called on every return to the foreground, so a
  /// download that died with the process quietly carries on.
  ///
  /// [build] is the newest one published, and anything staged for another
  /// one is thrown away rather than kept or installed. The release is a
  /// rolling one: an APK that finished downloading before the next build
  /// went out is not the update anybody is being offered any more, and
  /// handing it to the installer would walk somebody up through the
  /// releases one at a time — install, restart, find another update,
  /// install again — when one download would have taken them to the end.
  static Future<void> resume(int build) async {
    if (status.value.isBusy) return;
    final dir = await stagingDirectory();
    final staged = await _stampedBuild(File('${dir.path}/ThrowLab.apk.build'));

    if (staged != null && staged != build) {
      // Including a finished one sitting at [UpdateStage.ready], which the
      // screen would otherwise open the installer for the moment somebody
      // came back to the app.
      await _discard(dir);
      status.value = UpdateStatus.idle;
      return;
    }

    if (await File('${dir.path}/ThrowLab.apk').exists() && staged == build) {
      status.value =
          UpdateStatus(stage: UpdateStage.ready, build: build, progress: 1);
      return;
    }
    if (status.value.stage == UpdateStage.failed) return;
    final part = File('${dir.path}/ThrowLab.apk.part');
    if (!await part.exists() || staged != build) return;
    await download(build);
  }

  /// Clears the staging directory: the APK, whatever part of one is there,
  /// and the build it belonged to.
  static Future<void> _discard(Directory dir) async {
    for (final name in [
      'ThrowLab.apk',
      'ThrowLab.apk.part',
      'ThrowLab.apk.build'
    ]) {
      final file = File('${dir.path}/$name');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A file that will not delete is one the next download overwrites
        // anyway; the stamp is what decides, and that is rewritten there.
      }
    }
  }

  /// Which build the files in the staging directory belong to, if any.
  static Future<int?> _stampedBuild(File stamp) async {
    try {
      if (!await stamp.exists()) return null;
      return int.tryParse((await stamp.readAsString()).trim());
    } catch (_) {
      return null;
    }
  }

  /// How far through the part file is, as far as anyone can tell without
  /// the server: nothing, until the download says what the total is.
  static Future<double?> _fraction(File part) async {
    final done = status.value.progress;
    if (done != null) return done;
    return await part.exists() ? null : 0;
  }
}
