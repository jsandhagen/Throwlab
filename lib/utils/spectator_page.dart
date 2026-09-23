import 'package:flutter/material.dart';

import '../widgets/event_glyph.dart';
import '../widgets/gold.dart';
import '../widgets/sector_art.dart';

/// The page a spectator gets, served whole by `MeetServer`.
///
/// One file, and it fetches nothing but the competition's own state and the
/// app's own typeface — both off the phone in their hand. There is no
/// internet at a track, so a page that reaches for a font or a script on a
/// CDN is a page that renders as nothing in exactly the place it is wanted.
///
/// It is meant to read as ThrowLab rather than as a web page about
/// ThrowLab, so it is not styled by hand: the palette comes from the app's
/// own [ColorScheme], the type is the bundled Barlow served from the phone,
/// and the chrome is the app's — the two-cut angular silhouette of
/// `angularShape`, the segmented bar whose active block leans at the
/// sector's own half-angle, and the sector backdrop that stands behind the
/// library and the meet. A parent looking over the coach's shoulder should
/// see the same competition twice, not two apps.
///
/// It knows nothing about throwing. Places, the cut, the flight in the
/// ring, the band of the sector worth drawing and every mark's spelling all
/// arrive decided from `competitionFeed` — the page lays out answers. That
/// is what keeps it from becoming a second, disagreeing implementation of a
/// competition, and it is why switching tabs costs no request at all.
///
/// The one thing it asks for itself is who the reader is here for. A coach
/// reading the app is reading it for their own athletes, and every 'yours'
/// on their screen means that; somebody handed this link at a ring came to
/// watch one thrower, who is usually somebody else's. So the page asks, on
/// the way in, and sends the answer up with each poll — and the phone works
/// the board, the cut, the calls and the captions out around that athlete
/// instead. The page still says only what it is told: the question changes
/// who the sentences are about and not a word of them, and unanswered it is
/// the coach's own screen exactly as before.
/// [servedByPhone] is where it came from, which is the one thing on the
/// page a spectator is owed the truth about: off the phone, nothing left
/// it; through the relay, a competition sits on somebody else's computer
/// until it ages out. A page that went on promising the first while doing
/// the second would be telling somebody something untrue about a field of
/// other people's children.
///
/// The question is asked the same way whichever is carrying it, because it
/// can only be answered by the thing that works the competition out, and
/// that is the phone either way. Served off its own socket the phone reads
/// the set off the request and answers it there and then; pushed to the
/// relay, the relay writes the set down, hands it back on the next push,
/// and holds the answer that comes up with it. Neither is visible from
/// here: the page sends `?f=` and is handed a competition, and one code
/// path is the only thing that keeps the two from drifting.
String spectatorPage(
  ColorScheme scheme, {
  bool servedByPhone = true,
}) {
  String hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  // The theme is `main.dart`'s to decide, here as everywhere else — these
  // are read off it rather than matched by eye, so a change to the seed
  // colour reaches the spectator's page too.
  final palette = {
    'bg': hex(scheme.surface),
    'surface': hex(scheme.surfaceContainerHighest),
    'raised': hex(scheme.surfaceContainerHigh),
    'line': hex(scheme.outlineVariant),
    'text': hex(scheme.onSurface),
    'dim': hex(scheme.onSurfaceVariant),
    'accent': hex(scheme.primary),
    'bad': hex(scheme.error),
  };
  // The podium's three metals, written out of `gold.dart` rather than
  // matched by eye: the flat mid tone for type, and the five stops for the
  // lines on the board, which are big enough to show a ramp. Same stops,
  // same light from the same corner as the app strikes them with.
  // Single-quoted attributes on purpose: these defs are injected into a
  // JavaScript string literal, and a double quote would close it.
  String stops(Medal medal) => [
        for (var i = 0; i < medal.ramp.length; i++)
          "<stop offset='${metalStops[i]}' stop-color='${hex(medal.ramp[i])}'/>",
      ].join();
  final metals = {
    'first': Medal.gold,
    'second': Medal.silver,
    'third': Medal.bronze,
  };
  // The discus, the hammer and the javelin off `EventGlyph`'s own parts, as SVG in the
  // unit square: a real implement's proportions are too fine to trace by
  // hand twice and have both come out the same. The steel and the cord are
  // their own colors on the page as in the app, whatever the event's.
  String implement(List<GlyphPart> parts) => [
        for (final part in parts)
          '<path fill-rule="evenodd"${switch (part.material) {
            GlyphMaterial.paint => '',
            GlyphMaterial.steel => ' fill="#ffffff"',
            GlyphMaterial.cord => ' fill="${hex(glyphCord)}"',
          }} '
              'd="${[
            for (final outline in part.outlines)
              'M ${[
                for (final o in outline)
                  '${o.dx.toStringAsFixed(4)} ${o.dy.toStringAsFixed(4)}',
              ].join(' L ')} Z',
          ].join(' ')}"/>',
      ].join();
  return _page
      .replaceFirst(
          '/*NOTE*/',
          servedByPhone
              ? "Live from the coach's phone. Nothing here is stored "
                  'anywhere else.'
              : "Live from the coach's phone. Held only while the "
                  'competition is on, and not kept afterwards.')
      .replaceFirst('/*METALS*/', [
        for (final entry in metals.entries)
          '--${entry.key}: ${hex(entry.value.flat)};',
      ].join(' '))
      .replaceFirst('/*METAL_DEFS*/', [
        for (final entry in metals.entries)
          "<linearGradient id='m-${entry.key}' x1='0' y1='0' x2='1' y2='1'>"
              "${stops(entry.value)}</linearGradient>",
      ].join())
      .replaceFirst('/*PALETTE*/', [
        for (final entry in palette.entries) '--${entry.key}: ${entry.value};',
      ].join(' '))
      // The slant every leaning edge on the page uses, which is the one the
      // sector opens at — the same number the app's own bar leans by.
      .replaceFirst('/*LEAN*/', sectorHalfAngleDeg.toStringAsFixed(2))
      .replaceFirst('/*DISCUS*/', implement(discusParts()))
      .replaceFirst('/*HAMMER*/', implement(hammerParts()))
      .replaceFirst('/*JAVELIN*/', implement(javelinParts()));
}

const String _page = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="color-scheme" content="dark">
<title>ThrowLab</title>
<style>
  /* Barlow, off the phone rather than off a network that isn't there.
     Two weights: the app sets four, but a page this size only ever asks
     for body and emphasis, and every file is a quarter-megabyte of wifi. */
  @font-face {
    font-family: Barlow; font-style: normal; font-weight: 400;
    font-display: swap; src: url("f/r.ttf") format("truetype");
  }
  @font-face {
    font-family: Barlow; font-style: normal; font-weight: 600;
    font-display: swap; src: url("f/s.ttf") format("truetype");
  }
  /* --tint is the event's own color, set from the feed once it lands. The
     app's competition screen accents everything inside its cards with it
     and leaves the segmented bar on the theme's own primary, so this page
     does the same: --tint for the competition, --accent for the chrome. */
  :root { /*PALETTE*/ /*METALS*/ --tint: var(--accent); --pad: 16px;
          --lean: /*LEAN*/deg; }
  * { box-sizing: border-box; }
  /* The color goes on the page itself, not on the body: a body with its
     own background paints over the sector standing behind it. */
  html { background: var(--bg); }
  html, body { margin: 0; color: var(--text); }
  body {
    font-family: Barlow, system-ui, -apple-system, Roboto, sans-serif;
    font-size: 14px; line-height: 1.35;
    padding: 0 var(--pad) calc(var(--pad) + env(safe-area-inset-bottom));
    max-width: 720px; margin: 0 auto;
    -webkit-text-size-adjust: 100%;
  }

  /* The sector that backs the library and the meet, behind this too: the
     apex off the bottom-left corner, opening to the top-right, with the
     arcs kept between the sector lines — an arc outside them is a line no
     throwing field has. */
  /* Stretched to the viewport rather than fitted to its own box — the
     app paints this to whatever rectangle it is given, and the width and
     height here have to beat the sizing every other svg on the page gets. */
  #backdrop { position: fixed; inset: 0; width: 100%; height: 100%;
              z-index: -1; pointer-events: none; }

  /* Two opposite corners cut, the other two square — `angularShape`, which
     is what every surface in the app wears. */
  .angular {
    clip-path: polygon(12px 0, 100% 0, 100% calc(100% - 12px),
                       calc(100% - 12px) 100%, 0 100%, 0 12px);
  }

  header { padding: 16px 0 12px; }
  .title { display: flex; align-items: center; gap: 10px; }
  .title h1 { font-size: 19px; margin: 0; font-weight: 600; letter-spacing: 0.2px; }
  .title svg { flex: 0 0 auto; }
  .sub { color: var(--dim); font-size: 12px; }
  .age { display: flex; align-items: center; gap: 6px; font-size: 12px;
         color: var(--dim); margin-top: 8px; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--tint); }
  .age.stale .dot, .age.stale { color: var(--bad); }
  .age.stale .dot { background: var(--bad); }

  /* Who the page is being read for. A spectator is at the ring for their
     own athletes, so the page asks which — once, on the way in, and
     quietly from then on as a chip in the header. The app has no twin for
     this: the phone belongs to the coach, and the coach's own athletes are
     already the answer there. */
  .watch { margin-top: 10px; }
  .watch .who { display: inline-flex; align-items: center; gap: 8px;
                max-width: 100%;
                border: 1px solid color-mix(in srgb, var(--accent) 45%,
                transparent);
                background: color-mix(in srgb, var(--surface) 40%, transparent);
                color: var(--dim); font: inherit; font-size: 12px;
                border-radius: 999px; padding: 5px 12px; cursor: pointer; }
  .watch .who b { font-weight: 600; color: var(--accent); min-width: 0;
                  overflow: hidden; text-overflow: ellipsis;
                  white-space: nowrap; }
  .watch .who .chev { color: var(--dim); font-size: 11px; opacity: 0.8;
                      flex: 0 0 auto; }
  /* The same translucent card as everything else on the page — this is a
     question about the competition, not a dialog over it, and a scrim
     over the board would hide the thing somebody opened the link for. */
  .picker { background: color-mix(in srgb, var(--surface) 45%, transparent);
            border-radius: 16px; padding: 10px 4px 10px 12px; }
  .picker .ask { margin: 0; font-size: 13px; font-weight: 600; }
  .picker .why { margin: 2px 0 6px; font-size: 11px; color: var(--dim); }
  /* The field as the sheet it was read off: down the throwing order, a
     checkbox against each name and ruled off at the flights, which is how
     the app's own heat sheet is ticked through. Rows rather than pills,
     because a row is what a name is read on and a checkbox is a thing that
     has a line of its own — and because nobody is at a ring for exactly
     one athlete: a parent has two throwing and a club's supporter four. */
  .names { max-height: 46vh; overflow: auto; padding-right: 8px; }
  .names .pick { display: flex; align-items: center; gap: 10px; width: 100%;
                 border: 0; background: transparent; color: var(--text);
                 font: inherit; font-size: 13px; text-align: left;
                 padding: 7px 4px; cursor: pointer; border-radius: 8px; }
  .names .pick .nm { flex: 1; min-width: 0; overflow: hidden;
                     text-overflow: ellipsis; white-space: nowrap;
                     color: var(--dim); }
  .names .pick.on .nm { color: var(--text); font-weight: 600; }
  .names .pick.on { background: color-mix(in srgb, var(--accent) 12%,
                    transparent); }
  /* The box drawn rather than an <input>: a browser's own checkbox is the
     one control on this page that would arrive in somebody else's colors. */
  .tick { position: relative; flex: 0 0 auto; width: 17px; height: 17px;
          border-radius: 4px; border: 1.5px solid var(--dim); }
  .pick.on .tick { background: var(--accent); border-color: var(--accent); }
  .pick.on .tick::after { content: ""; position: absolute; left: 5px;
                          top: 1px; width: 4px; height: 9px;
                          border: solid var(--bg); border-width: 0 2px 2px 0;
                          transform: rotate(45deg); }
  /* Ticking is a decision, so the way out of the list is a button rather
     than a tap somewhere else — and the way out with nobody ticked is
     spelled out beside it, since an empty list read as 'not yet answered'
     would ask again on the next poll. */
  .picker .foot { display: flex; align-items: center; gap: 12px;
                  margin: 8px 8px 0 0; }
  .picker .plain { padding: 4px 0; border: 0; background: none;
                   color: var(--dim); font: inherit; font-size: 12px;
                   text-decoration: underline; cursor: pointer; }
  .picker .done { margin-left: auto; border: 0; border-radius: 999px;
                  background: var(--accent); color: var(--bg); font: inherit;
                  font-size: 12px; font-weight: 600; padding: 7px 18px;
                  cursor: pointer; }

  /* The app's own segmented bar: one surface with a slanted block under the
     active section and leaning dividers between the rest. The lean is the
     sector's half-angle, so the header leans the way the sector opens. */
  .tabs { position: relative; display: flex; height: 40px; margin-bottom: 12px;
          background: linear-gradient(135deg,
            color-mix(in srgb, var(--surface) 42%, transparent),
            color-mix(in srgb, var(--surface) 14%, transparent)); }
  .tabs button { position: relative; flex: 1; border: 0; background: transparent;
                 color: var(--dim); font: inherit; font-size: 13px;
                 font-weight: 500; letter-spacing: 0.2px; cursor: pointer;
                 display: flex; align-items: center; justify-content: center;
                 gap: 6px; }
  .tabs button + button::before {
    content: ""; position: absolute; left: 0; top: 6px; bottom: 6px;
    width: 1px; background: var(--line); transform: skewX(calc(-1 * var(--lean)));
  }
  .tabs button[aria-pressed="true"] { color: var(--accent); font-weight: 600; }
  /* The block is clipped rather than skewed, because its outer edge has to
     square up at the ends of the bar — a skew leans both edges and leaves a
     wedge of background sitting in the bar's own corner. */
  #block { position: absolute; top: 0; bottom: 0; left: 0;
           background: linear-gradient(135deg,
             color-mix(in srgb, var(--accent) 34%, transparent),
             color-mix(in srgb, var(--accent) 10%, transparent));
           border-bottom: 2px solid var(--accent);
           transition: left 240ms cubic-bezier(0.22, 1, 0.36, 1); }

  /* Translucent, and rounded rather than cut: the competition screen's
     cards are surfaceContainerHighest at 45%, so the sector stands through
     them, and they take the theme's own 16px card radius. The angular
     silhouette belongs to the segmented bar, not to these. */
  .card { background: color-mix(in srgb, var(--surface) 45%, transparent);
          border-radius: 16px; padding: 10px 12px; margin-bottom: 9px; }
  /* The athlete in the circle is edged in the event's color, so a coach
     looking down finds the row without reading a name. */
  .card.up { border-radius: 12px;
             box-shadow: inset 0 0 0 1.5px
               color-mix(in srgb, var(--tint) 80%, transparent); }
  /* The live card alone is opaque, blended to exactly the tone of the
     others rather than given a color of its own — the page's sector
     backdrop runs behind it, and two sectors drawn over each other at
     different angles are a picture of nothing. */
  .card.solid { background: color-mix(in srgb, var(--surface) 45%, var(--bg)); }
  /* The sector set into the card rather than run on from the header: a
     picture of a sector and a list of names are two different things to
     read, and the edge between them is what says so. */
  .board { margin-top: 12px; border-radius: 10px; overflow: hidden;
           background: var(--bg);
           border: 1px solid color-mix(in srgb, var(--line) 40%, transparent); }
  /* What the throw in the circle has to do, and what the athlete this page
     is being read for is short of — the lines the app prints under its
     board, in the colors it prints them in. */
  .cap { font-size: 13px; font-weight: 600; margin: 12px 0 0; }
  .cap + .cap { margin-top: 2px; }
  .cap.tint { color: var(--tint); }
  .cap.accent { color: var(--accent); }
  .cap.body { color: var(--text); }
  .up-rule { border-top: 1px solid color-mix(in srgb, var(--line) 50%,
             transparent); margin-top: 8px; }
  /* The app's own header over the field: where the round has got to, how
     much of it has been thrown, and the three an infield calls out. */
  .round { display: flex; justify-content: space-between; align-items: baseline;
           gap: 10px; }
  .round b { font-size: 13px; font-weight: 700; letter-spacing: 1.1px;
             text-transform: uppercase; color: var(--tint); }
  .bar { height: 5px; border-radius: 3px; margin-top: 8px; overflow: hidden;
         background: color-mix(in srgb, var(--line) 50%, transparent); }
  .bar i { display: block; height: 100%; background: var(--tint); }
  .call { display: flex; align-items: baseline; gap: 10px; margin-top: 8px; }
  .call .lbl { font-size: 11px; letter-spacing: 0.6px; color: var(--dim);
               min-width: 62px; white-space: nowrap; }
  .call.up .lbl { color: var(--tint); font-weight: 600; }
  .call .who { flex: 1; min-width: 0; overflow: hidden; white-space: nowrap;
               text-overflow: ellipsis; }
  .call.up .who { color: var(--text); }
  .lead-rule { border-top: 1px solid color-mix(in srgb, var(--line) 40%,
               transparent); margin-top: 10px; }
  /* An icon on a line of type, not a picture in a card: the rule above
     lays every other svg out as a full-width block, which would put the
     trophy on a line of its own above the word it belongs to. */
  .ico { display: inline-block; width: 13px; height: 13px; flex: 0 0 auto; }
  .call .lbl .ico { vertical-align: -2px; margin-right: 5px; }
  /* When the athlete being followed throws, for a flight that isn't
     theirs. */
  .later { display: flex; align-items: center; gap: 6px; font-size: 11px;
           color: var(--accent); margin: 6px 0 0; }


  main svg, .card svg { display: block; width: 100%; height: auto; }
  main svg.ico, .card svg.ico { display: inline-block; width: 13px;
                                height: 13px; }

  /* No rules between rows: the app's table doesn't draw them, and a
     four-line standings cut into boxes reads as four things rather than
     one competition. */
  .row { display: flex; align-items: baseline; gap: 10px; padding: 4px 0; }
  .pl { min-width: 22px; color: var(--dim); font-variant-numeric: tabular-nums;
        font-size: 13px; }
  /* A medal outranks whose it is: the name beside it and the mark after
     it both already carry that, so the podium keeps its own metal. All
     three are struck bold here, unlike the chip on a field card — a place
     in a table is two characters with nothing else on the line. */
  .pl.m1, .pl.m2, .pl.m3 { font-weight: 700; }
  .pl.mine { color: var(--tint); font-weight: 700; }
  /* What the cut is, over the table: right-aligned and quiet before it is
     made, in the theme's own accent once it is. */
  .advance { text-align: right; font-size: 11px; color: var(--dim);
             margin: 0 0 8px; }
  .advance.made { color: var(--accent); }
  /* Where they come in the throwing order, which is what the field is read
     down — the place rides on the right beside the mark. */
  .ord { min-width: 18px; color: var(--dim); font-size: 12px;
         font-variant-numeric: tabular-nums; }
  .chip { font-size: 11px; color: var(--dim); }
  /* Tucked under the name it belongs to, not floating between two rows. */
  .aside { color: var(--dim); font-size: 11px; margin: -3px 0 3px;
           padding-left: 32px; }
  /* Set back the way the app's own table sets the field back: the rest of
     the competition is here to be placed against, not read. The athlete
     the page is being read for is the one the eye should find, and a metal
     has to have something dimmer than itself to stand against — silver
     against bright type is not silver, it is type. */
  .nm { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis;
        white-space: nowrap; color: var(--dim); }
  .nm.mine { color: var(--text); font-weight: 600; }
  .bm { font-variant-numeric: tabular-nums; font-weight: 600;
        color: var(--dim); }
  .bm.mine { color: var(--tint); }
  /* A place is struck in its own metal, the same three the app's board
     draws its lines with. Flat, not a ramp: five stops across two digits
     is a muddy two digits, which is the rule the app follows too. */
  /* Weight as well as hue, the way the app's own place chip does it.
     Silver sits close to the dark theme's body gray, so on its own it
     would read as no color at all — the weight is what separates second
     from fourth. */
  .m1 { color: var(--first); font-weight: 700; }
  .m2 { color: var(--second); font-weight: 600; }
  .m3 { color: var(--third); font-weight: 600; }
  /* Two rules with the words between them, the way the app draws it. */
  .cut-rule { display: flex; align-items: center; gap: 8px; margin: 6px 0;
              font-size: 10px; color: var(--accent); }
  .cut-rule::before, .cut-rule::after { content: ""; flex: 1;
              border-top: 1px solid color-mix(in srgb, var(--accent) 50%,
              transparent); }
  .aside.needs { color: var(--accent); }

  /* One athlete in the field: who and how they are doing across the top,
     the series across the bottom. The embedded one lines its name up with
     the header above it rather than stepping in from it. */
  .entry.card { padding: 4px 4px 6px 10px; }
  .entry.in { margin-top: 6px; }
  .erow { display: flex; align-items: baseline; gap: 6px; }
  .erow .nm { font-size: 14px; font-weight: 600; margin-right: auto; }
  /* In the event's color when they are the one in the circle, which costs
     nothing across a crowded row — the word 'up' would have come off
     somebody's surname. */
  .erow .nm.now { color: var(--tint); }
  /* What they are standing on. The event's color for everyone here,
     unlike the standings: this is the only distance on the row. */
  .bm.big { font-size: 14px; font-weight: 700; color: var(--tint); }
  .heading { font-size: 11px; letter-spacing: 0.8px; color: var(--dim);
             text-transform: uppercase; margin: 16px 0 6px; }

  /* Six boxes across the full width, big enough to read at arm's length —
     the same split the app's own card uses. */
  .series { display: grid; grid-template-columns: repeat(6, 1fr); gap: 4px;
            margin-top: 10px; }
  /* Numbered in the corner the way the app numbers them: a coach reading
     a series wants to know which round a mark came out of. */
  .box { position: relative; background: var(--raised); border-radius: 6px;
         padding: 10px 1px 3px; text-align: center; font-size: 12px;
         font-variant-numeric: tabular-nums; min-height: 31px;
         white-space: nowrap; }
  .box i { position: absolute; top: 1px; left: 4px; font-style: normal;
           font-size: 8px; color: var(--dim); }
  .box.foul { color: var(--bad); }
  .box.pass { color: var(--dim); }
  .box.best { background: transparent; color: var(--tint); font-weight: 600;
              box-shadow: inset 0 0 0 1px var(--tint); }
  .box.out { opacity: 0.32; }
  /* Struck by the app itself and served as pixels — see MeetServer. */
  /* 13px, the size the app pins it at beside a mark — a badge before it
     is a picture, and the small one is the size that has to work. */
  .medal { height: 13px; width: auto; vertical-align: -1px; }


  /* The results sheet sits where the app puts it — an action in the top
     right, beside the title, not a button at the foot of the page. */
  .title { position: relative; }
  .sheet { margin-left: auto; flex: 0 0 auto; display: block; padding: 6px;
           color: var(--dim); line-height: 0; }
  .sheet svg { width: 22px; height: 22px; }
  .note { color: var(--dim); font-size: 12px; text-align: center; margin: 6px 0 0; }
  .empty { color: var(--dim); text-align: center; padding: 28px 10px; }
</style>
</head>
<body>
<svg id="backdrop" preserveAspectRatio="none" aria-hidden="true"></svg>
<header>
  <div class="title"><span id="glyph"></span><h1 id="label">…</h1>
    <a class="sheet" id="sheet" title="Results sheet" aria-label="Results sheet"><svg
      viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"
      stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path
      d="M14 3v5h5"/><path d="M9 13h6M9 17h4" stroke-linecap="round"/></svg></a></div>
  <div class="sub" id="meet"></div>
  <div class="sub" id="weather"></div>
  <div class="age" id="age"><i class="dot"></i><span id="ageText">connecting…</span></div>
  <div class="watch" id="watch"></div>
</header>
<div class="tabs angular" id="tabs">
  <div id="block"></div>
  <button data-tab="live" aria-pressed="true">Live</button>
  <button data-tab="series" aria-pressed="false">Series</button>
  <button data-tab="standings" aria-pressed="false">Standings</button>
</div>
<main id="view"></main>
<p class="note">/*NOTE*/</p>

<script>
(function () {
  "use strict";

  /* The share's own path — '/M/ABC123' off the phone. A page opened as a
     file (which is how it is reviewed) sits at '…/spectator.html', so the
     file name comes off and everything beside it resolves the same way. */
  var base = location.pathname.replace(/\/[^\/]*\.html$/, "").replace(/\/$/, "");
  var data = null, tab = "live", etag = null;
  var lastAt = 0, failed = 0;

  /* Who this browser is here to watch, and whether it has been asked.
     A list, because nobody is at a ring for exactly one athlete — the
     phone's own 'yours' is a whole roster too. The phone knows nothing
     about it: the choice rides on the poll as a query parameter, so two
     people on one link watch two different sets and the server still
     holds no spectator and no route that writes.

     Kept per share — one token, one competition — so a parent handed a
     second link at the next ring is asked again rather than inheriting
     the discus answer. In a browser that refuses storage the question is
     simply asked each time, which is a worse page and a working one. */
  var STORE = "throwlab.watch." + (base.split("/").pop() || "page");
  var follow = [], asked = false;
  try {
    var held = localStorage.getItem(STORE);
    if (held !== null) { asked = true; follow = held === "-" ? [] : held.split(","); }
  } catch (_) { /* private window. Ask, and forget. */ }
  /* Open on the way in, and only then: the question is worth one screen
     of somebody's attention once, and nothing after that. */
  var picking = !asked;
  /* What the panel was last painted from, so a poll landing every four
     seconds doesn't rebuild an open list under the thumb scrolling it —
     see render(). */
  var painted = null;

  function remember() {
    try {
      localStorage.setItem(STORE, follow.length ? follow.join(",") : "-");
    } catch (_) { /* as above */ }
  }

  /* What the watch panel is showing: the question or the chip, and the
     answer so far. Repainted only when this changes — see render(). */
  function watchSig() {
    return (picking ? "open" : "shut") + "|" + follow.join(",");
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function el(id) { return document.getElementById(id); }

  /* ---- the sector behind everything -------------------------------- */
  /* The same backdrop the library and the meet stand on: the apex off the
     bottom-left, the sector opening to the top-right corner, and arcs that
     stay between its two lines. */
  /* The sector the app stands on, painted the way SectorBackdropPainter
     paints it: the throwing circle just off the bottom-left corner, its
     distance arcs sweeping diagonally across the screen, and the two
     sector lines cutting through them. Faint by design — texture, not a
     diagram.

     Drawn at the viewport's own size rather than into a fixed viewBox. The
     element is stretched to fill the screen, so a box of some other shape
     came out with the wedge at the wrong angle and the arcs as ellipses —
     a sector nobody has ever thrown into. */
  function backdrop() {
    var svg = el("backdrop");
    var w = svg.clientWidth || window.innerWidth;
    var full = svg.clientHeight || window.innerHeight;
    /* Not the whole viewport: the app paints this into the body under its
       app bar, and the box the sector is laid out in is what decides the
       bearing from the corner. So it starts where the app's does — just
       above the segmented bar, which is the first thing in both bodies —
       and the two wedges cross the screen at the same angle instead of a
       couple of degrees apart. */
    var top = Math.max(el("tabs").getBoundingClientRect().top - 8, 0);
    var h = full - top;
    /* Close enough to the corner that the arcs actually curve. */
    var ax = -w * 0.16, ay = h * 1.12;
    var cx = w * 1.04, cy = -h * 0.04;
    var bearing = Math.atan2(cy - ay, cx - ax);
    var half = (34.92 / 2) * Math.PI / 180;
    var reach = Math.hypot(cx - ax, cy - ay);
    function edge(a, r) {
      return [ax + Math.cos(a) * r, ay + Math.sin(a) * r];
    }
    /* The app strokes all three of these through one gradient across the
       box, bottom-left to top-right, fading to a third of itself — so the
       art is strongest at the circle and nearly gone by the far corner. */
    function fade(id, alpha) {
      return '<linearGradient id="' + id + '" gradientUnits="userSpaceOnUse"' +
        ' x1="0" y1="' + h + '" x2="' + w + '" y2="0">' +
        '<stop offset="0" stop-color="var(--accent)" stop-opacity="' +
        alpha + '"/><stop offset="1" stop-color="var(--accent)" ' +
        'stop-opacity="' + (alpha * 0.3) + '"/></linearGradient>';
    }
    var out = ["<defs>" +
      '<radialGradient id="wash">' +
      '<stop offset="0" stop-color="var(--accent)" stop-opacity="0.07"/>' +
      '<stop offset="1" stop-color="var(--accent)" stop-opacity="0"/>' +
      "</radialGradient>" +
      fade("bArc", 0.24) + fade("bLine", 0.3) + fade("bRing", 0.34) +
      "</defs>"];
    /* A wash at the circle end, so the corner has depth behind the lines. */
    out.push('<circle cx="' + ax + '" cy="' + ay + '" r="' + h * 0.85 +
      '" fill="url(#wash)"/>');
    /* Distance arcs, drawn only between the sector lines: an arc outside
       them is a line that doesn't exist on a throwing field. */
    for (var i = 1; i <= 7; i++) {
      var r = reach * (0.1 + i * 0.15);
      var a = edge(bearing - half, r), b = edge(bearing + half, r);
      out.push('<path d="M ' + a[0] + " " + a[1] + " A " + r + " " + r +
        " 0 0 1 " + b[0] + " " + b[1] +
        '" stroke="url(#bArc)" stroke-width="1" fill="none"/>');
    }
    [-1, 1].forEach(function (sign) {
      var p = edge(bearing + sign * half, reach * 1.2);
      out.push('<path d="M ' + ax + " " + ay + " L " + p[0] + " " + p[1] +
        '" stroke="url(#bLine)" stroke-width="1.2" fill="none"/>');
    });
    /* The circle itself, mostly off-screen at the corner. */
    out.push('<circle cx="' + ax + '" cy="' + ay + '" r="' + w * 0.16 +
      '" stroke="url(#bRing)" stroke-width="1.4" fill="none"/>');
    svg.setAttribute("viewBox", "0 0 " + w + " " + full);
    svg.innerHTML = '<g transform="translate(0,' + top + ')">' +
      out.join("") + "</g>";
  }

  /* The two Material icons the app's own header carries, traced at 13px
     so they sit on a line of type rather than beside it: the trophy
     against whoever is in front, and the clock against the flight the
     coach's own athletes are waiting in. */
  var TROPHY = '<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">' +
    '<path fill="currentColor" d="M18 4V2H6v2H2v4a4 4 0 0 0 4 4h.4A6 6 0 0 0 ' +
    '11 15.9V19H7v2h10v-2h-4v-3.1A6 6 0 0 0 17.6 12H18a4 4 0 0 0 4-4V4h-4zM4 ' +
    '8V6h2v4a2 2 0 0 1-2-2zm12 2a4 4 0 0 1-8 0V4h8v6zm4-2a2 2 0 0 1-2 2V6h2v2z"/>' +
    "</svg>";
  var CLOCK = '<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">' +
    '<path fill="currentColor" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 ' +
    '18a8 8 0 1 1 0-16 8 8 0 0 1 0 16zm.5-13H11v6l5.2 3.1.8-1.3-4.5-2.6V7z"/>' +
    "</svg>";

  /* ---- the implement, drawn the way EventGlyph draws it ------------- */
  function glyph(event, tint) {
    var s = 22, g;
    if (event === "discus") {
      g = '<g transform="scale(' + s + ')">/*DISCUS*/</g>';
    } else if (event === "shotPut") {
      g = '<path fill-rule="evenodd" d="' + ring(0.5, 0.55, 0.31, 0.06, s, -0.11, -0.12) + '"/>';
    } else if (event === "hammer") {
      g = '<g transform="scale(' + s + ')">/*HAMMER*/</g>';
    } else {
      /* The discus, the hammer and the javelin are the app's own parts,
         handed over in the unit square rather than traced a second time. */
      g = '<g transform="scale(' + s + ')">/*JAVELIN*/</g>';
    }
    return '<svg width="' + s + '" height="' + s + '" viewBox="0 0 ' + s + " " + s +
      '" fill="' + tint + '" aria-hidden="true" style="width:' + s + "px;height:" +
      s + 'px">' + g + "</svg>";
  }
  /* A ball with its highlight punched out of it — even-odd fill, exactly
     as the painter does it. */
  function ring(cx, cy, r, hole, s, hx, hy) {
    function circle(x, y, rad) {
      return "M " + (x - rad) + " " + y + " a " + rad + " " + rad + " 0 1 0 " +
        2 * rad + " 0 a " + rad + " " + rad + " 0 1 0 " + -2 * rad + " 0 ";
    }
    return circle(cx * s, cy * s, r * s) +
      circle((cx + (hx || 0)) * s, (cy + (hy || 0)) * s, hole * s);
  }

  /* ---- the board --------------------------------------------------- */
  /* Everything about the scale has already been decided: which band of the
     sector, how far apart the marker lines are, and where each mark falls
     across it. All that is left here is drawing. */
  /* Portrait and filling its card, the way the app draws a board: a
     sector squashed into a landscape strip stacks the competition into an
     inch of it, which is the one thing a board is for. */
  /* The sector, laid out exactly as SectorBoard lays it out: the apex sits
     below the box, at whatever distance makes the wedge span TAKE of the
     width at its far edge, so a narrow sector (the javelin's) is drawn
     narrower and both are real wedges with real arcs rather than a ladder
     of straight lines across a trapezoid.

     Room above the furthest line for its label, and below the nearest one
     so it doesn't sit on the bottom edge — the app's own two pads. */
  var TOP = 30, BOTTOM_PAD = 14, TAKE = 0.46;
  /* One row of labels, and the extra a label pinned to an edge wants for
     the arrow that rides outside its pill. The app's own numbers: a label
     measured at the theme's own size plus its clearance, and _arrowRoom.
     Both sides stack a broken board the same way or neither can be looked
     at against the other. */
  var ROW = 24, ARROW = 11;

  /* The box the board is drawn in. The app gives it half the view — the
     room under the tabs, not the whole window — never squarer than 0.75
     of its own width and never taller than 1.15 of it, which is what
     keeps the card underneath (the athlete in the circle and the six
     boxes their mark goes in) under a thumb. */
  function boardBox(w) {
    var room = window.innerHeight - el("view").getBoundingClientRect().top;
    return { w: w, h: Math.min(Math.max(room * 0.5, w * 0.75), w * 1.15) };
  }

  function geom(box, halfDeg) {
    var half = (halfDeg || 17.46) * Math.PI / 180;
    var apexFromTop = box.w * TAKE / Math.tan(half);
    /* How far an arc drops from the middle of the sector to the lines
       either side. The near edge has to sit that far off the bottom or the
       closest mark of all is drawn as two stubs with its middle cut off. */
    var rise = apexFromTop * (1 - Math.cos(half));
    var floorY = box.h - BOTTOM_PAD - rise;
    return { half: half, ax: box.w / 2, ay: TOP + apexFromTop, top: TOP,
             floor: floorY, plot: floorY - TOP, w: box.w, h: box.h };
  }

  /* Where a distance lands, to scale across the band — off the ends for a
     mark outside it, which is answered at the edge rather than by moving
     the mark. */
  function yAt(g, f) { return g.top + (1 - f) * g.plot; }
  function radiusAt(g, f) { return g.ay - yAt(g, f); }
  /* The y a label sits at: level with the *ends* of its own arc rather
     than with its middle, which is what makes a label read as belonging
     to a line. */
  function endY(g, r) { return g.ay - r * Math.cos(g.half); }

  function arcOf(g, r) {
    var a0 = -Math.PI / 2 - g.half, a1 = -Math.PI / 2 + g.half;
    return "M " + (g.ax + r * Math.cos(a0)) + " " + (g.ay + r * Math.sin(a0)) +
      " A " + r + " " + r + " 0 0 1 " +
      (g.ax + r * Math.cos(a1)) + " " + (g.ay + r * Math.sin(a1));
  }
  function arc(g, f) { return arcOf(g, radiusAt(g, f)); }

  /* The grass: out past the top of the box, because a wedge that stopped
     at the furthest line would draw a seam across the card where the
     grass ran out. */
  function wedge(g) {
    var brim = (g.ay + 2) * Math.sin(g.half);
    return "M " + g.ax + " " + g.ay + " L " + (g.ax - brim) + " -2 L " +
      (g.ax + brim) + " -2 Z";
  }
  /* A circle as a path, for taking one out of the box with an even-odd
     fill — which is how the ground past the cut is shaded to its own arc. */
  function disc(g, r) {
    return "M " + (g.ax - r) + " " + g.ay + " a " + r + " " + r +
      " 0 1 0 " + (2 * r) + " 0 a " + r + " " + r + " 0 1 0 " + (-2 * r) +
      " 0 Z";
  }
  /* The flat tone a label is set in. The line itself takes the ramp — see
     the gradients in the board's own defs. */
  /* The same color for the athlete in the circle and the one being read
     for: it is the same athlete's line either way, and which of them is in
     the ring is said by the marker on it. */
  var INK = { first: "var(--first)", second: "var(--second)",
              third: "var(--third)", cut: "var(--dim)",
              upNow: "var(--tint)", mine: "var(--tint)" };
  var RAMPED = { first: 1, second: 1, third: 1 };
  /* Which of the three a place wears, for the type that carries a placing
     rather than draws one. */
  function metalOf(place) { return place <= 3 ? " m" + place : ""; }

  function board(b, c) {
    if (!b || !b.marks.length) {
      return '<p class="empty">Nothing on the board yet.</p>';
    }
    /* Measured rather than assumed: the app sizes its board off the room
       it is given, and a fixed viewBox would draw one shape of sector on
       every phone. */
    var box = boardBox(Math.max(el("view").clientWidth - 26, 240));
    var g = geom(box, c.sector), W = box.w, H = box.h;
    var out = ['<svg viewBox="0 0 ' + W + " " + H +
      '" role="img" aria-label="The competition on the sector">',
      "<defs>/*METAL_DEFS*/",
      '<linearGradient id="grass" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="var(--accent)" stop-opacity="0.10"/>' +
        '<stop offset="1" stop-color="var(--accent)" stop-opacity="0.02"/>' +
        "</linearGradient>",
      '<clipPath id="wedge"><path d="' + wedge(g) + '"/></clipPath>',
      "</defs>"];

    /* The grass: a wash between the sector lines, lighter the further
       out, so the wedge has a body under the marks. */
    out.push('<path d="' + wedge(g) + '" fill="url(#grass)"/>');

    /* The scale, drawn: a marker line every grid meters, the way a sector
       is painted. They are what makes a gap on the board a distance
       rather than a picture — and they carry no numbers of their own,
       because the corner says how far apart they are once and a number on
       every arc is five numbers competing with the marks. */
    out.push('<g clip-path="url(#wedge)">');
    b.markerLines.forEach(function (meters) {
      var f = (meters - b.near) / (b.far - b.near);
      if (f < 0 || f > 1) return;
      out.push('<path d="' + arc(g, f) +
        '" fill="none" stroke="var(--line)" stroke-width="1" opacity="0.32"/>');
    });

    /* Past the cut is where a throw has to land, so it is drawn as a
       place rather than as a line — and bounded by the cut's own arc, not
       by a horizontal edge: a throw lands the same distance out down the
       middle as by a sector line, and a straight edge would shade ground
       that is short of the cut at the sides, which is exactly where a
       place is lost. */
    var cut = null;
    b.marks.forEach(function (m) { if (m.line === "cut") cut = m; });
    if (cut && cut.fraction <= 1) {
      var r = g.ay - Math.min(yAt(g, cut.fraction), g.floor);
      out.push('<path fill-rule="evenodd" fill="var(--accent)" ' +
        'fill-opacity="0.07" d="M 0 -2 H ' + W + " V " + (H + 2) + " H 0 Z " +
        disc(g, Math.max(r, 0)) + '"/>');
    }
    out.push("</g>");

    /* The sector lines, out past the far edge of the band: they carry on
       to the back of the field, and stopping them at the top of the box
       would draw a room rather than a sector. */
    [-1, 1].forEach(function (sign) {
      var a = -Math.PI / 2 + sign * g.half, far = H * 3;
      out.push('<path d="M ' + g.ax + " " + g.ay + " L " +
        (g.ax + Math.cos(a) * far) + " " + (g.ay + Math.sin(a) * far) +
        '" stroke="var(--line)" stroke-width="1.2" opacity="0.8"/>');
    });

    /* Everybody else in the competition: the spread of the field, with no
       name on it. */
    (b.others || []).forEach(function (f) {
      if (f < 0 || f > 1) return;
      out.push('<path d="' + arc(g, f) + '" fill="none" stroke="var(--dim)" ' +
        'stroke-width="1" opacity="0.28"/>');
    });

    /* Labels are two pills at the edges of the box with the line running
       between them, level with the ends of their own arc — and one solid
       pill for a mark the band broke off, which has no line to leave room
       for. Only the labels move to avoid each other — the lines stay where
       the throws put them — and one that had to slide grows a leader back
       to its own. */
    var labels = b.marks.map(function (m) {
      var f = Math.max(0, Math.min(1, m.fraction));
      var y = m.off === "far" ? g.top + 5
            : m.off === "near" ? g.floor
            : endY(g, radiusAt(g, f));
      return { m: m, f: f, y: y, want: y };
    }).sort(function (a, c2) { return a.y - c2.y; });
    /* Stacked the way the app stacks them, down a running ceiling: each
       label kept clear of the one above it, and one pinned to an edge
       given the room its arrow needs on *both* sides rather than only
       under it. The arrow hangs outside the pill, and the lead and the cut
       can be off the same edge at once — that is the board that has
       broken — so a single gap between two of them draws the second one's
       arrow through the first one's pill. */
    var ceiling = g.top;
    labels.forEach(function (L) {
      var room = L.m.off ? ARROW : 0;
      L.y = Math.max(L.y, ceiling + room);
      ceiling = L.y + ROW + room;
    });
    /* Stacking them can push the last one off the bottom; lifting the
       whole set keeps the gaps and loses only the padding under it. */
    var over = labels.length ? labels[labels.length - 1].y - g.floor : 0;
    if (over > 0) {
      labels.forEach(function (L) { L.y = Math.max(g.top, L.y - over); });
    }

    /* Arcs first and labels after, which is the order the app paints them
       in and the whole reason it makes two passes: a line drawn later
       cuts straight through the label of the mark above it, and on a
       board that has broken the label above it is a pill pinned to the
       edge with nothing between the two. */
    labels.forEach(function (L) {
      var m = L.m;
      if (m.off) return;
      var ink = INK[m.line] || "var(--text)";
      /* A podium line is drawn in the metal itself rather than in its
         flat tone: an arc across the sector is the one thing here with
         the room to show a ramp. The leader's line and the one in the
         circle are struck heavier, as the app strikes them. */
      var line = RAMPED[m.line] ? "url(#m-" + m.line + ")" : ink;
      var lead = m.line === "first" || m.line === "upNow";
      out.push('<path d="' + arc(g, L.f) + '" fill="none" stroke="' + line +
        '" stroke-width="' +
        (m.line === "cut" ? 1.4 : lead ? 2.6 : 2) + '"' +
        (m.line === "cut" ? ' stroke-dasharray="6 5" opacity="0.9"' : "") +
        "/>");
      /* A marker at the middle of the line, for the athlete the board is
         being read for — it is how the app says which of these is theirs
         without spending a second color on it. */
      if (m.line === "upNow" || m.line === "mine") {
        out.push('<circle cx="' + g.ax + '" cy="' + yAt(g, L.f) +
          '" r="4" fill="' + ink + '"/>');
      }
    });

    labels.forEach(function (L) {
      var m = L.m, ink = INK[m.line] || "var(--text)";
      var named = (m.label ? m.label + "  " : "") + m.name;
      if (m.off) {
        /* Broken off the band: pinned to the edge it went out of, rather
           than squashing the run of the competition the board is drawing
           into an inch of sector to keep a runaway leader on the picture.
           Only the lines worth that get here — the lead, the cut and
           whoever the board is being read for; see MeetBoard. */
        out.push(edgeLabel(g, W, L.y, named, m, ink));
        return;
      }
      out.push(pill(4, L.y, named, ink, "start"));
      out.push(pill(W - 4, L.y, m.mark, ink, "end"));
      if (Math.abs(L.y - L.want) > 1.5) {
        out.push('<path d="M 96 ' + L.y + " L 120 " + L.want +
          '" stroke="' + ink + '" stroke-width="1" opacity="0.5" fill="none"/>');
      }
    });
    /* The scale, in words, in the bottom-left corner — where the app puts
       it. The sector narrows towards its circle, so the bottom corners of
       the box are empty at every zoom and nothing has to move to make room
       for it. */
    if (b.gridLabel) {
      out.push('<text x="8" y="' + (H - 5) +
        '" fill="var(--dim)" fill-opacity="0.7" font-size="10" ' +
        'font-weight="600">' + esc(b.gridLabel) + "</text>");
    }
    out.push("</svg>");
    return out.join("");
  }

  /* Measured rather than counted: the app lays a label out with a real
     text painter, and a width guessed at so many pixels a character
     leaves a panel hanging off the end of every short one. */
  var _ruler = document.createElement("canvas").getContext("2d");
  function textWidth(text, size, weight) {
    _ruler.font = weight + " " + size + 'px Barlow, system-ui, sans-serif';
    return _ruler.measureText(String(text)).width;
  }

  /* A mark the band broke off, drawn the way the app draws one: a single
     solid pill carrying the name and the mark, with an arrow that way and
     how far that way it is. One pill rather than the usual two, because
     there is no line running between them to leave room for and a gap
     there would say there was — solid is what makes it read as a marker
     rather than as a throw that landed on this stretch of sector. */
  function edgeLabel(g, W, y, text, m, ink) {
    var top = y - 11, far = m.off === "far";
    /* Solid, where the two pills are translucent — the app strikes this
       one at the backdrop's full weight for the same reason it runs the
       rect the whole way across. */
    var out = ['<g><rect x="4" y="' + top + '" width="' + (W - 8) +
      '" height="22" rx="4" fill="var(--bg)"/>' +
      '<text x="11" y="' + (y + 5) + '" fill="' + ink +
      '" font-size="13.5" font-weight="600">' + esc(text) + "</text>" +
      '<text x="' + (W - 11) + '" y="' + (y + 5) + '" fill="' + ink +
      '" font-size="13.5" font-weight="600" text-anchor="end">' +
      esc(m.mark) + "</text></g>"];
    if (!m.out) return out.join("");
    /* Drawn rather than typed: an arrow is not in every font, and a
       missing glyph is a box. */
    var w = textWidth(m.out, 10, 600);
    var tip = far ? top - 10 : top + 32;
    var base = far ? top - 2 : top + 24;
    var ax = W / 2 - w / 2 - 9;
    out.push('<path d="M ' + ax + " " + tip + " L " + (ax - 4.5) + " " + base +
      " L " + (ax + 4.5) + " " + base + ' Z" fill="' + ink +
      '" fill-opacity="0.85"/>');
    out.push('<text x="' + (W / 2 - w / 2 + 4) + '" y="' +
      ((tip + base) / 2 + 3.5) + '" fill="' + ink +
      '" fill-opacity="0.85" font-size="10" font-weight="600">' +
      esc(m.out) + "</text>");
    return out.join("");
  }

  function pill(x, y, text, ink, anchor) {
    var w = textWidth(text, 13.5, 600) + 14;
    var rx = anchor === "end" ? x - w : x;
    /* A quiet panel under bold type, not a stroked box: the app's labels
       are read as the line's own name, and an outline round every one of
       them turns the sector into a page of boxes. */
    return '<g><rect x="' + rx + '" y="' + (y - 11) + '" width="' + w +
      '" height="22" rx="4" fill="var(--bg)" fill-opacity="0.72"/>' +
      '<text x="' + (anchor === "end" ? x - 7 : x + 7) + '" y="' + (y + 5) +
      '" fill="' + ink + '" font-size="13.5" font-weight="600" text-anchor="' +
      anchor + '">' + esc(text) + "</text></g>";
  }

  /* ---- the three views --------------------------------------------- */
  /* The app's own header over the field, on a card of its own: the round
     and how much of it has been thrown, the three an infield calls out,
     and whoever is in front under a rule. */
  function header(c, withLeader) {
    return '<div class="card">' + headerBody(c, withLeader) + "</div>";
  }

  /* The header without a card around it, because the live view puts it in
     the same one as the board — which is what the app's own live card is:
     the flight, the sector and the athlete in the circle, on one surface. */
  function headerBody(c, withLeader) {
    var f = c.flight || {};
    var calls = (f.calls || []).map(function (r, i) {
      return row(r, i === 0);
    }).join("");
    var lead = withLeader && f.leading
      ? '<div class="lead-rule"></div>' + row(f.leading, false, TROPHY)
      : "";
    /* When the coach's own throw, for a flight that isn't theirs — the one
       line that is any use to somebody waiting on a thrower who hasn't
       been called in yet. */
    var later = f.elsewhere
      ? '<p class="later">' + CLOCK + esc(f.elsewhere) + "</p>"
      : "";
    return '<div class="round"><b>' + esc(c.status) +
      '</b><span class="sub">' + esc(f.thrownLabel || "") + "</span></div>" +
      '<div class="bar"><i style="width:' +
      Math.round((f.progress || 0) * 100) + '%"></i></div>' +
      calls + later + lead +
      (f.label ? '<div class="sub" style="margin-top:8px">' + esc(f.label) +
        "</div>" : "");
  }

  /* One call: what they are called, who they are, where they stand and
     what they are standing on. */
  function row(r, up, icon) {
    return '<div class="call' + (up ? " up" : "") + '"><span class="lbl">' +
      (icon || "") + esc(r.label) + '</span><span class="who">' +
      esc(r.name) + "</span>" +
      (r.mark ? '<span class="bm">' + esc(r.mark) + "</span>" : "") + "</div>";
  }

  /* The app's live card is one surface: the flight above the sector, the
     sector, what the throw in the circle has to do, and under a rule the
     athlete about to take it — with the same six boxes as the field.
     Opaque, unlike every other card here, because the page's own sector
     backdrop runs behind it and two sectors drawn over each other at
     different angles are a picture of nothing. */
  function liveView(c) {
    /* No leader row: the board below has the lead drawn across it, and the
       app's live header leaves it off for that reason. */
    var cap = (c.caption || []).map(function (line) {
      return '<p class="cap ' + esc(line.tone) + '">' + esc(line.text) + "</p>";
    }).join("");
    var up = null;
    if (c.flight && c.flight.upOrder != null) {
      c.places.forEach(function (p) {
        if (p.order === c.flight.upOrder) up = p;
      });
    }
    return '<div class="card solid">' + headerBody(c, false) +
      '<div class="board">' + board(c.board, c) + "</div>" + cap +
      (up ? '<div class="up-rule"></div>' + entryRow(c, up, true) : "") +
      "</div>";
  }

  function seriesView(c) {
    var field = c.places.slice().sort(function (a, b) { return a.order - b.order; });
    var flighted = c.places.some(function (q) { return q.flight; });
    var out = [header(c, true)], flight = null;
    field.forEach(function (p) {
      var f = p.flight || 1;
      if (flighted && f !== flight) {
        flight = f;
        out.push('<p class="heading">Flight ' + f + "</p>");
      }
      out.push(entryRow(c, p, false));
    });
    return out.join("") || '<p class="empty">Nobody entered yet.</p>';
  }

  /* One athlete in the field, as the app's own card draws them: who and
     how they are doing on the top row, the series across the bottom one.
     Embedded for the live card, which is already a surface — a card inside
     a card reads as a mistake. */
  function entryRow(c, p, embedded) {
    var up = c.flight && p.order === c.flight.upOrder;
    var metal = p.best ? metalOf(p.place) : "";
    var pb = p.series.some(function (a) { return a && a.pb; })
      ? '<img class="medal" src="' + base + '/pb.png" alt="Personal best">'
      : "";
    /* The order they throw in down the left, the way the app reads a
       field; the place rides on the right with the mark it was made on,
       and the medal between them, which is the order the app sets it in. */
    return '<div class="entry' + (embedded ? " in" : " card") +
      (up && !embedded ? " up" : "") + '"><div class="erow">' +
      '<span class="ord">' + (p.order + 1) + "</span>" +
      '<span class="nm' + (up ? " now" : p.mine ? " mine" : "") + '">' +
      esc(p.name) + "</span>" +
      (p.best
        ? '<span class="chip' + metal + '">' + esc(p.placeLabel) + "</span>" +
          pb + '<span class="bm big">' + esc(p.best) + "</span>"
        : "") +
      "</div>" + boxes(c, p) + "</div>";
  }

  function boxes(c, p) {
    var cells = p.series.map(function (a, i) {
      var spent = !p.throwsInFinal && i >= c.prelims;
      var n = "<i>" + (i + 1) + "</i>";
      if (!a) return '<div class="box' + (spent ? " out" : "") + '">' + n +
        "&nbsp;</div>";
      var cls = "box";
      if (a.kind === "foul") cls += " foul";
      if (a.kind === "pass") cls += " pass";
      if (a.mark && p.bestRound === i + 1) cls += " best";
      if (a.pb) cls += " pb";
      /* An X for a foul, the way the app's own boxes mark one — 'F' is a
         grade, and this is a throw that did not count. */
      var text = a.short ? esc(a.short) : a.kind === "foul" ? "X" : "P";
      return '<div class="' + cls + '">' + n + text + "</div>";
    }).join("");
    return '<div class="series">' + cells + "</div>";
  }

  function standingsView(c) {
    var rows = c.places.map(function (p, i) {
      var rule = "";
      var next = c.places[i + 1];
      /* The cut where it falls, drawn the way the app draws it: the words
         between two rules rather than a heading over the rest of the
         field. Everything under it is out of the final as things stand. */
      if (c.cut.has && p.advancing && next && !next.advancing) {
        rule = '<p class="cut-rule"><span>the cut</span></p>';
      }
      var metal = p.best ? metalOf(p.place) : "";
      /* Only the athlete this page is being read for carries the lines
         underneath, like the app's table: the rest of the field is here to
         be placed against, and what they need is not the reader's
         problem. */
      var aside = (p.consistency
        ? '<p class="aside">' + esc(p.consistency) + "</p>" : "") +
        (p.needed
          ? '<p class="aside needs">' + esc(p.needed) + "</p>" : "");
      /* The place is struck in its metal; the mark is not. The app colors
         a mark for whose it is — the coach's own in the event's color, the
         rest of the field set back — and gilding the leader's would be
         saying the same thing twice in the one row that already says it. */
      return '<div class="row"><span class="pl' + metal +
        (p.mine && !metal ? " mine" : "") + '">' +
        (p.best ? esc(p.place) : "–") +
        '</span><span class="nm' + (p.mine ? " mine" : "") + '">' +
        esc(p.name) + '</span><span class="bm' +
        (p.mine ? " mine" : "") + '">' + esc(p.best || "—") +
        "</span></div>" + aside + rule;
    }).join("");
    /* What the cut is, over the table — a promise before it is made and a
       fact after it, exactly as the app heads its own. */
    var advance = c.cut.has
      ? '<p class="advance' + (c.cut.made ? " made" : "") + '">' +
        esc(c.cut.label) + "</p>"
      : "";
    return rows ? '<div class="card">' + advance + rows + "</div>"
                : '<p class="empty">Nothing thrown yet.</p>';
  }

  /* Who the page is being read for: the question on the way in, and the
     chip it becomes once it has been answered.

     Nothing at all in a competition of one — there is nobody to choose
     between, and a field of one is a page about that athlete already. */
  function watchView() {
    if (!data) return "";
    /* Down the throwing order, which is the order a heat sheet prints a
       field in and the order the Series tab reads it in. */
    var field = (data.places || []).slice()
      .sort(function (a, b) { return a.order - b.order; });
    if (field.length < 2) return "";
    /* Read off the field rather than off what the phone last confirmed, so
       a tick shows the moment it is made instead of a poll later. */
    var names = [];
    field.forEach(function (p) {
      if (follow.indexOf(p.key) >= 0) names.push(p.name);
    });

    if (!picking) {
      /* 'Follow your athletes' is the whole invitation and needs nothing
         after it; a name does, or there is no way to tell the chip is
         still a control. Two names in full, and a count past that: a chip
         is one line of a header, and four surnames with their schools
         after them is not one line. */
      var who = names.length === 0 ? ""
        : names.length === 1 ? names[0]
        : names[0] + " and " + (names.length - 1) +
          (names.length === 2 ? " other" : " others");
      return '<button class="who" data-open aria-expanded="false">' +
        (who ? "Watching <b>" + esc(who) + '</b><span class="chev">change' +
          "</span>" : "Follow your athletes") + "</button>";
    }

    /* The field with a box against every name, ruled off where the flights
       are — the sheet, ticked. Several at once, because a parent with two
       throwing should not have to choose between them. */
    var rows = [], flight = null;
    var flighted = field.some(function (p) { return p.flight; });
    field.forEach(function (p) {
      var f = p.flight || 1;
      if (flighted && f !== flight) {
        flight = f;
        rows.push('<p class="heading">Flight ' + f + "</p>");
      }
      var on = follow.indexOf(p.key) >= 0;
      rows.push('<button class="pick' + (on ? " on" : "") + '" data-key="' +
        esc(p.key) + '" role="checkbox" aria-checked="' + on + '">' +
        '<span class="tick"></span><span class="ord">' + (p.order + 1) +
        '</span><span class="nm">' + esc(p.name) + "</span></button>");
    });
    return '<div class="picker"><p class="ask">Who are you here to watch?</p>' +
      '<p class="why">The board, the cut and the calls follow them.</p>' +
      '<div class="names" role="group">' + rows.join("") + "</div>" +
      '<div class="foot"><button class="plain" data-clear>' +
      (names.length ? "Stop following" : "Just the competition") +
      '</button><button class="done" data-done>Done</button></div></div>';
  }

  /* ---- painting ----------------------------------------------------- */
  function render() {
    if (!data) return;
    document.documentElement.style.setProperty("--tint", data.tint);
    el("label").textContent = data.label;
    el("glyph").innerHTML = glyph(data.event, data.tint);
    el("meet").textContent =
      [data.meet, data.date, data.venue].filter(Boolean).join(" · ");
    el("weather").textContent = data.conditions || "";
    /* Repainted when the question or the answer has changed, and left
       alone otherwise: a poll lands every four seconds, and a field long
       enough to scroll must not jump back to the top under the thumb that
       is scrolling it. A tick changes the signature, so the box fills
       under the finger that made it. */
    if (!picking || watchSig() !== painted) {
      el("watch").innerHTML = watchView();
      painted = watchSig();
    }

    slide(["live", "series", "standings"].indexOf(tab));
    Array.prototype.forEach.call(el("tabs").querySelectorAll("button"),
      function (b) {
        b.setAttribute("aria-pressed", String(b.dataset.tab === tab));
      });

    el("view").innerHTML = tab === "live" ? liveView(data)
      : tab === "series" ? seriesView(data) : standingsView(data);
    el("sheet").setAttribute("href", base + "/results.pdf");
    /* The sector is laid out from where the bar sits, and the bar does not
       sit anywhere until the header above it has its meet on it. */
    backdrop();
  }

  /* The block under the active section, leaning at the sector's own
     half-angle — and squaring off against whichever end of the bar it has
     reached, so it fills the corner instead of leaving a wedge behind it. */
  function slide(order) {
    var bar = el("tabs"), block = el("block");
    var lean = bar.offsetHeight / 2 * Math.tan(34.92 / 2 * Math.PI / 180);
    var seg = bar.offsetWidth / 3;
    var atStart = order === 0 ? 1 : 0, atEnd = order === 2 ? 1 : 0;
    block.style.left = (order * seg - lean) + "px";
    block.style.width = (seg + 2 * lean) + "px";
    block.style.clipPath = "polygon(" +
      (2 * lean - 2 * lean * atStart) + "px 0, 100% 0, " +
      (seg + 2 * lean * atEnd) + "px 100%, 0 100%)";
  }

  function tickAge() {
    if (!lastAt) return;
    var secs = Math.round((Date.now() - lastAt) / 1000);
    var stale = secs > 25 || failed > 2;
    el("age").className = "age" + (stale ? " stale" : "");
    el("ageText").textContent = stale
      ? "Not updating — is the phone still on this wifi?"
      : secs < 5 ? "Live" : "Updated " + secs + "s ago";
  }

  /* ---- the wire ------------------------------------------------------ */
  /* The tag is kept here rather than left to the browser's cache: the
     state is sent no-store precisely so it never lands in a spectator's
     history, and a 304 is still worth having between rounds. */
  function poll() {
    var headers = etag ? { "If-None-Match": etag } : {};
    /* Who is being followed goes with the ask: the phone works the board,
       the cut and the calls out around them and hands back the answers,
       exactly as it does for the coach's own on their own screen. */
    var at = base + "/state" +
      (follow.length ? "?f=" + follow.map(encodeURIComponent).join(",") : "");
    fetch(at, { headers: headers, cache: "no-store" })
      .then(function (r) {
        if (r.status === 304) { failed = 0; lastAt = Date.now(); return null; }
        if (!r.ok) throw new Error(r.status);
        etag = r.headers.get("ETag");
        return r.json();
      })
      .then(function (fresh) {
        failed = 0;
        lastAt = Date.now();
        if (!fresh) return;
        /* Following somebody the competition no longer holds — taken off
           the meet, or the whole field entered again. They come back
           missing from the answer, and the page drops them rather than
           going on asking for a ghost. The rest are untouched. */
        if (follow.length) {
          var live = (fresh.following || []).map(function (f) { return f.key; });
          var kept = follow.filter(function (k) { return live.indexOf(k) >= 0; });
          if (kept.length !== follow.length) { follow = kept; remember(); }
        }
        data = fresh;
        render();
      })
      .catch(function () { failed++; })
      .then(tickAge);
  }

  /* The picker. A tick fills at once and asks the phone for the same
     competition read for whoever is ticked now — the board and the
     captions come back with the next answer, a moment later, while the
     list is still open. The list closes on Done rather than on the first
     tick, because there may be two of them in the field. */
  el("watch").addEventListener("click", function (e) {
    var b = e.target.closest("button");
    if (!b) return;
    if (b.dataset.open !== undefined) { picking = true; render(); return; }
    if (b.dataset.done !== undefined) {
      /* Answered, even with nobody ticked: an empty list read as 'not yet
         asked' would put the question back up on the next visit. */
      asked = true;
      picking = false;
      remember();
      render();
      return;
    }
    /* The tag belongs to the answer we were being given, and either of
       these asks a different question. */
    if (b.dataset.clear !== undefined) {
      follow = [];
      asked = true;
      picking = false;
      remember();
      etag = null;
      render();
      poll();
      return;
    }
    if (b.dataset.key === undefined) return;

    var at = follow.indexOf(b.dataset.key);
    if (at < 0) follow.push(b.dataset.key);
    else follow.splice(at, 1);
    asked = true;
    remember();
    /* The row is turned over where it stands rather than by repainting the
       panel around it: a field long enough to scroll would otherwise jump
       back to the top under the finger that has just ticked somebody
       halfway down it. */
    var on = at < 0;
    b.className = "pick" + (on ? " on" : "");
    b.setAttribute("aria-checked", String(on));
    var out = el("watch").querySelector(".plain");
    if (out) {
      out.textContent =
        follow.length ? "Stop following" : "Just the competition";
    }
    painted = watchSig();
    etag = null;
    poll();
  });

  el("tabs").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-tab]");
    if (!b) return;
    tab = b.dataset.tab;
    render();
  });

  backdrop();
  /* The board is measured off the room it has, so a turned phone redraws
     it rather than stretching the one it drew in portrait. */
  addEventListener("resize", render);
  /* And once Barlow has landed, so the labels are laid out to the type
     they are actually set in rather than to the fallback's metrics. */
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () { render(); });
  }
  poll();
  setInterval(poll, 4000);
  setInterval(tickAge, 1000);
  /* Coming back to a page that has been in a pocket for ten minutes should
     not show a ten-minute-old board while it waits for the next tick. */
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden) poll();
  });
})();
</script>
</body>
</html>
''';
