#!/bin/bash
# Nightly GPU widget check (vommet-gpu-test, cubuntu Iris Xe). Fetches the
# latest testing-* Linux tarball, runs the dock probe (dock / pop out /
# fullscreen pixel checks) on Wayland and X11 under weston's GL renderer,
# and posts "widgets-gpu / linux (cubuntu igpu)" on the release's commit.
# Test page only, offline, throwaway profile. See README.md.
set -uo pipefail
API=https://nether.codes/api/v1
REPO=nether/vommet
CONTEXT="widgets-gpu / linux (cubuntu igpu)"
HERE=/opt/vommet-gpu-check
STATE=/var/lib/vommet-gpu-check
TOKEN_FILE=/etc/vommet-gpu-check/forgejo-token
# Light bookkeeping workflows that don't load the build runner.
LIGHT='^(pr-github|github-copy|nightly|upstream-sync)\.ya?ml$'
mkdir -p "$STATE/runs"
export PROBE_TMP=$STATE/tmp; mkdir -p "$PROBE_TMP"
log() { echo "$(date -u +%FT%TZ) $*"; }
auth() { printf 'Authorization: token %s' "$(cat "$TOKEN_FILE")"; }

busy() {
  local r n
  for r in nether/vommet nether/nether-voicebridge; do
    n=$(curl -sf -H "$(auth)" "$API/repos/$r/actions/tasks?limit=50" | python3 -c '
import json,re,sys
light=re.compile(sys.argv[1])
runs=json.load(sys.stdin).get("workflow_runs",[])
print(sum(1 for t in runs if t.get("status") in ("running","waiting") and not light.match(t.get("workflow_id",""))))' "$LIGHT") || n=0
    [ "${n:-0}" -gt 0 ] && return 0
  done
  return 1
}

# Wait up to 70 min for real CI jobs to finish, else skip the night.
for i in $(seq 0 14); do
  busy || break
  [ "$i" -eq 14 ] && { log "CI still busy after 70 min; skipping tonight"; exit 0; }
  log "CI busy, waiting 5 min"; sleep 300
done

read -r TAG URL < <(curl -sf "$API/repos/$REPO/releases?limit=20" | python3 -c '
import json,sys
for r in json.load(sys.stdin):
    t=r["tag_name"]
    if not t.startswith("testing-"): continue
    for a in r["assets"]:
        if a["name"]==f"vommet-linux-x64-{t}.tar.gz":
            print(t,a["browser_download_url"]); sys.exit()')
[ -n "${TAG:-}" ] || { log "no testing release with a Linux tarball"; exit 1; }
SHA=$(curl -sf "$API/repos/$REPO/tags/$TAG" | python3 -c 'import json,sys;print(json.load(sys.stdin)["commit"]["sha"])')
log "checking $TAG ($SHA)"

post() {  # state description
  curl -sf -o /dev/null -X POST -H "$(auth)" -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys;print(json.dumps({"state":sys.argv[1],"context":sys.argv[2],"description":sys.argv[3]}))' "$1" "$CONTEXT" "$2")" \
    "$API/repos/$REPO/statuses/$SHA" && log "posted $1: $2" || log "status post failed"
}

app=$STATE/app; rm -rf "$app"; mkdir -p "$app"
if ! curl -sfL "$URL" -o "$STATE/app.tar.gz" || ! curl -sfL "$URL.sha256" -o "$STATE/app.tar.gz.sha256"; then
  log "download failed"; exit 1
fi
if [ "$(awk '{print $1}' "$STATE/app.tar.gz.sha256")" != "$(sha256sum "$STATE/app.tar.gz" | awk '{print $1}')" ]; then
  log "checksum mismatch"; post error "tarball checksum mismatch"; exit 1
fi
tar -xzf "$STATE/app.tar.gz" -C "$app"; rm -f "$STATE/app.tar.gz"*

out=$STATE/runs/$(date -u +%Y%m%dT%H%MZ)-$TAG; mkdir -p "$out"
pass=0 fail=""
for b in wayland x11; do
  if "$HERE/probe-run.sh" "$app/bundle" "$b" "$b" "$out" >"$out/$b-summary.txt" 2>&1; then
    pass=$((pass+1))
  else
    fail="$fail $b($(grep -c '^FAIL' "$out/$b.log" 2>/dev/null) failed)"
  fi
  cat "$out/$b-summary.txt"
done
rm -rf "$app"
if [ -z "$fail" ]; then post success "$TAG: dock, pop out, fullscreen OK on Wayland + X11 (Iris Xe)"
else post failure "$TAG:$fail; logs in $out on vommet-gpu-test"; fi
# Keep two weeks of runs.
ls -1dt "$STATE"/runs/*/ 2>/dev/null | tail -n +15 | xargs -r rm -rf
[ -z "$fail" ]
