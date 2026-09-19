export { Competition } from './competition.js';

/**
 * The relay a competition is shared through.
 *
 * The routes are the ones the phone used to answer on its own socket, kept
 * character for character — `/M/<token>`, `/state`, `/results.pdf`,
 * `/f/<weight>.ttf`, `/pb.png` — because the page builds every one of them
 * off its own `location.pathname`. A page that does not know whether it is
 * talking to a phone on the wifi or to this is a page with one code path,
 * and one code path is the only way the two can't drift.
 *
 * There is nothing here that understands a competition. It routes, it
 * checks the shape of a token, and it hands the rest to the Durable Object
 * holding what the phone last pushed.
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const parts = url.pathname.split('/').filter(Boolean);

    // /M/<token>[/...] and nothing else exists. Anything else is a 404
    // rather than a 403: a link that has stopped being shared should look
    // like a link that was never there.
    if (parts[0] !== 'M' || !isToken(parts[1])) return notFound();

    const rest = parts.slice(2);

    // The typeface, which is the one thing here that is the same for every
    // share and every competition. It rides under the token's path because
    // that is where the page asks for it, and it is a static file rather
    // than something the phone uploads: half a megabyte per share, pushed
    // over a coach's cellular connection, to send the same two files again.
    if (rest[0] === 'f') {
      if (rest.length !== 2 || !FONTS.has(rest[1])) return notFound();
      return env.ASSETS.fetch(new URL(`/f/${rest[1]}`, url));
    }

    const id = env.COMPETITION.idFromName(parts[1]);
    const stub = env.COMPETITION.get(id);

    // The route travels as a search parameter so the object does not have
    // to re-parse a path it has no other use for.
    const inner = new URL(url);
    inner.pathname = '/';
    inner.search = `?route=${encodeURIComponent(rest.join('/'))}`;
    return stub.fetch(new Request(inner, request));
  },
};

/** The two weights the page asks for, and no other path under `f/`. */
const FONTS = new Set(['r.ttf', 's.ttf']);

/**
 * The token's shape, checked before a Durable Object is named after it.
 *
 * `idFromName` will happily name an object after anything, so without this
 * every stray path on the hostname would spin one up. The alphabet is the
 * app's own — no 0/O or 1/I, because the token is printed under the QR for
 * the times it will not scan in the sun and a link dictated across a
 * sector cannot afford a character that reads two ways.
 */
const TOKEN = /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6,32}$/;

function isToken(value) {
  return typeof value === 'string' && TOKEN.test(value);
}

function notFound() {
  return new Response('Nothing here.', {
    status: 404,
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'x-robots-tag': 'noindex, nofollow',
      'referrer-policy': 'no-referrer',
    },
  });
}
