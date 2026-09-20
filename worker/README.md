# throwlab — the share relay

The relay a competition is shared through.

The phone is still where a competition is worked out. It runs
`MeetStandings`, `MeetFlight` and `MeetBoard`, spells every mark through
`formatDistance`, and pushes the *answers* here; this holds them and hands
them to whoever opens the link. Nothing in this directory understands
countback, prelims or feet and inches, and nothing in it should ever learn
— a relay that understood the competition would be a second implementation
of it, free to disagree with the coach's own screen.

## The routes

They are the ones the phone used to answer on its own socket, kept
character for character, because the page builds every one of them off its
own `location.pathname`:

| Route | What it is |
| --- | --- |
| `GET /M/<token>` | the page, as the app generated it |
| `GET /M/<token>/state` | the competition, with the app's own ETag |
| `GET /M/<token>/state?f=<ids>` | the same competition, read for those athletes |
| `GET /M/<token>/results.pdf` | the sheet, once one has been pushed |
| `GET /M/<token>/f/r.ttf`, `/f/s.ttf` | Barlow, staged from `assets/fonts/` |
| `GET /M/<token>/pb.png` | the personal-best medal, struck by the app |
| `GET /M/<token>/wanted` | which sets are being followed — for the phone, behind the write key |
| `PUT /M/<token>/state` | the phone pushing — the only route that writes |

## The one question that comes from the stand

A spectator is asked on the way in who they came to watch, and everything
the competition says about 'yours' is then said about them. That is the one
thing here that cannot simply be held and handed back: answering it means
working the competition out again around a different set of athletes, and
the only thing that does that is the phone.

So this is a post box rather than an answer.

1. A poll arrives with `?f=`. The set is normalized — sorted, deduplicated,
   capped — and written down under that name. It is the one place a
   stranger with the link puts anything into storage, so it is a bounded
   number of bounded strings and they age out once nobody is asking.
2. The phone is told. On the answer to its next push, which is the hop it
   was making anyway, and on `GET /wanted` for the rounds where nothing is
   thrown and there would be no push to carry them.
3. The phone answers each set with an *overlay* — what that reading adds to
   the base feed: the keys that moved, `places` by the row, and a row by
   its fields. On a field of 16 that is under a kilobyte and a half, where
   the same answer sent whole would be the feed again per set per round.
4. A poll for a set we hold an answer for gets the base with that overlay
   applied, tagged with the fingerprint the phone took over the
   composition. One we do not gets the base with the asked-for names echoed
   back under `following`, so the tick survives the poll that made it and
   the board becomes theirs a push later.

`applyDelta` is the whole of what happens here, and it is arithmetic on
data that arrived already decided. It is still true that nothing in this
directory knows what a countback is.

## Two credentials, because there is now a route that writes

On the LAN there was one secret and no write path at all: a spectator could
not enter a mark because nothing on the server could. That stops being true
the moment a relay exists, so the two jobs the token used to do are split.

- **The share token** is in the link. It is printed under the QR and read
  out across a sector, so everybody at the meet has it. It reads, and that
  is all it does.
- **The write key** never leaves the phone. It is sent as
  `Authorization: Bearer …`, and the object stores only its SHA-256 — a
  dump of this storage should not let anybody publish to a stand.

The first push claims the token. A second phone landing on the same one
gets a 409 and picks another, rather than being allowed to overwrite a
competition in progress.

## Retention

Every push pushes the expiry out with it (`RETENTION_HOURS`, 12 by
default): a competition still being thrown is not one to clear up, and one
that finished an hour ago is still worth the drive home. After that the
object deletes everything it holds. A field of names — most of them other
people's athletes, and many of them children — should not still be here
next week.

## Running it

```sh
npm install
npm test        # miniflare, no account needed
npm run dev     # wrangler dev, on the staged fonts
npm run deploy  # by hand: needs `wrangler login` once
```

## Deploying it

Cloudflare Workers Builds, from the dashboard: the Worker is connected to
this repository with `main` as its production branch, so a push that
touches it deploys it. `npm run deploy` is the same thing by hand, for when
the build itself is what is broken. There is deliberately no second path —
two systems deploying one Worker race each other.

Whoever deploys, the fonts are staged first, by the `[build]` command in
`wrangler.toml` rather than by remembering. `public/` is gitignored, so a
fresh checkout has no such directory and the `assets.directory` field stops
`wrangler deploy` dead:

```
✘ [ERROR] The directory specified by the "assets.directory" field in your
  configuration file does not exist
```

That is an error and not a warning, which is what a git build that deploys
nothing looks like — and is how the relay sat on old code for a day while
the phone asked spectators who they came to watch and it threw the question
away before the Durable Object saw it. The hook is plain `node`, no npm, so
it works before `npm install` has run.

`npm run stage` copies Barlow out of the app's own `assets/fonts/` into
`public/f/`. The typeface is `main.dart`'s to decide, so the repo does not
carry a second copy of it that can fall behind — which is also why
`public/` is gitignored.

The medal goes the other way: it is pushed by the phone rather than staged,
because it is struck by the Dart painter and every number in there is
measured off a reference. It is two kilobytes, and a badge that is nearly
right is worse than none.

## What is not here yet

`MeetRelay` pushes here and the share sheet hands out the link. What this
cannot yet do is carry a competition worked out around whoever is reading
it — one feed is held and handed to everybody — so the page's own question
about who somebody came to watch is turned off on this path. See ROADMAP,
Phase 9; the measurements are written down there.
