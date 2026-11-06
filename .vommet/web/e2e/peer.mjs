// Extra helpers for the feature matrix (features.mjs) on top of device.mjs:
// rooms with another person, media, emoji packs, and reading back what the
// web app sent (replies, edits, threads, reactions, redactions, files).
import zlib from 'node:zlib';
import { OtherDevice } from './device.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const waitFor = async (what, fn, ms = 60000) => {
  const end = Date.now() + ms;
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
    await sleep(250);
  }
};

/// A 16×16 PNG (one colour) for emoji, stickers and uploads.
export function png(r = 200, g = 60, b = 160) {
  // Built by hand: IHDR + one deflated IDAT + IEND.
  const w = 16, h = 16;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) raw.set([r, g, b], y * (w * 3 + 1) + 1 + x * 3);
  }
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => { let c = 0xffffffff; for (const x of buf) c = crcTable[(c ^ x) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

/// Every event in [roomId] this device can read (decrypted where possible).
export function events(dev, roomId) {
  return dev.client.getRoom(roomId)?.getLiveTimeline().getEvents() ?? [];
}

/// The first readable event in [roomId] matching [pred], sent by [sender]
/// (default: anyone but this device).
export async function waitEvent(dev, roomId, what, pred, ms = 60000) {
  return waitFor(what, async () => events(dev, roomId).find((ev) =>
    !ev.isBeingDecrypted() && !ev.isDecryptionFailure() && ev.getSender() && pred(ev)), ms);
}

export async function createRoom(dev, { name, encrypted, invite = [] }) {
  const { room_id: roomId } = await dev.client.createRoom({
    name,
    invite,
    preset: 'private_chat',
    initial_state: encrypted
      ? [{ type: 'm.room.encryption', state_key: '', content: { algorithm: 'm.megolm.v1.aes-sha2' } }]
      : [],
  });
  await waitFor(`room ${name} in sync`, async () => dev.client.getRoom(roomId));
  return roomId;
}

export async function join(dev, roomId) {
  await dev.client.joinRoom(roomId);
  await waitFor('joined', async () => dev.client.getRoom(roomId)?.getMyMembership() === 'join');
}

export async function upload(dev, data, name, type = 'image/png') {
  const r = await fetch(`${dev.hs}/_matrix/media/v3/upload?filename=${encodeURIComponent(name)}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${dev.token}`, 'Content-Type': type },
    body: data,
  });
  if (!r.ok) throw new Error(`upload: ${r.status} ${await r.text()}`);
  return (await r.json()).content_uri;
}

/// A room emoji pack (im.ponies.room_emotes, what the app reads) with one
/// image usable as emoji and sticker.
export async function addEmotePack(dev, roomId, shortcode, mxc) {
  await dev.client.sendStateEvent(roomId, 'im.ponies.room_emotes', {
    pack: { display_name: 'E2E pack', usage: ['emoticon', 'sticker'] },
    images: { [shortcode]: { url: mxc, body: shortcode, info: { w: 16, h: 16, mimetype: 'image/png' } } },
  }, 'e2e');
}

export { OtherDevice };
