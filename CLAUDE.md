# ThrowLab

Flutter (Android-first) app for track & field throws: import a clip, scrub it
frame by frame, draw on it, measure release metrics, compare two throws.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/models/` | `ThrowVideo` (a clip + its metadata), `ThrowMark` (a throw nobody filmed), `ThrowEvent` and the implement specs, `AthleteProfile` and personal bests, `AthleteRecord` (the editable half — a nickname, the first and last name a heat sheet is matched against, and the school), `TrainingNote`, `Meet` (a competition and its series, plus `MeetFlight` — the flight being thrown and where it has got to), `Division` (who a competition is for — girls, boys, women, men), `MeetConditions` (what the day was like), `MeetBoard` (the competition as lines across the sector), `MeetOuting` (a season read from the athlete's side), `SeasonAverages` (what it averages between the bests) |
| `lib/services/` | `VideoLibrary` (clips and marks), `NotesLibrary` (training notes), `MeetLibrary` (meets), `AthleteLibrary` (athlete records — the display name every screen resolves through it), `VideoOptimizer` (ffmpeg re-encode/thumbnails), `ResultsSheet` (a meet's results as a PDF on the phone), `MeetServer` (the phone serving a meet to the people standing at it), `MeetRelay` (the same competition pushed to the Cloudflare relay in `worker/`, so a link reaches anybody rather than only the wifi), `JavelinDetector`, `AppUpdater` and `UpdateKeepAlive` (the foreground service that holds the process up while it downloads) |
| `lib/screens/` | `home_screen` (the library), `athlete_screen` (one athlete's profile), `note_editor_screen`, `group_screen`, `meets_screen` (the season, as a list or a calendar), `meet_screen` (a meet's events) and `meet_event_screen` (one competition, where the throwing is recorded), `schedule_import_screen` (a fixture list, read onto the calendar), `heat_sheet_import_screen` (a meet's program, read into its field), `analysis_screen`, `comparison_screen` |
| `lib/widgets/` | `throw_card`, `gold` (the medal and the frame), `event_glyph`, `logo_mark` (the app's own mark), `sector_art`, `mark_editor`, `attempt_entry` (one round of a meet), `entry_dialog` (an athlete into a meet), `note_text`, `conditions_sheet` (the weather, written down), `progression` (a season as a line), `sector_board` (the competition drawn on the sector), `import_source` (the page a schedule or a heat sheet is handed over on), `share_meet` (the link and its QR), `drawing_canvas` and `drawing_rail` (the tools, run along whichever edge of the frame costs least), playback controls, pickers |
| `lib/utils/` | Scrubbing, frame timing, projectile and release math, formatting, a zoomed frame drawn sharp once it settles (`zoom_detail`), reading a schedule (`schedule_parser`), reading a meet's program (`heat_sheet_parser`), `pdf_text` to get the words out of either as a PDF, `pdf_writer`/`meet_report` to put a results sheet back into one, and `meet_feed`/`spectator_page` — one competition worked out for somebody watching it, and the page it is read on, with `share_payload` holding that competition packaged for whoever carries it and the fingerprint that says whether it has moved |
| `test/` | Unit and widget tests — what CI runs |
| `worker/` | The Cloudflare Worker and Durable Object a competition is relayed through — routes only, and no understanding of a competition (its own README) |
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
                              tool/preview/share_preview.dart \
                              tool/preview/gold_preview.dart \
                              tool/preview/glyph_preview.dart \
                              tool/preview/logo_preview.dart
```

`share_preview` writes a second artifact beside its PNGs:
`build/preview/spectator.html`, the real spectator page with a competition's
feed baked in place of its fetch, and Barlow and the medal copied in beside
it so the type and the badge are the app's there too. A page whose whole job
happens in a browser cannot be reviewed as a golden — open the file, and
every tab works, and so does the question it opens with, because the page
holds the whole competition worked out for every set of athletes somebody
might be standing there to watch — every subset of the field, which is why
the discus it prints is five deep and not thirty.

It also shoots the app's own three views of the same competition
(`app_live`, `app_series`, `app_standings`) at the same 390 x 844 the page
is reviewed at — the two are changed in parallel, always, and this is how
that is checked. That is the comparison that matters — the page is meant to
read as the app, and the only way to know is to stand them side by side, at
one size, on one competition. Every difference this feature has fixed was
found that way and not by reading the CSS.

Standing them side by side is its own step, because a browser is the only
thing that can render the page:

```sh
node tool/preview/compare_share.js   # build/preview/compare_*.png
```

It opens `spectator.html` at the same 390 x 844, answers the question it
opens with (that state is shot first, as `web_asking`), shoots each tab
(`web_live`, `web_series`, `web_standings`) and composes each against the
app's own — three files to open, one per view. Then it ticks two athletes
nobody on the phone is tracking — the one in the circle and the one under
the cut — and shoots the sheet with its boxes ticked (`web_picking`) and
what it leaves behind (`web_following`): a line each on the board, the
caption and the emphasis down the field all moved to them. Those three
have no app side to stand beside, so they are files to open rather than a
fourth pair. It needs Playwright on the
machine (`npm i -g playwright`; the browser is already installed, so never
run `playwright install`), and it asserts nothing: looking at the three
files is the review. The competition it prints has a cut in it on purpose,
so the cut line and the heading over the table are drawn on both sides
rather than being the parity nobody looked at.

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
strip put away on its tab, then with a release marked (the scale counting
from it and the offset beside the clock), measuring (the step over the
instruction, upright and on its side) and a finger down with the loupe
over it — and the compare picker: both slots still empty,
one filled, both filled and ready to open, the sheet as it opens off a
throw, the same sheet off the event filter, and a search that found
something and one that found nothing, all under a navigation bar, which is
what the button at the foot of the sheet has to clear — and the comparison
itself: the two panes across a landscape screen and up a narrow one, the
mirror offered against each clip, and a mark on A before and after A is
turned round — and the gold itself: the medal at
every size the app pins it at, on a line of type and on a card's corner
beside the frame, and then one big enough to see what was drawn — and the
event glyphs at every size a screen pins them at, each row shot on its own
at a phone's pixels, with the javelin once more at 300 px — and the
app's own mark: the launcher icon at the sizes a home screen draws it,
the adaptive foreground under a circle, a squircle and a rounded square,
the app bar and the empty library. Open the
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
- The app's mark is `LogoMark` (`logo_mark.dart`): an Erlenmeyer flask that
  is also a throwing sector. Its walls lean at the sector's 34.92°, it is
  full to just below where the neck opens out, and the liquid carries the
  field — two sector lines leaving the meniscus exactly where it meets the
  glass and running to the base just inside the walls, and three evenly
  spaced distance arcs between them. The meniscus is the front of the
  throwing circle, or the javelin's foul line. It meets the glass below the
  shoulder on purpose: on the curve the wall is still turning, and a line
  leaving the corner there runs on under it. The liquid is one fill with
  the lines and arcs subtracted from it — filled and then cut, the two
  edges leave a hairline of the meniscus across each line — so the field is
  holes in it: white on the launcher's tile and the results sheet, the
  theme's dark in the app.
  It is drawn tight to the flask, never centered in a square: a tall
  narrow flask in a square box is a mark at half the size it was asked for,
  so `LogoMark` takes a height and its width from `logoAspect`. The app
  paints it; the launcher icons and the sheet's `logo.png` are written from
  the same painter by `flutter test tool/generate_icon.dart`, and committed.
  The adaptive foreground is sized to the largest that keeps every stroke
  inside the 66 dp circle Android guarantees, less a twentieth so a round
  icon does not look jammed; the legacy icon fills 80% of its white tile.
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
  not icon-font glyphs. The discus, the hammer and the javelin are drawn to
  a real one's proportions (`discusParts`, `hammerParts`, `javelinParts`),
  each part in what the real thing is made of (`GlyphMaterial`): the steel
  — the discus's rim and plate, the hammer's wire and handle, the javelin's
  head — in white and kept off the rest by a hairline, which is all that
  separates them on a card that draws the glyph all in white, and the
  javelin's cord grip in a near-black gray, light enough not to read as a
  gap on the dark theme. A hammer's handle is bare steel, with no cord. The
  hammer's handle is a closed triangle both hands go through, not a bar
  across the wire's end: the loop is what makes it a hammer. The discus is face on,
  not tilted: flat, it is a round implement the size of its neighbors. The spectator page is handed the same parts
  as SVG rather than tracing its own. The backdrop's arcs stay between the sector lines —
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
  The name is two fields, `firstName` and `lastName`, and `fullName` is what
  they come to. Which half is the family name is not something to be worked
  out from a string: everything that shortens a name to what a board has
  room for read the last word, which is right for 'Nnamdi Achebe', wrong for
  'Anna Sofia' — two given names, drawn across a sector as 'Sofia' — and
  wrong the other way for 'Anna van der Berg', whose surname is three words
  and matched a heat sheet on none of them. So the coach says once, and
  `AthleteRecord.boardName` is the answer: the family name, or the given name
  where they have said there is no other. `athleteBoardName` is where a
  record beats the guess, `AthleteLibrary.boardName` is the one call that
  makes it (the counterpart of `displayName`, with `boardNameFor` as its soft
  helper), and `boardNameOf` is still the reading for an athlete nobody has
  filled anything in for — the last word, which is right far more often than
  it is wrong. A record stored before the name had two halves is split on
  that same reading, so nothing moves on the day of the upgrade and the
  coach is looking at two fields they can put right.
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
  shared by `GoldEdgePainter` (the card's frame) and `PlaceMedal` (the
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
  There are three of them. `Medal` names the podium's metals together —
  gold, silver and bronze, the same five stops and the same light from the
  same corner, so three lines across a sector read as three medals rather
  than as a yellow, a gray and a brown. `medalFor(place)` is the one place
  a placing turns into a metal, and it returns null off the podium, which
  is most of a field. Each carries both a `ramp`, for something with the
  room to show a gradient (the board's lines, a medal's disc), and a
  `flat` mid tone, for type — five stops across two digits is a muddy two
  digits.
  The disc means two different things and so has two names: `PlaceMedal`
  for a placing in the competition in front of you, `PersonalBestMedal`
  for a mark against an athlete's own record book. Same painter, different
  metal and a different thing read out loud, because a screen reader has
  no context to tell them apart.
  Silver is the weak one and knows it: its flat tone sits close to the
  dark theme's own body gray, so a place set in silver alone can read as
  unstyled type. Everywhere a place is struck, weight carries what hue
  cannot — gold bold, silver and bronze semibold, the rest of the field
  medium — and the field around them is set back so a metal has something
  dimmer than itself to stand against.
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
- A competition is the event, the weight *and* the division
  (`MeetEntry.division`): the girls' and the women's 4 kg shot are two
  fields with two cuts even with one ball between them. The division is
  the word a coach looks for on a meet with the whole day's throwing on it,
  so it leads the label — 'Girls Shot Put · 4 kg', "Men's Discus · 2 kg" —
  and `MeetCompetition.byEvent` is the order a meet lists its competitions
  in, and the results sheet with it: by event, then girls, boys, women,
  men, then nobody's, heaviest first. Not by time, because a heat sheet
  does not carry one — the times are on a separate schedule when they are
  anywhere. `heat_sheet_parser` reads the division off the heading
  (`Division.read`, which will not guess from a 'U18' or a lone 'W'), and a
  field started by hand without one takes the sheet's when it is imported,
  rather than splitting into a plain 'Shot Put' beside a 'Boys Shot Put'.
  Null is a real answer — every meet stored before there was a division,
  and a small meet's field that is nobody's in particular — and keeps the
  label and the share link's id exactly as they were. It is never what a
  best is filed under: that stays the weight.
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
  described. It is also why the upright header is the title and two
  actions, compare and measure: who threw it, the note and the frame rate
  describe the throw, and live on that sheet. The rail on its side keeps
  all of them, having a whole edge to spend.
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
  over the frame. A clip filmed upright and watched upright is the first
  case again, not the second: it fills the screen, and a bar along the
  bottom sat on the athlete's feet and the circle. So `_toolsOnFrame` asks
  whether the band under the picture is deep enough for the bar and the
  transport together, and where it isn't the tools float up the right edge
  as the column they are on a turned phone. That is also what killed the line under the frame naming
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
- A throw's release is stored on the clip (`ThrowVideo.release`), because
  every screen that looks at a throw looks at it around that moment. The
  flag beside the speed marks it, the first tap of a measurement marks it
  (that tap is taken on the release frame), and a comparison reads it and
  writes it back, so 'Set release' is asked once per clip rather than once
  per pair.
- The scrubber is a scale, not a slider and a wheel. `ClipLine` is the whole
  clip as a hairline, the release notched into it in the medal's gold and
  each timer in its own ink; `ScrubWheel` under it is a ruler under a fixed
  needle — a tick per frame, and a numbered tick at the shortest round
  interval of time with room between numbers (`ScalePainter.labelStep`),
  counted from the release once there is one ('R', '-0.05', '+0.10') and
  from the start until then. It is a wheel, and feels like one because it
  behaves like one. The surface moves with the finger — the numbers read
  left to right, so later frames are pulled in from the right and a drag to
  the left goes forward, as a timeline or a tape does. That is the opposite
  of a drag on the frame, and on purpose: the first version kept the two
  the same and ran the ruler against the thumb, which read as something
  slipping under it rather than being turned. In the hand it is drawn where
  the hand has it — the frames stepped plus the part of one not stepped
  yet (`ScrubAccumulator.fraction`) — not where the player has got to,
  which lags a scrub by a seek and moved it in lurches; let go, it eases
  onto the frame it stopped at like a detent before following the player
  again. And it is drawn as a drum seen face on (`ScalePainter`): the
  spacing is true under the needle, where the finger is, and closes up and
  dims toward the edges, the numbers foreshortened with it. Paused, the
  needle and the readout work in whole frames (`formatSinceRelease` takes
  frames), because a seek lands a quarter frame short of the frame it
  shows and the release frame has to read 0.000.
- The scale is felt as well as seen (`FrameHaptics`): a selection click per
  frame, held to one per 35 ms so a fling is a ripple rather than a buzz, a
  light impact crossing the release, and one medium impact running into
  either end — where it stops, rather than asking for a seek that goes
  nowhere. The frame steps click too, and repeat while held. Nothing asks
  whether haptics are wanted; the phone's touch-feedback setting does.
- Measuring is said as a step and a sentence: which frame and which of the
  four taps (`RELEASE FRAME · 2 / 4`), one short instruction, a segment per
  tap, and Cancel, Undo tap and Next or Calculate. Undo tap walks the last
  tap back on every step, jumping the frame back where that tap jumped it,
  rather than a re-tap on one step and a drag on another. While a finger is
  down on the frame a loupe (`RawMagnifier`, 3x, hairlines broken round the
  point) stands off to the side of it, because a javelin tip is a few pixels
  and a fingertip forty; it magnifies what is painted, so it is the clip's
  own pixels, the sharp zoom still included.
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
- A zoomed frame is drawn sharp once it stops moving (`zoom_detail.dart`).
  Pinching blows the frame up on the GPU, bilinearly, and by 8x a hand at
  release is mush; so when nothing has moved for a moment, ffmpeg cuts what
  is on screen out of the playback copy, scales it to the screen's own
  pixels with lanczos, and `DetailStill` fades it in over the soft frame —
  from 2x up, since below that it is the GPU's picture again with a render
  spent on it. It is the pixels the clip has, drawn better — never an AI
  upscale, which would invent detail on the one part of the frame somebody
  is measuring off. And never past them: lanczos works by overshooting,
  which drew halos round hard edges and colors stronger than any in the
  clip, so the result is clamped (`maskedclamp`) between each pixel's
  darkest and brightest 3x3 neighbor in the clip, on every plane. No
  sharpening on top: in a phone's footage of a field the finest thing in
  the picture is the compression, and an unsharp mask drew it as grain and
  blocks, inside the range the clamp allows. Measured, and written down in
  `detailCommand` — change the filter by measuring again. It lives inside the zoom transform and is
  placed by the crop it was actually cut to (widened to even pixels), so a
  pan or pinch leaves it correct where it is while the next one renders; it
  only comes down when the *frame* changes — a play, a scrub's own stills,
  a step. Which frame is the whole difficulty, as at the scrub handoff:
  ffmpeg's `-ss` draws the first frame at or after the position, which is
  the player's rule after a seek and not after a pause out of playback, so
  `detailTarget` renders at the player's last seek (`FrameSeeker.lastTargetOf`,
  kept per player because the transport has seekers of its own) and, after
  playback, seeks the player onto the frame it is already showing first.
  The JPEG goes through `jpegColorFilter` like every other one, or the sharp
  still is a shade off the frame it lands on. A clip whose playback copy is
  owed a remake is left soft: the file is replaced under the open player.
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
  draws what is outside as an arrow off the edge carrying its mark and
  how far out it landed — a leader five meters clear is worth an arrow, not
  worth squashing the fight for second into an inch of sector.
  Not all of it, though: a line pinned to the edge costs a row of the
  picture the board exists to draw, so only the ones the band cannot
  answer for get one — the lead, the cut, and whoever the board is being
  read for (`_worthTheEdge`). Second and third, a long way up, are a list,
  and the standings are the list; four labels stacked at one edge is four
  rows spent saying 'there are people up there'. The exception is the
  athlete standing exactly on the cut, who is kept whatever their place:
  the cut gets no line of its own when somebody is already on it, so
  dropping them would take the cut off the board with them. The band's
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
  Both renderings stack them the same way or neither can be looked at
  against the other: down a running ceiling, furthest first, each label
  kept clear of the one above it and one pinned to an edge given the room
  its arrow needs on *both* sides rather than only under it — the lead and
  the cut can be off the same edge at once, which is the board that has
  broken. Every line is drawn before any label, too: a line drawn after one
  cuts straight through it, which is why `SectorBoard` makes two passes and
  why `spectator_page` does. The page had neither, and it took a
  competition with the cut broken off the far edge to show it —
  `web_following`, where a followed athlete's arc was painted across the
  pill of the athlete standing on the cut. Those three followed states are
  the ones with no app counterpart to stand beside, which is how it went
  unseen.
- A label on the board is two pills at the edges of the box — place and name
  at one, the mark at the other — with the line running between them, and
  they sit level with the ends of their own arc rather than with its middle,
  which is what makes a label read as belonging to a line. A mark the band
  broke off has no line to leave room for, so it gets one solid pill — the
  name at one end and the mark at the other, the backdrop at full weight
  where the pair are translucent — with the arrow and how far out it
  landed riding outside it. That arrow hangs past the pill, so an edge
  label is given room for it on both sides when the labels are stacked
  clear of each other: the lead and the cut can be off the same edge at
  once, which is exactly the board that has broken. The name is `MeetBoardMark.boardName`: the surname and whatever the
  sheet put in brackets after it, never the initial — 'Achebe (Croydon)'.
  A program spells a name for somebody who knows nobody; a board is read by
  somebody watching the competition, and the initial is a third of the width
  of every label on the sector. Which word the surname is comes off the
  athlete's record where there is one: `MeetBoard(boardNames:)` takes the
  resolver, threaded exactly as `isPersonalBest` is — through
  `competitionFeed`, `ShareSource` and `MeetServer`/`MeetRelay.start` — so
  the screen and the page are handed the same name already cut, the way they
  are handed every mark already spelled. Nothing but the label moves:
  `MeetBoardMark.name` stays the athlete tag every throw of theirs carries.
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
- The app's own mark goes in the sheet's top corner, out of the flow of the
  text — a letterhead, because a sheet is printed and pinned to a board
  beside three others and should say whose it is without being read.
  `PdfSheet.badge` places it and writes nothing else, so a report handed
  none is laid out byte for byte as it was; the meet's name is the one line
  wide enough to reach the corner, and is cut to what is left beside it
  (`columnsBeside`) rather than run under it.
  Pixels, not a drawing. `sheetLogo` has the engine decode
  `assets/icon/logo.png` at the height a sheet draws it — by height alone,
  since the mark is cropped to a tall flask and a square decode squashes
  it, which is also why the name beside it is cut to the logo's real width
  rather than to its height — and `PdfImage` embeds
  what it got — the same rule the personal-best medal is served under, for
  the same reason: every number in a mark somebody designed is measured off
  a reference, and one redrawn out of PDF operators until it looked about
  right would be nearly the logo. It is decoded once per process and asked
  for softly: no bundle or a decode that failed is a sheet without its
  logo, never a sheet a coach is waiting on. A PDF keeps color and alpha in
  two images, so it goes over as `/DeviceRGB` with a `/DeviceGray` `/SMask`
  beside it — line art on nothing, and painted as opaque pixels it would
  arrive as a white card with a drawing on it. Straight rather than
  premultiplied alpha, or every stroke gets a dark fringe. It is the one
  stream on the sheet that is deflated, because it is the one that is not a
  few kilobytes of text; `pdf_text` skips it on the way back, which is what
  `_isContent` has always been for.
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
- The share link is a public one, and the hostname it is built on is baked
  into the build: `--dart-define=THROWLAB_RELAY=...`, set in
  `.github/workflows/build-apk.yml` beside the build number. It is a
  property of the build rather than of a meet — a coach must never be
  typing a URL, and a wrong one fails at a ring with a stand watching — and
  it is not a secret, since it is printed under every QR the app hands out.
  A build that names none cannot share and says so on the sheet rather than
  guessing at a hostname, which is what a local `flutter run` gets and why
  sharing is dead in a debug build unless the define is passed.
- A competition can be followed by the people standing at it, and the phone
  is the server. `MeetServer` binds a socket and hands out
  `http://192.168.43.1:8080/M/<token>`; anyone on the same wifi — or on the
  phone's own hotspot, which is the case that reliably works, since venue
  wifi usually walls its clients off from each other — opens it in a
  browser. Nothing is uploaded and no account exists, which is the only
  shape of live sharing that survives a field with no signal on it. The
  token is per share and unguessable, a wrong one 404s rather than 403s (a
  link that has stopped being shared should look like one that never was),
  and there is no route that writes: a spectator cannot enter a mark
  because nothing on the server can.
- One ring, one link. A share is a `MeetCompetition`, never the meet: the
  link is handed over at a sector by somebody standing at it, and what the
  people there are watching is the discus — not the javelin two hours
  later, and not the rest of the day's field, who are other people's
  athletes and never agreed to be on anybody's phone. The discus link
  serves the discus and 404s everything else, including its own meet's
  other events and their results sheets. A coach with two rings going
  shares each and gets a link for each; the server holds a token per
  competition on one socket, and closes it with the last of them.
- The page is served the *answers*, never the rules. `competitionFeed` runs
  `MeetStandings`, `MeetFlight` and `MeetBoard` and hands over places, the
  cut, the three an infield calls and the band of sector worth drawing,
  with every mark already spelled through `formatDistance` — so the browser
  knows nothing about countback, prelims or feet and inches, and cannot
  become a second implementation of a competition that disagrees with the
  coach's own screen. That extends to every *sentence* the app prints off
  a rule: what the throw in the circle has to beat and what the coach's
  athlete is short of (`caption`, each line tagged with which of the app's
  colors it is set in rather than a hex, since the page already holds the
  palette), what the cut is called over the table (`cut.label`), what a
  row of it needs (`needed`), and when the coach's own throw in a flight
  that isn't the one in the ring (`flight.elsewhere` — which is why
  `yoursLater` lives on `MeetFlight` rather than on the screen that used
  to own it: one sentence written twice is two sentences waiting to
  disagree). `flight.upOrder` is who the live card is built around, given
  as a place in the throwing order rather than an id, because the field is
  already keyed by that on the wire. A series box carries the mark twice, in full and as
  `short` without its unit, because that is the one place the app itself
  drops it (`_AttemptBox`) and six boxes across a phone have no room. The
  server holds no copy of the competition: it reads the meet through
  callbacks per request, so a mark entered between polls — or an athlete
  entered after the link went out — is simply there on the next one.
- The whole competition goes out at once, so switching tab costs no request
  at all, and the page keeps working when the phone wanders off the wifi.
  It says how old it is rather than going blank.
- The page asks who the person reading it is there for, and that is the one
  question it has of its own. Everything the app says about 'yours' — the
  lines on the board and the run of the competition the band is hung on,
  what is needed to make the final, the averaging line under a standing,
  which flight yours are still waiting in — is said about
  `MeetEntry.tracked`, because the phone belongs to the coach. Somebody
  handed the link at a ring came to watch their own, who are usually
  somebody else's and are nobody at all on that phone. So the page asks on
  the way in, sends the answer up with every poll (`?f=<ids>`), and
  `competitionFeed` works the same sentences out around those athletes
  instead — `MeetBoard(following:)` for the lines and the band,
  `MeetFlight.laterFor` for the flight, `mine` on each place for the
  emphasis and the two asides. Not one new sentence anywhere: the question
  changes who they are about and not a word of them, which is what keeps
  the two renderings one competition. Unanswered, the feed is the coach's
  own screen exactly as before, which is the state the parity check is run
  in.
  A set, never one athlete. A parent has two throwing and a club's
  supporter four, and the coach's own 'yours' was a whole roster from the
  start — so it is asked as the field with a box against every name, read
  down the throwing order and ruled off at the flights the way a heat
  sheet is ticked through, and everything downstream takes them as a set:
  a line each on the board, the best-placed of them where the band is
  hung, ticked down the field and the standings, and the first of them in
  the caption, exactly as the app does with several of the coach's own. A
  tick turns its own row over rather than repainting the panel, because a
  field long enough to scroll must not jump back to the top under the
  finger that ticked somebody halfway down it — and the list closes on
  Done rather than on the first tick, since there may be two of them.
  By entry id, never by a place in the throwing order: the order is redrawn
  for the final and shifts under everybody below an athlete entered late,
  and a parent must not be quietly handed somebody else's daughter.
  Anybody the competition no longer holds is left out of the `following`
  it echoes back, and the page drops them and keeps the rest rather than
  following a ghost. The choice is
  remembered per share (`throwlab.watch.<token>`), so it is asked once at
  the discus and again at the javelin, and a browser that refuses storage
  is simply asked every time — a worse page and a working one. Nothing is
  registered on the phone: the choice rides on a GET and is spent on that
  one answer, two people on one link follow two different sets, and there
  is still no route that writes.
  Over the relay, the question is asked exactly the same way and answered
  by exactly the same phone — the page has one code path and cannot tell
  which is carrying it. What changes is *when*. Serving its own socket, the
  phone reads `?f=` off the request and works the competition out again
  inside it; pushed to a relay, there is one feed held for everybody and no
  phone at the far end to ask. So the relay is a post box: a poll carrying
  `?f=` has its set written down (`wanted`, capped and aged out, since the
  keys arrive off a query string), the sets go back to the phone on the
  answer to its next push — and on `/wanted`, behind the write key, for the
  rounds where nothing is thrown and there is no push to carry them — and
  the phone answers each with an overlay the relay files under that set and
  applies on the way out. A set it has not been answered for yet is served
  the coach's own reading with the `following` echo put back, so the tick
  survives the poll it was made on and the board becomes theirs a push
  later rather than unticking under the finger.
  Answered as a *delta*, not as a competition of its own: the keys that
  moved, `places` by the row, and a row by its fields. Measured on a field
  of sixteen, following three athletes moves `following`, `board`, a
  caption, and `mine` plus the two lines that hang off it on four rows —
  1.2 KB against a 9.5 KB feed, where the same answer sent whole would be
  the feed again per set, per round, on a coach's cellular connection.
  `feedDelta` is the subtraction and `applyDelta` in the worker is the only
  other half; the page is served the composition and never learns it was in
  two pieces. What the relay does with it is arithmetic on data that
  arrived already decided — it still knows nothing about countback, prelims
  or feet and inches, which is the whole rule this feature is written
  under.
  A set is what makes the overlay the right shape and a per-athlete answer
  the wrong one: the band hangs on the best placed of them and each of them
  gets a line, so two answers do not compose into the answer for the pair.
  Working that out in the browser would have been the second implementation
  of a competition all of this exists to avoid — so the phone is asked the
  question it can answer, and the relay only has to remember who asked.
- **`MeetEventScreen` and `spectator_page` are two renderings of one
  competition, and they are changed together or not at all.** Touching what
  a view says or how it reads on either side — the header card and its
  calls, the field card, the series boxes, the board, the standings, the
  metals, the type, the spacing, a color — is a change to both, in the same
  commit. They have already drifted once: the page was laid out from the
  code rather than from the screen, and it came back a blue app with
  opaque boxes, an F for a foul, a leader the live view never names and the
  field read down the wrong order. None of that was visible in a diff.
  So the check is not reading the CSS — it is `share_preview` and then
  `compare_share.js`, at one size, on one competition, looked at. Re-run
  both and open the three `compare_*.png`. It found all of this: a live
  view that stopped at the board where the app's carries the caption and
  the athlete in the circle, a translucent live card with the backdrop's
  sector crossing the drawn one, a trapezoid where the app draws a cone,
  a leader's mark gilded in a table that colors a mark for whose it is,
  the medal at twice its size and on the wrong side of the placing, and
  a cut the page drew as a heading where the app rules it across.
  Some things belong to one side only and that is fine: the coach's
  actions (the camera, the ruler, Add athlete, the round-entry sheet) can
  never be on a read-only page, and the page carries the meet's name, date,
  venue, conditions, how old it is and its own question about who is being
  followed — the field with a box against every name — because a spectator
  has no app around it for context and the coach's phone already knows
  whose athletes are theirs. Say which in the commit rather than letting the two drift
  quietly.
- The live view is one card, and it is the one card on the page that is
  opaque. The app's is the flight above the sector, the sector, what the
  throw in the circle has to do, and under a rule the athlete about to
  take it with the same six boxes as the field — one surface, blended to
  exactly the tone of the translucent ones rather than given a color of
  its own, because the page's own sector backdrop runs behind it and two
  sectors drawn over each other at different angles are a picture of
  nothing. The board inside it is drawn by the same geometry
  `SectorBoard` uses, ported rather than approximated: an apex below the
  box at whatever distance makes the wedge take 0.46 of the width at its
  far edge, real arcs struck around it, the sector's own half-angle off
  the feed, the grass wash, the marker lines clipped to the wedge, the
  ground past the cut shaded to the cut's own arc, and the scale in words
  in the bottom-left corner. It is measured off the room it has — half the
  view, clamped to its own width — so a turned phone redraws it rather
  than stretching a fixed viewBox, and the labels are measured in a canvas
  rather than counted in characters, because a width guessed at so many
  pixels a character leaves a panel hanging off the end of every short
  label.
- The page is laid out as the app lays the same three views out, not as a
  web page about them. Its header card is the app's — the round, how much
  of it has been thrown, the bar under that, and the three an infield calls
  out. Whoever is in front goes under a rule beneath them, but only on the
  Series tab and only when they are not already one of the three: that is
  `_FlightBody`'s own `showLeader` rule, and the live view leaves the
  leader off because the board below already draws the lead across it. The
  feed hands over the words
  (`thrownLabel`, `calls`, `leading`, `consistency`, `gridLabel`) rather
  than numbers for the browser to phrase. The field reads down the throwing
  order with the order number at the left and the place beside the mark on
  the right; the series boxes are numbered and a foul is an X, because a
  coach reading a series wants the round a mark came out of and an F is a
  grade. The standings draw no rules between rows — the app's table doesn't,
  and a four-line result cut into boxes reads as four things rather than one
  competition. Only the coach's own athletes carry the averaging line under
  them.
- Two accents, and they are not the same one. `--tint` is the event's own
  color, which is what the app's competition screen colors everything
  *inside* its cards with; `--accent` is the theme's primary, which is what
  the segmented bar is painted in. A page that used one for both read as a
  blue app beside a green one.
- The board is drawn portrait and fills its card, because a sector squashed
  into a landscape strip stacks the competition into an inch of it — which
  is the one thing a board is for. Its marker lines carry no numbers: the
  app doesn't label them either, it says how far apart they are once in the
  corner, and a number on every arc is five numbers competing with the
  marks. A label is bold type on a quiet panel rather than a stroked box,
  and the athlete the board is being read for carries a marker at the middle
  of their line.
- The personal-best medal is not ported to SVG. `medalPng` strikes it with
  the app's own painter and `MeetServer` serves the pixels, because every
  number in `_MedalPainter` is measured off a reference and a badge that is
  nearly right is worse than none. The page pins it beside the place, which
  is where the app pins it — so the best box keeps its own ring and a PB is
  never said twice.
- It is meant to read as ThrowLab rather than as a web page about ThrowLab,
  so `spectator_page` is not styled by hand. The palette is written out of
  the app's own `ColorScheme` — handed to `MeetServer.start` by the sheet
  that starts it, so the theme stays `main.dart`'s to decide — the type is
  the bundled Barlow, served off the phone at `f/r.ttf` and `f/s.ttf`
  because there is no network at a track to fetch a font from, and the
  chrome is the app's own: the segmented bar wearing the two-cut silhouette
  of `angularShape`, its block leaning at the sector's half-angle and
  squaring up against whichever end it has reached, the drawn `EventGlyph`
  in the event's own color, and the sector backdrop the library and the
  meet stand on — `SectorBackdropPainter`'s own geometry rather than an
  impression of it, drawn at the viewport's real size and from the top of
  the segmented bar down, because the app paints it into the body under
  its app bar and it is the shape of *that* box which sets the bearing the
  wedge crosses the screen on. A fixed viewBox stretched to fill the phone
  was the version that did not line up: the sector came out a couple of
  degrees off and its arcs came out as ellipses. The cards are *not* angular — the competition screen's are
  plain `Card`s at the theme's 16px radius, and translucent
  (`surfaceContainerHighest` at `cardOverSectorOpacity`, 70%, in
  `sector_art.dart`) so the sector stands through them, which is most of
  what made an opaque page read as a different app. Faintly, though: at
  45% the backdrop's lines ran through the type on every card. The header
  card over the field is solid (`solidCardOverSector`) on both sides, like
  the live card — it is what the whole list is read against. And the
  sector never runs through a header: whatever sits above a screen's
  scrolling content (the segmented bar, the meet's weather line, and on
  the page the title, the meet, the follow chip and the tabs) is laid on
  the plain surface — `HeaderBand` in the app, `.top` on the page — so the
  backdrop starts under it. A band over the backdrop, not the backdrop
  moved down, because the box it is laid out in sets its bearing. The
  athlete in the circle is edged in the event's color at 12px, as theirs
  is. The podium's three metals are written into it out of `gold.dart` too
  — the flat tones as CSS variables for the places, and the five stops as
  SVG gradients for the board's own lines, which are the one thing on the
  page big enough to show a ramp. The page never spells a color of its own.
  A placing is the bare number in the standings and the ordinal on a field
  card, which is how the app's own two lists count. Two weights, not the app's four: a page this size only sets body and
  emphasis, and each file is a quarter-megabyte of somebody's wifi. The
  font is the one thing here worth a browser cache; the state is sent
  `no-store` so it never lands in a spectator's history.
- The results sheet is a route, not a second implementation:
  `meetResultsPdf` is pure Dart over the meet and the record book, so it is
  generated into the response — this competition's, with `only:` set from
  the share. It is offered where the app offers it, as an action in the top
  right beside the title, rather than as a button at the foot of the page. A spectator leaving early downloads the event on their way to
  the car park, with no signal anywhere near it.
- The link is handed over by QR, because nobody types 192.168.43.1:8080 off
  a screen in sunlight — and printed under it in full, because sometimes
  they have to, which is why the token has no 0/O or 1/I in it. The code is
  black on a white card, the one place the app breaks its own dark theme:
  a dark-on-dark QR is one no camera will read. `QrPainter` holds the
  matrix and snaps modules to whole pixels, since a code drawn on
  fractional boundaries grows seams a camera reads as noise. It is offered
  from `MeetEventScreen`'s app bar beside that event's results sheet — the
  two things a coach reaches for standing at a ring — and the action is lit
  in the event's color while the phone is serving it, because a coach who
  has walked to the next ring has no other way to tell that it still is.

- The relay deploys itself, by Cloudflare Workers Builds: the Worker is
  connected to this repository with `main` as its production branch, so a
  push that touches `worker/` deploys it. Nothing in the repo shows that —
  it is dashboard-side — which is why `worker/README.md` says so. The one
  thing the repo must carry is the staging: `public/` is gitignored and
  built out of `assets/fonts/`, so a fresh checkout has no such directory
  and `wrangler deploy` stops dead on `assets.directory`. The `[build]`
  command in `wrangler.toml` runs `stage-fonts.js` before every deploy,
  whoever is deploying and before `npm install` has run. Without it every
  git build failed silently as far as anyone looking at the app could tell:
  the phone asked spectators who they came to watch and the relay, still on
  older code, threw `?f=` away before the Durable Object saw it.
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
