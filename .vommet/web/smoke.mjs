// Vommet web smoke test: loads the app in headless Chrome over CDP (Node's
// built-in WebSocket, no npm packages), prints console errors, uncaught
// exceptions and failed requests, and saves a screenshot. Exit 1 on any
// uncaught exception.
//   node smoke.mjs <devtools ws url> <app url> <out.png> <seconds>
import fs from 'node:fs';
const [ws, url, out, secs] = process.argv.slice(2);
const sock = new WebSocket(ws);
let id = 0; let exceptions = 0; let logged = 0; const pending = new Map();
const send = (method, params = {}, sessionId) => new Promise(r => { const i = ++id; pending.set(i, r); sock.send(JSON.stringify({ id: i, method, params, sessionId })); });
sock.onmessage = async (m) => {
  const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { pending.get(d.id)(d.result ?? d); pending.delete(d.id); return; }
  // Everything the app logs (Log.* prints go to console.log), capped.
  if (d.method === 'Runtime.consoleAPICalled' && logged++ < 300)
    console.log(`[console.${d.params.type}]`, d.params.args.map(a => a.value ?? a.description).join(' ').slice(0, 400));
  if (d.method === 'Runtime.exceptionThrown') exceptions++, console.log('[exception]', (d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text).slice(0, 600));
  if (d.method === 'Network.requestWillBeSent' && !d.params.request.url.startsWith('http://127.0.0.1') && !d.params.request.url.startsWith('data:'))
    console.log('[request]', d.params.request.method, d.params.request.url.slice(0, 200));
  if (d.method === 'Network.loadingFailed') console.log('[netfail]', d.params.errorText, d.params.requestId);
  if (d.method === 'Network.responseReceived' && d.params.response.status >= 400) console.log('[http]', d.params.response.status, d.params.response.url);
};
sock.onopen = async () => {
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  for (const d of ['Runtime', 'Network', 'Page']) await send(`${d}.enable`, {}, sessionId);
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false }, sessionId);
  await send('Page.navigate', { url }, sessionId);
  await new Promise(r => setTimeout(r, Number(secs) * 1000));
  const shot = await send('Page.captureScreenshot', { format: 'png' }, sessionId);
  fs.writeFileSync(out, Buffer.from(shot.data, 'base64'));
  const t = await send('Runtime.evaluate', { expression: 'document.title' }, sessionId);
  console.log('[title]', t.result?.value, '| uncaught exceptions:', exceptions);
  process.exit(exceptions ? 1 : 0);
};
