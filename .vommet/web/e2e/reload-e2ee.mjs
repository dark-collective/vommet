// Vommet web: encryption survives a page reload (Vommet issues 318 + 353).
//
// A real browser (Playwright: chromium or firefox) runs the built web app
// against a throwaway homeserver. Another device of the same user (device.mjs,
// matrix-js-sdk in Node) sets up cross-signing, a recovery key and a key
// backup, and sends an encrypted message. In the web app the user signs in and
// unlocks their messages with the recovery key (flow "key"), or approves the
// sign-in from the other device by comparing emoji (flow "emoji"), like a
// person would. Then the tab is reloaded twice and the browser restarted on
// the same profile, and each time the test checks what broke in the bug
// reports:
//   - the web device keeps its identity keys and stays cross-signed,
//   - the app doesn't ask "Is this you?" again,
//   - the old message still decrypts, a new one from the other device too,
//   - a message sent from the web arrives and decrypts on the other device,
//   - Settings › Security loads.
//
//   node reload-e2ee.mjs <browser> <app url> <homeserver url> <out dir> [key|emoji]
// Exit 0 = pass. Console output, screenshots and IndexedDB summaries go to
// <out dir>.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { chromium, firefox } from 'playwright';
import { register, OtherDevice } from './device.mjs';

const [browserName = 'chromium', appUrl = 'http://127.0.0.1:8765/', hs = 'https://localhost', outDir = 'e2e-out',
  flow = 'key'] = process.argv.slice(2);
// The homeserver as typed on the login page.
const hsName = new URL(hs).host;
const out = path.join(outDir, `${browserName}-${flow}`);
fs.mkdirSync(out, { recursive: true });
const report = fs.createWriteStream(path.join(out, 'report.txt'));
const say = (...a) => {
  const line = `[${new Date().toISOString().slice(11, 23)}] ${a.join(' ')}`;
  process.stdout.write(line + '\n');
  report.write(line + '\n');
};

const PASSWORD = 'Correct-Horse-Battery-9';
const user = `web_${browserName}_${flow}_${Date.now()}`;
const failures = [];
const check = (ok, what) => {
  say(ok ? 'PASS' : 'FAIL', what);
  if (!ok) failures.push(what);
};

let phase = 'start';
const consoleLog = fs.createWriteStream(path.join(out, 'console.txt'));

// A persistent profile, so the browser can be closed and started again with
// everything the app stored.
const profile = fs.mkdtempSync(path.join(os.tmpdir(), `vommet-e2e-${browserName}-`));
let context;
let page;
async function openBrowser() {
  const options = { ignoreHTTPSErrors: true, viewport: { width: 1280, height: 860 } };
  context = browserName === 'firefox'
    // Headless Firefox has no WebGL by default; Flutter then falls back to
    // slow CPU rendering. Headed under Xvfb (CI) it gets Mesa's software WebGL.
    ? await firefox.launchPersistentContext(profile, {
      ...options,
      headless: !process.env.DISPLAY,
      firefoxUserPrefs: { 'webgl.force-enabled': true, 'webgl.disabled': false },
    })
    : await chromium.launchPersistentContext(profile, options);
  page = context.pages()[0] ?? (await context.newPage());
  page.on('console', (m) => consoleLog.write(`[${phase}] [${m.type()}] ${m.text()}\n`));
  page.on('pageerror', (e) => consoleLog.write(`[${phase}] [pageerror] ${e.stack || e}\n`));
}
await openBrowser();

let shotN = 0;
const shot = async (name) => {
  const f = path.join(out, `${String(++shotN).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f, timeout: 20000 }).catch((e) => say(`screenshot ${name} failed: ${e.message.split('\n')[0]}`));
};

// ---- Flutter web, driven through its accessibility tree ----

async function enableSemantics() {
  // Flutter builds its accessibility tree (what this test reads and taps)
  // once its "Enable accessibility" placeholder is activated.
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

/// Elements whose visible text or accessible label is [text].
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
  const tree = await page.evaluate(() => document.querySelector('flt-semantics-host')?.outerHTML ?? '(no semantics tree)').catch((e) => String(e));
  fs.writeFileSync(path.join(out, `semantics-${shotN}.html`), tree);
  throw new Error(`"${text}" did not appear within ${timeout} ms (phase ${phase})`);
}

async function tapText(text, opts) {
  await waitText(text, opts);
  await byText(text, opts?.exact ?? false).last().click();
}

async function typeInto(input, value) {
  await input.click();
  // Flutter moves focus to its own editing element after the tap; keys typed
  // before that are lost.
  await page.waitForTimeout(600);
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 10 });
}

const textInputs = () => page.locator('input:not([type=hidden]), textarea');

// ---- What the browser stored ----

async function idbSummary(label) {
  const s = await page.evaluate(async () => {
    const out = {};
    const dbs = indexedDB.databases ? await indexedDB.databases() : [];
    for (const { name, version } of dbs) {
      const db = await new Promise((res, rej) => {
        const r = indexedDB.open(name);
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      });
      const stores = {};
      for (const store of db.objectStoreNames) {
        const tx = db.transaction(store, 'readonly');
        const os = tx.objectStore(store);
        const count = await new Promise((res) => { const r = os.count(); r.onsuccess = () => res(r.result); });
        stores[store] = { count };
        if (store === 'client') {
          const keys = await new Promise((res) => { const r = os.getAllKeys(); r.onsuccess = () => res(r.result); });
          stores[store].keys = keys;
          const acct = await new Promise((res) => { const r = os.get('olm_account'); r.onsuccess = () => res(r.result); });
          stores[store].olmAccountLength = typeof acct === 'string' ? acct.length : acct;
          const dev = await new Promise((res) => { const r = os.get('device_id'); r.onsuccess = () => res(r.result); });
          stores[store].deviceId = dev;
        }
      }
      db.close();
      out[`${name}@${version}`] = stores;
    }
    return out;
  });
  fs.writeFileSync(path.join(out, `idb-${label}.json`), JSON.stringify(s, null, 1));
  return s;
}

// ---- The scenario ----

let other;
let exitCode = 1;
try {
  phase = 'seed';
  await register(hs, user, PASSWORD);
  other = await OtherDevice.login(hs, user, PASSWORD, 'E2E other device');
  const recoveryKey = await other.setUpSecureMessaging();
  const roomId = await other.createEncryptedRoom('Reload room');
  await other.send(roomId, 'hello from before');
  await other.waitBackedUp();
  say(`seeded ${other.userId}: cross-signing, recovery key, backup, room ${roomId}`);

  phase = 'login';
  await page.goto(appUrl);
  await enableSemantics();
  const inputs = textInputs();
  const waitInputs = async (n, ms) => {
    for (let end = Date.now() + ms; (await inputs.count()) < n && Date.now() < end;) await page.waitForTimeout(250);
    return inputs.count();
  };
  await waitInputs(1, 120000);
  await shot('login');
  // The homeserver field first; the password form follows once it's checked.
  await typeInto(inputs.nth(0), hsName);
  if ((await waitInputs(3, 30000)) < 3) {
    if (await visible('Sign in with a password instead', false)) await tapText('Sign in with a password instead');
    await waitInputs(3, 30000);
  }
  say(`login page: ${await inputs.count()} text fields`);
  await shot('login-filled-hs');
  await typeInto(inputs.nth(1), user);
  await typeInto(inputs.nth(2), PASSWORD);
  await tapText('Login', { exact: true });

  phase = 'unlock';
  // First-run pages (welcome, diagnostics consent, what's new) come first.
  for (let end = Date.now() + 150000; ;) {
    if (await visible('Is this you?', false)) break;
    if (Date.now() > end) break;
    if (await visible('No thanks', true)) await tapText('No thanks', { exact: true });
    else if (await visible('Next', true)) await tapText('Next', { exact: true });
    else if (await visible('Done', true)) await tapText('Done', { exact: true });
    await page.waitForTimeout(1000);
  }
  await waitText('Is this you?', { timeout: 5000 });
  await shot('is-this-you');
  if (flow === 'emoji') {
    // The other device accepts and confirms its side; here the person taps
    // "They match!" once the emoji show.
    const approved = other.approveNextVerification();
    await tapText('Approve from another device');
    await waitText('They match!', { timeout: 120000 });
    await shot('emoji');
    await tapText('They match!');
    await approved;
    say('approved from the other device by emoji');
  } else {
    await tapText('Enter recovery key or phrase');
    await waitText('Enter your recovery key');
    await typeInto(textInputs().first(), recoveryKey);
    await tapText('Unlock my messages');
  }
  await waitText("You're all set", { timeout: 180000 });
  await shot('all-set');

  const devicesBefore = await other.devices();
  const webDevice = Object.keys(devicesBefore).find((d) => d !== other.deviceId);
  say(`web device ${webDevice}: ${JSON.stringify(devicesBefore[webDevice])}`);
  check(devicesBefore[webDevice]?.signedBySelfSigningKey === true, `web device cross-signed after ${flow === 'emoji' ? 'approval' : 'unlock'}`);
  await tapText('Start chatting');
  await page.waitForTimeout(3000);
  await tapText('Reload room', { timeout: 60000 });
  await waitText('hello from before', { timeout: 60000 });
  check(true, 'old message decrypts before reload (restored from backup)');
  await shot('room-before-reload');
  await idbSummary('before-reload');

  // Two reloads, then (round 3) the browser is closed and started again.
  for (const round of [1, 2, 3]) {
    phase = round === 3 ? 'restart' : `reload${round}`;
    const label = round === 3 ? 'browser restart' : `reload ${round}`;
    say(`--- ${label} ---`);
    if (round === 3) {
      await context.close();
      await openBrowser();
      await page.goto(appUrl);
    } else {
      await page.reload();
    }
    await enableSemantics();
    // Give the client time to load from IndexedDB and sync.
    const end = Date.now() + 45000;
    let asked = false;
    while (Date.now() < end) {
      if (await visible('Is this you?', false)) { asked = true; break; }
      if (await visible('Reload room', false)) break;
      await page.waitForTimeout(500);
    }
    await page.waitForTimeout(5000);
    if (!asked) asked = await visible('Is this you?', false);
    await shot(`after-reload-${round}`);
    const idb = await idbSummary(`after-reload-${round}`);
    say(`IndexedDB: ${JSON.stringify(Object.fromEntries(Object.entries(idb).map(([k, v]) => [k, v.client ?? Object.keys(v).length])))}`);
    check(!asked, `${label}: app doesn't ask "Is this you?" again`);

    const devs = await other.devices();
    check(devs[webDevice]?.ed25519 === devicesBefore[webDevice]?.ed25519,
      `${label}: web device keeps its identity key on the server`);
    check(Object.keys(devs).length === Object.keys(devicesBefore).length,
      `${label}: no new device appeared (${Object.keys(devs).join(',')})`);
    const v = await other.verification(webDevice);
    check(v?.crossSigningVerified === true, `${label}: other device sees web device as verified (${JSON.stringify(v)})`);

    await tapText('Reload room', { timeout: 60000 });
    await page.waitForTimeout(3000);
    check(await visible('hello from before', false), `${label}: old message still decrypts`);

    const fromOther = `from the other device, round ${round}`;
    await other.send(roomId, fromOther);
    let got = false;
    for (let i = 0; i < 120 && !got; i++) { got = await visible(fromOther, false); if (!got) await page.waitForTimeout(500); }
    check(got, `${label}: new message from the other device decrypts`);

    const fromWeb = `from the web, round ${round}`;
    const composer = textInputs().last();
    await typeInto(composer, fromWeb);
    await page.keyboard.press('Enter');
    let arrived = null;
    try { arrived = await other.waitMessage(roomId, fromWeb, 60000); } catch (e) { say(String(e)); }
    check(arrived != null, `${label}: message sent from the web arrives and decrypts on the other device`);
    await shot(`room-after-reload-${round}`);
  }

  // Settings › Security after the reloads: it loads, this session is
  // verified, cross-signing and the backup are on (Vommet issues 318, 353).
  phase = 'security';
  if (await visible('Settings', true)) await tapText('Settings', { exact: true });
  else await page.mouse.click(290, 832); // the gear beside the user panel
  await waitText('Security', { timeout: 30000, exact: true });
  await tapText('Security', { exact: true });
  let loaded = true;
  try { await waitText('Cross Signing & Backup', { timeout: 30000 }); } catch { loaded = false; }
  await page.waitForTimeout(3000);
  await shot('security');
  check(loaded, 'Settings › Security loads');
  check(!(await visible('Unverified', true)), 'Security: this session is verified');
  check(!(await visible('Enable', true)) && !(await visible('Enable backup', true)),
    'Security: cross-signing and backup are on (no "Enable" button)');
  check(await visible('Replace my recovery key', false), 'Security: secure messaging is ready');

  exitCode = failures.length ? 1 : 0;
} catch (e) {
  say('ERROR', e?.stack || String(e));
  await shot('error');
  exitCode = 1;
} finally {
  say(failures.length ? `FAILED: ${failures.join(' | ')}` : exitCode ? 'FAILED (error)' : 'ALL PASSED');
  other?.stop();
  await context?.close().catch(() => {});
  consoleLog.end();
  report.end();
  setTimeout(() => process.exit(exitCode), 500);
}
