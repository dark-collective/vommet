#!/usr/bin/env bash
# Run the integration tests (Flutter integration_test on the Linux desktop
# build) against a throwaway homeserver, under Xvfb, recording the screen.
#
#   .vommet/it/run.sh [test file under commet/, default integration_test/runner.dart]
#
# Needs: flutter + the Linux build deps on PATH, xvfb, ffmpeg, jq, openssl,
# TUWUNEL (binary path). Artifacts land in $OUT (default ./it-out).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
OUT=${OUT:-$repo/it-out}
TARGET=${1:-integration_test/vommet_runner.dart}
mkdir -p "$OUT"

export USER1_NAME=${USER1_NAME:-alice} USER1_PW=${USER1_PW:-AliceInWonderland}
export USER2_NAME=${USER2_NAME:-bob} USER2_PW=${USER2_PW:-CanWeFixIt}
export WORK=${WORK:-/tmp/vommet-it}

"$here/homeserver.sh" || exit 1

# Another Matrix client for the interop tests (cross_signing_test.dart):
# matrix-js-sdk with its Rust crypto, pinned by peers/js/package-lock.json.
# Only for the nightly secure-setup suite unless IT_PEERS=1; without it
# those tests skip.
if [[ ${IT_PEERS:-} == 1 || ( -z ${IT_PEERS:-} && $TARGET == *secure_setup_runner* ) ]]; then
  node=$(command -v node || true)
  for n in /opt/acttoolcache/node/*/x64/bin/node; do
    [[ -x $n ]] || continue
    [[ -z $node || $("$n" -p 'process.versions.node.split(".")[0]') -gt $("$node" -p 'process.versions.node.split(".")[0]') ]] && node=$n
  done
  if [[ -n $node && $("$node" -p 'process.versions.node.split(".")[0]') -ge 22 ]]; then
    rm -rf "$WORK/js-peer" && cp -r "$here/peers/js" "$WORK/js-peer"
    if (cd "$WORK/js-peer" && PATH="$(dirname "$node"):$PATH" npm ci --no-audit --no-fund --loglevel=error); then
      export IT_PEER_NODE=$node IT_PEER_JS=$WORK/js-peer/peer.mjs
      echo "js peer: node $("$node" --version), matrix-js-sdk $(cd "$WORK/js-peer" && "$node" -p 'require("./node_modules/matrix-js-sdk/package.json").version')"
    else
      echo "::warning::js peer setup failed; interop tests will skip"
    fi
  else
    echo "::warning::no node >= 22 for the js peer; interop tests will skip"
  fi
fi

# The secure-setup suite derives keys from recovery passwords: 500k PBKDF2
# rounds in vodozemac, which a debug build compiles unoptimised (11-15 s,
# past the SDK's 10 s limit; ~0.4 s optimised, as in release builds).
# cargokit inherits this. IT_NATIVE_OPT=1/0 forces it on/off.
if [[ ${IT_NATIVE_OPT:-} == 1 || ( -z ${IT_NATIVE_OPT:-} && $TARGET == *secure_setup_runner* ) ]]; then
  export CARGO_PROFILE_DEV_OPT_LEVEL=3
fi

export DISPLAY=:99
Xvfb :99 -ac -screen 0 1920x1080x24 >/dev/null 2>&1 &
xvfb=$!
sleep 1
ffmpeg -nostdin -loglevel error -f x11grab -video_size 1920x1080 -framerate 10 -i :99 \
  -c:v libx264 -preset ultrafast -crf 30 -pix_fmt yuv420p "$OUT/screen.mp4" &
rec=$!

cd "$repo/commet"
# A desktop session for the app: a session D-Bus with a notification server
# and an unlocked Secret Service keyring (libsecret token storage).
export TARGET OUT
dbus-run-session -- bash -c '
  echo -n vommet-it | gnome-keyring-daemon --unlock --components=secrets >/dev/null 2>&1
  dunst >/dev/null 2>&1 &   # org.freedesktop.Notifications
  flutter test "$TARGET" -d linux -r expanded \
    --dart-define=HOMESERVER=localhost --dart-define=BUILD_MODE=release \
    --dart-define=IT_KEYRING=true \
    --dart-define=USER1_NAME="$USER1_NAME" --dart-define=USER1_PW="$USER1_PW" \
    --dart-define=USER2_NAME="$USER2_NAME" --dart-define=USER2_PW="$USER2_PW" \
    2>&1 | tee "$OUT/flutter-test.log"
  exit ${PIPESTATUS[0]}'
rc=$?

kill -INT $rec 2>/dev/null; wait $rec 2>/dev/null
kill $xvfb 2>/dev/null
for hs in tuwunel synapse; do   # whichever homeserver.sh started (IT_HS)
  [[ -f $WORK/$hs.pid ]] || continue
  cp "$WORK/$hs.log" "$OUT/" 2>/dev/null
  kill "$(cat "$WORK/$hs.pid")" 2>/dev/null
done
cp "$WORK/synapse/homeserver.log" "$OUT/synapse-homeserver.log" 2>/dev/null
if [[ -f "$WORK/tuwunel2.pid" ]]; then   # IT_FEDERATION's second homeserver
  cp "$WORK/tuwunel2.log" "$OUT/" 2>/dev/null
  kill "$(cat "$WORK/tuwunel2.pid")" 2>/dev/null
fi
echo "integration tests exit $rc; artifacts in $OUT"
exit $rc
