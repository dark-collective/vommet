#!/usr/bin/env node
// Vommet: a fast check (node only, no browser) of the script the desktop
// widget window injects into every widget page (commet/assets/data/
// widgets_ipc.js, put together as rust/rust/src/widget_runner.rs does).
//
// It loads that script into a stand-in window, plays the app's side of the
// widget API (protocol.mjs) through the same JSON hops as the real runner
// (window.ipc -> stdout line -> host; host line -> window.onMessagePolyfill),
// and runs a widget client against it. The client is a strict one by default
// (it ignores messages whose source isn't window.parent, as Watch Together and
// Park Chess do); --widget-api <file> runs a real widget's widget-api.js
// instead (the nightly passes Watch Together's and Park Chess's).
//
// 2026-10-19: messages had no source, so Watch Together never answered the
// capability request and hung on "Confirming who you are". --self-test also
// checks that this check catches that.
//
//   node .vommet/widgets/ipc-check.mjs [--widget-api <file>]... [--self-test]
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { FakeHost } from "./protocol.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");

export function runnerScript(ipcSource) {
  const ipc = ipcSource ?? fs.readFileSync(path.join(root, "commet/assets/data/widgets_ipc.js"), "utf8");
  const common = fs.readFileSync(path.join(root, "commet/assets/data/widgets_common.js"), "utf8");
  const call = fs.readFileSync(path.join(root, "rust/rust/javascript/call_ipc.js"), "utf8");
  return ipc.replace("//${SEND_IPC_CODE}", call).replace("//${WIDGETS_COMMON}", common);
}

// A strict widget client: what Watch Together's and Park Chess's
// widget-api.js do, in the fewest lines.
const STRICT_CLIENT = `
class WidgetApi {
  constructor({ widgetId, capabilities }) {
    this.widgetId = widgetId; this.capabilities = capabilities || []; this.pending = new Map(); this.n = 0;
    this.granted = []; this.ready = new Promise((r) => (this._ready = r)); this.openid = new Map();
    window.addEventListener("message", (e) => this._on(e));
  }
  start() { this._req("supported_api_versions", {}).catch(() => {}); return this.ready; }
  _post(m) { window.parent.postMessage(m, "*"); }
  _req(action, data) {
    const requestId = "strict-" + ++this.n;
    return new Promise((resolve, reject) => {
      this.pending.set(requestId, { resolve, reject });
      this._post({ api: "fromWidget", widgetId: this.widgetId, requestId, action, data });
    }).then((response) => ({ requestId, response }));
  }
  _on(e) {
    if (e.source !== window.parent) return;
    const m = e.data;
    if (!m || typeof m !== "object") return;
    if (m.api === "fromWidget" && m.response !== undefined) {
      const p = this.pending.get(m.requestId); if (!p) return; this.pending.delete(m.requestId);
      m.response.error ? p.reject(new Error(m.response.error.message)) : p.resolve(m.response); return;
    }
    if (m.api !== "toWidget" || m.response !== undefined) return;
    const reply = (response) => this._post({ ...m, response });
    if (m.action === "capabilities") reply({ capabilities: this.capabilities });
    else if (m.action === "notify_capabilities") { this.granted = m.data.approved; reply({}); this._ready(this.granted); }
    else if (m.action === "openid_credentials") { reply({}); const w = this.openid.get(m.data.original_request_id); if (w) w(m.data); }
    else reply({});
  }
  async getOpenID() {
    const { requestId, response } = await this._req("get_openid", {});
    if (response.state === "allowed") return response;
    return new Promise((r) => this.openid.set(requestId, r));
  }
  async readEvents(type) { return (await this._req("org.matrix.msc2876.read_events", { type })).response.events; }
}
globalThis.WidgetApi = WidgetApi;
`;

// A real widget-api.js is an ES module; run it as a script in the window.
function clientSource(file) {
  if (!file) return STRICT_CLIENT;
  const src = fs.readFileSync(file, "utf8").replace(/^export\s+(class|function|const)\s/gm, "$1 ");
  return `${src}\n;globalThis.WidgetApi = WidgetApi;`;
}

const CAPS = ["org.matrix.msc2762.receive.event:im.nether.check", "org.matrix.msc2762.send.event:im.nether.check"];

/** One widget start-up through the injected script. Resolves to the steps reached. */
export async function simulate({ ipcSource, clientFile, timeoutMs = 5000 } = {}) {
  const lines = [];
  const win = {
    console: { log() {}, warn() {}, error: (...a) => lines.push(`console.error ${a.join(" ")}`) },
    setTimeout,
    clearTimeout,
    URL,
    Promise,
    ArrayBuffer,
    Uint8Array,
    Blob,
    atob,
    btoa,
    document: { referrer: "" },
    location: { href: "https://widget.example/?widgetId=check" },
    onmessage: null,
  };
  win.window = win;
  win.parent = win; // the widget page is the window's top-level page
  win.top = win;
  win.self = win;
  win.addEventListener = () => {};
  const ctx = vm.createContext(win);
  const widgetId = "nightly-check";

  const host = new FakeHost({
    widgetId,
    log: (s) => lines.push(s),
    // Dart: jsonEncode + "\n" to stdin; Rust: window.onMessagePolyfill(<JSON string>)
    send: (msg) => {
      const line = JSON.stringify(msg);
      setImmediate(() => vm.runInContext(`window.onMessagePolyfill(${JSON.stringify(line)})`, ctx));
    },
  });

  // Rust IPC handler: {type:"Widget", data} -> {type:"PostMessage", message} -> stdout line.
  win.ipc = {
    postMessage: (body) => {
      const outer = JSON.parse(body);
      const inner = JSON.parse(outer.data);
      const line = inner.message;
      setImmediate(() => host.receive(JSON.parse(line)));
    },
  };

  vm.runInContext(runnerScript(ipcSource), ctx, { filename: "widgets_ipc.js" });
  vm.runInContext(clientSource(clientFile), ctx, { filename: clientFile || "strict-client.js" });

  const result = { steps: host.steps, lines, openid: null, events: null, wantsOpenid: false, reads: false };
  const run = (async () => {
    const api = new win.WidgetApi({ widgetId, parentUrl: "commet://widget", capabilities: CAPS, onEvent() {} });
    await api.start();
    if (typeof api.getOpenID === "function") {
      result.wantsOpenid = true;
      const t = await api.getOpenID();
      result.openid = t && t.access_token;
    }
    if (typeof api.readEvents === "function") {
      result.reads = true;
      result.events = await api.readEvents("im.nether.check").catch((e) => `error: ${e.message}`);
    }
  })();
  await Promise.race([run, new Promise((r) => setTimeout(r, timeoutMs))]).catch((e) => lines.push(`client error: ${e.message}`));
  // The widget's answer to openid_credentials can land after its own token.
  if (result.openid) await host.waitFor("openid_credentials answered", 1000).catch(() => {});
  return result;
}

const REQUIRED = ["asked supported_api_versions", "capabilities answered", "notify_capabilities answered"];

function verdict(name, r) {
  const missing = REQUIRED.filter((s) => !r.steps.has(s));
  if (r.wantsOpenid && !r.steps.has("openid_credentials answered")) missing.push("openid_credentials answered");
  if (r.wantsOpenid && !r.openid) missing.push("widget got its OpenID token");
  if (r.reads && !Array.isArray(r.events)) missing.push(`room events read (${r.events})`);
  return missing.length ? `${name}: stopped before: ${missing.join(", ")}\n  ${r.lines.slice(-12).join("\n  ")}` : null;
}

async function main(argv) {
  const files = [];
  let selfTest = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--widget-api") files.push(argv[++i]);
    else if (argv[i] === "--self-test") selfTest = true;
    else throw new Error(`unknown argument ${argv[i]}`);
  }
  const failures = [];
  for (const f of [null, ...files]) {
    const name = f ? path.basename(path.dirname(f)) + "/" + path.basename(f) : "strict client";
    const r = await simulate({ clientFile: f, timeoutMs: f ? 20000 : 5000 });
    const v = verdict(name, r);
    if (v) failures.push(v);
    else console.log(`ok: ${name} (${[...r.steps].join(" > ")})`);
  }
  if (selfTest) {
    // Without a source on the events the strict client must hang: proves the
    // check would have caught the 2026-10-19 regression.
    const broken = fs
      .readFileSync(path.join(root, "commet/assets/data/widgets_ipc.js"), "utf8")
      .replace(/^\s*source:.*$/m, "");
    const r = await simulate({ ipcSource: broken, timeoutMs: 1500 });
    if (r.steps.has("capabilities answered")) failures.push("self-test: a source-less event still got through; the check can't catch the regression");
    else console.log("ok: self-test (messages without a source are caught)");
  }
  if (failures.length) {
    console.error(`widget IPC check FAILED\n${failures.join("\n")}`);
    process.exit(1);
  }
  console.log("widget IPC check passed");
  // A real widget-api.js leaves its own timers running.
  process.exit(0);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(`widget IPC check ERROR: ${e.stack || e}`);
    process.exit(2);
  });
}
