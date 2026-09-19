/**
 * Durable Object storage takes 128 KiB in any one value, and two of the
 * things a share carries — the page and the results sheet — have no
 * guaranteed ceiling. The page is 47 KB today and a results sheet grows
 * with the field, so both are written as a run of numbered chunks rather
 * than left to fail on whichever meet first gets big enough.
 *
 * Chunked well under the limit: the cap is on the serialized value, and
 * guessing how much of it the wrapper costs is how you find out in
 * production.
 */
const CHUNK = 96 * 1024;

/** Writes `bytes` as `<prefix>:0…n`, and returns how many chunks that was. */
export async function putBlob(storage, prefix, bytes) {
  const chunks = {};
  let count = 0;
  for (let at = 0; at < bytes.length; at += CHUNK) {
    chunks[`${prefix}:${count++}`] = bytes.slice(at, at + CHUNK);
  }
  // An empty blob is no chunks, which reads back as an empty blob.
  if (count > 0) await storage.put(chunks);
  return count;
}

/** Reads back what [putBlob] wrote, or null if any of it has gone. */
export async function getBlob(storage, prefix, count) {
  if (!count) return null;
  const keys = [];
  for (let i = 0; i < count; i++) keys.push(`${prefix}:${i}`);
  const held = await storage.get(keys);
  let total = 0;
  for (const key of keys) {
    const part = held.get(key);
    if (!part) return null;
    total += part.byteLength ?? part.length;
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const key of keys) {
    const part = new Uint8Array(held.get(key));
    out.set(part, at);
    at += part.length;
  }
  return out;
}

/** Deletes a run of chunks. */
export async function deleteBlob(storage, prefix, count) {
  if (!count) return;
  const keys = [];
  for (let i = 0; i < count; i++) keys.push(`${prefix}:${i}`);
  await storage.delete(keys);
}
