// Stands the app's three views of a competition next to the spectator
// page's three, at one size, on one competition.
//
//   flutter test --update-goldens tool/preview/share_preview.dart
//   node tool/preview/compare_share.js
//
// The first command writes the app's side (build/preview/app_*.png) and the
// page itself with a real feed baked into it (build/preview/spectator.html);
// this one opens that page in a browser at the same 390 x 844, shoots each
// tab, and composes the pairs into build/preview/compare_*.png.
//
// It exists because the screen and the page are two renderings of one
// competition and drift between them is invisible in a diff — every
// difference this feature has fixed was found by looking at these three
// files and none by reading the CSS. A check that only lives in somebody's
// shell history is not a check, which is why it is in the repo next to the
// preview it depends on.
//
// Nothing is asserted. The output is for looking at, exactly as the
// goldens beside it are.

const fs = require('fs');
const path = require('path');

// Playwright is not a dependency of this app — it is whatever the machine
// has, which on a fresh agent container is a global install.
const chromium = (() => {
  const tries = [
    'playwright',
    '/opt/node22/lib/node_modules/playwright',
    '/usr/lib/node_modules/playwright',
  ];
  for (const where of tries) {
    try {
      return require(where).chromium;
    } catch (_) {
      /* next */
    }
  }
  throw new Error(
    'playwright not found. npm i -g playwright (the browser is already at ' +
      '$PLAYWRIGHT_BROWSERS_PATH; do not run "playwright install")');
})();

const out = path.resolve(__dirname, '../../build/preview') + '/';
const views = ['live', 'series', 'standings'];

(async () => {
  for (const needed of ['spectator.html', ...views.map((v) => `app_${v}.png`)]) {
    if (!fs.existsSync(out + needed)) {
      throw new Error(
        `${needed} is missing — run the share preview first:\n` +
          '  flutter test --update-goldens tool/preview/share_preview.dart');
    }
  }

  const browser = await chromium.launch();
  // The phone the page is read on, at the ratio the app's goldens are shot
  // at, so a difference between the two is a difference and not a change of
  // canvas.
  const page = await browser.newPage({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,
  });
  // A page that dies on load still screenshots, as a blank one. Say so
  // rather than composing three pictures of nothing.
  page.on('pageerror', (e) => console.log('PAGE ERROR:', e.message));
  page.on('console', (m) => {
    if (m.type() === 'error') console.log('CONSOLE ERROR:', m.text());
  });

  await page.goto('file://' + out + 'spectator.html');
  await page.waitForTimeout(1200);
  for (const view of views) {
    await page.click(`button[data-tab="${view}"]`);
    await page.waitForTimeout(350);
    await page.screenshot({ path: `${out}web_${view}.png` });
  }

  // Composed in a browser rather than with an image library, because the
  // browser is already open and the app has no image dependency to add one
  // to. file:// images need a file:// page to sit on — an about:blank
  // origin is not allowed to load them.
  const pair = await browser.newPage({
    viewport: { width: 820, height: 900 },
    deviceScaleFactor: 2,
  });
  for (const view of views) {
    fs.writeFileSync(
      out + '_pair.html',
      `<style>
        body{margin:0;background:#222;font:12px system-ui;color:#ddd;display:flex;gap:8px;padding:8px}
        figure{margin:0}figcaption{padding:4px 2px;letter-spacing:1px;text-transform:uppercase}
        img{width:390px;display:block;border:1px solid #444}</style>
       <figure><figcaption>App — ${view}</figcaption><img src="app_${view}.png"></figure>
       <figure><figcaption>Shared page — ${view}</figcaption><img src="web_${view}.png"></figure>`);
    await pair.goto('file://' + out + '_pair.html');
    await pair.waitForTimeout(500);
    await pair.screenshot({ path: `${out}compare_${view}.png`, fullPage: true });
    console.log(`wrote build/preview/compare_${view}.png`);
  }
  fs.unlinkSync(out + '_pair.html');
  await browser.close();
})();
