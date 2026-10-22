// Vommet web: room widgets open in the web app and talk to it. A room gets a
// widget whose page (served here, on another origin than the app) speaks the
// widget API by hand: it asks for a capability, gets it through the
// permission dialog, and reads the room's topic through the app. A frame
// inside the widget page, on the widget's own origin, posts widget API
// requests to the app as well: the app must ignore them (only the widget
// frame's own window may talk to it).
//
// The app is served cross-origin isolated (serve.py: COEP credentialless).
// Chromium frames the widget as a credentialless iframe; Firefox has no such
// frames, so there the widget server sends COEP + CORP itself, as a widget
// that wants to work in isolated pages must.
//
//   node widgets.mjs <browser> <app url> <homeserver url> <out dir> [auto|wasm|js]
// Exit 1 if the widget didn't get its capability or the topic, or if the
// app answered the other frame.
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { chromium, firefox } from 'playwright';
import { register } from './device.mjs';
import { OtherDevice } from './peer.mjs';

const [browserName = 'chromium', appUrl = 'http://127.0.0.1:8765/', hs = 'https://localhost', outDir = 'e2e-out',
  force = 'auto'] = process.argv.slice(2);
const hsName = new URL(hs).host;
const out = path.join(outDir, `${browserName}-widgets${force === 'auto' ? '' : `-${force}`}`);
fs.mkdirSync(out, { recursive: true });
const report = fs.createWriteStream(path.join(out, 'report.txt'));
const say = (...a) => {
  const line = `[${new Date().toISOString().slice(11, 23)}] ${a.join(' ')}`;
  process.stdout.write(line + '\n');
  report.write(line + '\n');
};
const PASSWORD = 'Correct-Horse-Battery-9';
const user = `widgets_${browserName}_${Date.now()}`;
const TOPIC = `widget topic ${Date.now()}`;
const WIDGET_PORT = 8766;
const widgetOrigin = `http://127.0.0.1:${WIDGET_PORT}`;
const CAP = 'org.matrix.msc2762.receive.state_event:m.room.topic';

// ---- The widget's pages ----

const WIDGET_HTML = `<!doctype html><meta charset="utf-8"><title>E2E widget</title>
<body style="background:#fff;font:14px sans-serif"><p id="s">starting</p>
<iframe id="other" src="/other.html" style="width:10px;height:10px;border:0"></iframe>
<script>
const q = new URLSearchParams(location.search);
const widgetId = q.get('widgetId');
const parentUrl = q.get('parentUrl');
const w = window.__w = { widgetId, parentUrl, got: [], answeredOther: [], caps: null, topic: null, errors: [] };
let parentOrigin = '*';
try { parentOrigin = new URL(parentUrl).origin; } catch (e) { w.errors.push('parentUrl: ' + parentUrl); }
const status = (t) => { document.getElementById('s').textContent = t; };
let n = 0;
const pending = {};
function request(action, data) {
  const requestId = 'widget-' + (++n);
  return new Promise((resolve) => {
    pending[requestId] = resolve;
    parent.postMessage({ api: 'fromWidget', widgetId, requestId, action, data }, parentOrigin);
  });
}
const reply = (m, response) => parent.postMessage({ ...m, response }, parentOrigin);
addEventListener('message', async (e) => {
  if (e.source !== parent) return;
  const m = e.data || {};
  w.got.push({ origin: e.origin, api: m.api, action: m.action, requestId: m.requestId });
  if (String(m.requestId || '').startsWith('other-')) { w.answeredOther.push(m.requestId); return; }
  if (m.api === 'fromWidget') { pending[m.requestId]?.(m.response); delete pending[m.requestId]; return; }
  if (m.action === 'capabilities') { reply(m, { capabilities: [${JSON.stringify(CAP)}] }); return; }
  if (m.action === 'notify_capabilities') {
    reply(m, {});
    w.caps = m.data;
    status('capabilities: ' + JSON.stringify(m.data.approved));
    const r = await request('org.matrix.msc2876.read_events', { type: 'm.room.topic', state_key: '' });
    w.topic = r?.events?.[0]?.content?.topic ?? null;
    w.readResponse = r;
    status('topic: ' + w.topic);
    return;
  }
  reply(m, {});
});
request('supported_api_versions', {}).then((r) => { w.versions = r?.supported_versions; });
</script>`;

// Same origin as the widget, but not the widget frame's window.
const OTHER_HTML = `<!doctype html><meta charset="utf-8"><script>
const q = new URLSearchParams(parent.location.search);
let i = 0;
const send = () => window.top.postMessage({ api: 'fromWidget', widgetId: q.get('widgetId'), requestId: 'other-' + (++i),
  action: 'supported_api_versions', data: {} }, '*');
send(); setInterval(send, 2000);
</script>`;

const widgetServer = http.createServer((req, res) => {
  const p = new URL(req.url, widgetOrigin).pathname;
  const body = p === '/widget.html' ? WIDGET_HTML : p === '/other.html' ? OTHER_HTML : null;
  if (!body) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    ...(browserName === 'firefox'
      ? { 'Cross-Origin-Embedder-Policy': 'require-corp', 'Cross-Origin-Resource-Policy': 'cross-origin' }
      : {}),
  });
  res.end(body);
});
await new Promise((r) => widgetServer.listen(WIDGET_PORT, '127.0.0.1', r));

// ---- The browser ----

const consoleLog = fs.createWriteStream(path.join(out, 'console.txt'));
let phase = 'start';
const profile = fs.mkdtempSync(path.join(os.tmpdir(), `vommet-widgets-${browserName}-`));
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
  if (force === 'js') await context.addInitScript(() => { WebAssembly.validate = () => false; });
  if (force === 'wasm' && browserName !== 'chromium') {
    await context.route('**/flutter_bootstrap.js', async (route) => {
      const res = await route.fetch();
      const body = (await res.text()).replace('config: {', 'config: { wasmAllowList: { gecko: true },');
      await route.fulfill({ response: res, body });
    });
  }
  context.on('request', (r) => {
    if (/main\.dart\.wasm(\?|$)/.test(r.url())) loaded.wasm = true;
    if (/main\.dart\.(m?js)(\?|$)/.test(r.url())) loaded.js = true;
  });
  page = context.pages()[0] ?? (await context.newPage());
  page.on('console', (m) => consoleLog.write(`[${phase}] [${m.type()}] ${m.text()}\n`));
  page.on('pageerror', (e) => consoleLog.write(`[${phase}] [pageerror] ${e.stack || e}\n`));
}

let shotN = 0;
async function shot(name) {
  await page.screenshot({ path: path.join(out, `${String(++shotN).padStart(2, '0')}-${name}.png`), timeout: 20000 })
    .catch((e) => say(`screenshot ${name} failed: ${e.message.split('\n')[0]}`));
}
async function dumpTree(name) {
  const tree = await page.evaluate(() => document.querySelector('flt-semantics-host')?.outerHTML ?? '(no semantics tree)').catch((e) => String(e));
  fs.writeFileSync(path.join(out, `semantics-${String(shotN).padStart(2, '0')}-${name}.html`), tree);
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
  await shot(`missing-${text.replace(/\W+/g, '_').slice(0, 30)}`);
  await dumpTree(`missing-${text.replace(/\W+/g, '_').slice(0, 30)}`);
  throw new Error(`"${text}" did not appear within ${timeout} ms`);
}
async function tapText(text, opts) {
  await waitText(text, opts);
  await byText(text, opts?.exact ?? false).last().click();
}
/// Taps [text], the exact label if there is one, else a label containing it.
async function tapLabel(text, timeout = 60000) {
  await waitText(text, { timeout });
  await tapText(text, { exact: await visible(text, true) });
}
const textInputs = () => page.locator('input:not([type=hidden]), textarea');
async function typeInto(input, value) {
  await input.click();
  await page.waitForTimeout(600);
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value, { delay: 10 });
}

async function api(token, method, p, body) {
  for (;;) {
    const r = await fetch(`${hs}/_matrix/client/v3${p}`, {
      method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body && JSON.stringify(body),
    });
    if (r.status === 429) {
      const wait = (await r.json().catch(() => ({}))).retry_after_ms ?? 5000;
      await new Promise((res) => setTimeout(res, wait + 200));
      continue;
    }
    if (!r.ok) throw new Error(`${method} ${p}: ${r.status} ${await r.text()}`);
    return r.json();
  }
}

const widgetFrame = () => page.frames().find((f) => f.url().startsWith(`${widgetOrigin}/widget.html`));
const widgetState = async () => (await widgetFrame()?.evaluate(() => window.__w).catch(() => null)) ?? null;

let own;
let exitCode = 1;
const failures = [];
try {
  phase = 'seed';
  await register(hs, user, PASSWORD);
  own = await OtherDevice.login(hs, user, PASSWORD, 'E2E other device');
  const recoveryKey = await own.setUpSecureMessaging();
  const room = await api(own.token, 'POST', '/createRoom', {
    name: 'Widget Room', preset: 'private_chat', topic: TOPIC,
    initial_state: [{
      type: 'im.vector.modular.widgets', state_key: 'e2e-widget',
      content: { id: 'e2e-widget', type: 'm.custom', name: 'E2E Widget', url: `${widgetOrigin}/widget.html` },
    }],
  });
  say(`seeded ${room.room_id} for ${own.userId} (widget ${widgetOrigin})`);

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
  const isolated = await page.evaluate(() => window.crossOriginIsolated);
  say(`app crossOriginIsolated=${isolated}`);

  phase = 'open widget';
  // Room rows and widget tiles are labelled with their avatar letter too.
  await tapText('Widget Room', { timeout: 120000 });
  await page.waitForTimeout(2000);
  await tapLabel('Widgets');
  await waitText('E2E Widget');
  await shot('widgets-tab');
  await tapText('E2E Widget');
  await tapLabel('Open Widget');

  phase = 'handshake';
  for (let end = Date.now() + 60000; !widgetFrame() && Date.now() < end;) await page.waitForTimeout(500);
  if (!widgetFrame()) throw new Error('no widget frame on the page');
  const attrs = await page.evaluate((o) => {
    const find = (root) => {
      for (const f of root.querySelectorAll('iframe')) if (f.src.startsWith(o)) return f;
      for (const el of root.querySelectorAll('*')) if (el.shadowRoot) { const f = find(el.shadowRoot); if (f) return f; }
      return null;
    };
    const f = find(document);
    return f && { sandbox: f.getAttribute('sandbox'), allow: f.getAttribute('allow'), credentialless: f.hasAttribute('credentialless') };
  }, widgetOrigin);
  say(`frame: ${JSON.stringify(attrs)}`);
  await waitText('would like permission', { timeout: 60000 });
  await shot('permission');
  await tapLabel('Submit');

  phase = 'read state';
  let st;
  for (let end = Date.now() + 60000; Date.now() < end;) {
    st = await widgetState();
    if (st?.topic) break;
    await page.waitForTimeout(500);
  }
  // Leave the other frame a few more tries after the handshake.
  await page.waitForTimeout(5000);
  st = await widgetState();
  await shot('widget-open');
  fs.writeFileSync(path.join(out, 'widget-state.json'), JSON.stringify(st, null, 1));
  say(`widget: parentUrl=${st?.parentUrl} versions=${st?.versions?.length ?? 'none'} approved=${JSON.stringify(st?.caps?.approved)} topic=${JSON.stringify(st?.topic)}`);
  say(`widget saw ${st?.got?.length ?? 0} messages from the app; origins ${JSON.stringify([...new Set((st?.got ?? []).map((g) => g.origin))])}`);
  const appOrigin = new URL(appUrl).origin;

  if (!st) failures.push('widget page state unreadable');
  if (st && new URL(st.parentUrl).origin !== appOrigin) failures.push(`parentUrl ${st.parentUrl} is not the app's origin`);
  if (!st?.versions?.length) failures.push('no supported_api_versions answer');
  if (!st?.caps?.approved?.includes(CAP)) failures.push(`capability not approved: ${JSON.stringify(st?.caps)}`);
  if (st?.topic !== TOPIC) failures.push(`topic read back as ${JSON.stringify(st?.topic)}, want ${JSON.stringify(TOPIC)}`);
  if (st?.got?.some((g) => g.origin !== appOrigin)) failures.push('a message came from another origin');
  if (st?.answeredOther?.length) failures.push(`the app answered the other frame: ${st.answeredOther.join(', ')}`);
  if (st?.errors?.length) failures.push(`widget errors: ${st.errors.join('; ')}`);
  if (browserName === 'chromium' && isolated && !attrs?.credentialless) failures.push('isolated app framed the widget without credentialless');

  const want = force === 'auto' ? null : force;
  if (want && !loaded[want]) failures.push(`expected the ${want} build to run`);
  for (const f of failures) say(`FAIL: ${f}`);
  if (!failures.length) say('widget OK: capability granted through the dialog, topic read through the app, other frame ignored');
  exitCode = failures.length ? 1 : 0;
} catch (e) {
  say(`FAILED: ${e.stack || e}`);
  await shot('error').catch(() => {});
  await dumpTree('error').catch(() => {});
} finally {
  await context?.close().catch(() => {});
  try { own?.stop(); } catch {}
  widgetServer.close();
  report.end();
  consoleLog.end();
  process.exit(exitCode);
}
