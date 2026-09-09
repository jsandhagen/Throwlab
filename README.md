# ThrowLab

An Android app for coaching the throws — **shot put, discus, hammer, and
javelin**. Film a throw on a phone, break it down frame by frame, keep every
athlete's marks and bests in one place, and run a competition from the ring.

It is built to be used at a track, often with no signal: everything works
offline, and there is no account to make.

> **[⬇ Download ThrowLab.apk — latest build](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)**
>
> [![Latest APK](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fjsandhagen%2FThrowlab%2Freleases%2Flatest&query=%24.name&label=APK&logo=android&color=3ddc84)](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)

## What it does

**Break down a throw.** Import a clip from the camera roll and scrub it frame
by frame, from 0.1× to full speed. Step one frame at a time, read the exact
millisecond, and draw over any frame — freehand, straight lines, or a
three-point angle with a live degree readout — to mark a position worth
talking about.

**Compare two throws.** Pick any two clips, mark the release on each, and play
them back in sync — side by side, or one ghosted over the other with the
opacity you choose. A good day next to a bad one, or this month next to last.

**Keep every athlete's record.** Each athlete has a profile: their throws,
their personal bests, and the marks from meets nobody filmed. A best is kept
per event *and* per implement weight, so a lighter implement never overwrites
the mark set with the heavy one. Give an athlete a nickname to show them by,
and their full name and school so a heat sheet finds them. Distances go in
meters or feet, whichever you threw in.

**Write it down.** Training notes per athlete — session plans, cues that
worked, pictures of a position to remember — with headings, checklists, and
formatting, kept alongside their throws.

**Run the meet.** Build a season as a list or a calendar. A meet holds the
whole field, tracks the rounds and the cut, works out the standings with a
countback, and puts every measured attempt straight into the athlete's record.
Read a meet's program in from a heat sheet and its schedule in from a fixture
list — paste the text or open the PDF, and pick out the throwing.

**Measure the release _(beta)_.** Tag a couple of points on the release frame
and the app estimates release speed, release angle, and angle of attack — plus
a predicted distance for the shot and hammer. This is a beta feature and needs
an **exact side-on camera angle**: the phone square to the throw, 90° to the
direction it goes. A few degrees off the line and the numbers drift, so read
them as an estimate, not a measurement.

## Filming for the app

- One phone on a tripod, held steady.
- **Square to the throw — 90° to the direction it goes.** This matters for
  every measurement, and it is what the release-metrics beta depends on.
- Close or medium framing is best for coaching the technique; a wider frame
  catches the whole flight.

The implement itself is the ruler. Tag a throw with its event and weight, and
the app uses that implement's regulated size — the ball's diameter, the
javelin's length — as the reference to measure against. No markers or extra
gear to set up.

| Event    | Reference     | Common weights it measures against |
| -------- | ------------- | ---------------------------------- |
| Shot Put | Ball diameter | 7.26 kg / 16 lb down to the 3 kg   |
| Discus   | Disc diameter | 2 kg down to the 1 kg              |
| Hammer   | Head diameter | 7.26 kg down to the 3 kg           |
| Javelin  | Length        | 800 g down to the 600 g            |

## Installing it

Every build is published as an installable APK — no computer, no Play Store,
no account.

1. Open the download link above on your phone. (The badge shows which build
   you'll get; the [release page](https://github.com/jsandhagen/Throwlab/releases/tag/latest)
   has the same file with build notes.)
2. Open the downloaded file and allow the install when Android asks. The first
   time, you'll also allow installs from your browser, under
   Settings → Apps → Special app access → Install unknown apps.

After that the app keeps itself up to date: on launch it checks for a newer
build and offers an **Update** banner that downloads and installs it in place
(Android still asks you to confirm).

Builds are signed with the repository's committed debug key, which is meant
for personal sideloading — not Play Store distribution.

## Where it's going

ThrowLab is under active development. What's built and what's planned — from
automatic implement detection to pose estimation and progress tracking — is
laid out in [ROADMAP.md](ROADMAP.md).

## Building it yourself

The repository holds the Dart/Flutter source. To build from it, generate the
platform folders, fetch packages, and run:

```bash
flutter create . --platforms=android
flutter pub get
flutter test
flutter run
```

`image_picker` needs the usual photo-library permission on iOS
(`NSPhotoLibraryUsageDescription` in `ios/Runner/Info.plist`); recent Android
SDKs need nothing extra. Contributor notes and the layout of the code live in
[CLAUDE.md](CLAUDE.md).
