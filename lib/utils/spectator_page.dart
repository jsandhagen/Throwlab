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
  :root { /*PALETTE*/ /*METALS*/ --pad: 16px; --lean: /*LEAN*/deg; }
  * { box-sizing: border-box; }
  /* The color goes on the page itself, not on the body: a body with its
     own background paints over the sector standing behind it. */
  html { background: var(--bg); }
  html, body { margin: 0; color: var(--text); }
  body {
    font-family: Barlow, system-ui, -apple-system, Roboto, sans-serif;
    font-size: 15px; line-height: 1.4;
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
  .title h1 { font-size: 20px; margin: 0; font-weight: 600; letter-spacing: 0.2px; }
  .title svg { flex: 0 0 auto; }
  .sub { color: var(--dim); font-size: 13px; }
  .age { display: flex; align-items: center; gap: 6px; font-size: 12px;
         color: var(--dim); margin-top: 8px; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--accent); }
  .age.stale .dot, .age.stale { color: var(--bad); }
  .age.stale .dot { background: var(--bad); }

  /* The app's own segmented bar: one surface with a slanted block under the
     active section and leaning dividers between the rest. The lean is the
     sector's half-angle, so the header leans the way the sector opens. */
  .tabs { position: relative; display: flex; height: 44px; margin-bottom: 14px;
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

  .card { background: var(--surface); padding: 14px; margin-bottom: 12px; }
  .status { display: flex; justify-content: space-between; align-items: baseline;
            gap: 10px; }
  .status b { font-size: 17px; font-weight: 600; }
  .calls { display: grid; gap: 9px; margin-top: 14px; }
  .call { display: flex; align-items: baseline; gap: 12px; }
  .call span { font-size: 11px; letter-spacing: 0.8px; color: var(--dim);
               min-width: 76px; text-transform: uppercase; }
  .call b { font-size: 17px; font-weight: 600; }
  .call.up b { color: var(--accent); }

  main svg, .card svg { display: block; width: 100%; height: auto; }

  .row { display: flex; align-items: center; gap: 10px; padding: 9px 0;
         border-top: 1px solid var(--line); }
  .row:first-child { border-top: 0; }
  .pl { min-width: 34px; color: var(--dim); font-variant-numeric: tabular-nums;
        font-size: 13px; }
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
  .bm.mine { color: var(--accent); }
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
  .box { background: var(--raised); border-radius: 6px; padding: 6px 1px;
         text-align: center; font-size: 12px; font-variant-numeric: tabular-nums;
         min-height: 32px; white-space: nowrap; }
  .box.foul { color: var(--bad); }
  .box.pass { color: var(--dim); }
  .box.best { background: color-mix(in srgb, var(--accent) 18%, var(--raised));
              font-weight: 600; }
  .box.pb { box-shadow: inset 0 0 0 1px var(--first); }
  .box.out { opacity: 0.32; }
  .tag { font-size: 10px; color: var(--first); letter-spacing: 0.5px; }

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

  var base = location.pathname.replace(/\/$/, "");
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
  var W = 460, H = 330, TOP = 28, BOTTOM = 296, CX = W / 2;
  var NEAR_HALF = 74, FAR_HALF = 168, SAG = 11;

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
  var INK = { first: "var(--first)", second: "var(--second)",
              third: "var(--third)", cut: "var(--accent)",
              upNow: "var(--accent)", mine: "var(--accent)" };
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

    b.markerLines.forEach(function (meters) {
      var f = (meters - b.near) / (b.far - b.near);
      if (f < 0 || f > 1) return;
      out.push('<path d="' + arc(f) +
        '" fill="none" stroke="var(--line)" stroke-width="1"/>');
      /* Centred on the apex of its own arc. Down at the sector line it sat
         under whichever label was pinned to that edge of the box, and two
         pieces of text on top of each other is worse than a faint number
         crossing a line. */
      out.push('<text x="' + CX + '" y="' + (yAt(f) - SAG - 4) +
        '" fill="var(--dim)" opacity="0.7" font-size="10" text-anchor="middle">' +
        esc(meters) + ' m</text>');
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
      if (labels[i].y - labels[i - 1].y < 21) labels[i].y = labels[i - 1].y + 21;
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
      } else {
        /* Broken off the band: an arrow at the edge carrying its mark,
           rather than squashing the fight for second into an inch of
           sector to keep a runaway leader on the picture. */
        var ay = m.off === "far" ? TOP + 6 : BOTTOM - 6;
        out.push('<path d="M ' + (CX - 9) + " " + ay + " L " + CX + " " +
          (ay + (m.off === "far" ? -10 : 10)) + " L " + (CX + 9) + " " + ay +
          ' Z" fill="' + ink + '"/>');
      }
      out.push(pill(6, L.y, (m.label ? m.label + "  " : "") + m.name, ink, "start"));
      out.push(pill(W - 6, L.y, m.mark, ink, "end"));
      if (Math.abs(L.y - L.want) > 1.5) {
        out.push('<path d="M 96 ' + L.y + " L 120 " + L.want +
          '" stroke="' + ink + '" stroke-width="1" opacity="0.5" fill="none"/>');
      }
    });
    out.push("</svg>");
    return out.join("");
  }

  function pill(x, y, text, ink, anchor) {
    var w = String(text).length * 6.9 + 16;
    var rx = anchor === "end" ? x - w : x;
    return '<g><rect x="' + rx + '" y="' + (y - 11) + '" width="' + w +
      '" height="20" rx="4" fill="var(--bg)" stroke="' + ink +
      '" stroke-width="1"/><text x="' + (anchor === "end" ? x - 8 : x + 8) +
      '" y="' + (y + 4) + '" fill="' + ink + '" font-size="12.5" text-anchor="' +
      anchor + '">' + esc(text) + "</text></g>";
  }

  /* ---- the three views --------------------------------------------- */
  function liveView(c) {
    var f = c.flight || {};
    var calls = [["up", "Up", f.up], ["", "On deck", f.onDeck],
                 ["", "In the hole", f.inTheHole]]
      .filter(function (r) { return r[2]; })
      .map(function (r) {
        return '<div class="call ' + r[0] + '"><span>' + r[1] + "</span><b>" +
          esc(r[2]) + "</b></div>";
      }).join("");
    return '<div class="card angular"><div class="status"><b>' + esc(c.status) +
      '</b><span class="sub">' + esc(f.label || "") + "</span></div>" +
      (c.cut && c.cut.has && c.cut.mark
        ? '<div class="sub">Cut at ' + esc(c.cut.mark) + " for " +
          c.cut.advancing + "</div>"
        : "") +
      (calls ? '<div class="calls">' + calls + "</div>" : "") +
      '</div><div class="card angular">' + board(c.board) + "</div>";
  }

  function seriesView(c) {
    var field = c.places.slice().sort(function (a, b) { return a.order - b.order; });
    var flighted = c.places.some(function (q) { return q.flight; });
    var out = [], flight = null;
    field.forEach(function (p) {
      var f = p.flight || 1;
      if (flighted && f !== flight) {
        flight = f;
        out.push('<p class="heading">Flight ' + f + "</p>");
      }
      out.push('<div class="card angular"><div class="row"><span class="pl">' +
        esc(p.placeLabel) + '</span><span class="nm' + (p.tracked ? " mine" : "") +
        '">' + esc(p.name) + '</span><span class="bm' +
        (p.tracked ? " mine" : "") + (p.best ? metalOf(p.place) : "") + '">' +
        esc(p.best || "—") + "</span></div>" + boxes(c, p) + "</div>");
    });
    return out.join("") || '<p class="empty">Nobody entered yet.</p>';
  }

  function boxes(c, p) {
    var cells = p.series.map(function (a, i) {
      var out = !p.throwsInFinal && i >= c.prelims;
      if (!a) return '<div class="box' + (out ? " out" : "") + '">&nbsp;</div>';
      var cls = "box";
      if (a.kind === "foul") cls += " foul";
      if (a.kind === "pass") cls += " pass";
      if (a.mark && p.bestRound === i + 1) cls += " best";
      if (a.pb) cls += " pb";
      var text = a.short ? esc(a.short) : a.kind === "foul" ? "F" : "P";
      return '<div class="' + cls + '">' + text +
        (a.pb ? '<div class="tag">PB</div>' : "") + "</div>";
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
      return '<div class="row"><span class="pl' + metal + '">' +
        (p.best ? esc(p.place) : "–") +
        '</span><span class="nm' + (p.tracked ? " mine" : "") + '">' +
        esc(p.name) + '</span><span class="bm' +
        (p.tracked ? " mine" : "") + metal + '">' + esc(p.best || "—") +
        "</span></div>" + rule;
    }).join("");
    return rows ? '<div class="card angular">' + rows + "</div>"
                : '<p class="empty">Nothing thrown yet.</p>';
  }

  /* ---- painting ----------------------------------------------------- */
  function render() {
    if (!data) return;
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
