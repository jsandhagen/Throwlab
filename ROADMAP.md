# ThrowLab Roadmap

Checked items are implemented (at least in a first version). The phases are a suggested build order: each one delivers something a coach can use on day one.

## Phase 1 — Core video workflow (v0.1, current)

- [x] Video import + library with event/gender tagging
- [x] Frame-by-frame video scrubbing (configurable fps)
- [x] Slow-motion playback (0.1×–1×)
- [x] Manual drawing/annotation layer on any frame (pen, line, angle measure)
- [x] Throw comparison — two throws synced to release frame, side-by-side or ghost overlay
- [x] Select event + athlete gender (auto-sets implement dimensions)
- [x] Projectile physics core (predicted distance, flight time, optimal angle, distance lost to angle)
- [ ] In-app slow-motion capture (record directly instead of importing)
- [ ] Persist drawings per video and per frame
- [ ] Session scatter plot — release angle vs speed for all throws

## Phase 2 — Detection & calibration

- [ ] Auto-detect implement in frame (circle/ellipse/line detection + ML)
- [ ] Confirm calibration from known implement size
- [ ] Manual implement tap/assist when auto-detection fails
- [ ] OpenCV via Flutter FFI for shape fitting

## Phase 3 — Release metrics (all events)

- [ ] Release speed (±3–5% accuracy with side-on setup)
- [ ] Release angle
- [ ] Release height
- [ ] Trajectory arc overlay
- [ ] Predicted distance (from release speed + angle + height)
- [ ] Optimal release angle calculator UI ("your speed was X, optimal angle was Y, cost Z meters")

## Phase 4 — Flight analysis

- [ ] Full trajectory fit (parabolic)
- [ ] Actual vs predicted trajectory comparison
- [ ] Flight time measurement
- [ ] Implement orientation per frame (discus and javelin)

## Phase 5 — Event-specific analysis

### Discus
- [ ] Disc tilt angle per frame (from ellipse ratio)
- [ ] Angle of attack (disc angle vs velocity vector)
- [ ] Wobble/precession tracking
- [ ] Rotation count and RPM through the circle
- [ ] Low point and high point of disc orbit

### Hammer
- [ ] Full turn sequence tracking
- [ ] Rotation count and RPM per turn
- [ ] Low point consistency across turns
- [ ] Wire orbit radius (2D)
- [ ] Entry speed vs release speed per turn
- [ ] Turn-over-turn velocity gain

### Javelin
- [ ] Run-up speed (approach velocity)
- [ ] Penultimate step mechanics
- [ ] Javelin attitude angle per frame throughout flight
- [ ] Angle of attack at release
- [ ] Nose-down moment detection (when javelin begins pitching down)

### Shot put
- [ ] Glide vs rotational technique tagging
- [ ] Delivery stride length

## Phase 6 — Biomechanics (pose estimation layer)

- [ ] Hip–shoulder separation angle at release
- [ ] Trunk lean angle at release
- [ ] Blocking leg position and effectiveness
- [ ] Release point height relative to body
- [ ] Gross joint angles (shoulder, elbow, hip) at key frames
- [ ] Delivery stride length

## Phase 7 — Comparison & consistency

- [x] Throw overlay — ghost two throws on top of each other, synced to release frame
- [ ] Session scatter plot — release angle vs speed for all throws
- [ ] Consistency score (variance across session)
- [ ] Best throw highlight with delta to session average

## Phase 8 — Progress tracking

- [x] Athlete profiles (name, events thrown, bests per implement; no age category yet)
- [x] Results with no video — competition marks typed in, competing with the filmed throws for a best
- [ ] Season progression charts (release speed, release angle, predicted distance over time)
- [x] Personal bests with linked video
- [ ] Correlate training metrics with competition results
- [ ] Migrate persistence to SQLite (sqflite)

## Phase 9 — Coach tools

- [x] Training notes per athlete — headings, lists, checklists, pictures with captions
- [ ] Follow a set of athletes on the coach's own screen, the way the page
      already lets a spectator. `MeetEventScreen` reads 'yours' off
      `MeetEntry.tracked`, which is the whole roster and cannot be narrowed:
      a coach standing at a ring with four in the field wants the board hung
      on the two still in the cut, and at the next ring wants the other two.
      `competitionFeed(following:)` and `MeetBoard(following:)` already take
      a set and already work the same sentences out around it — the page asks
      the question and the screen does not, so what is missing is where a
      coach answers it, not what the answer does. Tracked stays the default,
      since it is right until somebody says otherwise.
- [x] Carry a followed set over the relay — a base feed plus an overlay
      per *set*, which is what the open part turned out to need: the band
      hangs on the best placed of them and each of them gets a line, so
      per-athlete overlays never would have composed. Which sets exist is
      the thing only the stand knows, so the relay writes down every `?f=`
      it is polled with and hands them back to the phone (on the answer to
      a push, and on `/wanted` for the rounds where nothing is thrown); the
      phone answers each and the relay applies it on the way out. Measured
      on a field of 16, an answer is 0.6–1.2 KB against a 9.5 KB feed.
- [ ] Saved coaching cue library (reusable text annotations)
- [ ] Session management (date, conditions, location)
- [ ] Wind speed/direction logging
- [ ] Implement tagging (track specific implements across sessions)

## Phase 10 — Export & sharing

- [ ] Export annotated frame + metrics as image
- [ ] One-tap PDF report (key frame + trajectory overlay + metrics table)
- [ ] Video clip export with overlays burned in
- [ ] Share directly with athlete
