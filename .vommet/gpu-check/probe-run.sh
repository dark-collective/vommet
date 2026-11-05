#!/bin/sh
# One dock probe run against an unpacked Vommet bundle under weston (GL
# renderer on the GPU). $1 = bundle dir, $2 = wayland|x11, $3 = label,
# $4 = output dir for screenshots + log. Exit 0 = all checks passed.
set -u
bundle=$1 backend=$2 label=$3 out=$4
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
run=$(mktemp -d -p "${PROBE_TMP:-/var/tmp}" vommet-probe.XXXXXX)
export XDG_RUNTIME_DIR=$run/xdg HOME=$run/home
mkdir -p "$XDG_RUNTIME_DIR" "$HOME" && chmod 700 "$XDG_RUNTIME_DIR"
weston --backend=headless --renderer=gl --xwayland --socket=wl-probe \
  --width=1280 --height=800 --debug >"$out/$label-weston.log" 2>&1 &
wpid=$!
sleep 4
export WAYLAND_DISPLAY=wl-probe DISPLAY=:0 GDK_BACKEND=$backend
export PROBE_PAGE=$here/page.html PROBE_SHOTS=$out PROBE_LABEL=$label
# Offline (no network namespace route) and a throwaway profile: the probe
# never talks to a homeserver and never touches a real account.
timeout 240 unshare -n dbus-run-session -- env LD_PRELOAD=$here/dockprobe.so \
  "$bundle/vommet" >"$out/$label.log" 2>&1
rc=$?
kill $wpid 2>/dev/null; wait $wpid 2>/dev/null
rm -rf "$run"
grep -E "^(PASS|FAIL|RESULT)|^  \[" "$out/$label.log"
grep -q "^RESULT PASS" "$out/$label.log" && return_rc=0 || return_rc=1
echo "== $label rc=$rc"
exit $return_rc
