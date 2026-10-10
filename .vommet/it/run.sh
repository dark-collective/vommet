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
