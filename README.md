# ThrowLab

A mobile app for analyzing track & field throwing events — **shot put, discus, hammer, and javelin** — using a single phone camera.

The camera is positioned dead-on to the side of the ring/runway, perpendicular to the throwing direction. This maximizes 2D accuracy and keeps the implement in-plane throughout the throw. The implement itself (standard regulated size) serves as the calibration reference — no setup markers or external equipment needed.

## Current status — v0.1

This is the v0.1 scaffold focused on the core coaching workflow:

- **Video import & library** — import throws from the camera roll, tagged with event + gender (which sets the implement calibration reference automatically)
- **Slow-motion breakdown** — playback at 0.1×–1×, frame-by-frame stepping with a configurable recorded frame rate (30/60/120/240 fps), millisecond + frame-number scrubber
- **Drawing layer** — freehand pen, straight lines, and a 3-point angle measurement tool (with live degree readout) drawn over any frame, in multiple colors, with undo
- **Comparison tools** — pick any two throws, mark the release frame on each, then scrub/step/play both in sync; side-by-side or ghost-overlay view with adjustable opacity
- **Physics core** — projectile model for predicted distance, flight time, optimal release angle, and "distance lost to angle" (UI hookup on the roadmap)

The full feature plan (detection/calibration, release metrics, event-specific analysis, pose estimation, progress tracking, coach tools, export) lives in [ROADMAP.md](ROADMAP.md).

## Install on Android (no computer needed)

[![Latest APK](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fjsandhagen%2FThrowlab%2Freleases%2Flatest&query=%24.name&label=APK&logo=android&color=3ddc84)](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)

Every push to `main` builds an installable APK via GitHub Actions and
republishes it to the rolling **latest** release, so this link always
downloads the newest build:

> **[⬇ Download ThrowLab.apk — latest build](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)**

1. Open the link above on your phone (the badge shows which build you'll
   get; the [release page](https://github.com/jsandhagen/Throwlab/releases/tag/latest)
   has the same file plus build notes)
2. Open the downloaded file and allow the install when Android asks
   (first time only: allow installs from your browser under
   Settings → Apps → Special app access → Install unknown apps)

After the first install the app updates itself: on launch it checks the
latest release and shows an **Update** banner that downloads and installs
the new build in-app (Android still asks you to confirm the install).

Updates install straight over the old version — builds are signed with the
repo's committed debug keystore (`.github/android-debug.keystore`), which is
for personal sideloading only, not Play Store distribution.

## Getting started (local development)

This repo contains the Dart/Flutter source. Generate the platform folders, fetch packages, and run:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter test
flutter run
```

> **Note:** `image_picker` needs the usual platform permissions after `flutter create`:
> on iOS add `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`;
> Android needs no extra setup on recent SDKs.

## Camera setup

- Single camera, tripod-mounted
- **90° to throwing direction** (dead-on side view)
- Two filming modes:
  - **Close/Medium** — circle + release + first few seconds of flight (default, best for coaching)
  - **Wide** — full flight arc visible (best for trajectory and carry distance)

## Implement reference sizes (calibration)

| Event    | Reference     | Men        | Women      |
| -------- | ------------- | ---------- | ---------- |
| Shot Put | Ball diameter | 110–130 mm | 95–110 mm  |
| Discus   | Disc diameter | 219–221 mm | 180–182 mm |
| Hammer   | Ball diameter | 102–120 mm | 95–110 mm  |
| Javelin  | Length        | 2.6–2.7 m  | 2.2–2.3 m  |

## Physics & accuracy notes

- Speed accuracy: ±3–5% with strict side-on camera position
- Angle accuracy: ±1–2°
- Implement orientation: ±3–5°
- Calibration is valid throughout most of flight; drifts slightly as the implement moves far downfield
- Pose estimation is reliable for shot put and javelin; limited during fast multi-turn rotation (hammer/discus)
- Speeds are displayed as estimates (e.g. "~14.2 m/s") to reflect projection limitations

## Tech stack

| Layer                   | Technology                            |
| ----------------------- | ------------------------------------- |
| UI + video + canvas     | Flutter                               |
| On-device ML (iOS)      | CoreML (custom YOLO / Vision) — planned |
| On-device ML (Android)  | ML Kit custom model — planned         |
| Implement shape fitting | OpenCV via Flutter FFI — planned      |
| Pose estimation         | ML Kit Pose Detection / Apple Vision — planned |
| Data persistence        | SharedPreferences now → SQLite (sqflite) planned |
| Export/PDF              | `pdf` package — planned               |

## Project structure

```
lib/
  main.dart                    # app entry, theme
  models/
    throw_event.dart           # events, gender, implement calibration specs
    throw_video.dart           # imported video metadata
  services/
    video_library.dart         # persisted video library
  screens/
    home_screen.dart           # library, import flow, compare picker
    analysis_screen.dart       # slow motion + frame stepping + drawing
    comparison_screen.dart     # synced two-throw comparison
  widgets/
    drawing_canvas.dart        # pen / line / angle annotation layer
    playback_controls.dart     # scrubber, frame step, speed menu
  utils/
    projectile.dart            # release-metrics physics
    time_format.dart
test/                          # physics + model tests
```
