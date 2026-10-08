#!/bin/bash
# Runs voice_filter_test.dart headless with a fake microphone.
#
#   run_voice_filter_test.sh <noisy clip.wav> <output dir>
#
# Needs pulseaudio, pulseaudio-utils and xvfb. The clip loops into a null sink
# whose monitor is the default source (the "microphone"); the call's received
# audio plays to a second null sink, which the test records once per phase.
set -euo pipefail
clip=$(realpath "$1")
out=$(realpath -m "$2")
mkdir -p "$out"
cd "$(dirname "$0")/../.."

pulseaudio --check 2>/dev/null || pulseaudio -D --exit-idle-time=-1 -n \
  --load=module-native-protocol-unix --load=module-always-sink
for _ in $(seq 20); do pactl info >/dev/null 2>&1 && break; sleep 0.5; done
pactl load-module module-null-sink sink_name=mic rate=48000 channels=1 >/dev/null
pactl load-module module-null-sink sink_name=out rate=48000 channels=1 >/dev/null
pactl set-default-source mic.monitor
pactl set-default-sink out

(while true; do paplay -d mic "$clip"; done) &
player=$!
trap 'kill $player 2>/dev/null || true' EXIT

VOICE_FILTER_OUT="$out" VOICE_FILTER_SINK=out \
  xvfb-run -a flutter test integration_test/voip/voice_filter_test.dart -d linux
