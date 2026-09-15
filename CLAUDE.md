# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowMark` (a throw nobody filmed), `ThrowEvent` and the implement specs, `AthleteProfile` and personal bests, `AthleteRecord` (the editable half — a nickname, and the full name and school a heat sheet is matched against), `TrainingNote`, `Meet` (a competition and its series, plus `MeetFlight` — the flight being thrown and where it has got to), `MeetConditions` (what the day was like), `MeetBoard` (the competition as lines across the sector), `MeetOuting` (a season read from the athlete's side), `SeasonAverages` (what it averages between the bests) |
| `lib/services/` | `VideoLibrary` (clips and marks), `NotesLibrary` (training notes), `MeetLibrary` (meets), `AthleteLibrary` (athlete records — the display name every screen resolves through it), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `ResultsSheet` (a meet's results as a PDF on the phone), `JavelinDetector`, `AppUpdater` and `UpdateKeepAlive` (the foreground service that holds the process up while it downloads) |
| `lib/screens/` | `home_screen` (the library), `athlete_screen` (one athlete's profile), `note_editor_screen`, `group_screen`, `meets_screen` (the season, as a list or a calendar), `meet_screen` (a meet's events) and `meet_event_screen` (one competition, where the throwing is recorded), `schedule_import_screen` (a fixture list, read onto the calendar), `heat_sheet_import_screen` (a meet's program, read into its field), `analysis_screen`, `comparison_screen` |
| `lib/widgets/` | `throw_card`, `gold` (the medal and the frame), `event_glyph`, `sector_art`, `mark_editor`, `attempt_entry` (one round of a meet), `entry_dialog` (an athlete into a meet), `note_text`, `conditions_sheet` (the weather, written down), `progression` (a season as a line), `sector_board` (the competition drawn on the sector), `import_source` (the page a schedule or a heat sheet is handed over on), `drawing_canvas` and `drawing_rail` (the tools, run along whichever edge of the frame costs least), playback controls, pickers |
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
                              tool/preview/analysis_preview.dart \
                              tool/preview/compare_preview.dart \
                              tool/preview/comparison_preview.dart \
                              tool/preview/gold_preview.dart
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
athlete and by event, a search in progress, the empty state, five athlete
profiles — among them a shot putter with a full season on him, six meets
this spring and three last, which is the shape the averages and the
record's own staircase are drawn for — each with the history of its best,
what it averages at a meet and what it fouled away, how that has moved
season by season, and the meets it was thrown at; and one of them read
over last season instead through the picker, and one read as the best of
each meet rather than as every throw of it, a training note (as
it opens, and with the keyboard up — which the note preview fakes, insets
and all — toolbar above it, and pinned to the top), and the meet tracker:
the meets as a list and as a calendar, a meet's events, one of them
part-way through, the standings with the cut and what the coach's own
athlete is averaging under it, the field as a list, the live card (four
times — a podium, a field with the
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
thrown folded away — and the analysis screen: the drawing tools up the right
edge of a frame on its side (on their own, with a ring, an arrow and a timer
on the frame, with the marks menu open, with the pen panel open, and folded
away to the one chevron), and the same tools lying along the bottom of an
upright screen, hard against the scrubber with the pen's weight and color
split onto a button each — at the width that holds them and at the one that
shrinks them, with the session on top as a strip of stills and with that
strip put away on its tab — and the compare picker: both slots still empty,
one filled, both filled and ready to open, the sheet as it opens off a
throw, the same sheet off the event filter, and a search that found
something and one that found nothing, all under a navigation bar, which is
what the button at the foot of the sheet has to clear — and the comparison
itself: the two panes across a landscape screen and up a narrow one, the
mirror offered against each clip, and a mark on A before and after A is
turned round — and the gold itself: the medal at
every size the app pins it at, on a line of type and on a card's corner
beside the frame, and then one big enough to see what was drawn. Open the
PNGs to see exactly what the screen paints. **Re-run it
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

The analysis and comparison previews are the ones that borrow from `test/`:
they mount the real screen on the widget tests' in-memory player, so the
'video' is a flat blue rectangle — which is the point, since what is being looked at is where
the chrome sits over the frame and how much of it it costs. Its clip is
stamped as already having scrub frames, so the screen never reaches for the
ffmpeg and path_provider plugins that aren't behind a widget test. A flat
rectangle cannot show a mirror, so the comparison preview draws a stroke on
a pane and then flips it: the ink is the only thing in there that moves.

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
  (`weightLabel`): the men's shot reads as a 16 lb and the U.S. high
  school boys' as a 12 lb, because that is what they are ordered as and
  called at the ring, not 7.26 kg and 5.44 kg. The 7.26 kg hammer is the
  same ball on a wire and takes the same name, since one weight reading
  two ways on one profile is the same implement called two things. The
  label is a name and never an identity — `weightKg` is what a throw is
  filed under, what a best is kept per, and what the analyzer calibrates
  against — and the 12 lb is its own weight rather than a rounded 5 kg,
  since a best is per implement. The discus goes the other way: a U.S.
  high school 1.6 kg is called a 1.6 wherever it is thrown, never a
  3.5 lb, so it keeps its metric name.
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
  The medal is a badge before it is a picture: it is pinned at 13 px beside
  a placing and at 34 px on a shelf, and the size that has to work is the
  small one. The disc is the subject, it carries the whole width, and it
  hangs clear of the ribbon — the two are the same metal, so with nothing
  between them the straps melt into the top of the coin. The ribbon is one
  band, tapering as it comes down, with a slot cut across it that leans
  harder than the band's edges draw in: the right-hand piece runs out to a
  point and the left carries on to a square end. That lopsidedness is the
  read. A ribbon has a front and a back and is folded through itself, and
  two straps leaning symmetrically into each other are a V, which is a
  letter — which is what the first one looked like beside a mark. Every
  number in `_MedalPainter` is measured off a reference rather than
  invented, so change them together or not at all. The star is a hole
  rather than a lighter shape, which is what keeps it a medal at 13 px
  instead of a yellow blob with a smudge in it.
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
- The set a throw was opened with hangs under the header, not along the
  bottom. A strip of stills is the right way to pick a throw out — a coach
  picks one by looking at it, which a list of 'Shot Put · Men · 2026-09-02'
  rows never allowed — and it is the first thing wanted on opening a throw,
  so it shows; but the bottom of the screen is where the scrubber, the
  transport and the drawing tools all already are, and down there it was in
  the way of all three. It puts away on a tab hanging off its own bottom
  edge — a handle on the thing it moves is the one nobody has to be told
  about, and the portrait header has no width for another button. Tap it or
  pull it: a bar across the top of a panel is the shape of something that
  gets dragged, so a thumb that comes down and pushes is asking for the
  tray whether or not anybody said it could, and a drag that did nothing
  would read as a handle that was stuck. Both land on the same toggle, so
  the tray is never left half way. The difference is that a pull means the
  way it points — pulling down on a tray already showing does nothing —
  while the tap is the gesture for 'whichever way it is now, change it'.
  What separates the two is Flutter's own `kTouchSlop`, already cleared
  before the first drag callback arrives, which is why `_pullSlop` is only
  big enough to read a direction off: a second threshold of any size on top
  of that only makes the tray answer late. And
  where it was last left is remembered (`throwlab.throwStrip`), because
  paging replaces the screen and would otherwise drop the strip back down
  under the finger that just put it away. The tab is a grab bar and nothing
  else — the box around it takes the tap, so it is easy to hit and nearly
  invisible — because it stands on the frame of every throw, including all
  the ones nobody is paging through, and a pixel of chrome there is a pixel
  of the throw. It keeps a faint surface behind it rather than sitting bare:
  a bar alone disappears against a bright frame, which is a handle nobody
  can find on exactly the throws this app is pointed at. The pager sits in
  the tray, at the ends of the stills it steps through: next and previous
  are about the set, and the set is what the tray is, so they come and go
  with it rather than holding a card and two buttons open over the frame
  for the whole session. The panel carries its own surface rather than
  the header's scrim — over a frame that fills the top of the screen, stills
  on a fading gradient read as floating over the throw instead of as a
  drawer in front of it. Landscape has no strip at all: the pager lives in
  the left rail there.
- The title names the throw and nothing else — the event and the weight.
  Which of eight throws is on screen is answered by the strip of stills, so
  spending the title on it said nothing a coach needed. Tapping it asks
  about the *throw*: when it was taken, how far it went, what was written
  down, and the edits for each — `showThrowActions`, the same sheet the
  library opens on a long press, so there is one place a throw is
  described.
- The drawing tools run along an edge of the frame and are anchored in its
  bottom-right corner. Which edge follows the shape of the *picture*, not
  the shape of the screen. A clip is filmed on its side, so held that way
  the frame fills the screen and the tools have to sit on it somewhere:
  they float over it as a column up the right edge, out past the release
  and the flight, which is the least of the picture to stand in front of.
  Held upright the same clip is letterboxed into a band of black above and
  below, and there the tools are not floated at all — they are laid out
  inside the bottom overlay, above the scrubber, so they sit hard against
  it whatever else the overlay is carrying rather than at a guessed inset
  over the frame. That is also what killed the line under the frame naming
  the calibration reference: the reference is stated where it is used, on
  the measure sheet and on the card in the library, and the two gestures
  were learned on the first drag.
  A phone is a few pixels short either way — ~300 of usable height on its
  side and ~352 of width upright, against the 305/377 the tools want — so
  the rail shrinks to fit, a few percent nobody sees. It only breaks into
  two runs where shrinking would leave a target a thumb misses at a track
  (`_minScale`), which is a screen no phone has; scrolling is never the
  answer, since a tool scrolled out of reach is one nobody finds and the
  scroll view that offered it swallowed every drag over the strip it
  covered. The seam, when it comes to that, is where the tools are already
  grouped — what a tool is picked with in the first run, what is done to the
  drawing in the second — and the chevron is still last, so it is still in
  the corner.
  What keeps the count down is that the marks *placed* on the frame share
  one menu button wearing whichever is selected. The pen is the one control
  that differs by axis: height is what a column is short of, so up an edge
  the weight and the color go behind a single button opening a panel of
  both, while a bar has the width for a button each, which is a tap closer
  to whichever half is being changed — eight controls up a column, nine
  along a bar. Undo, redo and clear are never behind a menu, because they
  are what a drawing hand reaches for most. Clear can sit in the open
  because undo brings the whole frame back — `DrawingController` keeps the
  edits rather than snapshots of the frame, since an annotation goes on
  mutating while the finger is down. Ten colors are a grid of swatches with
  their names as tooltips, never a list of ten named rows: a list that long
  scrolls on a short screen, and the name is the least of what a swatch
  says.
- A mark is made the way it is measured. An arrow is dragged tail to head,
  a curved arrow traces the path it wants and takes its head where the
  finger lifts, and a circle is dragged out from the middle: what is being
  circled — a hip, a hand, where the implement landed — stays under the
  finger that started it, which a corner-to-corner box does not. A circle is
  stored as its middle and a point on the rim rather than a radius, because
  the two axes normalize by different amounts and a stored radius would come
  back as an ellipse on a frame of another shape. An angle and a
  `TimerMarker` are tapped rather than dragged, since neither has a length
  to pull out.
- A `TimerMarker` is a stopwatch dropped on the frame: it holds the moment
  it was dropped at and reads the gap from there to wherever the clip is
  now, to the hundredth (`formatDelta`), so scrubbing forward times a
  phase — block to release, ground contact, the delivery — without anybody
  doing arithmetic on two frame numbers. It holds a position rather than a
  frame index, because a position is what the player reports and what the
  readout under the scrubber is already counting in. The canvas is rebuilt
  off the player's own value for it, so a box on the frame can never
  disagree with the numbers beside it. It reads a plain zero on its own
  frame rather than a signed one, and is signed either way off it, because a
  coach scrubs back through a throw as often as forward.
- Ink is ink but a reading is type. The two things the canvas paints as
  words — an angle's degrees and a timer's seconds — take their style from
  `Theme.of(context).textTheme`, handed down to the painter: a `TextSpan`
  built inside a `CustomPainter` inherits nothing, so left alone it sets
  them in the engine's fallback face while the rest of the app is in
  Barlow. Handing the style down is how they match without naming a family
  outside `main.dart`.
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
- A tag settles what the video means; `VideoOptimizer.jpegColorFilter` is
  what makes a still written out of it mean the same thing, and it is the
  bigger half of the same shift. A JPEG has nowhere to say what its numbers
  are: the format *is* full-range Rec. 601, and Flutter reads one that way —
  but ffmpeg, handed a Rec. 709 clip, writes the file by stretching the
  range and leaving the coefficients alone, so the still ends up holding 709
  numbers that are then read as 601. Measured on a real clip that cost the
  red track about nine levels of red for as long as a finger was down. So
  every JPEG this app writes — the scrub stills and the library thumbnail —
  names both ends of the conversion: the matrix the clip is actually in
  (what it declares, else the same HD-is-709 guess `colorTagsFor` makes), and
  the matrix a JPEG is actually read with.
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
  its own history: every throw that stood as the best at that event and
  weight on the day it was taken, against the calendar, the ones set at a
  meet solid and the ones set in training hollow — and says how far the
  mark has come and how many times it was broken to get there. Only those
  throws. A card under a heading that says PERSONAL BESTS is about the
  mark, and the scatter of every measured throw it used to draw was
  answering a different question — how the throwing is going — which the
  averages below answer properly, meet by meet and season by season. So the
  line climbs, because that is what a record does; a mark that only equals
  the best does not reset it, the way a record stands until it is beaten
  rather than matched. Under the bests,
  `MeetOuting` reads the meets from the athlete's side: the series round by
  round, which round the big throw came in, the field, the placing and the
  weather. The meets are looked up softly (`meetsOf`), like the athlete
  records, so a profile still paints with nothing but the clips.
  The Marks list underneath holds what is left over: a mark a meet series
  points at is written out round by round on that meet's own card, and
  listing it again below is the same throw twice — so the list is the
  throws no meet was keeping score for. They are still the athlete's marks
  everywhere else, bests included; a meet's are edited where they were
  entered, on the competition screen.
- A best is the one throw that came off; the season is what the rest of
  them average. `MeetSeries.average` is the mean of a series' legal marks
  and `fouls` is what it cost — never rolled together, since a foul is a
  throw that went unmeasured and averaging it in as zero would say an
  athlete threw half as far as they did. `SeasonAverages` reads those over
  a season, per event and weight the way a best is.
  Competitions only. Training is thrown under conditions nobody is
  recording — a light implement, a short run, a good day at the end of a
  session — and a number built out of it answers a question about Saturday
  with Tuesday's throwing. What an athlete does in training is drawn on the
  progression under their best, where every measured throw is plotted
  against the calendar; this section is about meets, and an athlete who has
  not competed has no section at all.
  A meet can be read two ways and both are worth asking — `MeetLine`: every
  measured attempt of the series averaged, or the best of it, the throw the
  placing was made on. An athlete whose averages climb while their bests
  stand still is closing on something; one whose bests hold up on a falling
  average is living off one throw a day. Neither shows on the other's line,
  so a switch in the card's header picks which, and everything on the card
  follows it at once — the figure, the line under it, and the seasons under
  that. Which way is remembered (`throwlab.meetLine`), because it is a
  preference about how a coach thinks rather than about one athlete.
  The averages sit in their own section under the bests, headed the way a
  competition names itself (`Discus · 1 kg`) rather than the way a record
  book does (`1 kg Discus`), so the two lists don't read as the same rows
  twice.
  A card says one number large and the rest small. Averages set as equals
  across the top read as rival answers to one question — 52.66 and 52.15
  are near enough alike that nothing about them says which is which — so
  the chosen reading leads, with what it was taken over written beneath it
  in the words a coach would say ('over 5 throws at 2 meets · 3 of 10
  fouled · 2 passed'; the fouls wear the app's red and the passes do not,
  since a pass is a round given up on purpose). The other reading, and the
  furthest thrown at a meet all season, follow as asides named in full. A
  mean is never drawn off a single throw: a mean of one is the throw again
  under a heading that promises a season.
  It is said where it is thrown, too: under each meet on a profile, and
  under the coach's own athletes in the standings — a coach at the ring is
  asking what the afternoon is averaging, not only what the best of it was.
- The averages are read one season at a time, and a season is a calendar
  year (`SeasonAverages.seasonsOf`, `forSeason(season:)`). A career average
  answers a question about this spring with the throwing of two years ago
  in it, so the section opens on the most recent season with a competition
  in it and the picker in its heading reaches the others, 'Every season'
  included. An athlete who has competed in one season is never shown it —
  there is nothing to tell apart — and the choice is not remembered between
  athletes, since the default is already the season being coached. A year
  is exactly right for an outdoor season and wrong for an indoor winter,
  which is one season across two years; `seasonsOf` is the one place that
  would have to learn the difference. The picker governs the section it
  sits in and nothing else: a personal best is a personal best whatever
  season it was thrown in.
- Under the card, the seasons themselves (`SeasonAverages.history`): what
  the meets came to each year, most recent first, read the same way the
  rest of the card is, with what each moved from the year before. The chart
  above it is the meets inside one season, which is the question asked in
  June; this is the one asked in January. Rows rather than a line — four
  points a year apart drawn as a line invent a shape between them nobody
  threw — and the picker never narrows it, since the comparison is the one
  thing on the card a season filter must not touch. What the bar draws is
  the *change*, not the mark: a bar for a 48 m average beside one for 52 m
  has to start somewhere, and anywhere but zero draws a seven per cent
  season as a fivefold one, while zero draws two bars of the same length
  and says nothing. A difference has a real zero.
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
- Comparing two throws is one picker, opened two ways. `pickThrowsToCompare`
  returns the pair in the order the comparison lays them out — A is the left
  pane in landscape, the top one in portrait, and the clip the linked scrub
  is driven from — so the sheet says which is which rather than leaving it
  to the order things were tapped in. Opened from a throw, that throw is A
  and one tap on a candidate opens the pair: it is the clip being watched,
  and confirming it would be a tap spent on something already on screen.
  Opened from the library, both halves go into slots that show what is
  chosen and what is still missing, and a tap with both full lands in B —
  the checkbox list this replaced swallowed the third tap, which is a
  control that looks broken. The narrowing is chips named after the
  reference throw's own event and athlete, on by default for the event
  because a javelin release against a shot put says nothing, and droppable
  because sometimes that is the comparison. Never onto an empty list,
  though: with nothing else of that event the sheet opens wide. A filter or
  a search that empties the list says which one did it and offers the one
  tap that undoes it.
- Linking two clips and looping them are two different questions, and the
  loop is armed by the *releases*. `_linked` is one scrubber driving both,
  which is worth having on any pair; the release loop plays the same
  stretch around each release over and over, which needs both releases
  marked to mean anything. An unmarked release is `Duration.zero` — the
  sentinel the sync row reads to say 'Set release' — so an unmarked clip
  contributes no lead-in while the follow-through still comes out at the
  full 1.5 s off the clips' lengths, and a window read on its own is
  positive for any two clips with a second and a half in them. Gated on
  that, hitting the link button before marking anything turned play into a
  1.5-second loop of the top of each clip. `_hasReleaseLoop` is the rule —
  both releases marked, and a window around them — and
  `CompareLoop.hasWindow` states the same one for the stills path. The two
  have to agree: the decoders are the fallback for the same routine, not a
  second feature. The stagger toggle hangs off it too, since a routine that
  holds one throw while the other finishes has nothing to hold around
  without releases.
- Either clip in a comparison can be turned left-to-right, because two
  throws are rarely filmed from the same side of the ring: a right-hander
  seen from the left is the mirror of the same right-hander seen from the
  right, so side by side the two turn away from each other and as ghosts
  they cross. It is a way of looking rather than an edit — the file on disk
  and the stored annotations are untouched. The picture turns over with a
  `Transform` around the player and its scrub still together (one of them
  flipped would swap the throw end for end at every scrub handoff), and the
  marks turn with it through `DrawingCanvas(mirrored: ...)`, which reverses
  the *geometry* in the painter rather than the layer. Reversing the layer
  would set the two things the canvas paints as words — an angle's degrees
  and a timer's clock — backwards. A touch on a mirrored pane is read at
  1 - x, so a mark is stored against the clip's own frame and stays on the
  shoulder it was drawn on when the flip comes back off. The control is a
  tick against each clip, down in the transport beside the link rather than
  up in the app bar: the bar already carries the fit and the mode, and a
  fourth control there cut the title to 'Javelin:…' on a narrow phone,
  while the transport wraps and so can never be the thing that runs off the
  edge.
- A modal bottom sheet is only safe at the top. `useSafeArea` insets the
  top and leaves the bottom to the sheet, which is right — a sheet runs to
  the bottom edge — but it means anything at the foot of one has to add
  `MediaQuery.paddingOf(context).bottom` itself or Android draws its
  navigation bar over it. The compare picker's Compare button is the one
  that was half unreachable. The padding goes to zero on its own once the
  keyboard is up, which is when the `viewInsets` padding above it takes
  over.
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
  The bytes do keep coming when somebody walks away, and that takes a
  foreground service (`update_keep_alive.dart`). A backgrounded Flutter app
  is a cached process — Android kills it when it wants the memory, and Doze
  cuts its network once the screen has been off a while — so a download in
  the main isolate stops whenever the system says so, which is exactly when
  a coach has gone to film something. The service costs a notification and
  buys a process Android leaves alone; the download stays in the main
  isolate, resuming from the same part file as before, and the service only
  holds it up. It is asked for and never depended on: every call goes
  through `AppUpdater._holding`, which swallows whatever the service makes
  of it, so a phone that refuses one downloads exactly as it did before any
  of this — as far as Android allows, then onward from the part file next
  time. That is the whole reason the download was wrapped in a service
  rather than moved inside one. The service has to be declared in the
  manifest by `.github/workflows/build-apk.yml`: the plugin's own manifest
  merges in FOREGROUND_SERVICE, WAKE_LOCK and POST_NOTIFICATIONS, but not
  the `<service>` element, not the Android 14+ `FOREGROUND_SERVICE_DATA_SYNC`
  and not the `ACCESS_WIFI_STATE` the wifi lock wants — so the step asserts
  both landed rather than trusting a `sed`.
