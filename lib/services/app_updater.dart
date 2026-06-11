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
  /// Returns the newer build number, or null if up to date / offline.
  static Future<int?> checkForUpdate() async {
    if (kDebugMode) return null; // dev builds aren't numbered by CI
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final latest = int.tryParse(response.body.trim()) ?? 0;
      return latest > current ? latest : null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the latest APK and hands it to the system installer.
  /// [onProgress] gets 0..1, or null while the size is unknown.
  static Future<void> downloadAndInstall(
      ValueChanged<double?> onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ThrowLab.apk');
    final client = http.Client();
    try {
      final response =
          await client.send(http.Request('GET', Uri.parse(_apkUrl)));
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
