# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowMark` (a throw nobody filmed), `ThrowEvent` and the implement specs, `AthleteProfile` and personal bests, `TrainingNote`, `Meet` (a competition and its series) |
| `lib/services/` | `VideoLibrary` (clips and marks), `NotesLibrary` (training notes), `MeetLibrary` (meets), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `JavelinDetector`, `AppUpdater` |
| `lib/screens/` | `home_screen` (the library), `athlete_screen` (one athlete's profile), `note_editor_screen`, `group_screen`, `meets_screen` (the season, as a list or a calendar), `meet_screen` (a meet's events) and `meet_event_screen` (one competition, where the throwing is recorded), `schedule_import_screen` (a fixture list, read onto the calendar), `heat_sheet_import_screen` (a meet's program, read into its field), `analysis_screen`, `comparison_screen` |
| `lib/widgets/` | `throw_card`, `gold` (the medal and the frame), `event_glyph`, `sector_art`, `mark_editor`, `attempt_entry` (one round of a meet), `entry_dialog` (an athlete into a meet), `note_text`, `import_source` (the page a schedule or a heat sheet is handed over on), drawing canvas and rail, playback controls, pickers |
| `lib/utils/` | Scrubbing, frame timing, projectile and release math, formatting, reading a schedule (`schedule_parser`), reading a meet's program (`heat_sheet_parser`), and `pdf_text` to get the words out of either as a PDF |
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

A Claude Code on the web session has no Flutter to run those with, so
`.claude/hooks/session-start.sh` installs one (pinned; CI tracks stable) and
runs `pub get` before the session starts. It is a no-op on a real machine.
Bump the version in it rather than installing an SDK by hand — a container
that has already run it keeps the SDK, and a session that installs its own
pays for the download again.

## Previewing UI changes without a device

There is no emulator in CI or in an agent session, so UI work is reviewed by
rendering it to PNGs:

```sh
flutter test --update-goldens tool/preview/home_preview.dart \
                              tool/preview/athlete_preview.dart \
                              tool/preview/note_preview.dart \
                              tool/preview/meet_preview.dart \
                              tool/preview/schedule_preview.dart \
                              tool/preview/heat_sheet_preview.dart \
                              tool/preview/season_preview.dart
```

That writes `build/preview/*.png` (gitignored) — the library grouped by
athlete and by event, a search in progress, the empty state, four athlete
profiles, a training note (as it opens, and with the keyboard up — which
the note preview fakes, insets and all — toolbar above it, and pinned to
the top), and the meet tracker: the meets as a list and as a calendar, a
meet's events, one of them part-way through, the standings with the cut,
and the sheet a round is entered in — and the schedule import: the page a
fixture list is pasted into, what the parser made of one, and the season it
leaves behind — and the heat sheet import: the program pasted in, the
events found in it, one opened on its field, and the meet it leaves
entered — and the season list: the next fixture at full size over the rest
of it, both on a day with a meet on and on a day without, and with what has been
thrown folded away. Open the PNGs to see exactly what the screen paints. **Re-run it
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
- American English throughout — strings, comments and identifiers: meters,
  color, gray, center, program. The one deliberate exception is
  `heat_sheet_parser`, which matches both spellings of a distance event
  because a programme printed in Britain says '100 metres'. A throw stored
  before this holds `'metres'` as its unit and still reads as
  `DistanceUnit.meters`, through the fallback every `fromJson` already had.
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
  `throw_event.dart` — nothing else enumerates them. A weight named in
  pounds where it is thrown carries a `label` and wears it everywhere
  (`weightLabel`): a U.S. high school shot reads as a 12 lb, because that
  is what it is ordered as and called at the ring, not as 5.44 kg. It is
  its own weight rather than a rounded 5 kg, since a best is per
  implement.
- A throw's distance (`ThrowVideo.distance`, always meters, null until
  recorded) is the badge on its card, shown in the unit it was entered in
  (`distanceUnit`). `DistanceField` is the meters/feet pair that converts
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
- The season reads forwards, not backwards. `MeetSeason` splits the meets
  into today, what is coming (soonest first) and what has been thrown (most
  recent first) — a list newest-first is a record of a season, which buries
  the next fixture under everything already done. The next fixture is drawn
  at the size of the question being asked — `_MeetHero`, with the days to
  it — and everything else is a row with the date down the left edge, at a
  fixed width so a column of dates lines up. A section is one surface with
  its meets ruled off inside it rather than a card each: a season is a list
  of one thing, and cutting it into separate boxes said it wasn't. A row
  says where and how far off for a fixture, and what happened for a meet
  already thrown — `_Facts` reads the entries against the library for the
  athletes, the events and the furthest thrown.
  Upcoming and Past fold away at their headings, remembered in
  `throwlab.meetsFolded`, and a folded heading keeps its count so what is
  behind it is still known. Today never folds — it is one meet, and the
  reason the screen was opened.
- Two countdowns, on purpose. `countdownTo` rounds ('in 3 weeks') for a row
  read at a glance, and says nothing about next spring, which is read by
  its date. The hero counts exact days, because that is the meet being
  packed for — and says nothing at all on the day itself, where the heading
  above it already says TODAY.
- A meet is a day, not a competition: the trophy in the library's app bar
  opens the season — a list, or a calendar of the months it falls in
  (remembered in `throwlab.meetsCalendar`) — a meet lists the events being
  contested at it, and the throwing is recorded one screen further down, in
  `MeetEventScreen`. That is the unit a competition is actually run in: one
  implement, one order, one cut. So the throwing order is per event too,
  even though `MeetEntry.order` numbers the whole meet — moving an athlete
  swaps two positions inside their own event and leaves the rest alone.
- A meet holds no results of its own: every measured attempt is a
  `ThrowMark` or a `ThrowVideo` in `VideoLibrary` the moment it is entered,
  which the `MeetAttempt` points at by id. That is what keeps a series from
  disagreeing with the record book, and puts a Saturday's competition in the
  athlete's personal bests without a second step. A foul or a pass holds no
  distance — a filmed foul keeps its clip and loses the number, or a throw
  that didn't count would stand as a best.
- A meet holds the whole field, not just the coach's athletes.
  `MeetEntry.tracked` is what separates them: an untracked entry writes
  nothing to `VideoLibrary` — its distances live on its `MeetAttempt`s — so
  a rival's throw can never surface as somebody's personal best or as a
  name in the athlete list. It is also why an attempt can carry either a
  `resultId` or a `distance`.
- A meet's format is `Meet.rounds` with `prelimRounds`: a 3 + 3 is six
  rounds cut after three, and a competition where the whole field throws
  the lot has the two equal (`hasFinal` is the difference). The cut only
  bites once every entry has had its prelims — `MeetStandings.cutMade` —
  because an athlete sitting ninth with a throw in hand is not out, and
  closing their rounds while they still have one would be wrong. After
  that, `throwsInFinal` is what grays the last three boxes on a card.
- Standings are worked out per `MeetCompetition` — everyone on the same
  event *and* implement, since that is the contest an athlete is placed in
  — and ties are broken by countback down the series, the way a
  competition breaks them. `Meet.advancing` draws the cut, which is what
  `neededToQualify` measures against: a centimeter past whoever holds the
  last qualifying place, because equalling a mark loses the countback.
  `MeetStandings.finalOrder` is the redraw for the final, leader last.
- A season can be read off a schedule rather than typed in a meet at a
  time. `schedule_parser` turns pasted text — or the text `pdf_text` pulls
  out of a PDF — into candidate meets, and `ScheduleImportScreen` puts them
  up for approval: nothing reaches `MeetLibrary` until a coach has ticked
  it. A fixture list is written for a person to read, so the parser is
  allowed to be unsure and says where it was: a row with no year on it is
  read as the season that hasn't happened yet, `4/12` is read month first,
  and both say so on the row. `pdf_text` is deliberately small — text
  operators, Flate, and the ToUnicode table a subset font needs — and
  returns null rather than mojibake, so a scanned schedule is turned away
  instead of guessed at. A meet carries a `venue` because that is most of
  what a fixture list has to say beyond the name and the date.
- A meet's field can be read off its heat sheet rather than entered a name
  at a time. `heat_sheet_parser` picks the throwing out of a program —
  every other event on the afternoon is there to close the throws event
  before it, so a relay's field is never read as shot putters — and
  `HeatSheetImportScreen` puts the events up to be chosen. The column that
  matters is the one no sheet has: `matchKnown` says which names the
  library already holds, by spelling or by surname and first initial
  ('J Sandhagen' is Jakob), and those come in `tracked` under the library's
  own spelling so a season can't split between two spellings of one person.
  Everybody else comes in untracked, which is what the rest of the field is.
  A weight named on the heading is snapped to the nearest implement the
  event is actually thrown at (a heat sheet's '12lb' is the 12 lb shot); a
  heading that names only a division is guessed at and says so.
- Filming at a meet skips the import's re-encode, which runs for minutes:
  `VideoOptimizer.stashCapture` copies the camera's file into app storage
  as it was shot and the clip is stamped `optimizePending`, which
  `AnalysisScreen` settles the first time the throw is opened. Nothing
  else should film without that flag.
- CI builds an APK from `main` and republishes the rolling `latest` release;
  the in-app updater compares build numbers against it.
