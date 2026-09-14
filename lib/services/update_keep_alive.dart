import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app's process alive while the update comes down.
///
/// A backgrounded Flutter app is a *cached* process: Android leaves it
/// running until it wants the memory, and once the screen has been off a
/// while Doze suspends its network outright. Neither is something Dart can
/// opt out of — a download started in the main isolate simply stops when the
/// system decides it should, which is exactly what walking away from the
/// phone looks like. The sanctioned way to go on working is a foreground
/// service, which costs a notification and buys a process the system leaves
/// alone.
///
/// The service is the only thing this holds. The download stays in the main
/// isolate where it already was, resuming from its own part file as before;
/// the service exists to stop that isolate being killed underneath it. The
/// plugin wants a task handler all the same, so [updateKeepAliveCallback]
/// hands it one that does nothing.
abstract class UpdateKeepAlive {
  /// Asks for the process to be held up while [build] downloads. Never
  /// throws, and a service that will not start is not an error — the
  /// download carries on exactly as it did before there was one.
  Future<void> start(int build);

  /// How far through, for the notification. 0..1, or null while unknown.
  Future<void> report(double? progress);

  Future<void> stop();
}

/// A handler that does nothing, because the service is not here to do
/// anything: the work is in the main isolate and this is what keeps that
/// isolate's process off the list of things Android may kill.
class _IdleHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

@pragma('vm:entry-point')
void updateKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_IdleHandler());
}

/// The real one: an Android foreground service, carrying the progress in its
/// notification.
class ForegroundKeepAlive implements UpdateKeepAlive {
  const ForegroundKeepAlive();

  /// Whole percent last written to the notification. A download hands over
  /// a new fraction every chunk, and posting a notification for each of
  /// those is a lot of work to move a bar by nothing.
  static int? _shown;

  @override
  Future<void> start(int build) async {
    _shown = null;
    try {
      // Android 13+ can refuse this. The service still runs when it does —
      // only the notification is suppressed — so nothing here waits on the
      // answer or turns it into a failure.
      await FlutterForegroundTask.requestNotificationPermission();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'throwlab_update',
          channelName: 'App updates',
          channelDescription: 'Shows while a new build is downloading.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          // Nothing repeats: the handler is idle and the main isolate is
          // doing the work.
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      await FlutterForegroundTask.startService(
        notificationTitle: 'Updating ThrowLab',
        notificationText: 'Build $build — starting',
        callback: updateKeepAliveCallback,
      );
    } catch (_) {
      // No service, then. The download is about to run either way; it will
      // get as far as Android lets it and pick up from the part file next
      // time, which is what it did before any of this existed.
    }
  }

  @override
  Future<void> report(double? progress) async {
    if (progress == null) return;
    final percent = (progress * 100).clamp(0, 100).round();
    if (percent == _shown) return;
    _shown = percent;
    try {
      await FlutterForegroundTask.updateService(
        notificationText: 'Downloading — $percent%',
      );
    } catch (_) {
      // The bytes matter; the notification does not.
    }
  }

  @override
  Future<void> stop() async {
    _shown = null;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {
      // Nothing to stop, or nothing listening. Either way the download is
      // over and the notification goes with the process.
    }
  }
}

/// Holds nothing up. What a test gets, and what runs anywhere there is no
/// foreground service to ask for.
@immutable
class NoKeepAlive implements UpdateKeepAlive {
  const NoKeepAlive();

  @override
  Future<void> start(int build) async {}

  @override
  Future<void> report(double? progress) async {}

  @override
  Future<void> stop() async {}
}
