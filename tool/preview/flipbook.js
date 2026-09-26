// Plays the frames motion_preview.dart shot back as a page, at the speed
// they were shot at — a golden is a still, and an animation is only right
// or wrong in motion.
//
//   flutter test --update-goldens tool/preview/motion_preview.dart
//   node tool/preview/flipbook.js     # build/preview/motion/site/index.html
//
// It also flies the spectator's page through the same throws the app's
// board was shot through (motion/web/spectator.html, with the four feeds
// baked in), on Playwright's fake clock so a frame is exactly 40 ms of the
// page's own time — the two renderings are changed together, and this is
// how the motion half of that is looked at.
//
// The site it writes is self-contained: every frame as a JPEG, a frame
// held still written once rather than thirty times, and the page that
// plays them. Open it; each scene loops, with a quarter-speed toggle and a
// scrubber. It asserts nothing; looking at it is the review.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const chromium = (() => {
  for (const where of ['playwright', '/opt/node22/lib/node_modules/playwright',
    '/usr/lib/node_modules/playwright']) {
    try { return require(where).chromium; } catch (_) { /* next */ }
  }
  throw new Error('playwright not found. npm i -g playwright (the browser ' +
    'is already at $PLAYWRIGHT_BROWSERS_PATH; do not run "playwright install")');
})();

const dir = path.join(__dirname, '../../build/preview/motion');
const site = path.join(dir, 'site');
const scenes = JSON.parse(fs.readFileSync(path.join(dir, 'scenes.json'), 'utf8'));
const pad = (n) => String(n).padStart(3, '0');

/* The page's half of the flight: the same four feeds the app's board was
   shot over, each one landed by the page's own poll and flown on the fake
   clock. */
async function shootPage(browser) {
  const page = await browser.newPage({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));
  await page.clock.install({ time: new Date('2026-06-13T14:32:00Z') });
  await page.goto('file://' + path.join(dir, 'web/spectator.html'));
  // Stopped, so the page's time moves only when it is told to: left
  // running, a screenshot's own hundred milliseconds are page time too,
  // and the flight plays three times too fast.
  await page.clock.pauseAt(new Date('2026-06-13T14:32:05Z'));
  await page.clock.runFor(1500);
  await page.click('#watch button[data-clear]');
  await page.clock.runFor(400);
  const out = path.join(dir, 'page');
  fs.mkdirSync(out, { recursive: true });
  const feeds = await page.evaluate(() => FEEDS.length);
  const cuts = [];
  let frame = 0;
  const shoot = async () => {
    await page.screenshot({ path: path.join(out, pad(frame++) + '.png') });
  };
  for (let i = 0; i < 12; i++) await shoot();
  const captions = scenes.flight.cuts.map((c) => c.caption);
  for (let n = 1; n < feeds; n++) {
    await page.evaluate((n) => { window.__feed = n; }, n);
    // The poll that lands it — the same one a returning pocket gets.
    await page.evaluate(() =>
      document.dispatchEvent(new Event('visibilitychange')));
    cuts.push({ from: frame, caption: captions[n - 1] || '' });
    for (let at = 0; at <= 1520; at += 40) {
      await shoot();
      await page.clock.runFor(40);
    }
    for (let i = 0; i < 14; i++) await shoot();
  }
  await page.close();
  scenes.page = { step: 40, frames: frame, cuts };
}

/* Every frame as a JPEG, and one file per distinct picture: a scene that
   holds still for a second is thirty copies of one frame. */
async function pack(browser) {
  fs.rmSync(site, { recursive: true, force: true });
  fs.mkdirSync(site, { recursive: true });
  const page = await browser.newPage();
  await page.goto('file://' + dir + '/');
  const packed = {};
  for (const name of Object.keys(scenes)) {
    const seen = new Map();
    const list = [];
    fs.mkdirSync(path.join(site, name));
    for (let i = 0; i < scenes[name].frames; i++) {
      const file = path.join(dir, name, pad(i) + '.png');
      const bytes = fs.readFileSync(file);
      const hash = crypto.createHash('sha1').update(bytes).digest('hex');
      if (!seen.has(hash)) {
        const jpeg = await page.evaluate(async (b64) => {
          const img = new Image();
          img.src = 'data:image/png;base64,' + b64;
          await img.decode();
          // A phone's own width is plenty to judge motion by, and a page
          // of three hundred frames has to load on one.
          const scale = Math.min(1, 540 / img.naturalWidth);
          const c = document.createElement('canvas');
          c.width = Math.round(img.naturalWidth * scale);
          c.height = Math.round(img.naturalHeight * scale);
          const g = c.getContext('2d');
          g.imageSmoothingQuality = 'high';
          g.drawImage(img, 0, 0, c.width, c.height);
          return c.toDataURL('image/jpeg', 0.8).split(',')[1];
        }, bytes.toString('base64'));
        const out = name + '/' + pad(seen.size) + '.jpg';
        fs.writeFileSync(path.join(site, out), Buffer.from(jpeg, 'base64'));
        seen.set(hash, out);
      }
      list.push(seen.get(hash));
    }
    packed[name] = list;
    console.log(name + ': ' + list.length + ' frames, ' + seen.size + ' distinct');
  }
  await page.close();
  return packed;
}

const titles = {
  flight: ['The last throw, flown in',
    'The live board as three throws come in. The lines are where the ' +
    'competition stands; the flight and the divot are what just happened.'],
  best: ['A new personal best',
    'A throw becomes a best: the gold frame is traced out of the medal\'s ' +
    'corner, the medal drops in on its ribbon, and the light runs across it once.'],
  flask: ['The logo as a progress gauge',
    'Importing a clip. The flask fills by volume, eases onto each reading, ' +
    'and its surface moves only while readings arrive, so a stall looks still.'],
  page: ['The same flight, on the spectator page',
    'The page a parent opens off the QR, stepped through the same four ' +
    'states of the same competition. It flies the throw exactly as the app does.'],
};

(async () => {
const browser = await chromium.launch();
if (fs.existsSync(path.join(dir, 'web/spectator.html'))) await shootPage(browser);
const files = await pack(browser);
await browser.close();

const order = ['flask', 'flight', 'page', 'best'].filter((name) => scenes[name]);
const data = {};
for (const name of order) {
  data[name] = {
    step: scenes[name].step,
    files: files[name],
    cuts: scenes[name].cuts,
    title: titles[name][0],
    blurb: titles[name][1],
  };
}

// Written as the body of a page rather than a whole document: it is what
// gets published for somebody to look at on a phone, and the host wraps it.
// A browser opens it as it is.
const html = `<title>ThrowLab Motion</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow:wght@400;500;600;700&display=swap">
<style>
  :root {
    --bg: #eef2f4; --surface: #ffffff; --text: #10181c; --dim: #56656d;
    --accent: #006689; --line: #d2dbe0; --gold: #b07a10; --frame: #0e1417;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --bg: #0c1215; --surface: #151e23; --text: #dce4e8; --dim: #92a2ab;
      --accent: #7fd0f7; --line: #25313a; --gold: #f7b733;
    }
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --bg: #0c1215; --surface: #151e23; --text: #dce4e8; --dim: #92a2ab;
    --accent: #7fd0f7; --line: #25313a; --gold: #f7b733;
  }
  body { background: var(--bg); color: var(--text);
    font: 15px/1.5 Barlow, "Segoe UI", system-ui, sans-serif; }
  main { max-width: 1320px; margin: 0 auto; padding: 28px 16px 56px; }
  header { max-width: 62ch; display: grid; gap: 6px; margin-bottom: 26px; }
  .eyebrow { font-size: 12px; font-weight: 600; letter-spacing: 0.12em;
    text-transform: uppercase; color: var(--accent); }
  h1 { margin: 0; font-size: 30px; line-height: 1.15; font-weight: 700;
    text-wrap: balance; }
  header p { margin: 0; color: var(--dim); }
  .scenes { display: grid; gap: 18px;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 290px), 1fr)); }
  .scene { background: var(--surface); border: 1px solid var(--line);
    border-radius: 16px; padding: 14px; display: grid; gap: 10px;
    grid-template-columns: minmax(0, 1fr); align-content: start;
    min-width: 0; }
  .scene h2 { margin: 0; font-size: 17px; font-weight: 700; }
  .scene .what { margin: 0; color: var(--dim); font-size: 14px; min-height: 4.5em; }
  .frame { position: relative; overflow: hidden; border-radius: 12px;
    background: var(--frame); aspect-ratio: var(--ratio, 9 / 19.5);
    max-width: 100%; }
  .frame img { position: absolute; inset: 0; width: 100%; height: 100%;
    display: block; }
  .cap { margin: 0; min-height: 3em; font-size: 14px; font-weight: 500; }
  .controls { display: flex; gap: 8px; align-items: center; }
  .controls button { font: inherit; font-size: 13px; font-weight: 600;
    color: var(--text); background: transparent; cursor: pointer;
    border: 1px solid var(--line); border-radius: 999px; padding: 5px 12px; }
  .controls button[aria-pressed="true"] { border-color: var(--accent);
    color: var(--accent); }
  .controls button:focus-visible, .controls input:focus-visible {
    outline: 2px solid var(--accent); outline-offset: 2px; }
  .controls input { flex: 1; min-width: 0; accent-color: var(--accent); }
  .count { font-size: 12px; color: var(--dim);
    font-variant-numeric: tabular-nums; min-width: 6.5ch; text-align: right; }
  footer { margin-top: 26px; color: var(--dim); font-size: 13px; max-width: 70ch; }
  footer code { font-size: 12.5px; }
</style>
<main>
  <header>
    <span class="eyebrow">Branch claude/throwing-animations-art-7npgti</span>
    <h1>Four animations, rendered from the app</h1>
    <p>Every frame here was painted by the real widgets on the test clock and
      is played back at the speed it was shot. Tap ¼× to slow one down, or
      drag the bar to stop on a frame.</p>
  </header>
  <div class="scenes" id="scenes"></div>
  <footer>Regenerate with <code>flutter test --update-goldens
    tool/preview/motion_preview.dart</code> then
    <code>node tool/preview/flipbook.js</code>.</footer>
</main>
<script>
const SCENES = ${JSON.stringify(data)};
const ORDER = ${JSON.stringify(order)};
const root = document.getElementById('scenes');
const still = window.matchMedia &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

ORDER.forEach((name) => {
  const s = SCENES[name];
  const el = document.createElement('section');
  el.className = 'scene';
  el.innerHTML = '<h2></h2><p class="what"></p>' +
    '<div class="frame"><img alt=""></div><p class="cap" aria-live="off"></p>' +
    '<div class="controls">' +
    '<button type="button" id="play-' + name + '" aria-pressed="true">Pause</button>' +
    '<button type="button" id="slow-' + name + '" aria-pressed="false">¼×</button>' +
    '<input type="range" id="at-' + name + '" min="0" value="0" aria-label="Frame">' +
    '<span class="count"></span></div>';
  el.querySelector('h2').textContent = s.title;
  el.querySelector('.what').textContent = s.blurb;
  root.appendChild(el);
  const img = el.querySelector('img');
  const cap = el.querySelector('.cap');
  const count = el.querySelector('.count');
  const range = el.querySelector('input');
  const play = el.querySelector('#play-' + name);
  const slow = el.querySelector('#slow-' + name);
  const total = s.files.length;
  range.max = total - 1;
  img.alt = s.title;

  const frames = s.files.map((src) => {
    const im = new Image();
    im.src = src;
    return im;
  });
  frames[0].addEventListener('load', () => {
    el.querySelector('.frame').style.setProperty('--ratio',
      frames[0].naturalWidth + ' / ' + frames[0].naturalHeight);
  });

  let i = 0, playing = !still, speed = 1, last = 0, acc = 0;
  function show(n) {
    i = n;
    img.src = frames[i].src;
    range.value = i;
    count.textContent = (i + 1) + ' / ' + total;
    let text = '';
    s.cuts.forEach((c) => { if (i >= c.from && c.caption) text = c.caption; });
    cap.textContent = text;
  }
  function setPlaying(on) {
    playing = on;
    play.textContent = on ? 'Pause' : 'Play';
    play.setAttribute('aria-pressed', String(on));
  }
  function tick(now) {
    if (last && playing) acc += (now - last) * speed;
    last = now;
    while (playing && acc >= s.step) { acc -= s.step; show((i + 1) % total); }
    requestAnimationFrame(tick);
  }
  play.addEventListener('click', () => setPlaying(!playing));
  slow.addEventListener('click', () => {
    speed = speed === 1 ? 0.25 : 1;
    slow.setAttribute('aria-pressed', String(speed !== 1));
  });
  range.addEventListener('input', () => {
    setPlaying(false);
    show(Number(range.value));
  });
  setPlaying(playing);
  // Reduced motion opens on the moment each scene is about, paused.
  show(still ? Math.min(total - 1, (s.cuts[s.cuts.length - 1] || {from: 0}).from + 30) : 0);
  requestAnimationFrame(tick);
});
</script>
`;

fs.writeFileSync(path.join(site, 'index.html'), html);
console.log('wrote ' + path.join(site, 'index.html'));
})();
