#!/usr/bin/env node
// Vommet: the nightly check for "direct" catalog widgets (Drawpile), which
// the app opens as a top-level page in a browser rather than in its widget
// window. Loads the widget's page in headless Chromium as the app would open
// it, follows it to the real app and waits for that app to start.
//
//   node direct.mjs <widget id> <url> <out dir>
// Prints one JSON line {ok, step, detail, warn}; exit 1 when it didn't load.
import fs from "node:fs";
import path from "node:path";

const [id, url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || "playwright");

const logs = [];
let step = "open the widget page";
let warn; // a non-fatal finding, shown as a CI warning by host.mjs
const result = (ok, detail) => {
  fs.writeFileSync(path.join(out, `${id}-direct.log`), logs.join("\n") + "\n");
  console.log(JSON.stringify({ ok, step, detail, warn }));
  process.exit(ok ? 0 : 1);
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on("console", (m) => logs.push(`${m.type()}: ${m.text()}`.slice(0, 400)));
page.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`.slice(0, 400)));
const shot = (name) => page.screenshot({ path: path.join(out, `${id}-${name}.png`) }).catch(() => {});

try {
  await page.goto(url, { waitUntil: "load", timeout: 60000 });

  if (id === "drawpile") {
    step = "landing page shows the join link";
    await page.waitForSelector("#direct:not([hidden])", { timeout: 15000 });
    if (await page.isVisible("#broken")) result(false, "the page says the link is missing its session details");
    const join = await page.getAttribute("#join", "href");
    const j = new URL(join);
    if (j.origin !== "https://web.drawpile.net" || !j.searchParams.get("host") || !/^vm-/.test(j.searchParams.get("session") || "") || !j.hash)
      result(false, `unexpected join link ${j.origin}${j.pathname}?${[...j.searchParams.keys()].join("&")}`);
    await shot("landing");

    step = "Drawpile's web app starts";
    await page.goto(join, { waitUntil: "load", timeout: 60000 });
    const iso = await page.evaluate(() => ({ coi: self.crossOriginIsolated, sab: typeof SharedArrayBuffer }));
    if (!iso.coi || iso.sab !== "function") result(false, `not cross-origin isolated (${JSON.stringify(iso)}): SharedArrayBuffer missing`);
    // web.drawpile.net shows its launcher (version picker + Start) first.
    const start = page.getByRole("button", { name: /^start$/i });
    await start.waitFor({ state: "visible", timeout: 30000 }).catch(() => {});
    if (await start.isVisible()) await start.click();
    // The Qt/WebAssembly app draws in a shadow-DOM canvas; its console says
    // how far it got. Nobody hosts the test session, so "Session not found"
    // is the expected answer: the app is up and talked to the server.
    // Only "app loaded" is required: the server and login lines depend on how
    // much the current web.drawpile.net build logs (it logged neither after
    // 10-22), so their absence is a warning. The server is the one the join
    // link names (fix/557-drawpile-own-server moved it off pub.drawpile.net).
    const host = j.searchParams.get("host").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const required = [["app loaded", /Persistent file system loaded/]];
    const optional = [
      [`connecting to ${j.searchParams.get("host")}`, new RegExp(`WebSocketServer connecting to .*${host}`)],
      ["the server answered the join", /Login error|Login failed|Session not found|Logged in|Joined session/i],
    ];
    const seen = ([, re]) => logs.some((l) => re.test(l));
    const t0 = Date.now();
    while (Date.now() - t0 < 120000 && ![...required, ...optional].every(seen)) {
      // Once the app is up, give the server lines a short grace period only.
      if (required.every(seen) && Date.now() - t0 > 30000) break;
      await page.waitForTimeout(1000);
    }
    await shot("app");
    const missing = required.filter((m) => !seen(m)).map(([n]) => n);
    if (missing.length) result(false, `stopped before: ${missing.join(", ")}`);
    const fatal = logs.find((l) => /pageerror|SharedArrayBuffer not|Out of bounds|Aborted\(/i.test(l));
    if (fatal) result(false, `app error: ${fatal}`);
    const quiet = optional.filter((m) => !seen(m)).map(([n]) => n);
    if (quiet.length) warn = `the app loaded but logged no line for: ${quiet.join(", ")}`;
    result(true, "landing page, join link and the Drawpile app all loaded");
  }

  // Any other direct widget: the page loads without script errors.
  step = "page loads";
  await page.waitForTimeout(10000);
  await shot("page");
  const err = logs.find((l) => l.startsWith("pageerror"));
  if (err) result(false, err);
  result(true, "page loaded");
} catch (e) {
  await shot("failed");
  result(false, e.message.split("\n")[0].slice(0, 300));
}
