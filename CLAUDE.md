# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowEvent`/`Gender` and implement specs |
| `lib/services/` | `VideoLibrary` (persistence), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `JavelinDetector`, `AppUpdater` |
| `lib/screens/` | `home_screen` (the library), `analysis_screen`, `comparison_screen` |
| `lib/widgets/`, `lib/utils/` | Playback controls, drawing canvas, projectile/release math, formatting |
| `test/` | Pure-Dart unit tests — what CI runs |
| `tool/preview/` | Headless UI preview harness (below) |

`android/` is not in the repo: CI runs `flutter create . --platforms=android`
before building, so platform config changes belong in
`.github/workflows/build-apk.yml`.

## Commands

```sh
flutter pub get
flutter test        # unit tests; CI gate
flutter analyze     # expect infos only (mostly withOpacity deprecations)
```

## Previewing UI changes without a device

There is no emulator in CI or in an agent session, so UI work is reviewed by
rendering it to PNGs:

```sh
flutter test --update-goldens tool/preview/home_preview.dart
```

That writes `build/preview/*.png` (gitignored) — the library grouped by
athlete and by event, a section expanded, a search in progress, and the empty
state. Open the PNGs to see exactly what the screen paints. **Re-run it after
touching a screen's layout and actually look at the output.**

The harness asserts nothing; `matchesGoldenFile` is used only as a way to
write a PNG. It lives in `tool/` rather than `test/` so `flutter test` — and
therefore CI — never runs it.

Two things it has to do, and any new preview needs as well:

- **Load fonts** from `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts`. The
  test engine ships no fonts, so without this every glyph and icon paints as a
  filled box.
- **Warm the image cache** (`_warmThumbnails`) before `pumpWidget`. Test
  bindings fake out async work, so an image first resolved inside a pump never
  finishes decoding and the thumbnail paints empty.

Sample throws and their thumbnails are generated at run time (there is a tiny
PNG encoder at the bottom of the file), so no fixtures are committed. To
preview another screen, add a file next to `home_preview.dart` following the
same shape: load fonts, seed `SharedPreferences.setMockInitialValues`, set
`tester.view.physicalSize`, pump, then `_shoot` each state worth seeing.

## Conventions

- Dark Material 3 theme seeded from the logo blue (`0xFF4FC3F7`); `main.dart`
  holds the theme, screens don't restyle it.
- `prefer_single_quotes` is on. Comments explain *why*, not what — match the
  density already in the file you're editing.
- The library is stored as JSON in SharedPreferences by `VideoLibrary`; it
  must keep working (in memory, with a banner) when storage fails.
- Dates shown in the library come from `ThrowVideo.displayDate` and are
  formatted with `formatShortDate` from `lib/utils/time_format.dart`.
- CI builds an APK from `main` and republishes the rolling `latest` release;
  the in-app updater compares build numbers against it.
