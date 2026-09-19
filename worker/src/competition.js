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

    await this.state.storage.put('meta', next);
    // Every push pushes the expiry out with it. A competition still being
    // thrown is not one to clear up, and one that stopped an hour ago is
    // still worth the drive home.
    await this.state.storage.setAlarm(now + this.retentionHours * 3600 * 1000);
    return json(200, { ok: true, fingerprint: next.fingerprint });
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
   */
  async #state(request) {
    const meta = await this.state.storage.get('meta');
    if (!meta) return plain(404, 'Nothing here.');
    const tag = `"${meta.fingerprint}"`;
    if (request.headers.get('if-none-match') === tag) {
      return new Response(null, {
        status: 304,
        headers: readHeaders({ etag: tag, 'cache-control': 'no-store' }),
      });
    }
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
