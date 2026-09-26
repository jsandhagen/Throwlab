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
          const c = document.createElement('canvas');
          c.width = img.naturalWidth; c.height = img.naturalHeight;
          c.getContext('2d').drawImage(img, 0, 0);
          return c.toDataURL('image/jpeg', 0.84).split(',')[1];
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
  page: ['The same flight, on the spectator page',
    'The page a parent opens off the QR, stepped through the same four ' +
    'states of the same competition. It flies the throw exactly as the app does.'],
  sector: ['Between two sector lines',
    'The page transition. The next screen opens out of the circle, rests a ' +
    'moment at the real 34.92° sector, then fills the screen. Back closes it.'],
};

(async () => {
const browser = await chromium.launch();
if (fs.existsSync(path.join(dir, 'web/spectator.html'))) await shootPage(browser);
const files = await pack(browser);
await browser.close();

const order = ['flight', 'page', 'best', 'sector'].filter((name) => scenes[name]);
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

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ThrowLab Motion</title>
<style>
  :root { --bg: #0f1417; --card: #1b2226; --text: #dee3e7; --dim: #9aa4ab;
          --accent: #7fd0f7; --line: #2f3a40; }
  @media (prefers-color-scheme: light) {
    :root:not([data-theme="dark"]) { --bg: #f3f5f6; --card: #ffffff;
      --text: #161b1e; --dim: #5a656c; --accent: #006a8e; --line: #d5dbdf; }
  }
  :root[data-theme="light"] { --bg: #f3f5f6; --card: #ffffff;
    --text: #161b1e; --dim: #5a656c; --accent: #006a8e; --line: #d5dbdf; }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font: 15px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 1240px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  .lede { color: var(--dim); margin: 0 0 24px; max-width: 62ch; }
  .scenes { display: grid; gap: 20px;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); }
  .scene { background: var(--card); border: 1px solid var(--line);
    border-radius: 14px; padding: 14px; display: flex; flex-direction: column; }
  .scene h2 { font-size: 16px; margin: 0 0 4px; }
  .scene p { color: var(--dim); font-size: 13.5px; margin: 0 0 12px; }
  .frame { position: relative; border-radius: 10px; overflow: hidden;
    background: #000; aspect-ratio: var(--ratio); }
  .frame img { position: absolute; inset: 0; width: 100%; height: 100%;
    display: block; }
  .cap { min-height: 2.9em; margin: 10px 0 8px; font-size: 13.5px; }
  .controls { display: flex; gap: 8px; align-items: center; }
  .controls button { font: inherit; font-size: 13px; color: var(--text);
    background: transparent; border: 1px solid var(--line);
    border-radius: 999px; padding: 5px 12px; cursor: pointer; }
  .controls button[aria-pressed="true"] { border-color: var(--accent);
    color: var(--accent); }
  .controls input { flex: 1; min-width: 0; accent-color: var(--accent); }
</style>
</head>
<body>
<main>
  <h1>ThrowLab motion</h1>
  <p class="lede">Frames rendered from the app's own widgets on the test
    clock, played back at the speed they were shot at. Use ¼× to look at
    one moment, or drag the scrubber to stop on a frame.</p>
  <div class="scenes" id="scenes"></div>
</main>
<script>
const SCENES = ${JSON.stringify(data)};
const ORDER = ${JSON.stringify(order)};
const root = document.getElementById('scenes');

ORDER.forEach((name) => {
  const s = SCENES[name];
  const el = document.createElement('section');
  el.className = 'scene';
  el.innerHTML = '<h2></h2><p></p><div class="frame"><img alt=""></div>' +
    '<div class="cap"></div><div class="controls">' +
    '<button data-play aria-pressed="true">Pause</button>' +
    '<button data-slow aria-pressed="false">¼×</button>' +
    '<input type="range" min="0" value="0" aria-label="Frame"></div>';
  el.querySelector('h2').textContent = s.title;
  el.querySelector('p').textContent = s.blurb;
  root.appendChild(el);
  const img = el.querySelector('img');
  const cap = el.querySelector('.cap');
  const range = el.querySelector('input');
  const play = el.querySelector('[data-play]');
  const slow = el.querySelector('[data-slow]');
  const count = s.files.length;
  range.max = count - 1;

  const frames = s.files.map((src) => {
    const im = new Image();
    im.src = src;
    return im;
  });
  frames[0].onload = () => {
    el.querySelector('.frame').style.setProperty('--ratio',
      frames[0].naturalWidth + ' / ' + frames[0].naturalHeight);
  };

  let i = 0, playing = true, speed = 1, last = 0, acc = 0;
  function show(n) {
    i = n;
    img.src = frames[i].src;
    range.value = i;
    let text = '';
    s.cuts.forEach((c) => { if (i >= c.from && c.caption) text = c.caption; });
    cap.textContent = text;
  }
  function tick(now) {
    if (last) acc += (now - last) * speed;
    last = now;
    if (playing) {
      while (acc >= s.step) { acc -= s.step; show((i + 1) % count); }
    } else {
      acc = 0;
    }
    requestAnimationFrame(tick);
  }
  play.onclick = () => {
    playing = !playing;
    play.textContent = playing ? 'Pause' : 'Play';
    play.setAttribute('aria-pressed', String(playing));
  };
  slow.onclick = () => {
    speed = speed === 1 ? 0.25 : 1;
    slow.setAttribute('aria-pressed', String(speed !== 1));
  };
  range.oninput = () => {
    playing = false;
    play.textContent = 'Play';
    play.setAttribute('aria-pressed', 'false');
    show(Number(range.value));
  };
  show(0);
  requestAnimationFrame(tick);
});
</script>
</body>
</html>
`;

fs.writeFileSync(path.join(site, 'index.html'), html);
console.log('wrote ' + path.join(site, 'index.html'));
})();
