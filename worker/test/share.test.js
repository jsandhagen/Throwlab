import { env, runInDurableObject, listDurableObjectIds } from 'cloudflare:test';
import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../src/index.js';

/**
 * The relay half of sharing a competition.
 *
 * The phone works the competition out and pushes the answers; everything
 * here is about holding them and handing them back on the same routes the
 * phone used to answer on itself. So the tests are mostly about the two
 * things that are genuinely new: that a link is a read credential and
 * nothing more, and that a competition clears itself up.
 */

const TOKEN = 'K7M2PQ9R';
const KEY = 'a-long-write-key-that-never-leaves-the-phone';

const feed = (fingerprint = 'abc123') => ({
  fingerprint,
  feed: { meet: 'County Champs', label: 'Discus · 1 kg', asOf: '2026-06-13T14:00:00.000Z' },
});

function call(path, init) {
  return worker.fetch(new Request(`https://share.test${path}`, init), env);
}

function push(body, { token = TOKEN, key = KEY } = {}) {
  return call(`/M/${token}/state`, {
    method: 'PUT',
    headers: key ? { authorization: `Bearer ${key}` } : {},
    body: JSON.stringify(body),
  });
}

describe('the link', () => {
  it('is a 404 for anything that is not a share', async () => {
    expect((await call('/')).status).toBe(404);
    expect((await call('/M')).status).toBe(404);
    // Lower case, and the characters the alphabet leaves out precisely so
    // a token read out across a sector cannot be heard two ways.
    expect((await call('/M/k7m2pq9r')).status).toBe(404);
    expect((await call('/M/K0M2PQ9R')).status).toBe(404);
    expect((await call('/M/K1M2PQ9R')).status).toBe(404);
    expect((await call('/M/SHORT')).status).toBe(404);
  });

  it('names no object for a token it turned away', async () => {
    await call('/M/k7m2pq9r');
    await call('/M/../../etc/passwd');
    expect(await listDurableObjectIds(env.COMPETITION)).toHaveLength(0);
  });

  it('is a 404 before anything has been pushed to it', async () => {
    const answer = await call(`/M/${TOKEN}`);
    expect(answer.status).toBe(404);
    // A link nobody has claimed and a link that has expired read the same.
    expect(await answer.text()).toBe('Nothing here.');
  });

  it('keeps the field away from crawlers', async () => {
    await push({ ...feed(), page: '<!doctype html><p>hello' });
    const answer = await call(`/M/${TOKEN}`);
    expect(answer.headers.get('x-robots-tag')).toBe('noindex, nofollow');
    expect(answer.headers.get('referrer-policy')).toBe('no-referrer');
  });
});

describe('the write side', () => {
  it('refuses a push with no key at all', async () => {
    expect((await push(feed(), { key: null })).status).toBe(401);
  });

  it('lets the first phone claim the token and keep it', async () => {
    expect((await push(feed('one'))).status).toBe(200);
    expect((await push(feed('two'))).status).toBe(200);

    const answer = await call(`/M/${TOKEN}/state`);
    expect(answer.headers.get('etag')).toBe('"two"');
  });

  it('turns a second phone away rather than letting it overwrite', async () => {
    await push(feed('mine'));
    const other = await push(feed('theirs'), { key: 'some-other-key' });
    expect(other.status).toBe(409);

    // And the competition on the stand is untouched.
    expect((await call(`/M/${TOKEN}/state`)).headers.get('etag')).toBe('"mine"');
  });

  it('does not hand the key back to anybody who asks', async () => {
    await push(feed());
    const id = env.COMPETITION.idFromName(TOKEN);
    const stored = await runInDurableObject(
      env.COMPETITION.get(id), (_, state) => state.storage.get('meta'));
    // Hashed, so a dump of this object cannot publish to a stand.
    expect(stored.keyHash).not.toContain(KEY);
    expect(stored.keyHash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('turns away a body that is not a competition', async () => {
    expect((await push({ nope: true })).status).toBe(400);
    const raw = await call(`/M/${TOKEN}/state`, {
      method: 'PUT',
      headers: { authorization: `Bearer ${KEY}` },
      body: 'not json at all',
    });
    expect(raw.status).toBe(400);
  });

  it('is the only method that writes', async () => {
    await push(feed());
    for (const method of ['POST', 'DELETE', 'PATCH']) {
      expect((await call(`/M/${TOKEN}/state`, { method })).status).toBe(405);
    }
  });
});

describe('the read side', () => {
  beforeEach(async () => {
    await push({
      ...feed(),
      page: '<!doctype html><title>ThrowLab</title>',
      medal: btoa('\x89PNG-ish'),
      pdf: btoa('%PDF-1.4 pretend'),
    });
  });

  it('hands over the competition the phone worked out', async () => {
    const answer = await call(`/M/${TOKEN}/state`);
    expect(answer.status).toBe(200);
    expect(await answer.json()).toEqual(feed().feed);
    // Never in a spectator's history.
    expect(answer.headers.get('cache-control')).toBe('no-store');
  });

  it('costs a 304 while nothing is being thrown', async () => {
    const tag = (await call(`/M/${TOKEN}/state`)).headers.get('etag');
    const again = await call(`/M/${TOKEN}/state`, { headers: { 'if-none-match': tag } });
    expect(again.status).toBe(304);

    // And 200 again the moment a mark moves the fingerprint.
    await push(feed('moved'));
    expect((await call(`/M/${TOKEN}/state`, { headers: { 'if-none-match': tag } })).status)
      .toBe(200);
  });

  it('serves the page, the medal and the sheet', async () => {
    const page = await call(`/M/${TOKEN}`);
    expect(page.headers.get('content-type')).toBe('text/html; charset=utf-8');
    expect(await page.text()).toContain('ThrowLab');

    const medal = await call(`/M/${TOKEN}/pb.png`);
    expect(medal.headers.get('content-type')).toBe('image/png');

    const sheet = await call(`/M/${TOKEN}/results.pdf`);
    expect(sheet.headers.get('content-type')).toBe('application/pdf');
    expect(sheet.headers.get('content-disposition')).toContain('attachment');
  });

  it('names the sheet what the app named it, and no more than that', async () => {
    await push({ ...feed(), pdf: btoa('%PDF'), sheetName: 'County Champs Discus 1kg.pdf' });
    expect((await call(`/M/${TOKEN}/results.pdf`)).headers.get('content-disposition'))
      .toBe('attachment; filename="County Champs Discus 1kg.pdf"');

    // A name that has been over a wire is not the app's any more: a quote
    // or a newline in here is a header somebody else wrote.
    await push({ ...feed(), pdf: btoa('%PDF'), sheetName: 'x"\r\nSet-Cookie: a=b' });
    expect((await call(`/M/${TOKEN}/results.pdf`)).headers.get('content-disposition'))
      .toBe('attachment; filename="xSet-Cookie ab"');
  });

  it('holds the page and the sheet while the feed moves under them', async () => {
    // A round is entered: the feed changes and 47 KB of unchanged HTML
    // does not come with it.
    await push(feed('round-two'));
    expect(await (await call(`/M/${TOKEN}`)).text()).toContain('ThrowLab');
    expect((await call(`/M/${TOKEN}/results.pdf`)).status).toBe(200);
  });

  it('carries a page far bigger than one stored value', async () => {
    // The real page is 47 KB and a results sheet grows with the field;
    // both are chunked, so neither has a cliff to fall off.
    const big = 'x'.repeat(400 * 1024);
    await push({ ...feed(), page: `<!doctype html>${big}` });
    const page = await call(`/M/${TOKEN}`);
    expect((await page.text()).length).toBe(big.length + 15);
  });

  it('says there is no sheet yet rather than pretending one failed', async () => {
    const fresh = await push(feed(), { token: 'W4X5Y6Z7' });
    expect(fresh.status).toBe(200);
    expect((await call('/M/W4X5Y6Z7/results.pdf')).status).toBe(404);
  });

  it('serves the app’s own typeface and nothing else under it', async () => {
    expect((await call(`/M/${TOKEN}/f/r.ttf`)).status).toBe(200);
    expect((await call(`/M/${TOKEN}/f/s.ttf`)).status).toBe(200);
    expect((await call(`/M/${TOKEN}/f/../../secret`)).status).toBe(404);
    expect((await call(`/M/${TOKEN}/f/Barlow-Bold.ttf`)).status).toBe(404);
  });

  it('turns away a route that is not one of the five', async () => {
    expect((await call(`/M/${TOKEN}/admin`)).status).toBe(404);
    expect((await call(`/M/${TOKEN}/state/../meta`)).status).toBe(404);
  });
});

describe('retention', () => {
  it('clears the competition up once its time is out', async () => {
    await push({ ...feed(), page: '<p>x', pdf: btoa('%PDF') });
    expect((await call(`/M/${TOKEN}/state`)).status).toBe(200);

    const stub = env.COMPETITION.get(env.COMPETITION.idFromName(TOKEN));
    await runInDurableObject(stub, (instance) => instance.alarm());

    // Everything, not just the feed: a field of names is the part that
    // should not still be here next week.
    expect((await call(`/M/${TOKEN}/state`)).status).toBe(404);
    expect((await call(`/M/${TOKEN}`)).status).toBe(404);
    expect((await call(`/M/${TOKEN}/results.pdf`)).status).toBe(404);
  });

  it('pushes the expiry out with every push', async () => {
    await push(feed('one'));
    const stub = env.COMPETITION.get(env.COMPETITION.idFromName(TOKEN));
    const first = await runInDurableObject(stub, (_, state) => state.storage.getAlarm());

    await new Promise((r) => setTimeout(r, 5));
    await push(feed('two'));
    const second = await runInDurableObject(stub, (_, state) => state.storage.getAlarm());

    // A competition still being thrown is not one to clear up.
    expect(second).toBeGreaterThan(first);
  });
});

/**
 * Following a set of athletes, which is the one question a spectator's
 * browser asks of its own.
 *
 * Answering it means working the competition out again around whoever was
 * ticked, and that only ever happens on the phone. So this half is a
 * post box: it writes down the sets being asked for, hands them back to
 * the phone, and files what comes up against the set that asked. Nothing
 * here knows what a cut is.
 */
describe('following a set', () => {
  /** A competition with a field in it, which is what a set is picked out of. */
  const field = (fingerprint = 'base1') => ({
    fingerprint,
    feed: {
      meet: 'County Champs',
      asOf: '2026-06-13T14:00:00.000Z',
      caption: [{ text: 'Achebe leads on 51.20 m', tone: 'body' }],
      places: [
        { place: 1, key: 'e1', name: 'Achebe', mine: false },
        { place: 2, key: 'e2', name: 'Sandhagen', mine: false },
        { place: 3, key: 'e3', name: 'Okonkwo', mine: false },
      ],
    },
  });

  /** What the phone pushes back for a set: what it adds to the base. */
  const answerFor = (key, fingerprint) => ({
    [key]: {
      fingerprint,
      delta: {
        set: {
          caption: [{ text: 'Sandhagen needs 48.00 m to make the final', tone: 'accent' }],
          following: [{ key: 'e2', name: 'Sandhagen' }],
        },
        // A row by the fields that moved, not the row over again: `mine`
        // turning over is a handful of bytes where the row is five hundred.
        places: { 1: { set: { mine: true }, drop: ['place'] } },
      },
    },
  });

  const wanted = (key = KEY) =>
    call(`/M/${TOKEN}/wanted`, { headers: key ? { authorization: `Bearer ${key}` } : {} });

  beforeEach(async () => {
    await push(field());
  });

  it('writes down the set a poll asked for and tells the phone', async () => {
    await call(`/M/${TOKEN}/state?f=e2`);

    // On the route the phone asks on between rounds...
    const asked = await (await wanted()).json();
    expect(asked.wanted).toContain('e2');
    expect(asked.reading).toBe(true);
    // ...and on the answer to the push it was making anyway.
    expect((await (await push(field('base2'))).json()).wanted).toContain('e2');
  });

  it('files one question under one name however it was asked', async () => {
    await call(`/M/${TOKEN}/state?f=e3,e1`);
    await call(`/M/${TOKEN}/state?f=e1,e3`);
    await call(`/M/${TOKEN}/state?f=e1,,e3,e1`);

    // Sorted and deduplicated at both ends, so two spectators who ticked
    // the same two names in a different order are answered once.
    const held = (await (await wanted()).json()).wanted;
    expect(held.filter((key) => key.includes('e1') || key.includes('e3')))
      .toEqual(['e1,e3']);
  });

  it('keeps the tick alive while the answer is still coming', async () => {
    const answer = await call(`/M/${TOKEN}/state?f=e2`);
    const read = await answer.json();

    // The competition is still the competition — nobody has worked it out
    // around e2 yet. What it carries is the echo, because the page drops
    // anybody the answer comes back without and would otherwise untick the
    // name under the finger that ticked it.
    expect(read.following).toEqual([{ key: 'e2', name: 'Sandhagen' }]);
    expect(read.places[1].mine).toBe(false);
    // And a tag of its own, so the board changes the moment it arrives.
    expect(answer.headers.get('etag')).not.toBe('"base1"');
  });

  it('hands over the answer once the phone has pushed it', async () => {
    await call(`/M/${TOKEN}/state?f=e2`);
    await push({ ...field('base2'), overlays: answerFor('e2', 'mine2') });

    const answer = await call(`/M/${TOKEN}/state?f=e2`);
    const read = await answer.json();
    expect(read.places[1].mine).toBe(true);
    expect(read.places[1].name).toBe('Sandhagen');
    expect(read.places[1]).not.toHaveProperty('place');
    expect(read.caption[0].tone).toBe('accent');
    expect(read.following).toEqual([{ key: 'e2', name: 'Sandhagen' }]);
    // Untouched where the set makes no difference: this is one competition
    // read two ways, not two competitions.
    expect(read.meet).toBe('County Champs');
    expect(read.places[0]).toEqual({ place: 1, key: 'e1', name: 'Achebe', mine: false });

    // Tagged with the fingerprint the phone took over the composition, so
    // a quiet round costs a 304 on this board rather than on the coach's.
    expect(answer.headers.get('etag')).toBe('"mine2"');
    const again = await call(`/M/${TOKEN}/state?f=e2`, {
      headers: { 'if-none-match': '"mine2"' },
    });
    expect(again.status).toBe(304);
  });

  it('leaves the coach\'s own reading exactly as it was', async () => {
    await push({ ...field('base2'), overlays: answerFor('e2', 'mine2') });

    const answer = await call(`/M/${TOKEN}/state`);
    expect(answer.headers.get('etag')).toBe('"base2"');
    expect((await answer.json()).places[1].mine).toBe(false);
  });

  it('stops serving a set the phone has stopped answering', async () => {
    await push({ ...field('base2'), overlays: answerFor('e2', 'mine2') });
    expect((await call(`/M/${TOKEN}/state?f=e2`)).headers.get('etag')).toBe('"mine2"');

    // The push carries the whole of what the phone stands behind, so an
    // answer left out of one is an answer withdrawn.
    await push({ ...field('base3'), overlays: {} });
    const answer = await call(`/M/${TOKEN}/state?f=e2`);
    expect(answer.headers.get('etag')).not.toBe('"mine2"');
    expect((await answer.json()).places[1].mine).toBe(false);
  });

  it('never holds an answer over a feed it was not taken from', async () => {
    await push({ ...field('base2'), overlays: answerFor('e2', 'mine2') });
    expect((await call(`/M/${TOKEN}/state?f=e2`)).headers.get('etag')).toBe('"mine2"');

    // An overlay is a subtraction from the feed directly above it — its
    // rows are that field, at that instant, by position. A push that says
    // nothing about them is a feed with no answers yet, not a feed to go
    // on applying the last one to.
    await push(field('base3'));
    const answer = await call(`/M/${TOKEN}/state?f=e2`);
    expect(answer.headers.get('etag')).not.toBe('"mine2"');
    expect((await answer.json()).places[1]).toHaveProperty('place');
  });

  it('will not hand the followed sets to somebody holding the link', async () => {
    await call(`/M/${TOKEN}/state?f=e2`);
    // The link reads the competition. Who at this meet somebody cared
    // enough to tick is the coach's business and takes the key that writes.
    expect((await wanted(null)).status).toBe(401);
    expect((await wanted('some-other-key')).status).toBe(409);
  });

  it('bounds what a query string can leave behind', async () => {
    const many = Array.from({ length: 40 }, (_, i) => `e${i}`);
    await call(`/M/${TOKEN}/state?f=${many.join(',')}`);
    await call(`/M/${TOKEN}/state?f=${'x'.repeat(200)}`);
    for (let i = 0; i < 20; i++) await call(`/M/${TOKEN}/state?f=q${i}`);

    const held = (await (await wanted()).json()).wanted;
    // A bounded number of sets, each naming a bounded number of athletes,
    // and nothing at all for an id no entry could have.
    expect(held.length).toBeLessThanOrEqual(12);
    expect(held.some((key) => key.includes('x'.repeat(200)))).toBe(false);
    const biggest = held.reduce((most, key) => Math.max(most, key.split(',').length), 0);
    expect(biggest).toBeLessThanOrEqual(32);
  });

  it('refuses an answer it could never find again', async () => {
    await push({
      ...field('base2'),
      // Not the canonical spelling of its own set, so no poll would ever
      // look for it under this name.
      overlays: { 'e3,e1': { fingerprint: 'nope', delta: {} }, ...answerFor('e2', 'mine2') },
    });
    expect((await call(`/M/${TOKEN}/state?f=e1,e3`)).headers.get('etag')).not.toBe('"nope"');
    expect((await call(`/M/${TOKEN}/state?f=e2`)).headers.get('etag')).toBe('"mine2"');
  });
});
