#!/usr/bin/env bash
# Surface a test log as GitHub annotations (#78): its SMOKE/CAPTURE result
# lines as a notice and, on failure, the log's tail as an error. Annotations
# are readable without a token, unlike job logs and artifacts.
#
#   annotate.sh <log file> <exit code> <title> [line a pass must contain]
#
# Exits with the run's final status: a 0 whose log lacks the pass line (a
# skipped or empty run) becomes a failure.
log=$1 rc=$2 title=$3 must=${4:-}
if [ "$rc" = 0 ] && [ -n "$must" ] && ! grep -q -- "$must" "$log" 2>/dev/null; then
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::error title=$title::exit 0 but no '$must' line; treating as failure"
  rc=1
fi
[ -n "${GITHUB_ACTIONS:-}" ] && [ -f "$log" ] || exit "$rc"
enc() { sed -e 's/%/%25/g' -e 's/\r/%0D/g' | awk 'BEGIN{ORS="%0A"} {print}'; }
lines=$(grep -E '(SMOKE|CAPTURE) ' "$log" | tail -40 | enc)
[ -n "$lines" ] && echo "::notice title=$title results::$lines"
if [ "$rc" != 0 ]; then
  echo "::error title=$title failed (exit $rc)::$(grep -v '^\s*$' "$log" | tail -60 | cut -c1-300 | enc)"
fi
exit "$rc"
