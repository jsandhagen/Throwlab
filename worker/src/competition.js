import { putBlob, getBlob, deleteBlob } from './blob.js';

/**
 * One shared competition, held between the phone that is throwing it and
 * the people reading it.
 *
 * The phone is still where a competition is worked out — this holds the
 * answers it pushed and hands them to a browser, and it knows nothing
 * about countback, prelims or feet and inches. That is the same rule the
 * page is written under, one hop further along: a relay that understood
 * the competition would be a second implementation of it, free to
 * disagree with the coach's own screen.
 *
 * It is a Durable Object because the alternative is a cache with no owner.
 * A share is one competition being pushed by one phone and read by the
 * stand around it, which wants a single place that is always consistent
 * with itself rather than an eventually-consistent copy per edge.
 */
export class Competition {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    /* When somebody last read this competition, held in memory rather than
       in storage: a spectator polls every four seconds, and a stored write
       per poll per spectator is a lot of writing to answer a question
       whose whole use is 'is anybody out there'. Losing it to an eviction
       costs one slow beat on the phone before the next poll sets it
       again. */
    this.readAt = 0;
    /* The last feed parsed, kept against its fingerprint. A followed
       reading has to compose the base with an overlay, and re-parsing 15 KB
       for every spectator on every poll is the one cost this design adds
       to a round where nothing has happened. */
    this.parsed = null;
  }

  /** How long a competition outlives its last push, in hours. */
  get retentionHours() {
    return Number(this.env.RETENTION_HOURS ?? 12);
  }

  async fetch(request) {
    const url = new URL(request.url);
    const route = url.searchParams.get('route') ?? '';
    if (request.method === 'PUT' && route === 'state') return this.#push(request);
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return plain(405, 'GET only.');
    }
    switch (route) {
      case '':
        return this.#page();
      case 'state':
        return this.#state(request);
      case 'wanted':
        return this.#wanted(request);
      case 'results.pdf':
        return this.#sheet();
      case 'pb.png':
        return this.#medal();
      default:
        return plain(404, 'Nothing here.');
    }
  }

  /* ---- the write side, which is the whole of the new attack surface --- */

  /**
   * The phone pushing what it has just worked out.
   *
   * The token in the link is a *read* credential and nothing else — it is
   * printed under a QR and read out loud across a sector, so everybody at
   * the meet has it. Writing takes a second secret that never leaves the
   * phone, and the first push is what fixes it: whoever claims a token
   * holds it until it expires, and a second phone landing on the same one
   * is turned away to pick another rather than allowed to overwrite a
   * competition in progress.
   *
   * Stored as a hash. A dump of this object's storage should not hand
   * somebody the ability to publish to a stand.
   */
  async #push(request) {
    const offered = bearer(request);
    if (!offered) return plain(401, 'No key.');

    const meta = (await this.state.storage.get('meta')) ?? null;
    const hash = await sha256(offered);
    if (meta && !constantTimeEqual(meta.keyHash, hash)) {
      // Not 403: a token somebody else holds should look exactly like a
      // token that is already taken, because that is what it is.
      return plain(409, 'That link is taken.');
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return plain(400, 'Not JSON.');
    }
    if (!body || typeof body.fingerprint !== 'string' || typeof body.feed !== 'object') {
      return plain(400, 'A push carries a feed and its fingerprint.');
    }

    const now = Date.now();
    const next = {
      keyHash: hash,
      createdAt: meta?.createdAt ?? now,
      lastPushAt: now,
      fingerprint: body.fingerprint,
      pageChunks: meta?.pageChunks ?? 0,
      pdfChunks: meta?.pdfChunks ?? 0,
      hasMedal: meta?.hasMedal ?? false,
      sheetName: meta?.sheetName ?? 'results.pdf',
    };

    await this.state.storage.put('feed', new TextEncoder().encode(JSON.stringify(body.feed)));

    // The page, the sheet and the medal are pushed when they change and
    // held when they do not: the feed moves every round, and re-sending 47
    // KB of unchanged HTML behind it would be most of the share's traffic.
    if (typeof body.page === 'string') {
      await deleteBlob(this.state.storage, 'page', next.pageChunks);
      next.pageChunks = await putBlob(
        this.state.storage, 'page', new TextEncoder().encode(body.page));
    }
    if (typeof body.pdf === 'string') {
      await deleteBlob(this.state.storage, 'pdf', next.pdfChunks);
      next.pdfChunks = await putBlob(this.state.storage, 'pdf', base64(body.pdf));
    }
    if (typeof body.sheetName === 'string') next.sheetName = fileName(body.sheetName);
    if (typeof body.medal === 'string') {
      await this.state.storage.put('medal', base64(body.medal));
      next.hasMedal = true;
    }

    // The competition worked out again for each set of athletes somebody
    // at the ring asked to follow, as what each adds to the feed above.
    //
    // Replaced every push, and never held the way the page and the medal
    // are. Those are the same file until the app changes; an overlay is a
    // subtraction from the feed directly above it and means nothing
    // against any other — its rows are the field at that instant, by
    // position. So a push with none clears them rather than leaving them,
    // because what it is saying is that this feed has no answers yet.
    await this.state.storage.put('overlays', overlaysOf(body.overlays));

    await this.state.storage.put('meta', next);
    // Every push pushes the expiry out with it. A competition still being
    // thrown is not one to clear up, and one that stopped an hour ago is
    // still worth the drive home.
    await this.state.storage.setAlarm(now + this.retentionHours * 3600 * 1000);
    // The questions travel back on the answer to a push, which is the hop
    // the phone is already making every time somebody throws — see
    // #wanted for the other half, and for why there is a route at all.
    return json(200, {
      ok: true,
      fingerprint: next.fingerprint,
      ...(await this.#asking()),
    });
  }

  /** Retention: the competition clears itself up rather than waiting to be asked. */
  async alarm() {
    await this.state.storage.deleteAll();
  }

  /* ---- the read side, which is what the link reaches ------------------ */

  async #page() {
    const meta = await this.state.storage.get('meta');
    const held = await getBlob(this.state.storage, 'page', meta?.pageChunks);
    if (!held) return plain(404, 'Nothing here.');
    return new Response(held, {
      status: 200,
      headers: readHeaders({
        'content-type': 'text/html; charset=utf-8',
        // It changes when the app that pushed it does, which a spectator's
        // browser has no way to know.
        'cache-control': 'no-store',
      }),
    });
  }

  /**
   * The competition itself, with the ETag the phone worked out.
   *
   * The tag is the fingerprint the app already took over the feed without
   * its clock, so a quiet round between throws costs a 304 and not 15 KB —
   * exactly as it did when the phone was answering the poll directly.
   *
   * `?f=` is who the person reading it came to watch, and it is the one
   * thing on this hop that is not simply held and handed back. The phone
   * serving its own socket could work the competition out again around
   * them inside the request; there is no phone at the other end of this
   * one. So the question is *recorded* — see #remember — the phone is told
   * what is being asked the next time it pushes, and what comes back is
   * filed here against the set that asked it. Reading it is then the same
   * hand-over as ever: the base, with that set's answer applied.
   *
   * Nothing here works anything out. Applying a delta is arithmetic on
   * data that arrived already decided, and a relay that decided any of it
   * would be the second implementation of a competition this whole feature
   * exists to avoid.
   */
  async #state(request) {
    const meta = await this.state.storage.get('meta');
    if (!meta) return plain(404, 'Nothing here.');

    const url = new URL(request.url);
    const asked = followingKey(url.searchParams.get('f'));
    // Somebody is out there. Worth knowing on the phone, which polls this
    // object faster while a stand is reading it than while nobody is.
    this.readAt = Date.now();
    if (asked) await this.#remember(asked);

    // Nobody followed: the coach's own reading, handed over as the bytes
    // that arrived. This is the path the parity check runs on and it is
    // untouched — no parse, no compose, no copy.
    if (!asked) return this.#served(request, `"${meta.fingerprint}"`);

    const overlays = (await this.state.storage.get('overlays')) ?? {};
    const held = overlays[asked];
    if (held) {
      // The answer for this set, tagged with the fingerprint the phone
      // took over the composition — so a spectator between rounds gets a
      // 304 on their own board rather than on somebody else's.
      const tag = `"${held.fingerprint}"`;
      if (request.headers.get('if-none-match') === tag) return notModified(tag);
      const base = await this.#feed(meta);
      if (!base) return plain(404, 'Nothing here.');
      return served(JSON.stringify(applyDelta(base, held.delta)), tag);
    }

    // Asked for, and not answered yet — a set somebody has just this
    // moment ticked, whose answer is on a phone that has not pushed since.
    // The competition is the competition, so it goes out as the coach's
    // own reading; what is added is the echo of who was asked for, because
    // the page drops anybody the answer comes back without and would
    // otherwise untick the name under the finger that ticked it. One push
    // later it is their board.
    const base = await this.#feed(meta);
    if (!base) return plain(404, 'Nothing here.');
    const tag = `"${meta.fingerprint}~${short(asked)}"`;
    if (request.headers.get('if-none-match') === tag) return notModified(tag);
    return served(JSON.stringify({ ...base, following: echo(base, asked) }), tag);
  }

  /** The stored feed as it was pushed, answered conditionally. */
  async #served(request, tag) {
    if (request.headers.get('if-none-match') === tag) return notModified(tag);
    const feed = await this.state.storage.get('feed');
    if (!feed) return plain(404, 'Nothing here.');
    return new Response(feed, {
      status: 200,
      headers: readHeaders({
        'content-type': 'application/json; charset=utf-8',
        etag: tag,
        // Never in a spectator's history.
        'cache-control': 'no-store',
      }),
    });
  }

  /**
   * The stored feed, parsed, kept against the push it came in on.
   *
   * Against the push and not the fingerprint: the fingerprint is taken
   * without the clock, so two pushes a moment apart with nothing thrown
   * between them share one — and serving the earlier `asOf` to whoever is
   * following somebody, while the coach's own reading carried the later
   * one, is the page telling two people different things about how old the
   * board in front of them is.
   */
  async #feed(meta) {
    if (this.parsed && this.parsed.at === meta.lastPushAt) return this.parsed.feed;
    const held = await this.state.storage.get('feed');
    if (!held) return null;
    try {
      const feed = JSON.parse(new TextDecoder().decode(held));
      this.parsed = { at: meta.lastPushAt, feed };
      return feed;
    } catch {
      return null;
    }
  }

  /**
   * What is being asked of this competition, for the phone that can answer
   * it.
   *
   * A push carries this back on its own, which covers every afternoon
   * where somebody is throwing. This route is for the gaps: a spectator
   * who ticks a name while the field is walking back from the sector would
   * otherwise wait for the next mark to be entered before the board became
   * theirs. It is a few hundred bytes and the phone asks for it on a
   * clock.
   *
   * Behind the write key. The sets being followed are a list of who at
   * this meet somebody cared enough to tick, which is nobody's business
   * but the coach's.
   */
  async #wanted(request) {
    const offered = bearer(request);
    if (!offered) return plain(401, 'No key.');
    const meta = await this.state.storage.get('meta');
    if (!meta) return plain(404, 'Nothing here.');
    if (!constantTimeEqual(meta.keyHash, await sha256(offered))) {
      return plain(409, 'That link is taken.');
    }
    return json(200, { ok: true, ...(await this.#asking()) });
  }

  /**
   * The sets worth answering, and whether anybody is reading at all.
   *
   * `reading` is what the phone paces itself off: a competition with a
   * stand on it is worth asking after every few seconds, and one nobody
   * has opened is worth a minute. It is the live half of the same
   * question, so it rides with the sets rather than in a route of its own.
   */
  async #asking() {
    const wanted = (await this.state.storage.get('wanted')) ?? {};
    const fresh = Date.now() - WANTED_TTL;
    const keys = Object.keys(wanted)
      .filter((key) => wanted[key] > fresh)
      .sort((a, b) => wanted[b] - wanted[a])
      .slice(0, WANTED_KEEP);
    return { wanted: keys, reading: Date.now() - this.readAt < READING_WINDOW };
  }

  /**
   * A set somebody is following, written down so the phone can be told.
   *
   * Written rarely on purpose. A spectator polls every four seconds and
   * the answer to 'is this still being followed' does not change between
   * two of them, so a set already recorded inside [ASK_REFRESH] costs
   * nothing at all; what is left is one write when somebody ticks, and one
   * a minute to say they are still there.
   *
   * Capped and aged out, because the keys arrive off a query string: this
   * is the one place a stranger with the link can put something into
   * storage, and what they can put is a bounded number of bounded strings
   * that stop being held once nobody is asking for them.
   */
  async #remember(key) {
    const now = Date.now();
    const wanted = (await this.state.storage.get('wanted')) ?? {};
    if (wanted[key] && now - wanted[key] < ASK_REFRESH) return;
    wanted[key] = now;
    const fresh = now - WANTED_TTL;
    const kept = {};
    for (const held of Object.keys(wanted)
      .filter((k) => wanted[k] > fresh)
      .sort((a, b) => wanted[b] - wanted[a])
      .slice(0, WANTED_KEEP)) {
      kept[held] = wanted[held];
    }
    await this.state.storage.put('wanted', kept);
  }

  async #sheet() {
    const meta = await this.state.storage.get('meta');
    const held = await getBlob(this.state.storage, 'pdf', meta?.pdfChunks);
    // A competition whose sheet has not been pushed yet is not an error —
    // it is a meet that has not finished. The page hides the action.
    if (!held) return plain(404, 'No sheet yet.');
    return new Response(held, {
      status: 200,
      headers: readHeaders({
        'content-type': 'application/pdf',
        'content-disposition': `attachment; filename="${meta.sheetName ?? 'results.pdf'}"`,
        'cache-control': 'no-store',
      }),
    });
  }

  /**
   * The personal-best medal, struck by the app's own painter and pushed as
   * pixels.
   *
   * Not drawn here and not ported to SVG: every number in the Dart
   * painter is measured off a reference, and a badge that is nearly right
   * is worse than none. It is two kilobytes and it changes when the app
   * does, so the phone sends it with the page.
   */
  async #medal() {
    const held = await this.state.storage.get('medal');
    if (!held) return plain(404, 'No medal here.');
    return new Response(held, {
      status: 200,
      headers: readHeaders({
        'content-type': 'image/png',
        'cache-control': 'max-age=86400',
      }),
    });
  }
}

/* ---- small shared pieces ---------------------------------------------- */

/**
 * How many athletes one followed set may name, and how many sets are held
 * at once.
 *
 * Both are bounds on what a stranger holding the link can ask a coach's
 * phone to work out. A field is ticked out of a list, so neither bites on
 * anything the page itself sends; a query string written by hand is what
 * they are here for.
 */
const MAX_FOLLOWED = 32;
const WANTED_KEEP = 12;

/** How long a set goes on being answered after the last poll asked for it. */
const WANTED_TTL = 10 * 60 * 1000;

/** How often a set already being followed is written down again. */
const ASK_REFRESH = 60 * 1000;

/** How recently the competition must have been read to count as watched. */
const READING_WINDOW = 2 * 60 * 1000;

/** The most the answers for every followed set may come to, in bytes. */
const MAX_OVERLAYS = 96 * 1024;

/**
 * A followed set as both ends name it: sorted, deduplicated, capped.
 *
 * The same rule as `followingKey` in the app, and it has to be — the phone
 * files its answers under this and a poll finds them under this, so a
 * disagreement here is a competition worked out and then never handed to
 * the person who asked for it.
 */
function followingKey(value) {
  if (!value) return '';
  const ids = [];
  for (const raw of String(value).split(',')) {
    const id = raw.trim();
    if (!id || id.length > 64 || ids.includes(id)) continue;
    ids.push(id);
  }
  return ids.sort().slice(0, MAX_FOLLOWED).join(',');
}

/**
 * The base feed with one set's answer applied — see `feedDelta` in the
 * app, which is the half that works out what to send.
 *
 * A map is patched by the keys that moved, `places` is patched by the row,
 * and a row is patched the same way a map is. That is what following
 * somebody moves: their row and the coach's, the board, the caption, the
 * flight line — and inside a row, the two or three fields that hang off
 * whose it is.
 *
 * It is a patch applied to data, not a competition being worked out, which
 * is the only reason it is allowed to happen here at all.
 */
function applyDelta(feed, delta) {
  if (!delta || typeof delta !== 'object') return { ...feed };
  const out = patch(feed, delta);
  if (delta.places && typeof delta.places === 'object') {
    const rows = Array.isArray(out.places) ? out.places.slice() : [];
    for (const at of Object.keys(delta.places)) {
      const i = Number(at);
      if (!Number.isInteger(i) || i < 0 || i >= rows.length) continue;
      rows[i] = patch(rows[i], delta.places[at]);
    }
    out.places = rows;
  }
  return out;
}

/** One map, with the keys a delta sets set and the keys it drops gone. */
function patch(value, delta) {
  const out = { ...value };
  if (!delta || typeof delta !== 'object') return out;
  if (delta.set && typeof delta.set === 'object') {
    for (const key of Object.keys(delta.set)) out[key] = delta.set[key];
  }
  if (Array.isArray(delta.drop)) {
    for (const key of delta.drop) delete out[key];
  }
  return out;
}

/**
 * Which of an asked-for set the field actually holds, in the shape the
 * feed echoes them back in.
 *
 * Only ever used for a set the phone has not answered yet. The page drops
 * anybody missing from the echo — that is how somebody taken off the meet
 * stops being followed — so handing back nothing would untick a name the
 * moment it was ticked. Picking rows out of a list by their key is not
 * knowing anything about a competition.
 */
function echo(feed, key) {
  const wanted = key.split(',');
  const out = [];
  for (const place of Array.isArray(feed.places) ? feed.places : []) {
    if (place && wanted.includes(place.key)) out.push({ key: place.key, name: place.name });
  }
  return out;
}

/** The answers a push carried, checked for shape and bounded for size. */
function overlaysOf(offered) {
  if (!offered || typeof offered !== 'object' || Array.isArray(offered)) return {};
  const kept = {};
  let bytes = 0;
  for (const raw of Object.keys(offered)) {
    if (Object.keys(kept).length >= WANTED_KEEP) break;
    const key = followingKey(raw);
    // Filed under anything but its own canonical name, it could never be
    // found again — so it is not held.
    if (!key || key !== raw) continue;
    const held = offered[raw];
    if (!held || typeof held !== 'object') continue;
    if (typeof held.fingerprint !== 'string' || !held.delta || typeof held.delta !== 'object') {
      continue;
    }
    const entry = { fingerprint: held.fingerprint, delta: held.delta };
    bytes += JSON.stringify(entry).length + key.length;
    if (bytes > MAX_OVERLAYS) break;
    kept[key] = entry;
  }
  return kept;
}

/** A short, stable stamp for a key that is too long to put in a header. */
function short(text) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(36);
}

function served(body, tag) {
  return new Response(body, {
    status: 200,
    headers: readHeaders({
      'content-type': 'application/json; charset=utf-8',
      etag: tag,
      'cache-control': 'no-store',
    }),
  });
}

function notModified(tag) {
  return new Response(null, {
    status: 304,
    headers: readHeaders({ etag: tag, 'cache-control': 'no-store' }),
  });
}

/**
 * Nothing served here is for a crawler, and a competition's field is a
 * list of names — most of them other people's athletes, and many of them
 * children. On a LAN this was belt and braces; on a public hostname it is
 * the point.
 */
function readHeaders(extra) {
  return {
    'x-robots-tag': 'noindex, nofollow',
    'referrer-policy': 'no-referrer',
    ...extra,
  };
}

function plain(status, body) {
  return new Response(body, {
    status,
    headers: readHeaders({ 'content-type': 'text/plain; charset=utf-8' }),
  });
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: readHeaders({ 'content-type': 'application/json; charset=utf-8' }),
  });
}

function bearer(request) {
  const header = request.headers.get('authorization') ?? '';
  const match = /^Bearer (.+)$/.exec(header);
  return match ? match[1] : null;
}

async function sha256(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Compared without leaking where it stopped matching. Both sides are
 * hex of a fixed length here, so length alone gives nothing away.
 */
function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * The sheet's own name, cut back to what a header will take.
 *
 * The app already strips it to what a file system will take, which is a
 * subset of this — but a name that arrives here has been over a wire, and
 * a quote or a newline in a `content-disposition` is a header somebody
 * else wrote. Trusting the other end to have done it is how that stops
 * being true.
 */
function fileName(name) {
  const clean = name.replace(/[^A-Za-z0-9 ._-]/g, '').trim().slice(0, 120);
  return clean.length > 0 ? clean : 'results.pdf';
}

function base64(text) {
  const binary = atob(text);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
