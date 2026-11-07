import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A rate and a size the phone's back camera will really record at.
class CameraMode {
  const CameraMode({
    required this.width,
    required this.height,
    required this.fps,
    required this.highSpeed,
  });

  factory CameraMode.fromMap(Map<Object?, Object?> map) => CameraMode(
        width: map['width']! as int,
        height: map['height']! as int,
        fps: map['fps']! as int,
        highSpeed: map['highSpeed'] as bool? ?? false,
      );

  final int width;
  final int height;
  final int fps;

  /// Recorded through Camera2's high-speed session, which is the only way a
  /// phone films faster than 60.
  final bool highSpeed;

  Map<String, Object> toMap() => {
        'width': width,
        'height': height,
        'fps': fps,
        'highSpeed': highSpeed,
      };

  /// '1080p', '4K' — what a phone's own camera calls the size.
  String get resolution {
    final short = height < width ? height : width;
    return short >= 2160 ? '4K' : '${short}p';
  }

  @override
  bool operator ==(Object other) =>
      other is CameraMode &&
      other.width == width &&
      other.height == height &&
      other.fps == fps &&
      other.highSpeed == highSpeed;

  @override
  int get hashCode => Object.hash(width, height, fps, highSpeed);

  @override
  String toString() => '$resolution · $fps fps';
}

/// What the camera offers, and how its sensor is mounted.
class CameraModes {
  const CameraModes(this.modes,
      {required this.sensorOrientation, this.details = const []});

  final List<CameraMode> modes;

  /// Degrees the sensor is turned from the phone's natural orientation.
  final int sensorOrientation;

  /// What every back camera tells apps it can film, a line at a time.
  final List<String> details;
}

/// An open camera and what it is filming at. Its picture is shown by
/// [CameraPreview].
class OpenCamera {
  const OpenCamera({required this.mode, required this.sensorOrientation});

  final CameraMode mode;
  final int sensorOrientation;
}

/// A take as the camera delivered it: the file, and how many frames went
/// into it over how long — counted off the camera's own results, so a take
/// that was meant to be 120 fps and wasn't says so.
class RecordedTake {
  const RecordedTake(
      {required this.path,
      required this.frames,
      required this.seconds,
      this.failed = 0});

  factory RecordedTake.fromMap(Map<Object?, Object?> map) => RecordedTake(
        path: map['path']! as String,
        frames: map['frames'] as int? ?? 0,
        seconds: (map['seconds'] as num?)?.toDouble() ?? 0,
        failed: map['failed'] as int? ?? 0,
      );

  final String path;
  final int frames;
  final double seconds;

  /// Frames the camera reported it could not deliver.
  final int failed;

  /// The rate the camera really delivered, or null when it delivered too
  /// little to tell.
  double? get deliveredFps =>
      frames > 1 && seconds > 0 ? (frames - 1) / seconds : null;
}

/// A video the phone's own camera app saved, found in its media store.
class PhoneVideo {
  const PhoneVideo({
    required this.uri,
    required this.added,
    required this.duration,
    required this.width,
    required this.height,
    this.name = '',
  });

  factory PhoneVideo.fromMap(Map<Object?, Object?> map) => PhoneVideo(
        uri: map['uri']! as String,
        added: DateTime.fromMillisecondsSinceEpoch(
            (map['addedMillis'] as num?)?.toInt() ?? 0),
        duration: Duration(
            milliseconds: (map['durationMillis'] as num?)?.toInt() ?? 0),
        width: map['width'] as int? ?? 0,
        height: map['height'] as int? ?? 0,
        name: map['name'] as String? ?? '',
      );

  final String uri;
  final DateTime added;
  final Duration duration;
  final int width;
  final int height;
  final String name;
}

/// The sound the phone makes, for the athlete twenty meters away who can't
/// see the screen.
enum Beep { tick, go, stop }

/// ThrowLab's camera — see `ThrowlabCameraPlugin.kt` for why it is its own.
class ThrowCamera {
  static const channel = MethodChannel('throwlab_camera');

  /// What the back camera records at. Asks for the camera permission the
  /// first time.
  static Future<CameraModes> modes() async {
    final reply = (await channel.invokeMapMethod<Object?, Object?>('modes'))!;
    return CameraModes(
      [
        for (final mode in (reply['modes'] as List? ?? const []))
          CameraMode.fromMap(mode as Map<Object?, Object?>),
      ],
      sensorOrientation: reply['sensorOrientation'] as int? ?? 90,
      details: [
        for (final line in (reply['details'] as List? ?? const []))
          line as String,
      ],
    );
  }

  /// Whether the camera has its preview and is ready to record. Set when a
  /// session is up on the preview's surface, which is after [open] has
  /// returned and the preview has been laid out.
  static final ValueNotifier<bool> ready = ValueNotifier(false);

  /// Why the camera could not start a session, once it has said.
  static final ValueNotifier<String?> failure = ValueNotifier(null);

  static void _listen() {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ready':
          failure.value = null;
          ready.value = true;
        case 'failed':
          ready.value = false;
          failure.value = call.arguments as String?;
      }
    });
  }

  static Future<OpenCamera> open(CameraMode mode) async {
    _listen();
    ready.value = false;
    failure.value = null;
    final reply = (await channel.invokeMapMethod<Object?, Object?>(
        'open', mode.toMap()))!;
    return OpenCamera(
      mode: CameraMode.fromMap(reply),
      sensorOrientation: reply['sensorOrientation'] as int? ?? 90,
    );
  }

  /// Starts writing what the camera sees to [path], an `.mp4`.
  static Future<void> start(String path) =>
      channel.invokeMethod('start', {'path': path});

  /// Stops, and returns the take it wrote.
  static Future<RecordedTake> stop() async => RecordedTake.fromMap(
      (await channel.invokeMapMethod<Object?, Object?>('stop'))!);

  static Future<void> close() {
    ready.value = false;
    return channel.invokeMethod('close');
  }

  static Future<void> beep(Beep kind) =>
      channel.invokeMethod('beep', {'kind': kind.name});

  /// Which camera app the phone has for what this one can't film:
  /// 'samsung', 'other', or null when there is none.
  static Future<String?> phoneCamera() =>
      channel.invokeMethod<String>('phoneCamera');

  /// Opens the phone's camera app the way its own icon does, so it comes
  /// back in the mode it was last left in. False when it wouldn't open.
  static Future<bool> openPhoneCamera() async =>
      await channel.invokeMethod<bool>('openPhoneCamera') ?? false;

  /// Videos the phone has saved since [since], newest first. Asks for
  /// permission to read them the first time.
  static Future<List<PhoneVideo>> videosSince(DateTime since) async {
    final found = await channel.invokeListMethod<Object?>(
        'videosSince', {'since': since.millisecondsSinceEpoch});
    return [
      for (final video in found ?? const [])
        PhoneVideo.fromMap(video! as Map<Object?, Object?>),
    ];
  }

  /// Copies a video the phone saved into [path], and returns it.
  static Future<String> copyVideo(String uri, String path) async =>
      (await channel
          .invokeMethod<String>('copyVideo', {'uri': uri, 'path': path}))!;

  /// How far the screen is turned from the phone's natural orientation, in
  /// degrees — what the preview has to be turned against.
  static Future<int> displayRotation() async =>
      await channel.invokeMethod<int>('displayRotation') ?? 0;
}

/// The camera's viewfinder: an Android SurfaceView in the app's own window,
/// composited by the system rather than drawn by Flutter — see
/// `ThrowlabCameraPlugin.kt` for why. Hybrid composition, because that is
/// the mode a SurfaceView keeps its own surface in. The system turns the
/// picture upright; the caller gives it the shape the mode's picture has
/// on this screen.
class CameraPreview extends StatelessWidget {
  const CameraPreview({super.key});

  static const viewType = 'throwlab_camera/preview';

  @override
  Widget build(BuildContext context) => PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) =>
            PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
        )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..create(),
      );
}
