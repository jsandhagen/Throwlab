# ThrowLab

A coaching app for the throws — **shot put, discus, hammer, and javelin**. It
started as a way to break a throw down on a phone, and has grown into the
whole coaching record: every athlete's marks and bests, their training notes,
and the meets they throw at, all on the one device and all working offline.

There is no account to make and no signal needed — it is built to be used at a
track.

> **[⬇ Download ThrowLab.apk — latest build](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)**
>
> [![Latest APK](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fjsandhagen%2FThrowlab%2Freleases%2Flatest&query=%24.name&label=APK&logo=android&color=3ddc84)](https://github.com/jsandhagen/Throwlab/releases/download/latest/ThrowLab.apk)

## Break down a throw

Import a clip from the camera roll and scrub it frame by frame, from 0.1× to
full speed. Step a single frame at a time and read the exact millisecond.

Draw over any frame — freehand, straight lines, or a three-point angle with a
live degree readout — to mark a position worth talking about.

Pick any two throws and play them back in sync: mark the release on each, then
watch them side by side, or with one ghosted over the other at the opacity you
choose. A good day next to a bad one, this season next to last.

## Athlete profiles

Every athlete has a profile that gathers their whole season: their filmed
throws, their personal bests, and the marks from meets nobody had a camera up
for. A best is kept per event **and per implement weight**, so a lighter
implement never overwrites the mark set with the heavy one — and a throw that
was only ever written down can hold the record just as a filmed one can.

Give an athlete a nickname to show them by, and record their full name and
school so a heat sheet can find them automatically. Distances go in meters or
feet, whichever they were thrown in — typed either way and converted as you go.

## Training notes

Keep session plans, cues that worked, and pictures of a position to remember —
written per athlete, alongside their throws. Notes take headings, bullets,
numbered lists, checklists, and pictures with captions, with bold/italic/
underline formatting, so a training log reads like one rather than a wall of
text.

## Meets and the season

Build a season and read it forwards: today's meet, what's coming, and what has
been thrown — as a list, or as a calendar of the months it falls in.

A meet holds the **whole field**, not just your own athletes. It tracks the
format (a 3 + 3 is six rounds cut after three), works out the standings per
event and implement, and breaks ties by countback down the series the way a
competition does. Enter each round from the ring as it's thrown; a foul or a
pass is recorded as one.

Every measured attempt becomes a mark in the thrower's record the moment it's
entered, so a Saturday's competition lands in their personal bests without a
second step — and a rival's throw, entered against the field but not tracked,
never turns up as one of your athletes' marks.

## Read a schedule

Rather than typing a season in a meet at a time, paste a fixture list — or open
the PDF the meet sent — and ThrowLab picks the meets out of it and puts them up
for approval. Nothing is added until you tick it. Where the text is ambiguous
(a date with no year, a `4/12` that could go either way) it reads it the most
likely way and says so on the row, so you can check.

## Read a heat sheet

Read a meet's program the same way: paste it or open the PDF, and the throwing
events are pulled out — everything else on the afternoon is left alone. Your
own athletes are matched against the field (by name, or by the full name and
school on their profile) and **highlighted**, so you can see who's yours in a
long list at a glance. They come in tracked, under your own spelling of their
name; the rest of the field comes in as the rest of the field. When a heading
names a division but no weight, the implement is guessed from it — a boys' shot
is a 12 lb, a girls' discus is a 1 kg — and flagged so you can confirm.

## Measure the release _(beta)_

Tag a couple of points on the release frame and ThrowLab estimates release
speed, release angle, and angle of attack — plus a predicted distance for the
shot and hammer.

This is a beta feature and needs an **exact side-on camera angle**: the phone
square to the throw, 90° to the direction it goes. A few degrees off the line
and the numbers drift, so read them as an estimate rather than a measurement.

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

| Event    | Reference     | Measured against            |
| -------- | ------------- | --------------------------- |
| Shot Put | Ball diameter | 7.26 kg / 16 lb down to 3 kg |
| Discus   | Disc diameter | 2 kg down to 1 kg           |
| Hammer   | Head diameter | 7.26 kg down to 3 kg        |
| Javelin  | Length        | 800 g down to 600 g         |

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
