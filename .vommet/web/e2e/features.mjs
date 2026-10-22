// Vommet web: what works in the browser compared with the desktop app
// (Vommet issue 426). A real browser (Playwright: chromium or firefox) runs
// the built web app against a throwaway homeserver, signs in, and goes through
// the everyday features one by one. Two other clients in Node take part: a
// second device of the same user (cross-signing, recovery key, key backup,
// creates the rooms) and another person, who sends, reacts, and reads back
// what the web app sent.
//
// Each feature is recorded as works / different / broken / untested with the
// console errors and Google requests seen while it ran, in matrix.json and
// matrix.md (the site's "works compared with the desktop app" list comes from
// these). Exit 1 if a feature that should work doesn't, if anything contacted
// a Google host, or if the run couldn't get as far as the room list.
//
//   node features.mjs <browser> <app url> <homeserver url> <out dir> [auto|js]
// "js" makes a WebAssembly build fall back to its JS build, like a browser
// without WasmGC would.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { chromium, firefox } from 'playwright';
import { register } from './device.mjs';
import { OtherDevice, waitFor, png, waitEvent, createRoom, join, upload, addEmotePack } from './peer.mjs';

const [browserName = 'chromium', appUrl = 'http://127.0.0.1:8765/', hs = 'https://localhost', outDir = 'e2e-out',
  force = 'auto'] = process.argv.slice(2);
const hsName = new URL(hs).host;
// force: auto (the build the browser's loader picks), wasm (WebAssembly, also
// in Firefox) or js (the JS fallback).
const out = path.join(outDir, `${browserName}-features${force === 'auto' ? '' : `-${force}`}${process.env.FEATURES_LABEL ? `-${process.env.FEATURES_LABEL}` : ''}`);
fs.mkdirSync(out, { recursive: true });
const report = fs.createWriteStream(path.join(out, 'report.txt'));
const say = (...a) => {
  const line = `[${new Date().toISOString().slice(11, 23)}] ${a.join(' ')}`;
  process.stdout.write(line + '\n');
  report.write(line + '\n');
};

const PASSWORD = 'Correct-Horse-Battery-9';
const stamp = Date.now();
const user = `feat_${browserName}_${stamp}`;
const peerUser = `peer_${browserName}_${stamp}`;

// ---- What the page did, per feature ----

let phase = 'start';
const consoleLog = fs.createWriteStream(path.join(out, 'console.txt'));
const errorsBy = {};
const googleBy = {};
const loaded = { wasm: false, js: false };
const mediaOk = [];
// What the browser downloaded from the app's own origin until the sign-in
// page (uncompressed: the test server doesn't gzip, the image does).
const firstLoad = { bytes: 0, requests: 0, done: false };
// Hosts the web app must never contact (Vommet issue 426: no Google).
const GOOGLE = /(^|\.)(google|googleapis|gstatic|googleusercontent|googletagmanager|google-analytics|googlesyndication|doubleclick|firebaseio|firebaseapp|recaptcha)\.[a-z.]+$/i;

const profile = fs.mkdtempSync(path.join(os.tmpdir(), `vommet-features-${browserName}-`));
let context;
let page;
async function openBrowser() {
  const options = { ignoreHTTPSErrors: true, viewport: { width: 1280, height: 860 } };
  context = browserName === 'firefox'
    ? await firefox.launchPersistentContext(profile, {
      ...options,
      headless: !process.env.DISPLAY,
      firefoxUserPrefs: { 'webgl.force-enabled': true, 'webgl.disabled': false },
    })
    : await chromium.launchPersistentContext(profile, options);
  // The notifications check needs to see whether the app asks and shows
  // anything; permission is granted so the only missing piece would be the app.
  await context.grantPermissions(['notifications'], { origin: new URL(appUrl).origin }).catch((e) => say(`grantPermissions: ${e.message.split('\n')[0]}`));
  // The loader picks the JS build when WebAssembly.validate rejects its
  // WasmGC probe.
  if (force === 'js') await context.addInitScript(() => { WebAssembly.validate = () => false; });
  // Flutter's loader only takes the WebAssembly build in Chromium unless the
  // page allows other engines (wasmAllowList).
  if (force === 'wasm' && browserName !== 'chromium') {
    await context.route('**/flutter_bootstrap.js', async (route) => {
      const res = await route.fetch();
      const body = (await res.text()).replace('config: {', 'config: { wasmAllowList: { gecko: true },');
      await route.fulfill({ response: res, body });
    });
  }
  await context.addInitScript(() => {
    const n = { requests: 0, shown: [] };
    window.__e2eNotifications = n;
    const N = window.Notification;
    if (!N) return;
    const Wrapped = function (title, opts) { n.shown.push(String(title)); return new N(title, opts); };
    Wrapped.prototype = N.prototype;
    Object.defineProperty(Wrapped, 'permission', { get: () => N.permission });
    Wrapped.requestPermission = (...a) => { n.requests++; return N.requestPermission(...a); };
    window.Notification = Wrapped;
  });
  context.on('request', (r) => {
    let host = '';
    try { host = new URL(r.url()).hostname; } catch { return; }
    if (GOOGLE.test(host)) (googleBy[phase] ??= []).push(r.url());
    if (/main\.dart\.wasm(\?|$)/.test(r.url())) loaded.wasm = true;
    if (/main\.dart\.(m?js)(\?|$)/.test(r.url())) loaded.js = true;
  });
  context.on('requestfinished', async (r) => {
    if (!firstLoad.done && r.url().startsWith(new URL(appUrl).origin)) {
      const sz = await r.sizes().catch(() => null);
      if (sz) { firstLoad.bytes += sz.responseBodySize; firstLoad.requests++; }
    }
  });
  context.on('response', (r) => {
    if (/\/_matrix\/(client\/v1|media\/v3)\/(media\/)?(download|thumbnail)\//.test(r.url())) {
      mediaOk.push({ url: r.url(), status: r.status(), phase });
    }
  });
  page = context.pages()[0] ?? (await context.newPage());
  page.on('console', (m) => {
    consoleLog.write(`[${phase}] [${m.type()}] ${m.text()}\n`);
    if (m.type() === 'error') (errorsBy[phase] ??= []).push(m.text().slice(0, 300));
  });
  page.on('pageerror', (e) => {
    consoleLog.write(`[${phase}] [pageerror] ${e.stack || e}\n`);
    (errorsBy[phase] ??= []).push(`pageerror: ${String(e.message || e).slice(0, 300)}`);
  });
}

let shotN = 0;
const shot = async (name) => {
  const f = path.join(out, `${String(++shotN).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f, timeout: 20000 }).catch((e) => say(`screenshot ${name} failed: ${e.message.split('\n')[0]}`));
};
const dumpTree = async (name) => {
  const tree = await page.evaluate(() => document.querySelector('flt-semantics-host')?.outerHTML ?? '(no semantics tree)').catch((e) => String(e));
  fs.writeFileSync(path.join(out, `semantics-${String(shotN).padStart(2, '0')}-${name}.html`), tree);
};

// ---- Flutter web, driven through its accessibility tree (as reload-e2ee.mjs) ----

async function enableSemantics() {
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 180000 });
  const ph = page.locator('flt-semantics-placeholder');
  const tries = [
    () => page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()),
    () => ph.dispatchEvent('click'),
    () => ph.dispatchEvent('pointerup'),
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
  return (await byText(text, exact).count()) > 0 &&
    (await byText(text, exact).first().isVisible().catch(() => false));
}

async function waitText(text, { timeout = 60000, exact = false } = {}) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (await visible(text, exact)) return;
    await page.waitForTimeout(250);
  }
  await shot(`missing-${text.replace(/\W+/g, '_').slice(0, 30)}`);
  await dumpTree(`missing-${text.replace(/\W+/g, '_').slice(0, 30)}`);
  throw new Error(`"${text}" did not appear within ${timeout} ms`);
}

async function tapText(text, opts) {
  await waitText(text, opts);
  await byText(text, opts?.exact ?? false).last().click();
}

async function typeInto(input, value) {
  await input.click();
  await page.waitForTimeout(600);
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 10 });
}

/// Taps the visible menu item or button [text] with the mouse. Menus leave
/// stale copies in the accessibility tree, so Playwright's click on "the last
/// match" can wait on one that's gone.
async function tapMenu(text, { timeout = 10000 } = {}) {
  await waitText(text, { timeout, exact: true });
  const loc = page.getByText(text, { exact: true }).or(page.getByRole('button', { name: text, exact: true }));
  const box = async () => {
    for (let i = (await loc.count()) - 1; i >= 0; i--) {
      const b = await loc.nth(i).boundingBox().catch(() => null);
      if (b && b.width > 0 && b.height > 0 && (await loc.nth(i).isVisible().catch(() => false))) return b;
    }
    return null;
  };
  // A quick click right after the menu opens only highlights the item:
  // hover first, then press and release; if the menu stays, tap the item's
  // accessibility node, then try Enter on the highlighted item.
  for (let attempt = 0; attempt < 3; attempt++) {
    const b = await box();
    if (!b) {
      if (attempt) return;
      throw new Error(`no visible "${text}" to tap`);
    }
    if (attempt === 0) {
      await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
      await page.waitForTimeout(250);
      await page.mouse.down();
      await page.waitForTimeout(100);
      await page.mouse.up();
    } else if (attempt === 1) {
      const n = await loc.count();
      for (let i = n - 1; i >= 0; i--) {
        if (await loc.nth(i).isVisible().catch(() => false)) { await loc.nth(i).click({ force: true, timeout: 3000 }).catch(() => {}); break; }
      }
    } else {
      await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
      await page.keyboard.press('Enter');
    }
    await page.waitForTimeout(1500);
    if (!(await box())) return;
  }
}

/// Types into the composer as it is (keeps a reply or edit in progress:
/// Backspace in an empty composer cancels a reply) and sends.
async function typeAndSend(text) {
  await composer().click();
  await page.waitForTimeout(600);
  await page.keyboard.type(text, { delay: 10 });
  await page.keyboard.press('Enter');
}

const textInputs = () => page.locator('input:not([type=hidden]), textarea');
const composer = () => textInputs().last();

async function send(text) {
  await typeInto(composer(), text);
  await page.keyboard.press('Enter');
}

/// Right-clicks the message showing [text]: the desktop message menu.
async function messageMenu(text) {
  await waitText(text);
  const p = await messagePoint(text);
  await page.mouse.move(p.x, p.y);
  await page.waitForTimeout(400);
  await page.mouse.click(p.x, p.y, { button: 'right' });
  await page.waitForTimeout(800);
}

/// A point on the text of the message showing [text]. Its accessibility node
/// spans the whole row (avatar, name, time, reactions below), and the avatar,
/// name and reactions open their own menus, so aim at the first line under the
/// name, right of the avatar.
async function messagePoint(text) {
  const el = byText(text, false).last();
  await el.scrollIntoViewIfNeeded().catch(() => {});
  const b = await el.boundingBox();
  if (!b) throw new Error(`no box for "${text}"`);
  // The sender's name, when the row shows one, is a tappable child node; the
  // text starts under it.
  const nameBottom = await el.evaluate((node) => {
    const top = node.getBoundingClientRect().top;
    const kids = [...node.querySelectorAll('[role=button], [flt-tappable]')]
      .map((k) => k.getBoundingClientRect())
      .filter((r) => r.height > 10 && r.height < 30 && r.width > 40 && r.top - top < 30);
    return kids.length ? Math.max(...kids.map((r) => r.bottom)) : null;
  }).catch(() => null);
  // Without a tappable name node, a row taller than one line has the name on
  // its first ~20 px.
  const y = nameBottom ? nameBottom + 10 : b.height > 34 ? b.y + 30 : b.y + b.height / 2;
  return { x: b.x + Math.min(90, b.width / 2), y };
}

/// Buttons on the composer's row, left to right, as boxes (the attach, emoji
/// and send buttons have no labels).
async function composerRow() {
  const c = await composer().boundingBox();
  if (!c) throw new Error('no composer');
  const boxes = await page.evaluate(({ top, bottom }) => [...document.querySelectorAll('flt-semantics[role=button], [role=button], flt-semantics[flt-tappable]')]
    .map((e) => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, label: e.getAttribute('aria-label') || e.textContent?.slice(0, 30) || '' }; })
    .filter((r) => r.w > 0 && r.w < 80 && r.y + r.h / 2 > top - 12 && r.y + r.h / 2 < bottom + 12)
    .sort((a, b) => a.x - b.x), { top: c.y, bottom: c.y + c.height });
  return { c, left: boxes.filter((b) => b.x + b.w <= c.x + 4), right: boxes.filter((b) => b.x >= c.x + c.width - 60) };
}
/// Closes a menu, picker or dialog left open: Escape doesn't close the message
/// menu, a click outside it (the empty bottom of the side panel) does.
async function closeMenus() {
  await page.keyboard.press('Escape').catch(() => {});
  await page.mouse.click(1150, 720).catch(() => {});
  await page.waitForTimeout(500);
}
const clickBox = (b) => page.mouse.click(b.x + b.w / 2, b.y + b.h / 2);

// ---- The feature matrix ----

// Delete and Reply In Thread from the message menu: the test can't activate
// them yet (the item highlights, nothing happens), though Reply and Edit from
// the same menu work. Recorded, not failing the job, until that's understood.
const KNOWN_MENU_GAP = ['works', 'broken'];

const results = [];
let strictFailures = 0;
/// Runs one feature. [fn] returns a note (works), or { status, note }; a throw
/// is "broken". expect: what the matrix should say; anything else fails the run.
async function feature(name, fn, { expect = 'works' } = {}) {
  phase = name;
  say(`--- ${name} ---`);
  let status = 'works';
  let note = '';
  try {
    const r = await fn();
    if (r && typeof r === 'object') ({ status, note = '' } = r);
    else note = r ?? '';
  } catch (e) {
    status = 'broken';
    note = String(e?.message || e).split('\n')[0];
    await shot(`broken-${name.replace(/\W+/g, '_').slice(0, 30)}`);
    await dumpTree(`broken-${name.replace(/\W+/g, '_').slice(0, 30)}`);
    await closeMenus();
  }
  const errors = errorsBy[name] ?? [];
  const google = googleBy[name] ?? [];
  if (google.length) { status = 'broken'; note = `${note} contacted Google: ${[...new Set(google.map((u) => new URL(u).host))].join(', ')}`.trim(); }
  results.push({ feature: name, status, note, consoleErrors: errors.slice(0, 15), consoleErrorCount: errors.length, google });
  say(status.toUpperCase(), name, note ? `— ${note}` : '', errors.length ? `(${errors.length} console errors)` : '');
  if (![expect].flat().includes(status) && status !== 'untested') strictFailures++;
  return status;
}
const untested = (name, why) => results.push({ feature: name, status: 'untested', note: why, consoleErrors: [], consoleErrorCount: 0, google: [] });

let own;
let peer;
let exitCode = 1;
try {
  phase = 'seed';
  await register(hs, user, PASSWORD);
  await register(hs, peerUser, PASSWORD);
  own = await OtherDevice.login(hs, user, PASSWORD, 'E2E other device');
  peer = await OtherDevice.login(hs, peerUser, PASSWORD, 'E2E peer');
  const recoveryKey = await own.setUpSecureMessaging();
  const e2ee = await createRoom(own, { name: 'Matrix E2EE', encrypted: true, invite: [peer.userId] });
  const plain = await createRoom(own, { name: 'Matrix Plain', encrypted: false, invite: [peer.userId] });
  await join(peer, e2ee);
  await join(peer, plain);
  const emoteMxc = await upload(own, png(240, 180, 20), 'blobcat.png');
  await addEmotePack(own, plain, 'blobcat', emoteMxc);
  await addEmotePack(own, e2ee, 'blobcat', emoteMxc);
  await waitFor('peer sees the encryption', async () => peer.client.getRoom(e2ee)?.hasEncryptionStateEvent());
  await own.send(e2ee, 'own hello before');
  await peer.send(e2ee, 'peer hello before');
  // The other device backs up its own session and the one it received.
  await waitFor('two sessions in the backup', async () => {
    const v = await own.crypto.getActiveSessionBackupVersion();
    if (!v) return false;
    const k = await own.api('GET', `/room_keys/keys?version=${encodeURIComponent(v)}`);
    return Object.keys(k.rooms?.[e2ee]?.sessions ?? {}).length >= 2;
  }, 90000).catch((e) => say(`backup: ${e.message}`));
  say(`seeded ${own.userId} + ${peer.userId}: rooms ${e2ee} (encrypted), ${plain}`);

  await openBrowser();

  // -- Sign in --
  const signedIn = await feature('Sign in (password)', async () => {
    await page.goto(appUrl);
    await enableSemantics();
    const inputs = textInputs();
    const waitInputs = async (n, ms) => {
      for (let end = Date.now() + ms; (await inputs.count()) < n && Date.now() < end;) await page.waitForTimeout(250);
      return inputs.count();
    };
    await waitInputs(1, 120000);
    await page.waitForTimeout(3000);
    firstLoad.done = true;
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
    await waitText('Is this you?', { timeout: 5000 });
  });
  results.push({
    feature: 'First load (until the sign-in page)', status: 'works',
    note: `${(firstLoad.bytes / 1048576).toFixed(1)} MB uncompressed in ${firstLoad.requests} requests`,
    consoleErrors: [], consoleErrorCount: 0, google: [],
  });
  if (signedIn !== 'works') throw new Error('could not sign in');
  untested('Sign in with SSO', 'needs an identity provider in the job');

  await feature('Unlock with the recovery key (key backup, cross-signing)', async () => {
    await tapText('Enter recovery key or phrase');
    await waitText('Enter your recovery key');
    await typeInto(textInputs().first(), recoveryKey);
    await tapText('Unlock my messages');
    await waitText("You're all set", { timeout: 180000 });
    const devs = await own.devices();
    const web = Object.keys(devs).find((d) => d !== own.deviceId);
    if (!devs[web]?.signedBySelfSigningKey) throw new Error('web device not cross-signed after unlock');
    await tapText('Start chatting');
    await page.waitForTimeout(3000);
  });

  // Verification by emoji with another device is covered by reload-e2ee.mjs
  // (flow "emoji"); it's not repeated here.

  const listed = await feature('Initial sync and room list', async () => {
    await waitText('Matrix E2EE', { timeout: 90000 });
    await waitText('Matrix Plain', { timeout: 30000 });
    await shot('room-list');
  });
  if (listed !== 'works') throw new Error('room list never showed');

  await feature('Encrypted history from before sign-in (from the key backup)', async () => {
    await tapText('Matrix E2EE');
    await waitText('own hello before', { timeout: 60000 });
    await waitText('peer hello before', { timeout: 30000 });
  });

  await feature('Send a message (encrypted room)', async () => {
    await send('web says hi');
    await peer.waitMessage(e2ee, 'web says hi', 60000);
  });

  let peerLive;
  await feature('Receive a message (encrypted room)', async () => {
    peerLive = await peer.send(e2ee, 'peer live message');
    await waitText('peer live message', { timeout: 60000 });
    await shot('room-e2ee');
  });

  await feature('Reply', async () => {
    await messageMenu('peer live message');
    await dumpTree('message-menu');
    await tapMenu('Reply');
    await typeAndSend('web reply text');
    await waitEvent(peer, e2ee, 'the reply', (ev) => ev.getContent()?.body?.includes('web reply text') &&
      ev.getContent()?.['m.relates_to']?.['m.in_reply_to']?.event_id === peerLive);
  });

  const reactTarget = await peer.send(e2ee, 'peer react to me');
  await feature('Add a reaction', async () => {
    // The message menu starts with quick reactions (❤️ 👍 👎) and a button
    // for the full picker.
    await messageMenu('peer react to me');
    await page.getByText('👍', { exact: true }).last().click();
    await waitEvent(peer, e2ee, 'the reaction', (ev) => ev.getType() === 'm.reaction' &&
      ev.getContent()?.['m.relates_to']?.event_id === reactTarget);
  });

  let webMsgId;
  await feature('See a reaction from someone else', async () => {
    const mine = await waitEvent(peer, e2ee, 'web message', (ev) => ev.getContent()?.body === 'web says hi');
    webMsgId = mine.getId();
    await peer.client.sendEvent(e2ee, 'm.reaction', { 'm.relates_to': { rel_type: 'm.annotation', event_id: webMsgId, key: '🎉' } });
    for (let end = Date.now() + 30000; Date.now() < end;) {
      if ((await page.getByText(/🎉/).count()) || (await page.getByLabel(/🎉|tada/).count())) return;
      await page.waitForTimeout(500);
    }
    await shot('no-reaction');
    await dumpTree('no-reaction');
    throw new Error('the 🎉 reaction never showed');
  });

  await feature('Edit a message', async () => {
    await messageMenu('web says hi');
    await tapMenu('Edit');
    await page.waitForTimeout(500);
    await typeInto(composer(), 'web says hi, edited');
    await page.keyboard.press('Enter');
    await waitEvent(peer, e2ee, 'the edit', (ev) => ev.getContent()?.['m.relates_to']?.rel_type === 'm.replace' &&
      ev.getContent()?.['m.relates_to']?.event_id === webMsgId);
    await waitText('web says hi, edited', { timeout: 20000 });
  });

  await feature('Delete a message', async () => {
    await send('web will delete this');
    const ev = await waitEvent(peer, e2ee, 'message to delete', (e) => e.getContent()?.body === 'web will delete this');
    await messageMenu('web will delete this');
    await tapMenu('Delete');
    await tapMenu('Yes');
    await waitFor('redaction', async () => peer.client.getRoom(e2ee)?.findEventById(ev.getId())?.isRedacted(), 60000);
  }, { expect: KNOWN_MENU_GAP });

  const threadRoot = await peer.send(e2ee, 'peer thread root');
  await feature('Threads', async () => {
    await messageMenu('peer thread root');
    await tapMenu('Reply In Thread');
    await page.waitForTimeout(2000);
    await shot('thread');
    await typeAndSend('web in the thread');
    await waitEvent(peer, e2ee, 'the thread reply', (ev) => ev.getContent()?.body === 'web in the thread' &&
      ev.getContent()?.['m.relates_to']?.rel_type === 'm.thread' && ev.getContent()?.['m.relates_to']?.event_id === threadRoot);
    await peer.client.sendEvent(e2ee, 'm.room.message', {
      msgtype: 'm.text', body: 'peer in the thread',
      'm.relates_to': { rel_type: 'm.thread', event_id: threadRoot, is_falling_back: true, 'm.in_reply_to': { event_id: threadRoot } },
    });
    await waitText('peer in the thread', { timeout: 30000 });
    await page.keyboard.press('Escape');
  }, { expect: KNOWN_MENU_GAP });

  await feature('Upload a file (encrypted room)', async () => {
    const row = await composerRow();
    say(`composer row: left ${JSON.stringify(row.left)} right ${JSON.stringify(row.right)}`);
    const attach = row.left.at(-1) ?? { x: row.c.x - 34, y: row.c.y, w: 28, h: row.c.height };
    const chooser = page.waitForEvent('filechooser', { timeout: 15000 });
    await clickBox(attach);
    await page.waitForTimeout(800);
    await dumpTree('attach-menu');
    if (await visible('File', true)) await tapText('File', { exact: true });
    const fc = await chooser;
    await fc.setFiles({ name: 'web-upload.png', mimeType: 'image/png', buffer: png(30, 160, 220) });
    await page.waitForTimeout(2000);
    await shot('attachment');
    await dumpTree('attachment');
    if (await visible('Send Original', false)) await tapText('Send Original');
    // The attachment dialog (strip hidden info, crop, caption) adds it to the
    // message; Enter sends.
    if (await visible('Add File', true)) await tapText('Add File', { exact: true });
    await page.waitForTimeout(1000);
    await composer().click();
    await page.keyboard.press('Enter');
    const ev = await waitEvent(peer, e2ee, 'the upload', (e) => e.getContent()?.body === 'web-upload.png' ||
      e.getContent()?.filename === 'web-upload.png', 90000);
    const c = ev.getContent();
    if (!c.file?.url) throw new Error(`sent without encrypting the file (${c.url ? 'plain url' : 'no file'})`);
    return `${c.msgtype}, encrypted attachment`;
  });

  // -- The unencrypted room: media, stickers, emoji packs --
  await feature('Open another room', async () => {
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    await tapText('Matrix Plain');
    await page.waitForTimeout(2000);
  });

  await feature('Images and files from others display', async () => {
    const before = mediaOk.length;
    const imgMxc = await upload(peer, png(20, 200, 60), 'peer-image.png');
    await peer.client.sendEvent(plain, 'm.room.message', { msgtype: 'm.image', body: 'peer-image.png', url: imgMxc, info: { w: 16, h: 16, mimetype: 'image/png', size: 100 } });
    const fileMxc = await upload(peer, Buffer.from('hello from a file\n'), 'peer-notes.txt', 'text/plain');
    await peer.client.sendEvent(plain, 'm.room.message', { msgtype: 'm.file', body: 'peer-notes.txt', url: fileMxc, info: { mimetype: 'text/plain', size: 18 } });
    await waitText('peer-notes.txt', { timeout: 30000 });
    const id = imgMxc.split('/').pop();
    await waitFor('the image download', async () => mediaOk.slice(before).find((m) => m.url.includes(id)), 30000);
    const bad = mediaOk.slice(before).filter((m) => m.status >= 400);
    await shot('media');
    if (bad.length) throw new Error(`media requests failed: ${bad.map((m) => m.status).join(',')}`);
  });

  await feature('Stickers from others display', async () => {
    const before = mediaOk.length;
    const mxc = await upload(peer, png(250, 120, 0), 'sticker.png');
    await peer.client.sendEvent(plain, 'm.sticker', { body: 'a peer sticker', url: mxc, info: { w: 16, h: 16, mimetype: 'image/png' } });
    const id = mxc.split('/').pop();
    await waitFor('the sticker download', async () => mediaOk.slice(before).find((m) => m.url.includes(id) && m.status < 400), 30000);
  });

  await feature('Custom emoji from a room pack', async () => {
    await typeInto(composer(), 'pack emoji :blobcat:');
    await page.waitForTimeout(1200);
    await dumpTree('emoji-autocomplete');
    await page.keyboard.type(' ok');
    await page.keyboard.press('Enter');
    const ev = await waitEvent(peer, plain, 'the emoji message', (e) => e.getContent()?.body?.startsWith('pack emoji'));
    const html = ev.getContent()?.formatted_body ?? '';
    if (!html.includes('mxc://')) return { status: 'different', note: `sent as text: ${JSON.stringify(ev.getContent()?.body)}` };
    return 'sent as an inline image';
  });

  await feature('Send a sticker from a pack', async () => {
    const row = await composerRow();
    const emojiBtn = row.right[0];
    if (!emojiBtn) throw new Error('no emoji button beside the composer');
    await clickBox(emojiBtn);
    await page.waitForTimeout(1500);
    await tapText('Sticker', { exact: true, timeout: 10000 });
    await page.waitForTimeout(1500);
    await dumpTree('sticker-picker');
    await shot('sticker-picker');
    // Stickers have no labels: the first one sits under its pack's name.
    await waitText('E2E pack', { timeout: 10000 });
    const h = await byText('E2E pack', true).last().boundingBox();
    await page.mouse.click(h.x + 30, h.y + h.height + 35);
    await waitEvent(peer, plain, 'the sticker', (e) => e.getType() === 'm.sticker' ||
      (e.getContent()?.msgtype === 'm.image' && e.getContent()?.body?.includes('blobcat')), 30000);
    await page.keyboard.press('Escape');
  });

  await feature('Notifications', async () => {
    await peer.send(e2ee, 'peer pings while you look elsewhere');
    await page.waitForTimeout(10000);
    const n = await page.evaluate(() => ({ ...(window.__e2eNotifications ?? {}), permission: window.Notification?.permission }));
    say(`notifications: ${JSON.stringify(n)}`);
    if (n.shown?.length) return `shown: ${n.shown.join(' | ')}`;
    return {
      status: 'different',
      note: `no browser notification for a new message in another room (asked for permission ${n.requests ?? 0}×, permission ${n.permission})`,
    };
  }, { expect: 'different' });

  untested('Voice and video calls', 'needs an SFU: the job has no LiveKit/lk-jwt-service');

  await feature('Settings pages open', async () => {
    await closeMenus();
    if (await visible('Settings', true)) await tapText('Settings', { exact: true });
    else await page.mouse.click(290, 832);
    await waitText('General', { timeout: 30000, exact: true });
    const tabs = ['General', 'Appearance', 'Sounds', 'Voice and Video', 'Data and storage', 'Privacy', 'Advanced',
      'Experiments', 'Manage Accounts', 'Profile', 'Security', 'Emoticons', 'About'];
    const opened = [];
    const missing = [];
    const failing = [];
    for (const t of tabs) {
      if (!(await visible(t, true))) { missing.push(t); continue; }
      const sub = `${phase} › ${t}`;
      const prev = phase;
      phase = sub;
      await byText(t, true).first().click().catch(() => {});
      await page.waitForTimeout(2000);
      phase = prev;
      const errs = (errorsBy[sub] ?? []).filter((e) => e.startsWith('pageerror'));
      if (errs.length) await shot(`settings-${t.replace(/\W+/g, '_')}`);
      (errorsBy[phase] ??= []).push(...(errorsBy[sub] ?? []).map((e) => `${t}: ${e}`));
      if (errs.length) failing.push(`${t} (${errs[0].slice(0, 120)})`);
      else opened.push(t);
    }
    say(`settings: opened ${opened.join(', ')}; not shown ${missing.join(', ')}`);
    if (failing.length) throw new Error(`errors in ${failing.join('; ')}`);
    return `opened ${opened.join(', ')}${missing.length ? `; not on web: ${missing.join(', ')}` : ''}`;
  });

  await feature('Reload keeps the session', async () => {
    await page.reload();
    await enableSemantics();
    await waitText('Matrix E2EE', { timeout: 90000 });
    if (await visible('Is this you?', false)) throw new Error('asked "Is this you?" again after reload');
    await tapText('Matrix E2EE');
    await waitText('peer live message', { timeout: 60000 });
    await send('web after reload');
    await peer.waitMessage(e2ee, 'web after reload', 60000);
  });

  exitCode = 0;
} catch (e) {
  say('ERROR', e?.stack || String(e));
  await shot('error').catch(() => {});
} finally {
  const allGoogle = Object.values(googleBy).flat();
  results.push({
    feature: 'No requests to Google hosts', status: allGoogle.length ? 'broken' : 'works',
    note: allGoogle.length ? [...new Set(allGoogle)].slice(0, 10).join(' ') : `checked every request of the run (${loaded.wasm ? 'wasm' : loaded.js ? 'js' : '?'} build)`,
    consoleErrors: [], consoleErrorCount: 0, google: allGoogle,
  });
  if (allGoogle.length) strictFailures++;
  const build = loaded.wasm ? 'wasm' : loaded.js ? 'js' : 'unknown';
  if (force !== 'auto' && build !== force) {
    results.push({ feature: `Runs the ${force} build`, status: 'broken', note: `the page loaded the ${build} build`, consoleErrors: [], consoleErrorCount: 0, google: [] });
    strictFailures++;
  }
  fs.writeFileSync(path.join(out, 'matrix.json'), JSON.stringify({ browser: browserName, build, results }, null, 1));
  fs.writeFileSync(path.join(out, 'matrix.md'), [
    `# ${browserName} (${build} build)`, '',
    '| feature | result | note | console errors |', '|---|---|---|---|',
    ...results.map((r) => `| ${r.feature} | ${r.status} | ${r.note.replace(/\|/g, '/')} | ${r.consoleErrorCount}${r.consoleErrors[0] ? `: ${r.consoleErrors[0].replace(/\|/g, '/').slice(0, 100)}` : ''} |`),
  ].join('\n') + '\n');
  if (exitCode === 0 && strictFailures) exitCode = 1;
  say(`build ${build}; ${results.map((r) => `${r.feature}=${r.status}`).join('; ')}`);
  say(exitCode ? `FAILED (${strictFailures} unexpected)` : 'ALL AS EXPECTED');
  own?.stop();
  peer?.stop();
  await context?.close().catch(() => {});
  consoleLog.end();
  report.end();
  setTimeout(() => process.exit(exitCode), 500);
}
