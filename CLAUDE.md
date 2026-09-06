# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowEvent`/`Gender` and implement specs |
| `lib/services/` | `VideoLibrary` (persistence), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `JavelinDetector`, `AppUpdater` |
| `lib/screens/` | `home_screen` (the library), `group_screen`, `analysis_screen`, `comparison_screen` |
| `lib/widgets/` | `throw_card`, `event_glyph`, `sector_art`, drawing canvas and rail, playback controls, pickers |
| `lib/utils/` | Scrubbing, frame timing, projectile and release math, formatting |
| `test/` | Unit and widget tests — what CI runs |
| `tool/preview/` | Headless UI preview harness (below) |

`android/` is not in the repo: CI runs `flutter create . --platforms=android`
before building, so platform config changes belong in
`.github/workflows/build-apk.yml`.

## Commands

```sh
flutter pub get
flutter test        # unit + widget tests; CI gate
flutter analyze     # expect infos, plus one pre-existing unused-import warning
```

## Previewing UI changes without a device

There is no emulator in CI or in an agent session, so UI work is reviewed by
rendering it to PNGs:

```sh
flutter test --update-goldens tool/preview/home_preview.dart
```

That writes `build/preview/*.png` (gitignored) — the library grouped by
athlete and by event, a search in progress, and the empty state. Open the
PNGs to see exactly what the screen paints. **Re-run it after touching a
screen's layout and actually look at the output.**

The harness asserts nothing; `matchesGoldenFile` is used only as a way to
write a PNG. It lives in `tool/` rather than `test/` so `flutter test` — and
therefore CI — never runs it.

`tool/preview/harness.dart` holds the two things every preview needs, so use
it rather than rolling your own:

- `loadPreviewFonts()` — registers the app's bundled Barlow plus the SDK's
  Material icon font. The test engine ships no fonts, so without this every
  glyph and icon paints as a filled box.
- `warmImages()` — decodes files into the image cache *before* `pumpWidget`.
  Test bindings fake out async work, so an image first resolved inside a pump
  never finishes decoding and the thumbnail paints empty.

Sample throws and their thumbnails are generated at run time (there is a tiny
PNG encoder at the bottom of `home_preview.dart`), so no fixtures are
committed. To preview another screen, add a file beside it following the same
shape: `loadPreviewFonts()`, seed `SharedPreferences.setMockInitialValues`,
set `tester.view.physicalSize`, pump, then `_shoot` each state worth seeing.

## Conventions

- Dark Material 3 theme seeded from the logo blue (`0xFF4FC3F7`); `main.dart`
  holds the theme, screens don't restyle it.
- Type is Barlow, bundled under `assets/fonts/` (OFL) rather than fetched at
  runtime — the app is used at a track, often with no signal. It is set once
  as `ThemeData.fontFamily`; don't name a family anywhere else.
- `prefer_single_quotes` is on. Comments explain *why*, not what — match the
  density already in the file you're editing.
- The library is stored as JSON in SharedPreferences by `VideoLibrary`; it
  must keep working (in memory, with a banner) when storage fails.
- Event iconography comes from `EventGlyph`; the competition sector in
  `sector_art.dart` backs the library and the empty state. Both are drawn,
  not icon-font glyphs. The backdrop's arcs stay between the sector lines —
  an arc outside them is a line no throwing field has.
- A throw's distance (`ThrowVideo.distance`, metres, null until recorded)
  is the badge on its card. Parse and print it with `parseDistance` /
  `formatDistance` so a comma decimal mark and the centimetres both survive.
- CI builds an APK from `main` and republishes the rolling `latest` release;
  the in-app updater compares build numbers against it.
