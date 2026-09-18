import 'package:flutter/material.dart';

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
String spectatorPage(ColorScheme scheme) {
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
  return _page
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
      .replaceFirst('/*LEAN*/', sectorHalfAngleDeg.toStringAsFixed(2));
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

  .card { background: var(--surface); padding: 10px 12px; margin-bottom: 9px; }
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
               min-width: 62px; }
  .call.up .lbl { color: var(--tint); font-weight: 600; }
  .call .who { flex: 1; min-width: 0; overflow: hidden; white-space: nowrap;
               text-overflow: ellipsis; }
  .call.up .who { color: var(--text); }
  .lead-rule { border-top: 1px solid color-mix(in srgb, var(--line) 40%,
               transparent); margin-top: 10px; }

  main svg, .card svg { display: block; width: 100%; height: auto; }

  /* No rules between rows: the app's table doesn't draw them, and a
     four-line standings cut into boxes reads as four things rather than
     one competition. */
  .row { display: flex; align-items: baseline; gap: 10px; padding: 4px 0; }
  .pl { min-width: 22px; color: var(--dim); font-variant-numeric: tabular-nums;
        font-size: 13px; }
  /* Where they come in the throwing order, which is what the field is read
     down — the place rides on the right beside the mark. */
  .ord { min-width: 18px; color: var(--dim); font-size: 12px;
         font-variant-numeric: tabular-nums; }
  .chip { font-size: 11px; color: var(--dim); }
  /* Tucked under the name it belongs to, not floating between two rows. */
  .aside { color: var(--dim); font-size: 11px; margin: -3px 0 3px;
           padding-left: 32px; }
  /* Set back the way the app's own table sets the field back: the rest of
     the competition is here to be placed against, not read. The coach's
     own athlete is the one the eye should find, and a metal has to have
     something dimmer than itself to stand against — silver against bright
     type is not silver, it is type. */
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
  .cut-rule { border-top: 1px dashed var(--accent); margin: 8px 0 0;
              padding-top: 6px; font-size: 11px; color: var(--accent);
              letter-spacing: 0.8px; text-transform: uppercase; }
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
  .medal { height: 22px; width: auto; vertical-align: -6px; margin-right: 1px; }
  /* The athlete in the circle, marked the way the app marks their card. */
  .card.up { box-shadow: inset 0 0 0 1px var(--tint); }

  .downloads { display: flex; gap: 8px; margin: 18px 0 8px; }
  .downloads a { flex: 1; text-align: center; text-decoration: none;
                 padding: 12px 14px; font-size: 14px; font-weight: 500;
                 background: var(--surface); color: var(--text); }
  .note { color: var(--dim); font-size: 12px; text-align: center; margin: 6px 0 0; }
  .empty { color: var(--dim); text-align: center; padding: 28px 10px; }
</style>
</head>
<body>
<svg id="backdrop" preserveAspectRatio="none" aria-hidden="true"></svg>
<header>
  <div class="title"><span id="glyph"></span><h1 id="label">…</h1></div>
  <div class="sub" id="meet"></div>
  <div class="sub" id="weather"></div>
  <div class="age" id="age"><i class="dot"></i><span id="ageText">connecting…</span></div>
</header>
<div class="tabs angular" id="tabs">
  <div id="block"></div>
  <button data-tab="live" aria-pressed="true">Live</button>
  <button data-tab="series" aria-pressed="false">Series</button>
  <button data-tab="standings" aria-pressed="false">Standings</button>
</div>
<main id="view"></main>
<div class="downloads" id="downloads"></div>
<p class="note">Live from the coach's phone. Nothing here is stored anywhere else.</p>

<script>
(function () {
  "use strict";

  /* The share's own path — '/M/ABC123' off the phone. A page opened as a
     file (which is how it is reviewed) sits at '…/spectator.html', so the
     file name comes off and everything beside it resolves the same way. */
  var base = location.pathname.replace(/\/[^\/]*\.html$/, "").replace(/\/$/, "");
  var data = null, tab = "live", etag = null;
  var lastAt = 0, failed = 0;

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
  function backdrop() {
    var w = 400, h = 700, ax = -w * 0.16, ay = h * 1.12;
    var cx = w * 1.04, cy = -h * 0.04;
    var bearing = Math.atan2(cy - ay, cx - ax);
    var half = (34.92 / 2) * Math.PI / 180;
    var reach = Math.hypot(cx - ax, cy - ay);
    function edge(a, r) {
      return [ax + Math.cos(a) * r, ay + Math.sin(a) * r];
    }
    var out = ['<defs><radialGradient id="wash">' +
      '<stop offset="0" stop-color="var(--accent)" stop-opacity="0.07"/>' +
      '<stop offset="1" stop-color="var(--accent)" stop-opacity="0"/>' +
      "</radialGradient></defs>"];
    out.push('<circle cx="' + ax + '" cy="' + ay + '" r="' + h * 0.85 +
      '" fill="url(#wash)"/>');
    [-half, half].forEach(function (a) {
      var p = edge(bearing + a, reach);
      out.push('<path d="M ' + ax + " " + ay + " L " + p[0] + " " + p[1] +
        '" stroke="var(--accent)" stroke-opacity="0.16" stroke-width="1.4" fill="none"/>');
    });
    /* Arcs at a few depths, drawn only across the wedge. */
    [0.42, 0.62, 0.82, 1.0].forEach(function (t) {
      var r = reach * t;
      var a = edge(bearing - half, r), b = edge(bearing + half, r);
      out.push('<path d="M ' + a[0] + " " + a[1] + " A " + r + " " + r +
        " 0 0 1 " + b[0] + " " + b[1] +
        '" stroke="var(--accent)" stroke-opacity="0.09" stroke-width="1" fill="none"/>');
    });
    var svg = el("backdrop");
    svg.setAttribute("viewBox", "0 0 " + w + " " + h);
    svg.innerHTML = out.join("");
  }

  /* ---- the implement, drawn the way EventGlyph draws it ------------- */
  function glyph(event, tint) {
    var s = 22, g;
    if (event === "discus") {
      g = '<path fill-rule="evenodd" d="' + ring(0.5, 0.5, 0.33, 0.075, s) + '"/>';
    } else if (event === "shotPut") {
      g = '<path fill-rule="evenodd" d="' + ring(0.5, 0.55, 0.31, 0.06, s, -0.11, -0.12) + '"/>';
    } else if (event === "hammer") {
      g = '<circle cx="' + 0.30 * s + '" cy="' + 0.70 * s + '" r="' + 0.17 * s + '"/>' +
        '<path d="M ' + 0.41 * s + " " + 0.59 * s + " L " + 0.74 * s + " " + 0.30 * s +
        '" stroke="' + tint + '" stroke-width="' + 0.05 * s + '" fill="none"/>';
    } else {
      /* The javelin: a needle drawn tail to tip, thickest just past the
         middle where the cord grip is. */
      g = '<path d="M ' + 0.12 * s + " " + 0.88 * s + " L " + 0.60 * s + " " +
        0.34 * s + " L " + 0.88 * s + " " + 0.12 * s + " L " + 0.66 * s + " " +
        0.44 * s + ' Z"/>';
    }
    return '<svg width="' + s + '" height="' + s + '" viewBox="0 0 ' + s + " " + s +
      '" fill="' + tint + '" aria-hidden="true" style="width:' + s + "px;height:" +
      s + 'px">' + g + "</svg>";
  }
  /* A disc with a hole in it, which is both the discus and the shot's
     highlight — even-odd fill, exactly as the painter does it. */
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
  var W = 360, H = 372, TOP = 26, BOTTOM = 344, CX = W / 2;
  var NEAR_HALF = 62, FAR_HALF = 158, SAG = 13;

  function yAt(f) { return BOTTOM - f * (BOTTOM - TOP); }
  function halfAt(y) {
    var t = (BOTTOM - y) / (BOTTOM - TOP);
    return NEAR_HALF + t * (FAR_HALF - NEAR_HALF);
  }
  /* An arc at a constant distance from the circle dips at the sector
     lines: a point out at the edge is the same distance away but less far
     up the page. Drawn as a quadratic through the middle of the band. */
  function arc(f) {
    var y = yAt(f), h = halfAt(y);
    return "M " + (CX - h) + " " + (y + SAG) +
           " Q " + CX + " " + (y - SAG) + " " + (CX + h) + " " + (y + SAG);
  }
  function wedge() {
    return "M " + (CX - NEAR_HALF) + " " + BOTTOM +
           " L " + (CX - FAR_HALF) + " " + TOP +
           " L " + (CX + FAR_HALF) + " " + TOP +
           " L " + (CX + NEAR_HALF) + " " + BOTTOM + " Z";
  }
  /* The flat tone a label is set in. The line itself takes the ramp — see
     the gradients in the board's own defs. */
  /* The same color for the athlete in the circle and the coach's own: it
     is the same athlete's line either way, and which of them is in the
     ring is said by the marker on it. */
  var INK = { first: "var(--first)", second: "var(--second)",
              third: "var(--third)", cut: "var(--dim)",
              upNow: "var(--tint)", mine: "var(--tint)" };
  var RAMPED = { first: 1, second: 1, third: 1 };
  /* Which of the three a place wears, for the type that carries a placing
     rather than draws one. */
  function metalOf(place) { return place <= 3 ? " m" + place : ""; }

  function board(b) {
    if (!b || !b.marks.length) {
      return '<p class="empty">Nothing on the board yet.</p>';
    }
    var out = ['<svg viewBox="0 0 ' + W + ' ' + H +
      '" role="img" aria-label="The competition on the sector">',
      "<defs>/*METAL_DEFS*/</defs>"];
    out.push('<path d="' + wedge() +
      '" fill="rgba(0,0,0,0.22)" stroke="var(--line)" stroke-width="1"/>');

    /* Ground short of the cut, shaded to its own arc — a throw lands the
       same distance out down the middle as it does by a sector line, so a
       straight edge across the wedge would shade ground that is past the
       cut at the sides. */
    var cut = null;
    b.marks.forEach(function (m) { if (m.line === "cut") cut = m; });
    if (cut && cut.fraction > 0 && cut.fraction < 1) {
      out.push('<path d="' + arc(cut.fraction) +
        " L " + (CX + NEAR_HALF) + " " + BOTTOM +
        " L " + (CX - NEAR_HALF) + " " + BOTTOM + ' Z" fill="rgba(0,0,0,0.34)"/>');
    }

    /* The marker lines carry no numbers of their own — the app's board
       doesn't label them either, it says how far apart they are once, in
       the corner. A number on every arc is five numbers competing with the
       marks, which are what the board is for. */
    b.markerLines.forEach(function (meters) {
      var f = (meters - b.near) / (b.far - b.near);
      if (f < 0 || f > 1) return;
      out.push('<path d="' + arc(f) +
        '" fill="none" stroke="var(--line)" stroke-width="1"/>');
    });

    /* Labels are two pills at the edges of the box with the line running
       between them, level with the ends of their own arc. Only the labels
       move to avoid each other — the lines stay where the throws put
       them — and one that had to slide grows a leader back to its own. */
    var labels = b.marks.map(function (m) {
      var f = Math.max(0, Math.min(1, m.fraction));
      return { m: m, f: f, y: yAt(f) + SAG, want: yAt(f) + SAG };
    }).sort(function (a, c) { return a.y - c.y; });
    for (var i = 1; i < labels.length; i++) {
      if (labels[i].y - labels[i - 1].y < 24) labels[i].y = labels[i - 1].y + 24;
    }

    labels.forEach(function (L) {
      var m = L.m, ink = INK[m.line] || "#c2ced4";
      if (!m.off) {
        /* A podium line is drawn in the metal itself rather than in its
           flat tone: an arc across the sector is the one thing here with
           the room to show a ramp. */
        var line = RAMPED[m.line] ? "url(#m-" + m.line + ")" : ink;
        out.push('<path d="' + arc(L.f) + '" fill="none" stroke="' + line +
          '" stroke-width="2"' +
          (m.line === "cut" ? ' stroke-dasharray="6 5"' : "") + "/>");
        /* A marker at the middle of the line, for the athlete the board is
           being read for — it is how the app says which of these is theirs
           without spending a second color on it. */
        if (m.line === "upNow" || m.line === "mine") {
          out.push('<circle cx="' + CX + '" cy="' + (yAt(L.f) - SAG / 2) +
            '" r="4" fill="' + ink + '"/>');
        }
      } else {
        /* Broken off the band: an arrow at the edge carrying its mark,
           rather than squashing the fight for second into an inch of
           sector to keep a runaway leader on the picture. */
        var ay = m.off === "far" ? TOP + 6 : BOTTOM - 6;
        out.push('<path d="M ' + (CX - 9) + " " + ay + " L " + CX + " " +
          (ay + (m.off === "far" ? -10 : 10)) + " L " + (CX + 9) + " " + ay +
          ' Z" fill="' + ink + '"/>');
      }
      out.push(pill(4, L.y, (m.label ? m.label + "  " : "") + m.name, ink, "start"));
      out.push(pill(W - 4, L.y, m.mark, ink, "end"));
      if (Math.abs(L.y - L.want) > 1.5) {
        out.push('<path d="M 96 ' + L.y + " L 120 " + L.want +
          '" stroke="' + ink + '" stroke-width="1" opacity="0.5" fill="none"/>');
      }
    });
    out.push("</svg>");
    return out.join("");
  }

  function pill(x, y, text, ink, anchor) {
    var w = String(text).length * 7.6 + 14;
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
  function header(c) {
    var f = c.flight || {};
    var calls = (f.calls || []).map(function (r, i) {
      return row(r, i === 0);
    }).join("");
    var lead = f.leading
      ? '<div class="lead-rule"></div>' + row(f.leading, false)
      : "";
    return '<div class="card angular"><div class="round"><b>' + esc(c.status) +
      '</b><span class="sub">' + esc(f.thrownLabel || "") + "</span></div>" +
      '<div class="bar"><i style="width:' +
      Math.round((f.progress || 0) * 100) + '%"></i></div>' +
      calls + lead +
      (f.label ? '<div class="sub" style="margin-top:8px">' + esc(f.label) +
        "</div>" : "") + "</div>";
  }

  /* One call: what they are called, who they are, where they stand and
     what they are standing on. */
  function row(r, up) {
    return '<div class="call' + (up ? " up" : "") + '"><span class="lbl">' +
      esc(r.label) + '</span><span class="who">' + esc(r.name) + "</span>" +
      (r.mark ? '<span class="bm">' + esc(r.mark) + "</span>" : "") + "</div>";
  }

  function liveView(c) {
    return header(c) + '<div class="card angular">' + board(c.board) +
      (c.board && c.board.gridLabel && c.board.marks.length
        ? '<div class="sub" style="margin-top:6px">' + esc(c.board.gridLabel) +
          "</div>"
        : "") + "</div>";
  }

  function seriesView(c) {
    var field = c.places.slice().sort(function (a, b) { return a.order - b.order; });
    var flighted = c.places.some(function (q) { return q.flight; });
    var calls = (c.flight || {}).calls || [];
    var up = calls.length ? calls[0].name : null;
    var out = [header(c)], flight = null;
    field.forEach(function (p) {
      var f = p.flight || 1;
      if (flighted && f !== flight) {
        flight = f;
        out.push('<p class="heading">Flight ' + f + "</p>");
      }
      var metal = p.best ? metalOf(p.place) : "";
      var pb = p.series.some(function (a) { return a && a.pb; })
        ? '<img class="medal" src="' + base + '/pb.png" alt="Personal best">'
        : "";
      /* The order they throw in down the left, the way the app reads a
         field; the place rides on the right with the mark it was made on. */
      out.push('<div class="card angular' + (p.name === up ? " up" : "") +
        '"><div class="row"><span class="ord">' +
        (p.order + 1) + '</span><span class="nm' + (p.tracked ? " mine" : "") +
        '">' + esc(p.name) + "</span>" +
        (p.best ? pb + '<span class="chip' + metal + '">' + esc(p.placeLabel) +
          "</span>" : "") +
        '<span class="bm' + (p.tracked ? " mine" : "") + '">' +
        esc(p.best || "—") + "</span></div>" + boxes(c, p) + "</div>");
    });
    return out.join("") || '<p class="empty">Nobody entered yet.</p>';
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
      if (c.cut.has && p.advancing && next && !next.advancing) {
        rule = '<p class="cut-rule">' + (c.cut.made ? "Cut" : "Cut line") +
          (c.cut.mark ? " · " + esc(c.cut.mark) : "") + "</p>";
      }
      var metal = p.best ? metalOf(p.place) : "";
      /* Only the coach's own carry the line underneath, like the app's
         table: the rest of the field is here to be placed against. */
      var aside = p.consistency
        ? '<p class="aside">' + esc(p.consistency) + "</p>"
        : "";
      return '<div class="row"><span class="pl' + metal + '">' +
        (p.best ? esc(p.place) : "–") +
        '</span><span class="nm' + (p.tracked ? " mine" : "") + '">' +
        esc(p.name) + '</span><span class="bm' +
        (p.tracked ? " mine" : "") + metal + '">' + esc(p.best || "—") +
        "</span></div>" + aside + rule;
    }).join("");
    return rows ? '<div class="card angular">' + rows + "</div>"
                : '<p class="empty">Nothing thrown yet.</p>';
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

    slide(["live", "series", "standings"].indexOf(tab));
    Array.prototype.forEach.call(el("tabs").querySelectorAll("button"),
      function (b) {
        b.setAttribute("aria-pressed", String(b.dataset.tab === tab));
      });

    el("view").innerHTML = tab === "live" ? liveView(data)
      : tab === "series" ? seriesView(data) : standingsView(data);
    el("downloads").innerHTML =
      '<a class="angular" href="' + base + '/results.pdf">Results sheet</a>';
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
    fetch(base + "/state", { headers: headers, cache: "no-store" })
      .then(function (r) {
        if (r.status === 304) { failed = 0; lastAt = Date.now(); return null; }
        if (!r.ok) throw new Error(r.status);
        etag = r.headers.get("ETag");
        return r.json();
      })
      .then(function (fresh) {
        failed = 0;
        lastAt = Date.now();
        if (fresh) { data = fresh; render(); }
      })
      .catch(function () { failed++; })
      .then(tickAge);
  }

  el("tabs").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-tab]");
    if (!b) return;
    tab = b.dataset.tab;
    render();
  });

  backdrop();
  addEventListener("resize", function () {
    slide(["live", "series", "standings"].indexOf(tab));
  });
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
