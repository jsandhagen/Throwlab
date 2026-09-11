# ThrowLab

**Android app for coaching the throws.** Shot put, discus, hammer, javelin.

Film a throw, break it down frame by frame, and keep the whole season in one place. Marks, bests, notes, and meets all live on the phone.

Works offline. No account, no signup, no signal needed.

---

## Install

No computer, no Play Store, no account.

> **[⬇ Download ThrowLab.apk (latest build)](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)**
>
> [![Latest APK](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fjsandhagen%2FThrowlab%2Freleases%2Flatest&query=%24.name&label=APK&logo=android&color=3ddc84)](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)

1. Open the download link above **on your phone**
2. Open the downloaded file
3. Allow the install when Android asks

> [!NOTE]
> First time only: Android will ask you to allow installs from your browser. That's under **Settings > Apps > Special app access > Install unknown apps**.

**Updates are automatic.** On launch the app checks for a newer build and shows an Update banner that downloads and installs it in place. Android still asks you to confirm.

---

## What's in it

| Feature | What it does |
| --- | --- |
| **Video breakdown** | Frame by frame scrubbing, slow motion, drawing tools |
| **Throw comparison** | Two clips synced to release, side by side or overlaid |
| **Athlete profiles** | Personal bests per implement weight, season progression, meet history |
| **Training notes** | Per athlete, with pictures and checklists |
| **Meet tracking** | Full field, rounds, cuts, standings, countback, live flight order |
| **Live card** | Up / on deck / in the hole, the sector board, and the mark entered under it |
| **Results sheets** | A meet or one event, written out as a PDF to hand around |
| **Schedule import** | Paste text or open a PDF, builds your season |
| **Heat sheet import** | Pulls the throws out and finds your athletes |
| **Release metrics** | Speed and angle estimates (beta) |

---

## Video breakdown

- Import any clip from the camera roll
- Scrub frame by frame, or play at 0.1x up to full speed
- Step one frame at a time and read the exact millisecond
- Draw on any frame:
  - Freehand pen
  - Straight lines
  - 3 point angle tool with a live degree readout
- Undo, multiple colors

**Comparing two throws:**

1. Pick any two clips
2. Mark the release frame on each
3. Play them back in sync

View them side by side, or ghost one over the other and set the opacity. Good day next to bad day, this season next to last.

---

## Athlete profiles

Every athlete gets a profile holding their whole season.

- Filmed throws, personal bests, and marks from meets nobody filmed
- **Bests are tracked per event AND per implement weight.** A 12 lb PR never gets wiped out by a 4 kg throw
- A written down mark can hold the record same as a filmed one
- Distances in meters or feet, typed either way and converted as you go

**Season progression.** Every best draws the throws behind it against the calendar — meet throws filled in, training throws hollow — and says what the season has moved, first mark to last. A PR tells you the ceiling; the line tells you which way it is going.

**Meet by meet.** Under the bests, every meet they have thrown at: the series round by round, which round the big one came in, the field, where it placed them, and what the weather was doing. Tap one to open the competition it was thrown in.

**Editable fields:**

| Field | Used for |
| --- | --- |
| Nickname | What gets displayed everywhere instead of their filed name |
| Full name | Matching them on a heat sheet |
| School | Matching them on a heat sheet |

---

## Training notes

Written per athlete and kept next to their throws.

- Session plans, cues that worked, pictures of a position to remember
- Headings, bullets, numbered lists, checklists
- Pictures with captions
- Bold, italic, underline

---

## Meet tracking

Build a season and read it forward. Today's meet first, then what's coming, then what's already been thrown. View it as a list or a calendar.

**A meet holds the whole field, not just your athletes.**

- Set the format (3 + 3 means six rounds with a cut after three)
- Enter each round from the ring as it gets thrown
- Fouls and passes get recorded as fouls and passes
- Standings calculate per event and implement
- Ties break by countback down the series, same as a real competition

**Live, while it happens.** An event opens on one card: which round is being thrown and how far through it you are, who is **up, on deck and in the hole**, the competition drawn on the sector under them, what the next throw has to do — and the athlete in the circle on their own card from the series list — same rounds, same buttons — so a mark goes in the same way wherever you are standing. All of it worked out from the order and the series, so it stays right without anybody telling it whose turn it is.

**The sector board.** The heart of the live card: the podium as lines struck in the same gold, silver and bronze as the medal, the cut as a dashed line with the qualifying ground shaded above it, and your athlete's mark in the event's color wherever they are standing. The sector is drawn at the event's real angle (the javelin's is narrower); the distances are spread out so a competition decided by a centimeter is still readable, and every line carries its own number on a chip you can read across a field.

**Two rows an athlete.** The top row is who and how they are doing — flight number, name, place, best — with the camera and the ruler beside it. The bottom row is the series: six boxes across the full width of the card, big enough to read at arm's length and to hit without looking down. Tap any box to go back and fix an earlier round.

**Conditions.** One line across the top of a meet takes down the sky, the temperature and the wind. A javelin series into a headwind is a different competition from the same series with it behind, and in six months there is no other way to tell.

---

## Results sheets

At the end of a Saturday the sheet in your pocket is the only one anybody has. Hit the PDF button on a meet — or on one event inside it — and it writes one out: place, name, the series round by round with the fouls and passes still in it, the mark each athlete was placed on, and the cut drawn where it falls. Standings order, laid out like the program it will be read next to. Conditions ride along at the top.

The file lands in the app's storage and opens in whatever reads PDFs on your phone, which is where printing, mailing and sharing live. Nothing is uploaded anywhere.

**Why it matters:** every measured attempt drops into that thrower's record the moment you enter it. A Saturday meet lands in their PBs with no second step. Rival throws stay on the meet and never show up as your athletes' marks.

---

## Schedule import

Instead of typing a season in one meet at a time:

1. Paste a fixture list, or open the PDF the meet sent
2. ThrowLab pulls the meets out of it
3. Tick the ones you want

Nothing gets added until you approve it. If a row is ambiguous (a date with no year, or a `4/12` that could go either way) it reads it the most likely way and flags the row so you can check.

---

## Heat sheet import

Same idea for a meet program.

1. Paste the program or open the PDF
2. Throwing events get pulled out, everything else on the afternoon gets ignored
3. Pick the events you want

**Your athletes get highlighted** so you can spot who's yours in a long field. They're matched by name, or by the full name and school on their profile.

- Your athletes come in tracked, under your spelling of their name
- Everyone else comes in as the rest of the field
- If a heading names a division but no weight, the implement gets guessed from it (boys shot = 12 lb, girls discus = 1 kg) and flagged so you can confirm

---

## Release metrics (beta)

Tag a couple of points on the release frame and get:

- Release speed
- Release angle
- Angle of attack
- Predicted distance (shot and hammer only)

> [!WARNING]
> **This is a beta feature and it needs an exact side on camera angle.**
> The phone has to be square to the throw, 90° to the direction it goes. A few degrees off the line and the numbers drift. Read them as estimates, not measurements.

---

## Camera setup

- One phone, tripod mounted, held steady
- **90° to the throwing direction.** Dead on side view
- Close or medium framing for coaching technique
- Wider framing to catch the whole flight

**The implement is the ruler.** Tag a throw with its event and weight and the app uses that implement's regulated size as the measuring reference. No markers or extra gear to set up.

| Event | Reference | Range covered |
| --- | --- | --- |
| Shot Put | Ball diameter | 7.26 kg / 16 lb down to 3 kg |
| Discus | Disc diameter | 2 kg down to 1 kg |
| Hammer | Head diameter | 7.26 kg down to 3 kg |
| Javelin | Length | 800 g down to 600 g |

---

## Roadmap

Still under active development. What's built and what's planned (automatic implement detection, pose estimation, progress tracking) is in [ROADMAP.md](ROADMAP.md).

## Build from source

```bash
flutter create . --platforms=android
flutter pub get
flutter test
flutter run
```
