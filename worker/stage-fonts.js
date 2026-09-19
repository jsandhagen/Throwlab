// Copies the app's own Barlow into the Worker's static assets. The
// typeface is `main.dart`'s to decide and `assets/fonts/` is where it
// lives, so this stages it rather than the repo carrying a second copy
// that can fall behind.
import { mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const fonts = join(here, '..', 'assets', 'fonts');
const out = join(here, 'public', 'f');

// Emptied first, not added to. `public/` is served to the internet whole,
// and a build that restores it from a cache rather than building it can
// carry a file nobody meant to publish — which is exactly what the first
// deploy did, reading three files where this writes two.
rmSync(join(here, 'public'), { recursive: true, force: true });
mkdirSync(out, { recursive: true });
for (const [name, file] of [
  ['r.ttf', 'Barlow-Regular.ttf'],
  ['s.ttf', 'Barlow-SemiBold.ttf'],
]) {
  copyFileSync(join(fonts, file), join(out, name));
}
console.log('staged Barlow into worker/public/f');
