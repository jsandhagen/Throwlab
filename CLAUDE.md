# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowMark` (a throw nobody filmed), `ThrowEvent` and the implement specs, `AthleteProfile` and personal bests, `AthleteRecord` (the editable half — a nickname, and the full name and school a heat sheet is matched against), `TrainingNote`, `Meet` (a competition and its series, plus `MeetFlight` — the flight being thrown and where it has got to), `MeetConditions` (what the day was like), `MeetBoard` (the competition as lines across the sector), `MeetOuting` (a season read from the athlete's side) |
| `lib/services/` | `VideoLibrary` (clips and marks), `NotesLibrary` (training notes), `MeetLibrary` (meets), `AthleteLibrary` (athlete records — the display name every screen resolves through it), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `ResultsSheet` (a meet's results as a PDF on the phone), `JavelinDetector`, `AppUpdater` |
| `lib/screens/` | `home_screen` (the library), `athlete_screen` (one athlete's profile), `note_editor_screen`, `group_screen`, `meets_screen` (the season, as a list or a calendar), `meet_screen` (a meet's events) and `meet_event_screen` (one competition, where the throwing is recorded), `schedule_import_screen` (a fixture list, read onto the calendar), `heat_sheet_import_screen` (a meet's program, read into its field), `analysis_screen`, `comparison_screen` |
| `lib/widgets/` | `throw_card`, `gold` (the medal and the frame), `event_glyph`, `sector_art`, `mark_editor`, `attempt_entry` (one round of a meet), `entry_dialog` (an athlete into a meet), `note_text`, `conditions_sheet` (the weather, written down), `progression` (a season as a line), `sector_board` (the competition drawn on the sector), `import_source` (the page a schedule or a heat sheet is handed over on), `drawing_canvas` and `drawing_rail` (the tools, as a bar along the bottom of the frame), playback controls, pickers |
| `lib/utils/` | Scrubbing, frame timing, projectile and release math, formatting, reading a schedule (`schedule_parser`), reading a meet's program (`heat_sheet_parser`), `pdf_text` to get the words out of either as a PDF, and `pdf_writer`/`meet_report` to put a results sheet back into one |
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
                              tool/preview/season_preview.dart \
                              tool/preview/analysis_preview.dart
```

The results sheet is reviewed the same way, except that the artifact is the
PDF itself — it writes no golden and asserts nothing, because looking at the
file is the review:

```sh
flutter test tool/preview/report_preview.dart   # build/preview/results_sheet.pdf
```

It prints a championship with everything the sheet has to cope with on it: a
discus cut to a final, a shot thrown in two flights, a javelin measured in
feet in a field measured in meters, a personal best, and enough of a field
to push the last event onto a second page.

That writes `build/preview/*.png` (gitignored) — the library grouped by
athlete and by event, a search in progress, the empty state, four athlete
profiles (each with the season drawn under its best, and the meets it was
thrown at), a training note (as it opens, and with the keyboard up — which
the note preview fakes, insets and all — toolbar above it, and pinned to
the top), and the meet tracker: the meets as a list and as a calendar, a
meet's events, one of them part-way through, the standings with the cut,
the field as a list, the live card (four times — a podium, a field with the
cut falling below it, a board that has broken, where the leader is off
the top of it as an arrow, and a field thrown in flights, where the coach's
own athlete is in the one that hasn't been called), the flighted field as a
list — ruled off at the flights, and scrolled down to the one still to come
— and the sheet a round is entered in — and the schedule import: the page a
fixture list is pasted into, what the parser made of one, and the season it
leaves behind — and the heat sheet import: the program pasted in, the
events found in it, one opened on its field with the flights ruled off in
it, and the meet it leaves entered — and the season list: the next fixture at full size over the rest
of it, both on a day with a meet on and on a day without, and with what has been
thrown folded away — and the analysis screen: the drawing tools as a bar
along the bottom (on their own, with a ring and an arrow drawn, with the
shape menu open, and folded away to the one chevron), and the same bar
sitting in the letterbox under an upright frame. Open the PNGs to see
exactly what the screen paints. **Re-run it
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

The analysis preview is the one that borrows from `test/`: it mounts the
real screen on the widget tests' in-memory player, so the 'video' is a flat
blue rectangle — which is the point, since what is being looked at is where
the chrome sits over the frame and how much of it it costs. Its clip is
stamped as already having scrub frames, so the screen never reaches for the
ffmpeg and path_provider plugins that aren't behind a widget test.

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
  as you type; `parseFeet` takes "191-08" the way a meet writes it.
- A mark in feet is written in feet and inches, never in decimal feet.
  `formatFeet` is the other half of `parseFeet`: it spells a throw
  '191-08', '44-06.25' — what was called across the sector, printed on the
  program and posted afterwards — because '191.67 ft' beside a sheet
  reading '191-08' is one throw in two notations. To the *lesser* quarter
  inch, which is the rule the mark was recorded under: a tape reading 44
  feet 6.4 inches is a 44-06.25, and 12.19 m is a 39-11.75 rather than a
  40 flat. The quarter is left off when there isn't one. Everything that
  shows a mark goes through `formatDistance`, so this is the one place it
  is decided — including the differences (a winning margin, a season's
  movement), which are the same unit as the marks they came from. A
  fixed-width sheet has to make room for it: `meet_report` measures the
  series before it sets the column, since '191-04.75' does not fit a
  column cut for '44.90'.
- A personal best is per athlete, per event, *per implement weight* — a
  lighter implement never erases the mark set with the heavy one. The rule
  lives in `personalBestIds` (`athlete_profile.dart`) and nowhere else;
  `VideoLibrary.isPersonalBest` caches it, and a card that gets
  `isPersonalBest: true` wears the gold frame and the medal. Untagged
  throws hold no marks: "Unassigned" is not a person. An athlete's heading
  in the library opens `AthleteScreen` — their bests, notes, marks and
  throws — while an event or a date opens the plain `GroupScreen` grid.
- An `AthleteProfile` is *derived* from the throws — there is nothing stored
  to edit. What a coach fills in that no throw carries lives in an
  `AthleteRecord` in `AthleteLibrary` instead: a nickname, a full name and a
  school. The record is keyed to the athlete by their library spelling (the
  athlete tag every throw already holds) and never renames it, so a nickname
  is a label over the identity rather than a new one — retagging a clip can't
  orphan the record. Screens resolve what to show through
  `AthleteLibrary.displayName` (the `displayNameOf`/`athleteRecordsOf`
  helpers look the service up softly, so a screen mounted in a test without
  it still paints under the plain spelling). The full name and school are
  what `heat_sheet_parser.matchAthlete` links a program's entry against, so
  an athlete filed under a nickname a sheet would never print is still found
  on one — by the full name, or by the same surname at the same school.
- A heat sheet heading that names a division but no weight is guessed at in
  `heat_sheet_parser`: a bare 'Men'/'Women' is the senior implement, and
  'Boys'/'Girls'/'High School'/U18-and-under is the U.S. school one — the
  12 lb shot and 1.6 kg discus for the boys, the same 4 kg / 1 kg as the
  women for the girls, the 800 g javelin for both. The screen still says the
  weight was guessed, because a division is not a spec and a best is per
  weight.
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
  swaps two positions inside their own event and leaves the rest alone. It
  is the unit one is removed in, too: `MeetLibrary.removeCompetition` takes
  the event and everybody in it off the meet, because a program read in
  with the wrong event ticked is thirty entries nobody wants to tap away
  one at a time. What was thrown stays where it is — the marks and clips
  are the athlete's record, not the meet's, exactly as when one athlete is
  taken out.
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
  heading that names only a division is guessed at and says so. A field too
  long for the page has its heading printed again over the rest of it —
  '(continued)', or the whole line in brackets — and that reads as the same
  event carrying on, flight and all, rather than as a second one of the same
  name: the fields it happens to are the long ones, which are exactly the
  flighted ones.
- The drawing tools are a bar along the bottom of the frame, never a column
  down its side. A clip is filmed on its side, so the screen reading one has
  ~360 logical pixels of height: a column of ten controls is taller than
  that and crosses the right-center and upper-right of the picture, which is
  the release and the flight out of it. Held upright the bar is better
  still — a widescreen clip letterboxed into a portrait screen leaves a band
  of black under it, and the bar sits in the band without covering any of
  the frame. It scales down rather than scrolling on a screen too narrow to
  hold it: a tool scrolled out of reach is one nobody finds, and the scroll
  view that offered it swallowed every drag over the strip it covered. The
  shapes a drag builds share one menu button wearing whichever is selected,
  and the pen weight and color are menus too, which is what keeps the bar to
  ten controls; undo, redo and clear are never among them, because they are
  what a drawing hand reaches for most. Clear can sit in the open because
  undo brings the whole frame back — `DrawingController` keeps the edits
  rather than snapshots of the frame, since an annotation goes on mutating
  while the finger is down.
- A shape is drawn the way it is measured. An arrow is dragged tail to head,
  a curved arrow traces the path it wants and takes its head where the
  finger lifts, and a circle is dragged out from the middle: what is being
  circled — a hip, a hand, where the implement landed — stays under the
  finger that started it, which a corner-to-corner box does not. A circle is
  stored as its middle and a point on the rim rather than a radius, because
  the two axes normalize by different amounts and a stored radius would come
  back as an ellipse on a frame of another shape.
- Filming at a meet skips the import's re-encode, which runs for minutes:
  `VideoOptimizer.stashCapture` copies the camera's file into app storage
  as it was shot and the clip is stamped `optimizePending`, which
  `AnalysisScreen` settles the first time the throw is opened. Nothing
  else should film without that flag.
- The playback copy is tagged with the color it is in
  (`VideoOptimizer.colorTagsFor`). A clip that says nothing leaves the two
  things this app points at one throw guessing differently — a player reads
  untagged HD as Rec. 709, which is what a phone shoots, and ffmpeg's
  scaler falls back to Rec. 601 whatever the size — and that shows at the
  scrub handoff, where an ffmpeg still is replaced by the player's own
  frame. Only for HD, and only when nobody has said: standard definition
  really is Rec. 601.
- A meet is tracked live, not written up afterwards. `MeetFlight` works
  out where a competition has got to — the round being thrown, and the
  three an infield calls out (`inTheCircle`, `onDeck`, `inTheHole`) — from
  the throwing order and the series already entered, because nobody
  standing at a sector has a hand free to tell an app whose turn it is.
  Both the meet's event card and the event screen's own header read their
  wording off it, so the two can't drift. A competition of one has no
  flight worth naming (`hasOrder`): the athlete is always up, and saying so
  over the only card on the screen tells a coach what they are looking at —
  but `next` still answers who is about to throw, because a mark still has
  to be written down for them.
- A big field is not thrown in one order, and `MeetEntry.flight` is which
  part of it somebody throws in. Thirty shot putters are split into flights
  of a dozen, each throwing its prelims right through before the next walks
  in, so `MeetFlight` is worked out over *one* flight — the first still owed
  a round (`flight`, `flightCount`, `flightDone`) — rather than over the
  whole field: flight 2 standing on the grass with nothing entered would
  otherwise hold the round at one forever and call its first thrower into a
  circle an hour early. The cut dissolves them, because a final is thrown by
  the qualifiers as one group whichever flight they came through, and so
  everything flighted stops at `MeetStandings.cutMade`. Standings never
  split: an athlete is placed against the whole competition, not against the
  dozen they happened to throw with. A competition small enough to be thrown
  in one order has one flight, which is no flights — nothing says a word
  about them, and that is the case every screen was written for first.
  `heat_sheet_parser` reads the 'Flight 2 of 3' a program prints over each
  run of names (a sheet may call it a section, or borrow the running's word
  and say heat); the flights come in as runs of the order, the field is
  ruled off at them in the list, and the live card says when the coach's own
  athlete is up where the flight in the ring is somebody else's.
- An athlete's card in the field is two rows, and the split is what each
  row is for. The top one answers *who, and how are they doing* — the
  flight number, the name, the place, the mark they are standing on — and
  carries the camera and the ruler, because those are the only two things
  a coach does here. The bottom one is the series: six boxes across the
  full width, big enough to read at arm's length and to hit without looking
  down. It was three rows once, with the buttons on a line of their own,
  and one row after that with no room for them; two is where a field fits
  on a screen with nothing a coach reaches for taken away. The card marks
  only the athlete in the circle, and marks them by coloring the name
  rather than by spending a name's worth of width on the word — the three
  calls are on the bar above the field. The place is on every card: one
  that only exists on another tab is one a coach has to leave the
  competition to read.
- The live board is drawn to a scale, and the scale is a round number of
  meters (`boardSpans`) rather than whatever the field happens to span: a
  gap across the board is the same number of meters after a throw as it was
  before it, and a marker line every `MeetBoard.grid` says how many — the
  lines a sector is painted with, never 'rings', because in throwing the
  ring is the circle the throw is made from and there is one of those on
  the board already. `fitBand` picks
  it — the shallowest rung that holds every line, going deeper only while
  going deeper picks up another mark. When one doesn't, the board *breaks*
  rather than zooming out: it keeps the run of the competition around the
  athlete it belongs to (whoever is in the circle, else the coach's own) and
  draws whatever is outside as an arrow off the edge carrying its mark and
  how far out it landed — a leader five meters clear is worth an arrow, not
  worth squashing the fight for second into an inch of sector. The band's
  edges snap to the marker lines so it moves a line at a time instead of
  sliding under every throw. The ground past the cut is shaded to its own
  arc rather than to a horizontal edge: a throw lands the same distance out
  whether it goes down the middle or close to a sector line, and a straight
  edge across the wedge shades ground that is short of the cut at the sides
  — which is exactly where a place is lost. Pinching picks a rung by hand and a double-tap goes
  back to fitting; there are no zoom buttons, because a control over the
  board costs a meter of sector to answer a question the board has usually
  already answered. Only the labels move to avoid each other — the lines
  stay where the throws put them, and a label that had to slide grows a
  leader back to its own line.
- A label on the board is two pills at the edges of the box — place and name
  at one, the mark at the other — with the line running between them, and
  they sit level with the ends of their own arc rather than with its middle,
  which is what makes a label read as belonging to a line. A mark the band
  broke off has no line to leave room for, so it gets one solid pill and the
  arrow. The name is `MeetBoardMark.boardName`: the surname and whatever the
  sheet put in brackets after it, never the initial — 'Achebe (Croydon)'.
  A program spells a name for somebody who knows nobody; a board is read by
  somebody watching the competition, and the initial is a third of the width
  of every label on the sector.
- A meet carries `MeetConditions`: the sky, the temperature as it was
  written (in the unit it was written in — nothing computes with it, so
  converting would only round a number somebody typed exactly), the wind as
  it hit the sector, and a note for the rest. Asked for in one line across
  the top of the meet, and never for a fixture that hasn't happened yet.
- An athlete's profile reads the season two ways. Each personal best draws
  the throws behind it — every measured mark at that event and weight,
  against the calendar, the ones taken at a meet solid and the training
  marks hollow — and says what the season moved, first mark to last rather
  than best to best, since a best only ever goes up. Under the bests,
  `MeetOuting` reads the meets from the athlete's side: the series round by
  round, which round the big throw came in, the field, the placing and the
  weather. The meets are looked up softly (`meetsOf`), like the athlete
  records, so a profile still paints with nothing but the clips.
- A meet's results go out as a PDF, written by `pdf_writer` — as narrow as
  `pdf_text` is at the other end, and set in Courier, because a results
  sheet is columns and a fixed-width face lines them up without a table of
  glyph widths. `meet_report` lays it out the way a program is laid out:
  standings order, the series with its fouls and passes still in it, and
  the cut drawn where it falls. The tests read the generated file back with
  the app's own `pdf_text`, which is the honest check.
- The sheet is a report, not a dump. A table says what everybody threw and
  hides what the afternoon was like, so each competition is drawn as well
  as tabulated: a bar to the throw an athlete was placed on, a tick for
  every other legal throw of their series, marker lines at a round number
  of meters off the board's own `boardSpans`, and the cut as a dashed line
  across all of it — whether the winner was clear or hunted, and who found
  it once against who was there all day. The picture is drawn to the
  table's width rather than the page's so the two read as one block, and it
  carries no distances of its own: the table gives every mark in the unit
  it was entered in, a chart can only have one scale, and two numbers for
  one throw is worse than none. Under the table, how it was won — the round
  it turned on, and by how much or on countback. `PdfSheet.figure` hands out
  a box with its own coordinates so nothing outside `pdf_writer` has to know
  what a PDF operator looks like, and `PdfSheet.columns` sets one row out of
  runs so the throw somebody was placed on can be bold where it sits in the
  series without the columns under it moving.
- The one thing on the sheet the meet does not know is a personal best, and
  it is the part somebody will read out. `personalBestIds` — the record
  book's own rule — is run over the same marks the tables are built from:
  the throw is flagged PB in its row, counted in the line across the top of
  the sheet, and named at the foot of it with what it beat. Only a tracked
  athlete can hold one, which falls out for free, because the rest of the
  field's distances never reach the library to be ranked.
- CI builds an APK from `main` and republishes the rolling `latest` release;
  the in-app updater compares build numbers against it. The download belongs
  to `AppUpdater`, not to the screen that started it, and writes into a part
  file it resumes from with a range request — so leaving the app mid-update
  costs the time it was away and none of the bytes, and Android reclaiming
  the app costs the same. Only ever the newest build: the release is a
  rolling one, so anything staged for another build — a half-downloaded
  part file, or a finished APK sitting ready to install — is thrown away
  rather than resumed or opened. Keeping it would walk somebody up through
  the releases one at a time, install and restart and find another update,
  when one download takes them to the end. `_discard` is where that
  happens, and `install` refuses an APK whose stamp is not the build being
  offered. The banner carries the progress; nothing is
  blocked while it runs. The installer is opened when the app is in front of
  somebody, which is the one part that cannot happen in the background.
