# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowMark` (a throw nobody filmed), `ThrowEvent` and the implement specs, `AthleteProfile` and personal bests, `TrainingNote` |
| `lib/services/` | `VideoLibrary` (clips and marks), `NotesLibrary` (training notes), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `JavelinDetector`, `AppUpdater` |
| `lib/screens/` | `home_screen` (the library), `athlete_screen` (one athlete's profile), `note_editor_screen`, `group_screen`, `analysis_screen`, `comparison_screen` |
| `lib/widgets/` | `throw_card`, `gold` (the medal and the frame), `event_glyph`, `sector_art`, `mark_editor`, `note_text`, drawing canvas and rail, playback controls, pickers |
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
flutter test --update-goldens tool/preview/home_preview.dart \
                              tool/preview/athlete_preview.dart \
                              tool/preview/note_preview.dart
```

That writes `build/preview/*.png` (gitignored) — the library grouped by
athlete and by event, a search in progress, the empty state, four athlete
profiles, and a training note: as it opens, and with the keyboard up (which
the note preview fakes, insets and all) — toolbar above it, and pinned to
the top. Open the PNGs to see exactly what the screen paints. **Re-run it
after touching a screen's layout and actually look at the output.** Run the
previews one command at a time: two `flutter test` runs at once fight over
the compiler and kill each other.

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

Sample throws and their thumbnails come from `sample_library.dart`, generated
at run time (there is a tiny PNG encoder at the bottom of it), so no fixtures
are committed. To preview another screen, add a file beside it following the
same shape: `loadPreviewFonts()`, seed
`SharedPreferences.setMockInitialValues`, set `tester.view.physicalSize`,
pump, then `_shoot` each state worth seeing. A preview that mounts one screen
rather than the whole app paints it under `ThrowLabApp.theme`, so it looks
like the app rather than a bare Material default.

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
- A throw is tagged with what was thrown, by weight: `ThrowVideo.implementKg`
  picks an `ImplementSpec` whose regulated dimension is what the analyzer
  calibrates against. Add a weight by adding a row to the table in
  `throw_event.dart` — nothing else enumerates them.
- A throw's distance (`ThrowVideo.distance`, always metres, null until
  recorded) is the badge on its card, shown in the unit it was entered in
  (`distanceUnit`). `DistanceField` is the metres/feet pair that converts
  as you type; `parseFeet` also takes "191-08" the way a meet writes it.
- A personal best is per athlete, per event, *per implement weight* — a
  lighter implement never erases the mark set with the heavy one. The rule
  lives in `personalBestIds` (`athlete_profile.dart`) and nowhere else;
  `VideoLibrary.isPersonalBest` caches it, and a card that gets
  `isPersonalBest: true` wears the gold frame and the medal. Untagged
  throws hold no marks: "Unassigned" is not a person. An athlete's heading
  in the library opens `AthleteScreen` — their bests, notes, marks and
  throws — while an event or a date opens the plain `GroupScreen` grid.
- Bests are scored over `ThrowResult`, which a clip (`ThrowVideo`) and a
  typed-in mark (`ThrowMark`) both implement — most of what an athlete
  throws is measured at a meet nobody filmed, and a record book that
  ignored those would be wrong. Marks live under their own storage key, so
  a corrupt mark list costs the marks and never the clips.
- The gold is drawn, not tinted: `gold.dart` holds one narrow metal ramp
  shared by `GoldEdgePainter` (the card's frame) and `FirstPlaceMedal` (the
  star-cutout medal), so the two read as the same metal. Keep the ramp
  narrow — a wide one makes a convincing coin and a blotchy frame.
- A training note is a list of typed blocks (`NoteBlockKind`), not a
  document: heading, paragraph, bullet, numbered, checklist, picture with a
  caption. Emphasis is markers in the text (`**bold**`, `*italic*`,
  `__underline__`) parsed by `inlineRuns`; `NoteTextController` styles them
  live in the field so nobody has to think in markers. Pictures are copied
  into the app's own storage on the way in — the picker's file will not
  survive, and deleting the block deletes the file. The formatting bar sits
  in the editor's body, never in `bottomNavigationBar`: a bottom bar stays
  under the keyboard, which is exactly when the tools are wanted. It can be
  pinned under the app bar instead (remembered in `throwlab.noteToolbarTop`),
  and the delete tools stay put at its end rather than scrolling off it.
- CI builds an APK from `main` and republishes the rolling `latest` release;
  the in-app updater compares build numbers against it.
