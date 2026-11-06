import 'package:flutter/services.dart';

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
  const CameraModes(this.modes, {required this.sensorOrientation});

  final List<CameraMode> modes;

  /// Degrees the sensor is turned from the phone's natural orientation.
  final int sensorOrientation;
}

/// An open camera: the texture its preview is drawn into, and what it is
/// filming at.
class OpenCamera {
  const OpenCamera({
    required this.textureId,
    required this.mode,
    required this.sensorOrientation,
  });

  final int textureId;
  final CameraMode mode;
  final int sensorOrientation;
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
    );
  }

  static Future<OpenCamera> open(CameraMode mode) async {
    final reply = (await channel.invokeMapMethod<Object?, Object?>(
        'open', mode.toMap()))!;
    return OpenCamera(
      textureId: reply['textureId']! as int,
      mode: CameraMode.fromMap(reply),
      sensorOrientation: reply['sensorOrientation'] as int? ?? 90,
    );
  }

  /// Starts writing what the camera sees to [path], an `.mp4`.
  static Future<void> start(String path) =>
      channel.invokeMethod('start', {'path': path});

  /// Stops, and returns the file it wrote.
  static Future<String> stop() async =>
      (await channel.invokeMethod<String>('stop'))!;

  static Future<void> close() => channel.invokeMethod('close');

  static Future<void> beep(Beep kind) =>
      channel.invokeMethod('beep', {'kind': kind.name});

  /// How far the screen is turned from the phone's natural orientation, in
  /// degrees — what the preview has to be turned against.
  static Future<int> displayRotation() async =>
      await channel.invokeMethod<int>('displayRotation') ?? 0;
}
