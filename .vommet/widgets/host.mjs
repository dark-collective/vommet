#!/usr/bin/env node
// Vommet: the nightly widget check's driver. For every widget in
// commet/assets/data/widget_catalog.json (plus EXTRA below) it opens the
// widget in the real desktop widget window (rust/rust/src/widget_runner.rs,
// built by run.sh) and plays the app's side of the widget API over the
// window's stdin/stdout (newline-delimited JSON, as
// matrix_subprocess_widget_transceiver.dart does), with protocol.mjs. It
// records how far each widget gets; "direct" widgets go to direct.mjs
// (headless Chromium) instead, as the app opens those in a browser.
//
//   node host.mjs <widget window binary> <out dir>
//
// WIDGET_URLS='{"park-chess": "https://<preview>/widgets/park-chess/play/?..."}'
// (or the same JSON in .vommet/ci/widget-urls, for a pushed trial) tries a
// widget's page from elsewhere (a site preview) with the same checks.
//
// Optional real sign-in (else a made-up OpenID token, which Watch Together's
// server is expected to refuse cleanly):
//   NIGHTLY_MATRIX_HOMESERVER, NIGHTLY_MATRIX_USER, NIGHTLY_MATRIX_TOKEN  a test
//   account; NIGHTLY_WT_ROOM  a room Watch Together serves that account in.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FakeHost, widgetUrl } from "./protocol.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const [bin, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });

// Widgets the catalog doesn't list (yet) but Nether runs.
const EXTRA = [
  {
    id: "watch-together",
    name: "Watch Together",
    url: "https://nether.channel/widget/?widgetId=$matrix_widget_id&roomId=$matrix_room_id",
  },
];

// Ours (Nether/Vommet): a failure fails the nightly. Others are reported as
// warnings: their code isn't ours to fix, but a break is worth knowing.
const OURS = new Set(["watch-together", "park-chess", "drawpile"]);

// How far each widget must get. Every framed widget must finish the
// capability handshake; these go further.
const BASE = ["asked supported_api_versions", "capabilities answered", "notify_capabilities answered"];
const EXPECT = {
  "watch-together": [...BASE, "asked get_openid", "openid_credentials answered"],
  "park-chess": [...BASE, "asked org.matrix.msc2876.read_events"],
};

const catalog = JSON.parse(fs.readFileSync(path.join(root, "commet/assets/data/widget_catalog.json"), "utf8"));
const widgets = [...catalog.widgets, ...EXTRA.filter((e) => !catalog.widgets.some((w) => w.id === e.id))];
const urlsFile = path.join(root, ".vommet/ci/widget-urls");
const overrides = JSON.parse(process.env.WIDGET_URLS || (fs.existsSync(urlsFile) ? fs.readFileSync(urlsFile, "utf8") : "{}"));
for (const w of widgets) if (overrides[w.id]) w.url = overrides[w.id];
const only = process.env.WIDGETS ? new Set(process.env.WIDGETS.split(/[ ,]+/)) : null;

const real = ["NIGHTLY_MATRIX_HOMESERVER", "NIGHTLY_MATRIX_USER", "NIGHTLY_MATRIX_TOKEN", "NIGHTLY_WT_ROOM"].every((k) => process.env[k]);
const roomId = real ? process.env.NIGHTLY_WT_ROOM : "!vommet-nightly:example.org";
const userId = real ? process.env.NIGHTLY_MATRIX_USER : "@vommet-nightly:example.org";

async function openidToken() {
  if (!real) return undefined;
  const hs = process.env.NIGHTLY_MATRIX_HOMESERVER.replace(/\/$/, "");
  const r = await fetch(`${hs}/_matrix/client/v3/user/${encodeURIComponent(userId)}/openid/request_token`, {
    method: "POST",
    headers: { Authorization: `Bearer ${process.env.NIGHTLY_MATRIX_TOKEN}`, "Content-Type": "application/json" },
    body: "{}",
  });
  if (!r.ok) throw new Error(`test account OpenID token: HTTP ${r.status}`);
  return r.json();
}

function screenshot(file) {
  spawnSync("ffmpeg", ["-loglevel", "error", "-y", "-f", "x11grab", "-video_size", "1280x720", "-i", process.env.DISPLAY, "-frames:v", "1", file], {
    timeout: 15000,
  });
}

async function framed(w, timeoutMs) {
  const widgetId = `nightly-${w.id}`;
  const url = widgetUrl(w.url, {
    widgetId,
    userId,
    roomId,
    displayName: "Vommet nightly",
    deviceId: "NIGHTLY",
    baseUrl: "https://example.org",
    theme: "dark",
  });
  const log = fs.createWriteStream(path.join(out, `${w.id}.log`));
  const t0 = Date.now();
  const note = (s) => log.write(`${((Date.now() - t0) / 1000).toFixed(1)}s ${s}\n`);
  note(`open ${url.replace(/([?&](?:key|session)=)[^&]+/g, "$1…")}`);

  const child = spawn(bin, [`--title=${w.name}`, `--url=${url}`], { stdio: ["pipe", "pipe", "pipe"] });
  let exited = null;
  child.on("exit", (code, sig) => {
    exited = `window exited (${code ?? sig})`;
    note(exited);
  });
  child.stderr.on("data", (d) => log.write(d));
  child.stdin.on("error", () => {});

  const host = new FakeHost({
    widgetId,
    log: note,
    openid: await openidToken(),
    send: (msg) => child.stdin.write(JSON.stringify(msg) + "\n"),
  });
  let buf = "";
  child.stdout.on("data", (d) => {
    buf += d;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        note(`stdout: ${line.slice(0, 200)}`);
        continue;
      }
      host.receive(msg).catch((e) => note(`host error: ${e.message}`));
    }
  });

  const want = EXPECT[w.id] || BASE;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline && !exited && !want.every((s) => host.steps.has(s))) await new Promise((r) => setTimeout(r, 250));
  // Let the page settle for the screenshot.
  if (!exited) await new Promise((r) => setTimeout(r, 3000));
  screenshot(path.join(out, `${w.id}.png`));
  child.stdin.end(); // the window exits when its stdin closes
  setTimeout(() => child.kill("SIGKILL"), 3000).unref();

  const missing = want.filter((s) => !host.steps.has(s));
  const res = {
    id: w.id,
    name: w.name,
    ok: missing.length === 0,
    steps: [...host.steps],
    detail: missing.length ? `stopped before "${missing[0]}"${exited ? `; ${exited}` : ""}` : `reached ${want[want.length - 1]}`,
  };

  // Watch Together: does its server take the token the widget was given?
  if (w.id === "watch-together" && res.ok) {
    const r = await fetch("https://nether.channel/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json", "User-Agent": "Mozilla/5.0 (Vommet nightly widget check)" },
      body: JSON.stringify({ room: roomId, openid: host.openid }),
    }).catch((e) => ({ ok: false, status: 0, json: async () => ({ error: e.message }) }));
    const body = await r.json().catch(() => ({}));
    note(`server sign-in: HTTP ${r.status} ${JSON.stringify(body).slice(0, 200)}`);
    if (real) {
      res.ok = r.ok && !!body.token;
      res.detail = res.ok ? "signed in to the Watch Together server" : `server refused the test account: HTTP ${r.status} ${body.error || ""}`;
    } else {
      // A made-up token in a made-up room: the server must answer, and say no.
      res.ok = r.status === 403 && typeof body.error === "string";
      res.detail = res.ok
        ? `handshake + OpenID done; server up (refused the made-up token as expected). Real sign-in not checked: no test account`
        : `server didn't refuse cleanly: HTTP ${r.status} ${JSON.stringify(body).slice(0, 120)}`;
    }
  }
  log.end();
  return res;
}

function direct(w) {
  const url = widgetUrl(w.url, { widgetId: `nightly-${w.id}`, userId, roomId, theme: "dark" });
  const r = spawnSync("node", [path.join(here, "direct.mjs"), w.id, url, out], { encoding: "utf8", timeout: 300000 });
  let j;
  try {
    j = JSON.parse(r.stdout.trim().split("\n").pop());
  } catch {
    j = { ok: false, step: "start the browser", detail: (r.stderr || r.error?.message || "no output").trim().split("\n").pop() };
  }
  return { id: w.id, name: w.name, ok: !!j.ok, steps: [j.step], detail: j.ok ? j.detail : `${j.step}: ${j.detail}` };
}

const results = [];
for (const w of widgets) {
  if (only && !only.has(w.id)) continue;
  const r = w.direct ? direct(w) : await framed(w, Number(process.env.WIDGET_TIMEOUT || 60) * 1000);
  r.ours = OURS.has(w.id);
  r.runner = w.direct ? "chromium (direct)" : "widget window";
  results.push(r);
  console.log(`${r.ok ? "ok  " : r.ours ? "FAIL" : "warn"} ${w.name}: ${r.detail}`);
}
fs.writeFileSync(path.join(out, "results.json"), JSON.stringify({ real_signin: real, results }, null, 1));
process.exit(results.some((r) => !r.ok && r.ours) ? 1 : 0);
