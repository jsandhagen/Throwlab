# throwlab-share

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
| `GET /M/<token>/results.pdf` | the sheet, once one has been pushed |
| `GET /M/<token>/f/r.ttf`, `/f/s.ttf` | Barlow, staged from `assets/fonts/` |
| `GET /M/<token>/pb.png` | the personal-best medal, struck by the app |
| `PUT /M/<token>/state` | the phone pushing — the only route that writes |

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
npm run deploy  # needs `wrangler login` once
```

`npm run stage` copies Barlow out of the app's own `assets/fonts/` into
`public/f/`. The typeface is `main.dart`'s to decide, so the repo does not
carry a second copy of it that can fall behind — which is also why
`public/` is gitignored.

The medal goes the other way: it is pushed by the phone rather than staged,
because it is struck by the Dart painter and every number in there is
measured off a reference. It is two kilobytes, and a badge that is nearly
right is worse than none.

## What is not here yet

The app still serves on the LAN; nothing pushes to this. Wiring the phone
to it, and choosing what a coach sees when the push cannot get through, is
the next step.
