// Vommet web smoke test: loads the app in headless Chrome over CDP (Node's
// built-in WebSocket, no npm packages), prints console errors, uncaught
// exceptions and failed requests, and saves a screenshot. Exit 1 on any
// uncaught exception, on any request to Google (fonts, CDN), or when the
// build that ran isn't the expected one, on the engine's missing-glyph
// warning, or when the first load exceeds $SMOKE_BUDGET_MB (if set). Starts
// from an empty browser cache, so the size is a first visit's. Then types
// emoji into the first text field it can focus (Tab) and reports whether the
// engine fetched the Noto Color Emoji fallback for them (on demand):
//   expect=wasm  the WebAssembly build ran (main.dart.wasm, skwasm) and the
//                page is cross-origin isolated
//   expect=js    the JS fallback ran (main.dart.mjs/.wasm never fetched);
//                the page pretends to lack WasmGC
//   node smoke.mjs <devtools ws url> <app url> <out.png> <seconds> [expect]
import fs from 'node:fs';
const [ws, url, out, secs, expect = 'any'] = process.argv.slice(2);
const sock = new WebSocket(ws);
let id = 0; let exceptions = 0; let missingGlyphs = 0; let logged = 0; const pending = new Map();
const google = [];
const isGoogle = (u) => /^https?:\/\/([^/]*\.)?(gstatic\.com|googleapis\.com|google\.com)(\/|$)/.test(u);
const send = (method, params = {}, sessionId) => new Promise(r => { const i = ++id; pending.set(i, r); sock.send(JSON.stringify({ id: i, method, params, sessionId })); });
sock.onmessage = async (m) => {
  const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { pending.get(d.id)(d.result ?? d); pending.delete(d.id); return; }
  // Everything the app logs (Log.* prints go to console.log), capped.
  if (d.method === 'Runtime.consoleAPICalled' && /Could not find a set of Noto fonts/.test(JSON.stringify(d.params.args))) missingGlyphs++;
  if (d.method === 'Runtime.consoleAPICalled' && logged++ < 300)
    console.log(`[console.${d.params.type}]`, d.params.args.map(a => a.value ?? a.description).join(' ').slice(0, 400));
  if (d.method === 'Runtime.exceptionThrown') exceptions++, console.log('[exception]', (d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text).slice(0, 600));
  if (d.method === 'Network.requestWillBeSent') {
    const u = d.params.request.url;
    if (isGoogle(u)) google.push(u);
    if (!u.startsWith('http://127.0.0.1') && !u.startsWith('data:') && !u.startsWith('blob:'))
      console.log('[request]', d.params.request.method, u.slice(0, 200));
  }
  if (d.method === 'Network.loadingFailed') console.log('[netfail]', d.params.errorText, d.params.requestId);
  if (d.method === 'Network.responseReceived' && d.params.response.status >= 400) console.log('[http]', d.params.response.status, d.params.response.url);
};
// A frozen page never answers Runtime.evaluate: fail instead of hanging the job.
setTimeout(() => { console.log('[FAIL] page or DevTools stopped answering'); process.exit(1); }, (Number(secs) + 90) * 1000);
sock.onopen = async () => {
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  for (const d of ['Runtime', 'Network', 'Page']) await send(`${d}.enable`, {}, sessionId);
  await send('Network.clearBrowserCache', {}, sessionId);
  // The loader picks the JS build when WebAssembly.validate rejects its WasmGC probe.
  if (expect === 'js')
    await send('Page.addScriptToEvaluateOnNewDocument', { source: 'WebAssembly.validate = () => false;' }, sessionId);
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false }, sessionId);
  await send('Page.navigate', { url }, sessionId);
  await new Promise(r => setTimeout(r, Number(secs) * 1000));
  const ev = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true }, sessionId)).result?.value;
  // Everything up to here is the first load; the emoji probe comes after.
  const res = await ev(`performance.getEntriesByType('resource').map(e => [e.name.split('?')[0], e.transferSize, e.decodedBodySize])`) || [];
  const nav = await ev(`(performance.getEntriesByType('navigation')[0] || {}).transferSize || 0`) || 0;
  const key = async (k, code, vk) => { for (const type of ['rawKeyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: k, code, windowsVirtualKeyCode: vk }, sessionId); };
  let typed = false; let fallbackMissing = false;
  for (let i = 0; i < 4 && !typed; i++) {
    await key('Tab', 'Tab', 9); await new Promise(r => setTimeout(r, 700));
    typed = await ev(`['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)`);
  }
  if (typed) {
    // Common, Unicode 15 and 16, and flag emoji (the bundled Twemoji draws
    // what it has), and a CJK character no bundled font has, which must make
    // the engine fetch a fallback font piece from fonts/fallback/.
    const before = new Set(res.map(([u]) => u));
    await send('Input.insertText', { text: ' \u{1F642}\u{1FABF}\u{1FAE9}\u{1F1E8}\u{1F1E6}\u6F22' }, sessionId);
    await new Promise(r => setTimeout(r, 6000));
    const later = (await ev(`performance.getEntriesByType('resource').map(e => e.name.split('?')[0])`) || []).filter(u => !before.has(u) && u.includes('/fonts/fallback/'));
    const emoji = later.filter(u => /notocoloremoji/i.test(u));
    console.log(`[emoji] typed into a text field; fallback fonts fetched on demand: ${later.length} (Noto Color Emoji: ${emoji.length})`, later.map(u => u.split('/fallback/').pop()).join(' '));
    if (!later.length) fallbackMissing = true;
  } else console.log('[emoji] no text field took focus; emoji probe skipped');
  const shot = await send('Page.captureScreenshot', { format: 'png' }, sessionId);
  fs.writeFileSync(out, Buffer.from(shot.data, 'base64'));
  const title = await ev('document.title');
  const isolated = await ev('self.crossOriginIsolated');
  const base = (u) => u.split('/').pop();
  const has = (n) => res.some(([u]) => base(u) === n);
  const wasm = has('main.dart.wasm'); const js = has('main.dart.js');
  const renderer = has('skwasm.wasm') ? 'skwasm' : has('skwasm_heavy.wasm') ? 'skwasm_heavy' : has('canvaskit.wasm') ? 'canvaskit' : '?';
  const total = res.reduce((s, r) => s + (r[1] || 0), 0);
  console.log('[title]', title, '| uncaught exceptions:', exceptions);
  console.log(`[build] ${wasm ? 'wasm' : js ? 'js' : 'unknown'} (renderer ${renderer}), crossOriginIsolated=${isolated}`);
  console.log(`[size] loaded ${((total + nav) / 1e6).toFixed(2)} MB in ${res.length + 1} requests`);
  for (const [u, t] of res.filter(r => r[1] > 100000).sort((a, b) => b[1] - a[1])) console.log(`[size]   ${base(u)} ${(t / 1e6).toFixed(2)} MB`);
  const fonts = res.filter(([u]) => /\.(ttf|otf|woff2?)$/i.test(u));
  console.log(`[fonts] ${fonts.length} fetched, ${(fonts.reduce((s, r) => s + (r[1] || 0), 0) / 1e6).toFixed(2)} MB`);
  const seen = {};
  for (const [u, t] of res) if (t > 0) seen[u] = (seen[u] || 0) + 1;
  for (const [u, n] of Object.entries(seen)) if (n > 1) console.log(`[size]   fetched ${n} times: ${u.replace(/^https?:\/\/[^/]+/, '')}`);
  let fail = exceptions > 0;
  if (fallbackMissing) fail = true, console.log('[FAIL] typed text no bundled font has, but no fallback font was fetched');
  if (missingGlyphs) fail = true, console.log(`[FAIL] engine reported missing glyphs ${missingGlyphs} time(s)`);
  const budget = Number(process.env.SMOKE_BUDGET_MB || 0);
  if (budget && (total + nav) / 1e6 > budget) fail = true, console.log(`[FAIL] first load ${((total + nav) / 1e6).toFixed(2)} MB is over the ${budget} MB budget`);
  if (google.length) fail = true, console.log(`[FAIL] ${google.length} request(s) to Google:`, google.slice(0, 5).join(' '));
  if (expect === 'wasm' && !(wasm && !js && isolated === true)) fail = true, console.log('[FAIL] expected the WebAssembly build, cross-origin isolated');
  if (expect === 'js' && !(js && !wasm)) fail = true, console.log('[FAIL] expected the JS fallback build');
  process.exit(fail ? 1 : 0);
};
