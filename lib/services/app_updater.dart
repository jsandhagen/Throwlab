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

/// Checks the rolling GitHub "latest" release for a newer build and installs
/// it in-app. CI stamps every APK with the workflow run number as its build
/// number and publishes the same number as version.txt next to the APK.
class AppUpdater {
  /// A rolling release re-uploads the same asset URLs, so GitHub's CDN/edge
  /// happily serves a stale copy — the reason a freshly published build often
  /// isn't seen. Ask every layer not to cache, and vary the URL per request
  /// so nothing can key a hit against a previous fetch.
  static const _noCacheHeaders = {
    'Cache-Control': 'no-cache, no-store, max-age=0',
    'Pragma': 'no-cache',
  };

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
        final response = await http
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

  /// Downloads the latest APK and hands it to the system installer.
  /// [onProgress] gets 0..1, or null while the size is unknown.
  static Future<void> downloadAndInstall(
      ValueChanged<double?> onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ThrowLab.apk');
    final client = http.Client();
    try {
      // Same rolling-asset caching risk as the version check: bust it so the
      // installer never receives a stale APK for the new build number.
      final request = http.Request('GET', _fresh(_apkUrl))
        ..headers.addAll(_noCacheHeaders);
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('download failed (HTTP ${response.statusCode})');
      }
      final total = response.contentLength;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total == null ? null : received / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
