/// The page a spectator gets, served whole by [MeetServer].
///
/// One file, no fetches of its own beyond the meet's own state: there is no
/// internet at a track, so a page that reaches for a font or a script on a
/// CDN is a page that renders as nothing in exactly the place it is wanted.
/// The type is whatever the phone already has, for the same reason the app
/// bundles Barlow rather than fetching it.
///
/// It knows nothing about throwing. Places, the cut, the flight in the
/// ring, the band of the sector worth drawing and every mark's spelling all
/// arrive decided from `meetFeed` — the page lays out answers. That is what
/// keeps it from becoming a second, disagreeing implementation of a
/// competition, and it is why switching tabs or events costs no request:
/// the whole meet is already here.
const String spectatorPage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="color-scheme" content="dark">
<title>ThrowLab</title>
<style>
  :root {
    --bg: #0d1214; --surface: #161d20; --raised: #1e272b; --line: #2b353b;
    --text: #e6edf0; --dim: #93a3ab; --accent: #4fc3f7; --gold: #e8c468;
    --bad: #ef6b6b; --pad: 16px;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--bg); color: var(--text); }
  body {
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    font-size: 15px; line-height: 1.4;
    padding: 0 var(--pad) calc(var(--pad) + env(safe-area-inset-bottom));
    max-width: 720px; margin: 0 auto;
    -webkit-text-size-adjust: 100%;
  }
  h1 { font-size: 21px; margin: 0; letter-spacing: 0.2px; }
  header { padding: 18px 0 10px; }
  .sub { color: var(--dim); font-size: 13px; }
  .age { display: flex; align-items: center; gap: 6px; font-size: 12px;
         color: var(--dim); margin-top: 6px; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--accent); }
  .age.stale .dot { background: var(--bad); }
  .age.stale { color: var(--bad); }

  /* A row of events, and a row of views. Both scroll sideways rather than
     wrapping: a meet with four competitions on it should not push the
     board off the bottom of a phone before it is drawn. */
  .strip { display: flex; gap: 8px; overflow-x: auto; padding-bottom: 10px;
           scrollbar-width: none; }
  .strip::-webkit-scrollbar { display: none; }
  .chip { flex: 0 0 auto; padding: 7px 13px; border-radius: 999px;
          border: 1px solid var(--line); background: var(--surface);
          color: var(--dim); font: inherit; font-size: 13px; cursor: pointer; }
  .chip[aria-pressed="true"] { background: var(--accent); border-color: var(--accent);
                               color: #06181f; font-weight: 600; }
  .tabs { display: flex; gap: 4px; background: var(--surface); padding: 4px;
          border-radius: 12px; border: 1px solid var(--line); margin-bottom: 14px; }
  .tabs button { flex: 1; padding: 8px 4px; border: 0; border-radius: 9px;
                 background: transparent; color: var(--dim); font: inherit;
                 font-size: 13px; cursor: pointer; }
  .tabs button[aria-pressed="true"] { background: var(--raised); color: var(--text);
                                      font-weight: 600; }

  .card { background: var(--surface); border: 1px solid var(--line);
          border-radius: 14px; padding: 14px; margin-bottom: 12px; }
  .status { display: flex; justify-content: space-between; align-items: baseline;
            gap: 10px; margin-bottom: 4px; }
  .status b { font-size: 16px; }
  .calls { display: grid; gap: 8px; margin-top: 12px; }
  .call { display: flex; align-items: baseline; gap: 10px; }
  .call span { font-size: 11px; letter-spacing: 0.8px; color: var(--dim);
               min-width: 84px; text-transform: uppercase; }
  .call b { font-size: 17px; }
  .call.up b { color: var(--accent); }

  svg { display: block; width: 100%; height: auto; }

  .row { display: flex; align-items: center; gap: 10px; padding: 9px 0;
         border-top: 1px solid var(--line); }
  .row:first-child { border-top: 0; }
  .pl { min-width: 34px; color: var(--dim); font-variant-numeric: tabular-nums;
        font-size: 13px; }
  .nm { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis;
        white-space: nowrap; }
  .nm.mine { color: var(--accent); }
  .bm { font-variant-numeric: tabular-nums; font-weight: 600; }
  .gold { color: var(--gold); }
  .cut-rule { border-top: 1px dashed var(--accent); margin: 8px 0 0;
              padding-top: 6px; font-size: 11px; color: var(--accent);
              letter-spacing: 0.8px; text-transform: uppercase; }
  .heading { font-size: 11px; letter-spacing: 0.8px; color: var(--dim);
             text-transform: uppercase; margin: 16px 0 6px; }

  /* The series: six boxes across the full width, big enough to read at
     arm's length — the same split the app's own card uses. */
  .series { display: grid; grid-template-columns: repeat(6, 1fr); gap: 4px;
            margin-top: 8px; }
  .box { background: var(--raised); border-radius: 6px; padding: 6px 1px;
         text-align: center; font-size: 12px; font-variant-numeric: tabular-nums;
         min-height: 30px; white-space: nowrap; }
  .box.foul { color: var(--bad); }
  .box.pass { color: var(--dim); }
  .box.best { background: #253238; color: var(--text); font-weight: 600; }
  .box.pb { box-shadow: inset 0 0 0 1px var(--gold); }
  .box.out { opacity: 0.32; }
  .tag { font-size: 10px; color: var(--gold); letter-spacing: 0.5px; }

  .downloads { display: flex; flex-wrap: wrap; gap: 8px; margin: 18px 0 8px; }
  .downloads a { flex: 1 1 auto; text-align: center; text-decoration: none;
                 padding: 11px 14px; border-radius: 11px; font-size: 14px;
                 border: 1px solid var(--line); background: var(--surface);
                 color: var(--text); }
  .note { color: var(--dim); font-size: 12px; text-align: center; margin: 4px 0 0; }
  .empty { color: var(--dim); text-align: center; padding: 28px 10px; }
</style>
</head>
<body>
<header>
  <h1 id="meet">…</h1>
  <div class="sub" id="where"></div>
  <div class="sub" id="weather"></div>
  <div class="age" id="age"><i class="dot"></i><span id="ageText">connecting…</span></div>
</header>
<div class="strip" id="events"></div>
<div class="tabs" id="tabs">
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
  var data = null, eventId = null, tab = "live", etag = null;
  var lastAt = 0, failed = 0;

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function el(id) { return document.getElementById(id); }

  /* ---- the board -------------------------------------------------- */
  /* Everything about the scale has already been decided: which band of
     the sector, how far apart the marker lines are, and where each mark
     falls across it. All that is left here is drawing. */
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
  var INK = { first: "#e8c468", second: "#c2ced4", third: "#c08457",
              cut: "#4fc3f7", upNow: "#4fc3f7", mine: "#7bd88f" };

  function board(b) {
    if (!b || !b.marks.length) {
      return '<p class="empty">Nothing on the board yet.</p>';
    }
    var out = ['<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="The competition on the sector">'];
    out.push('<path d="' + wedge() + '" fill="#101a1e" stroke="#2b353b" stroke-width="1"/>');

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
      out.push('<path d="' + arc(f) + '" fill="none" stroke="#243036" stroke-width="1"/>');
      // Centred on the apex of its own arc. Down at the sector line it sat
      // under whichever label was pinned to that edge of the box, and two
      // pieces of text on top of each other is worse than a faint number
      // crossing a line.
      out.push('<text x="' + CX + '" y="' + (yAt(f) - SAG - 4) +
        '" fill="#5d6c74" font-size="10" text-anchor="middle">' +
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
      var dashed = m.line === "cut";
      if (!m.off) {
        out.push('<path d="' + arc(L.f) + '" fill="none" stroke="' + ink +
          '" stroke-width="2"' + (dashed ? ' stroke-dasharray="6 5"' : "") + '/>');
      } else {
        /* Broken off the band: an arrow at the edge carrying its mark,
           rather than squashing the fight for second into an inch of
           sector to keep a runaway leader on the picture. */
        var ay = m.off === "far" ? TOP + 6 : BOTTOM - 6;
        out.push('<path d="M ' + (CX - 9) + ' ' + ay + ' L ' + CX + ' ' +
          (ay + (m.off === "far" ? -10 : 10)) + ' L ' + (CX + 9) + ' ' + ay +
          ' Z" fill="' + ink + '"/>');
      }
      var left = (m.label ? m.label + "  " : "") + m.name;
      out.push(pill(6, L.y, left, ink, "start"));
      out.push(pill(W - 6, L.y, m.mark, ink, "end"));
      if (Math.abs(L.y - L.want) > 1.5) {
        out.push('<path d="M 96 ' + L.y + ' L 120 ' + L.want +
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
      '" height="20" rx="10" fill="#0d1214" stroke="' + ink +
      '" stroke-width="1"/><text x="' + (anchor === "end" ? x - 8 : x + 8) +
      '" y="' + (y + 4) + '" fill="' + ink + '" font-size="12.5" text-anchor="' +
      anchor + '">' + esc(text) + "</text></g>";
  }

  /* ---- the three views -------------------------------------------- */
  function liveView(c) {
    var f = c.flight || {};
    var calls = [["up", "Up", f.up], ["", "On deck", f.onDeck], ["", "In the hole", f.inTheHole]]
      .filter(function (r) { return r[2]; })
      .map(function (r) {
        return '<div class="call ' + r[0] + '"><span>' + r[1] + '</span><b>' +
          esc(r[2]) + "</b></div>";
      }).join("");
    return '<div class="card"><div class="status"><b>' + esc(c.status) +
      "</b><span class=\"sub\">" + esc(f.label || "") + "</span></div>" +
      '<div class="sub">' + esc(c.label) +
      (c.cut && c.cut.has && c.cut.mark
        ? " · cut at " + esc(c.cut.mark) + " for " + c.cut.advancing
        : "") + "</div>" +
      (calls ? '<div class="calls">' + calls + "</div>" : "") +
      "</div>" + '<div class="card">' + board(c.board) + "</div>";
  }

  function seriesView(c) {
    var field = c.places.slice().sort(function (a, b) { return a.order - b.order; });
    var out = [], flight = null;
    field.forEach(function (p) {
      var f = p.flight || 1;
      if (c.places.some(function (q) { return q.flight; }) && f !== flight) {
        flight = f;
        out.push('<p class="heading">Flight ' + f + "</p>");
      }
      out.push('<div class="card"><div class="row"><span class="pl">' +
        esc(p.placeLabel) + '</span><span class="nm' + (p.tracked ? " mine" : "") +
        '">' + esc(p.name) + '</span><span class="bm' +
        (p.place === 1 ? " gold" : "") + '">' + esc(p.best || "—") + "</span></div>" +
        boxes(c, p) + "</div>");
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
      return '<div class="row"><span class="pl">' + esc(p.placeLabel) +
        '</span><span class="nm' + (p.tracked ? " mine" : "") + '">' + esc(p.name) +
        "</span><span class=\"bm" + (p.place === 1 ? " gold" : "") + '">' +
        esc(p.best || "—") + "</span></div>" + rule;
    }).join("");
    return rows ? '<div class="card">' + rows + "</div>"
                : '<p class="empty">Nothing thrown yet.</p>';
  }

  /* ---- painting --------------------------------------------------- */
  function current() {
    if (!data || !data.competitions.length) return null;
    for (var i = 0; i < data.competitions.length; i++) {
      if (data.competitions[i].id === eventId) return data.competitions[i];
    }
    return data.competitions[0];
  }

  function render() {
    if (!data) return;
    el("meet").textContent = data.name;
    el("where").textContent = [data.date, data.venue].filter(Boolean).join(" · ");
    el("weather").textContent = data.conditions || "";

    var c = current();
    eventId = c ? c.id : null;

    el("events").innerHTML = data.competitions.length > 1
      ? data.competitions.map(function (k) {
          return '<button class="chip" data-event="' + esc(k.id) + '" aria-pressed="' +
            (k.id === eventId) + '">' + esc(k.label) + "</button>";
        }).join("")
      : "";

    Array.prototype.forEach.call(el("tabs").children, function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.tab === tab));
    });

    el("view").innerHTML = !c
      ? '<p class="empty">No events on this meet yet.</p>'
      : tab === "live" ? liveView(c)
      : tab === "series" ? seriesView(c)
      : standingsView(c);

    el("downloads").innerHTML = !c ? "" :
      '<a href="' + base + "/results.pdf?event=" + encodeURIComponent(c.id) +
      '">' + esc(c.label) + " sheet</a>" +
      (data.competitions.length > 1
        ? '<a href="' + base + '/results.pdf">Whole meet</a>' : "");
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

  /* ---- the wire --------------------------------------------------- */
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
  el("events").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-event]");
    if (!b) return;
    eventId = b.dataset.event;
    render();
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
