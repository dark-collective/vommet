// Vommet web: space and room avatars show their pictures. Seeds spaces, child
// spaces and rooms with avatars (PNG and JPEG, small to large), signs in, and
// counts each avatar's colours on screen: every avatar is two-tone (left half
// one colour, right half another, unique per room), so a letter placeholder
// or a solid black square doesn't pass. Checked on the space rail, a space's
// home (its child spaces) and the room list, after sign-in and after two page
// reloads.
//
//   node avatars.mjs <browser> <app url> <homeserver url> <out dir> [auto|wasm|js]
// Exit 1 if an avatar is black or still missing after the settle time.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { chromium, firefox } from 'playwright';
import { register } from './device.mjs';
import { OtherDevice, waitFor } from './peer.mjs';
import { skipTour } from './no-tour.mjs';

const [browserName = 'chromium', appUrl = 'http://127.0.0.1:8765/', hs = 'https://localhost', outDir = 'e2e-out',
  force = 'auto'] = process.argv.slice(2);
const hsName = new URL(hs).host;
const out = path.join(outDir, `${browserName}-avatars${force === 'auto' ? '' : `-${force}`}`);
fs.mkdirSync(out, { recursive: true });
const report = fs.createWriteStream(path.join(out, 'report.txt'));
const say = (...a) => {
  const line = `[${new Date().toISOString().slice(11, 23)}] ${a.join(' ')}`;
  process.stdout.write(line + '\n');
  report.write(line + '\n');
};
const PASSWORD = 'Correct-Horse-Battery-9';
const user = `avatars_${browserName}_${Date.now()}`;
// How long avatars get to appear after a view opens.
const SETTLE_MS = Number(process.env.AVATAR_SETTLE_MS ?? 20000);

// ---- Images ----

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

/// A w×h PNG, left half [a], right half [b] (RGB).
function twoTonePng(w, h, a, b) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    const row = y * (w * 3 + 1);
    for (let x = 0; x < w; x++) raw.set(x < w / 2 ? a : b, row + 1 + x * 3);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

let haveConvert = true;
function twoToneJpeg(w, h, a, b) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'avatar-'));
  try {
    fs.writeFileSync(path.join(tmp, 'a.png'), twoTonePng(w, h, a, b));
    execFileSync('convert', [path.join(tmp, 'a.png'), '-quality', '95', path.join(tmp, 'a.jpg')]);
    return fs.readFileSync(path.join(tmp, 'a.jpg'));
  } catch (e) {
    haveConvert = false;
    return null;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

/// Decodes a PNG screenshot (8-bit RGB or RGBA, not interlaced) to RGBA.
function decodePng(buf) {
  let p = 8; let w = 0; let h = 0; let ct = 0; const idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p); const type = buf.toString('ascii', p + 4, p + 8);
    const data = buf.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); ct = data[9]; if (data[8] !== 8 || data[12]) throw new Error('unsupported PNG'); }
    if (type === 'IDAT') idat.push(data);
    p += 12 + len;
  }
  const bpp = ct === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  const px = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) {
      const left = i >= bpp ? line[i - bpp] : 0; const up = prev[i]; const ul = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (f === 1) v += left;
      else if (f === 2) v += up;
      else if (f === 3) v += (left + up) >> 1;
      else if (f === 4) { const q = left + up - ul; const pa = Math.abs(q - left); const pb = Math.abs(q - up); const pc = Math.abs(q - ul); v += pa <= pb && pa <= pc ? left : pb <= pc ? up : ul; }
      line[i] = v & 0xff;
    }
    for (let x = 0; x < w; x++) {
      px[(y * w + x) * 4] = line[x * bpp]; px[(y * w + x) * 4 + 1] = line[x * bpp + 1]; px[(y * w + x) * 4 + 2] = line[x * bpp + 2];
      px[(y * w + x) * 4 + 3] = bpp === 4 ? line[x * bpp + 3] : 255;
    }
    prev = line;
  }
  return { w, h, px };
}

const near = (px, i, c, tol = 28) => Math.abs(px[i] - c[0]) <= tol && Math.abs(px[i + 1] - c[1]) <= tol && Math.abs(px[i + 2] - c[2]) <= tol;
/// Pixels close to [c] in the screenshot, optionally inside [box] (CSS px = screenshot px at scale 1).
function count(img, c, box) {
  const x0 = box ? Math.max(0, Math.floor(box.x)) : 0; const y0 = box ? Math.max(0, Math.floor(box.y)) : 0;
  const x1 = box ? Math.min(img.w, Math.ceil(box.x + box.width)) : img.w; const y1 = box ? Math.min(img.h, Math.ceil(box.y + box.height)) : img.h;
  let n = 0; let black = 0; let all = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = (y * img.w + x) * 4;
      all++;
      if (near(img.px, i, c)) n++;
      if (img.px[i] < 16 && img.px[i + 1] < 16 && img.px[i + 2] < 16) black++;
    }
  }
  return { n, black, all };
}

// Unique, saturated colour pairs (HSV, hue steps), far from greys and black.
function hsv(h, s = 0.85, v = 0.9) {
  const f = (n) => { const k = (n + h / 60) % 6; return Math.round(255 * (v - v * s * Math.max(0, Math.min(k, 4 - k, 1)))); };
  return [f(5), f(3), f(1)];
}

// What gets seeded: [name, kind, format, width, height]. Top-level spaces sit
// on the rail; "Avatar Hub" holds child spaces (its home lists them) and rooms.
const SPEC = [
  ['Avatar Hub', 'space', 'png', 512, 512],
  ['Space Jpeg', 'space', 'jpeg', 300, 300],
  ['Space Tiny', 'space', 'png', 48, 48],
  ['Space Huge', 'space', 'jpeg', 3000, 2000],
  ['Space Ninety', 'space', 'png', 96, 96],
  ['Space Tall', 'space', 'jpeg', 200, 400],
  ['Child Png', 'child', 'png', 256, 256],
  ['Child Jpeg', 'child', 'jpeg', 640, 480],
  ['Child Small', 'child', 'png', 64, 64],
  ['Child Large', 'child', 'jpeg', 2400, 2400],
  ...Array.from({ length: 14 }, (_, i) => [`Room ${String.fromCharCode(65 + i)}${String.fromCharCode(97 + i)}`, 'room',
    i % 2 ? 'jpeg' : 'png', [64, 96, 128, 256, 512, 1024, 1600][i % 7], [64, 96, 128, 256, 512, 1024, 1600][(i + 2) % 7]]),
];
const items = SPEC.map(([name, kind, format, w, h], i) => ({
  name, kind, format, w, h,
  a: hsv((i * 360 / SPEC.length) % 360), b: hsv((i * 360 / SPEC.length + 150) % 360, 0.9, 0.55),
}));

// ---- The browser ----

const consoleLog = fs.createWriteStream(path.join(out, 'console.txt'));
const media = [];
let phase = 'start';
const profile = fs.mkdtempSync(path.join(os.tmpdir(), `vommet-avatars-${browserName}-`));
let context;
let page;
const loaded = { wasm: false, js: false };
async function openBrowser() {
  const options = { ignoreHTTPSErrors: true, viewport: { width: 1280, height: 860 } };
  context = browserName === 'firefox'
    ? await firefox.launchPersistentContext(profile, {
      ...options,
      headless: !process.env.DISPLAY,
      firefoxUserPrefs: { 'webgl.force-enabled': true, 'webgl.disabled': false },
    })
    : await chromium.launchPersistentContext(profile, options);
  await skipTour(context);
  if (force === 'js') await context.addInitScript(() => { WebAssembly.validate = () => false; });
  if (force === 'wasm' && browserName !== 'chromium') {
    await context.route('**/flutter_bootstrap.js', async (route) => {
      const res = await route.fetch();
      const body = (await res.text()).replace('config: {', 'config: { wasmAllowList: { gecko: true },');
      await route.fulfill({ response: res, body });
    });
  }
  // What the browser's image decoding did (the engine decodes through <img>
  // where there is no ImageDecoder, i.e. outside Chromium).
  await context.addInitScript(() => {
    const s = { decodeOk: 0, decodeFail: [], bitmaps: 0, bitmapFail: [], imageDecoder: typeof window.ImageDecoder };
    window.__e2eImages = s;
    const dec = HTMLImageElement.prototype.decode;
    HTMLImageElement.prototype.decode = function (...a) {
      return dec.apply(this, a).then((v) => { s.decodeOk++; return v; },
        (e) => { s.decodeFail.push(`${e?.name}: ${e?.message} (${this.naturalWidth}x${this.naturalHeight})`); throw e; });
    };
    const cib = window.createImageBitmap;
    window.createImageBitmap = function (...a) {
      return cib.apply(this, a).then((v) => { s.bitmaps++; return v; },
        (e) => { s.bitmapFail.push(`${e?.name}: ${e?.message}`); throw e; });
    };
  });
  context.on('request', (r) => {
    if (/main\.dart\.wasm(\?|$)/.test(r.url())) loaded.wasm = true;
    if (/main\.dart\.(m?js)(\?|$)/.test(r.url())) loaded.js = true;
  });
  const isMedia = (u) => /\/_matrix\/(client\/v1|media\/v3)\/(media\/)?(download|thumbnail)\//.test(u);
  context.on('response', (r) => { if (isMedia(r.url())) media.push({ phase, status: r.status(), url: r.url().replace(/^.*\/(download|thumbnail)\//, '$1/') }); });
  context.on('requestfailed', (r) => { if (isMedia(r.url())) media.push({ phase, status: 'failed', error: r.failure()?.errorText, url: r.url().replace(/^.*\/(download|thumbnail)\//, '$1/') }); });
  page = context.pages()[0] ?? (await context.newPage());
  page.on('console', (m) => consoleLog.write(`[${phase}] [${m.type()}] ${m.text()}\n`));
  page.on('pageerror', (e) => consoleLog.write(`[${phase}] [pageerror] ${e.stack || e}\n`));
}

let shotN = 0;
async function shot(name) {
  const f = path.join(out, `${String(++shotN).padStart(2, '0')}-${name}.png`);
  const buf = await page.screenshot({ path: f, timeout: 20000 });
  return decodePng(buf);
}

async function enableSemantics() {
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 180000 });
  const ph = page.locator('flt-semantics-placeholder');
  const tries = [
    () => page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()),
    () => ph.dispatchEvent('click'),
    async () => { await ph.focus(); await page.keyboard.press('Enter'); },
    () => ph.click({ force: true }),
  ];
  for (let i = 0; i < 40; i++) {
    if ((await page.locator('flt-semantics').count()) > 0) return;
    if ((await ph.count()) > 0) await tries[i % tries.length]().catch(() => {});
    await page.waitForTimeout(1500);
  }
  throw new Error('Flutter accessibility tree never appeared');
}
const byText = (text, exact = true) =>
  page.getByText(text, { exact }).or(page.getByLabel(text, { exact })).or(page.getByRole('button', { name: text, exact }));
async function visible(text, exact = true) {
  return (await byText(text, exact).count()) > 0 && (await byText(text, exact).first().isVisible().catch(() => false));
}
async function waitText(text, { timeout = 60000, exact = false } = {}) {
  for (const end = Date.now() + timeout; Date.now() < end;) {
    if (await visible(text, exact)) return;
    await page.waitForTimeout(250);
  }
  await shot(`missing-${text.replace(/\W+/g, '_').slice(0, 30)}`).catch(() => {});
  throw new Error(`"${text}" did not appear within ${timeout} ms`);
}
async function tapText(text, opts) {
  await waitText(text, opts);
  await byText(text, opts?.exact ?? false).last().click();
}
const textInputs = () => page.locator('input:not([type=hidden]), textarea');
async function typeInto(input, value) {
  await input.click();
  await page.waitForTimeout(600);
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 10 });
}

/// Boxes of the accessibility nodes labelled exactly [name] (the space rail's
/// buttons are labelled with the space's name).
async function boxesOf(name) {
  return page.evaluate((n) => [...document.querySelectorAll('flt-semantics[aria-label], [aria-label]')]
    .filter((e) => e.getAttribute('aria-label') === n)
    .map((e) => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; })
    .filter((r) => r.width > 8 && r.height > 8 && r.width < 160 && r.height < 160), name);
}

const results = [];
let failures = 0;
/// Checks the avatars of [names] in a screenshot of the current view.
async function check(view, names) {
  phase = view;
  const end = Date.now() + SETTLE_MS;
  let img; let rows;
  // Poll: done as soon as every avatar shows, else the last state counts.
  for (;;) {
    await page.waitForTimeout(2000);
    img = decodePng(await page.screenshot({ timeout: 20000 }));
    rows = [];
    for (const name of names) {
      const it = items.find((x) => x.name === name);
      const a = count(img, it.a).n; const b = count(img, it.b).n;
      let black = null;
      if (it.kind !== 'room') {
        for (const box of await boxesOf(name)) {
          const c = count(img, [0, 0, 0], box);
          black = Math.max(black ?? 0, c.black / c.all);
        }
      }
      rows.push({ name, kind: it.kind, format: it.format, size: `${it.w}x${it.h}`, a, b, black,
        state: black !== null && black > 0.4 ? 'black' : a >= 40 && b >= 40 ? 'shown' : 'missing' });
    }
    if (rows.every((r) => r.state === 'shown') || Date.now() > end) break;
  }
  fs.writeFileSync(path.join(out, `${String(++shotN).padStart(2, '0')}-${view.replace(/\W+/g, '_')}.png`), await page.screenshot());
  const imgState = await page.evaluate(() => window.__e2eImages).catch(() => null);
  for (const r of rows) {
    say(`${view}: ${r.name} (${r.kind} ${r.format} ${r.size}): ${r.state.toUpperCase()} a=${r.a} b=${r.b}${r.black !== null ? ` black=${r.black.toFixed(2)}` : ''}`);
    if (r.state !== 'shown') failures++;
    results.push({ view, ...r });
  }
  say(`${view}: browser decodes ok=${imgState?.decodeOk} failed=${imgState?.decodeFail?.length} bitmaps=${imgState?.bitmaps} ImageDecoder=${imgState?.imageDecoder}`);
  if (imgState?.decodeFail?.length) say(`  decode failures: ${[...new Set(imgState.decodeFail)].slice(0, 5).join(' | ')}`);
}

async function api(token, method, p, body) {
  for (;;) {
    const r = await fetch(`${hs}/_matrix/client/v3${p}`, {
      method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body && JSON.stringify(body),
    });
    // Synapse limits room creation even in the job (rc_room_creation).
    if (r.status === 429) {
      const wait = (await r.json().catch(() => ({}))).retry_after_ms ?? 5000;
      say(`${method} ${p.split('/')[1]}: rate limited, waiting ${Math.round(wait / 1000)} s`);
      await new Promise((res) => setTimeout(res, wait + 200));
      continue;
    }
    if (!r.ok) throw new Error(`${method} ${p}: ${r.status} ${await r.text()}`);
    return r.json();
  }
}

let own;
let exitCode = 1;
try {
  phase = 'seed';
  await register(hs, user, PASSWORD);
  own = await OtherDevice.login(hs, user, PASSWORD, 'E2E other device');
  const recoveryKey = await own.setUpSecureMessaging();
  const ids = {};
  for (const it of items) {
    let data = it.format === 'jpeg' ? twoToneJpeg(it.w, it.h, it.a, it.b) : null;
    let type = 'image/jpeg';
    if (!data) { data = twoTonePng(it.w, it.h, it.a, it.b); type = 'image/png'; it.format = 'png'; }
    const up = await fetch(`${hs}/_matrix/media/v3/upload?filename=${encodeURIComponent(it.name)}.${it.format === 'jpeg' ? 'jpg' : 'png'}`, {
      method: 'POST', headers: { Authorization: `Bearer ${own.token}`, 'Content-Type': type }, body: data,
    });
    if (!up.ok) throw new Error(`upload ${it.name}: ${up.status}`);
    const mxc = (await up.json()).content_uri;
    const r = await api(own.token, 'POST', '/createRoom', {
      name: it.name, preset: 'private_chat',
      ...(it.kind !== 'room' ? { creation_content: { type: 'm.space' } } : {}),
      initial_state: [{ type: 'm.room.avatar', state_key: '', content: { url: mxc, info: { mimetype: type, w: it.w, h: it.h, size: data.length } } }],
    });
    ids[it.name] = r.room_id;
  }
  if (!haveConvert) say('ImageMagick convert missing: JPEG avatars seeded as PNG');
  const hub = ids['Avatar Hub'];
  const child = (parent, kid) => Promise.all([
    api(own.token, 'PUT', `/rooms/${encodeURIComponent(parent)}/state/m.space.child/${encodeURIComponent(kid)}`, { via: [hsName] }),
    api(own.token, 'PUT', `/rooms/${encodeURIComponent(kid)}/state/m.space.parent/${encodeURIComponent(parent)}`, { via: [hsName], canonical: true }),
  ]);
  const hubRooms = items.filter((x) => x.kind === 'room').slice(0, 8).map((x) => x.name);
  for (const it of items) {
    if (it.kind === 'child' || hubRooms.includes(it.name)) await child(hub, ids[it.name]);
  }
  // The other rooms go into the other spaces (two each, until they run out).
  const others = items.filter((x) => x.kind === 'room' && !hubRooms.includes(x.name));
  const spaces = items.filter((x) => x.kind === 'space' && x.name !== 'Avatar Hub');
  for (let i = 0; i < others.length; i++) await child(ids[spaces[Math.floor(i / 2) % spaces.length].name], ids[others[i].name]);
  say(`seeded ${items.length} rooms for ${own.userId}`);

  await openBrowser();
  phase = 'sign-in';
  await page.goto(appUrl);
  await enableSemantics();
  const inputs = textInputs();
  const waitInputs = async (n, ms) => {
    for (let end = Date.now() + ms; (await inputs.count()) < n && Date.now() < end;) await page.waitForTimeout(250);
    return inputs.count();
  };
  await waitInputs(1, 120000);
  await page.waitForTimeout(3000);
  await typeInto(inputs.nth(0), hsName);
  if ((await waitInputs(3, 30000)) < 3) {
    if (await visible('Sign in with a password instead', false)) await tapText('Sign in with a password instead');
    await waitInputs(3, 30000);
  }
  await typeInto(inputs.nth(1), user);
  await typeInto(inputs.nth(2), PASSWORD);
  await tapText('Login', { exact: true });
  for (let end = Date.now() + 150000; ;) {
    if (await visible('Is this you?', false)) break;
    if (Date.now() > end) break;
    if (await visible('No thanks', true)) await tapText('No thanks', { exact: true });
    else if (await visible('Next', true)) await tapText('Next', { exact: true });
    else if (await visible('Done', true)) await tapText('Done', { exact: true });
    await page.waitForTimeout(1000);
  }
  await tapText('Enter recovery key or phrase');
  await waitText('Enter your recovery key');
  await typeInto(textInputs().first(), recoveryKey);
  await tapText('Unlock my messages');
  await waitText("You're all set", { timeout: 180000 });
  await tapText('Start chatting');
  say(`signed in (${loaded.wasm ? 'wasm' : ''}${loaded.js ? ' js' : ''})`);

  const rail = items.filter((x) => x.kind === 'space').map((x) => x.name);
  const hubView = [...rail, ...items.filter((x) => x.kind === 'child').map((x) => x.name), ...hubRooms];
  for (const round of ['first load', 'reload 1', 'reload 2']) {
    if (round !== 'first load') {
      phase = round;
      await page.reload();
      await enableSemantics();
    }
    await waitText('Avatar Hub', { timeout: 120000, exact: true });
    await check(`${round}: rail`, rail);
    await tapText('Avatar Hub', { exact: true });
    await waitText('Child Png', { timeout: 60000 });
    await check(`${round}: Avatar Hub home`, hubView);
  }
  const want = force === 'auto' ? null : force;
  if (want && !loaded[want]) { say(`expected the ${want} build to run, but it didn't`); failures++; }
  exitCode = failures ? 1 : 0;
} catch (e) {
  say(`FAILED: ${e.stack || e}`);
  await shot('error').catch(() => {});
} finally {
  const byStatus = {};
  for (const m of media) byStatus[`${m.phase.split(':')[0]} ${m.status}${m.error ? ` ${m.error}` : ''}`] = (byStatus[`${m.phase.split(':')[0]} ${m.status}${m.error ? ` ${m.error}` : ''}`] ?? 0) + 1;
  say(`media responses: ${JSON.stringify(byStatus)}`);
  fs.writeFileSync(path.join(out, 'media.json'), JSON.stringify(media, null, 1));
  fs.writeFileSync(path.join(out, 'avatars.json'), JSON.stringify(results, null, 1));
  say(`${failures} avatar checks failed`);
  await context?.close().catch(() => {});
  try { own?.stop(); } catch {}
  report.end();
  consoleLog.end();
  process.exit(exitCode);
}
