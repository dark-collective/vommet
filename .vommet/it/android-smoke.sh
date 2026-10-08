#!/usr/bin/env bash
# Run the cross-platform smoke suite (#78) on a booted Android emulator against
# the throwaway homeserver from homeserver.sh (https://localhost on the host).
#
#   .vommet/it/android-smoke.sh [device id, default emulator-5554]
#
# The emulator reaches the host's port 443 through `adb reverse`, so the app
# still talks to https://localhost; the test CA is handed to the app as a
# dart-define (Android apps don't trust user-installed CAs).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
DEVICE=${1:-emulator-5554}
OUT=${OUT:-$repo/it-out}
WORK=${WORK:-/tmp/vommet-it}
mkdir -p "$OUT"

# Binding the device-side port 443 needs a root adbd (google_apis images allow it).
adb -s "$DEVICE" root >/dev/null
adb -s "$DEVICE" wait-for-device
adb -s "$DEVICE" reverse tcp:443 tcp:443 || { echo "adb reverse failed" >&2; exit 1; }

adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" logcat >"$OUT/logcat.txt" 2>&1 &
logcat=$!

cd "$repo/commet"
flutter test integration_test/smoke_runner.dart -d "$DEVICE" -r expanded \
  --dart-define=HOMESERVER=localhost --dart-define=BUILD_MODE=release \
  --dart-define=PLATFORM=android \
  --dart-define=TEST_CA_PEM_B64="$(base64 -w0 "$WORK/ca.crt")" \
  --dart-define=USER1_NAME="$USER1_NAME" --dart-define=USER1_PW="$USER1_PW" \
  --dart-define=USER2_NAME="$USER2_NAME" --dart-define=USER2_PW="$USER2_PW" \
  2>&1 | tee "$OUT/flutter-test.log"
rc=${PIPESTATUS[0]}

adb -s "$DEVICE" exec-out screencap -p >"$OUT/final-screen.png" 2>/dev/null
kill $logcat 2>/dev/null
cp "$WORK/tuwunel.log" "$OUT/" 2>/dev/null
# On failure, the device side's view: crashes, ANRs, low-memory kills.
if [ "$rc" != 0 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
  crash=$(grep -E 'FATAL|AndroidRuntime|lowmemorykiller|lmkd|am_kill|ANR in|Fatal signal|SIGSEGV|SIGABRT|Out of memory' \
    "$OUT/logcat.txt" 2>/dev/null | tail -40 | cut -c1-300 | sed -e 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=Android logcat (crashes, kills)::${crash:-no crash or kill lines in logcat}"
  # The emulator itself has gone offline mid-run: did the runner's kernel
  # kill it (OOM), or did it die on its own?
  host=$( { free -m; sudo dmesg 2>/dev/null | grep -iE 'oom|killed process|out of memory|qemu|emulator|kvm' | tail -20; \
    pgrep -fa qemu-system | cut -c1-120 || echo "no qemu process"; } | sed -e 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=Android host (memory, kernel kills)::$host"
fi
"$here/annotate.sh" "$OUT/flutter-test.log" "$rc" "Android smoke" "SMOKE sent encrypted"
rc=$?
echo "android smoke exit $rc; artifacts in $OUT"
exit "$rc"
