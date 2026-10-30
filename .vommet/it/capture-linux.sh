#!/usr/bin/env bash
# Microphone capture test (#78) on the Linux desktop build: a PulseAudio null
# sink's monitor is the default source (the "microphone"), and a speech-like
# signal loops into it. Needs pulseaudio, pulseaudio-utils, xvfb, python3.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../../it-out}
mkdir -p "$OUT"

pulseaudio --check 2>/dev/null || pulseaudio -D --exit-idle-time=-1 -n \
  --load=module-native-protocol-unix --load=module-always-sink
for _ in $(seq 20); do pactl info >/dev/null 2>&1 && break; sleep 0.5; done
pactl load-module module-null-sink sink_name=mic rate=48000 channels=1 >/dev/null
pactl load-module module-null-sink sink_name=out rate=48000 channels=1 >/dev/null
pactl set-default-source mic.monitor
pactl set-default-sink out

python3 "$here/make_signal.py" /tmp/capture-signal.wav 10
(while true; do paplay -d mic /tmp/capture-signal.wav; done) &
player=$!
trap 'kill $player 2>/dev/null || true' EXIT

cd "$here/../../commet"
xvfb-run -a flutter test integration_test/capture_runner.dart -d linux -r expanded \
  --dart-define=CAPTURE_TEST=true 2>&1 | tee "$OUT/capture-linux.log"
rc=${PIPESTATUS[0]}
"$here/annotate.sh" "$OUT/capture-linux.log" "$rc" "Linux capture" "CAPTURE PASS"
rc=$?
exit "$rc"
