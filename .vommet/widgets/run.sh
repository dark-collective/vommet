#!/usr/bin/env bash
# Vommet: the nightly widget check (vommet-nightly.yml "widgets" job on the
# GitHub copy). Builds the desktop widget window on its own (runner/), then:
#   1. ipc-check.mjs: the injected script against the strict client and the
#      live Watch Together and Park Chess widget-api.js (node, no browser);
#   2. host.mjs: every catalog widget (+ Watch Together) in the real widget
#      window under Xvfb, with a stand-in app on its stdin/stdout; "direct"
#      widgets (Drawpile) in headless Chromium.
# Output (logs, screenshots, results.json, summary.md) in $OUT.
# Needs: cargo, node >= 20, Xvfb, ffmpeg, libwebkit2gtk-4.1-dev, Playwright's
# Chromium for direct widgets.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
OUT=${OUT:-$root/widgets-out}
mkdir -p "$OUT"
fail=0

step() { echo "== $*"; }

step "build the widget window"
cp "$root/Cargo.lock" "$here/runner/Cargo.lock"
if ! (cd "$here/runner" && cargo build 2>"$OUT/build.log"); then
  echo "widget window: build failed" >> "$OUT/failures"
  tail -n 40 "$OUT/build.log"
  exit 1
fi
bin=$here/runner/target/debug/vommet-widget-window

step "IPC check (node)"
api=$OUT/widget-api
mkdir -p "$api/watch-together" "$api/park-chess"
args=(--self-test)
fetch() { curl -fsSL -m 30 -A 'Mozilla/5.0 (Vommet nightly widget check)' -o "$2" "$1" && args+=(--widget-api "$2"); }
fetch https://nether.channel/widget/widget-api.js "$api/watch-together/widget-api.js" || echo "Watch Together widget-api.js: download failed" >> "$OUT/failures"
fetch https://vommet.app/widgets/park-chess/play/widget-api.js "$api/park-chess/widget-api.js" || echo "Park Chess widget-api.js: download failed" >> "$OUT/failures"
node "$here/ipc-check.mjs" "${args[@]}" 2>&1 | tee "$OUT/ipc-check.log"
[ "${PIPESTATUS[0]}" = 0 ] || { echo "IPC check (node): $(grep -m1 'stopped before\|ERROR\|self-test' "$OUT/ipc-check.log")" >> "$OUT/failures"; fail=1; }

step "widgets in the widget window and Chromium"
export DISPLAY=${DISPLAY:-:99}
if ! xdpyinfo >/dev/null 2>&1; then
  Xvfb "$DISPLAY" -screen 0 1280x720x24 -nolisten tcp >"$OUT/xvfb.log" 2>&1 &
  for _ in $(seq 50); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.2; done
fi
# WebKit in a CI container: software rendering, no bubblewrap sandbox.
export WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 LIBGL_ALWAYS_SOFTWARE=1
dbus-run-session -- node "$here/host.mjs" "$bin" "$OUT" 2>&1 | tee "$OUT/widgets.log"
[ "${PIPESTATUS[0]}" = 0 ] || fail=1
grep -E '^FAIL' "$OUT/widgets.log" | sed 's/^FAIL //' >> "$OUT/failures"

# A readable summary (GitHub job summary when there).
{
  echo "## Widgets"
  echo
  echo "| Widget | Runs in | Result |"
  echo "|---|---|---|"
  node -e '
    const r = require(process.argv[1]);
    for (const w of r.results) console.log(`| ${w.name}${w.ours ? "" : " (not ours)"} | ${w.runner} | ${w.ok ? "✅" : w.ours ? "❌" : "⚠️"} ${w.detail.replace(/\|/g, "/")} |`);
    if (!r.real_signin) console.log("\nWatch Together sign-in used a made-up token (no test account configured).");
  ' "$OUT/results.json" 2>/dev/null
  echo
  echo "IPC check: $(tail -n1 "$OUT/ipc-check.log")"
} > "$OUT/summary.md"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$OUT/summary.md" >> "$GITHUB_STEP_SUMMARY"
exit $fail
