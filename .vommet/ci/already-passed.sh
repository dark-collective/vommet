#!/usr/bin/env bash
# Skip a heavy CI job whose result we already have.
#
#   already-passed.sh "<workflow> / <job>"     (e.g. "build / linux")
#
# On a push, writes skip=true to $GITHUB_OUTPUT when this exact commit already
# passed that check, or when the commit is contained in the current testing
# and testing passed it. That covers testing/main right after a promote (the
# same commits passed as sync/*) and the topic branches a promote moves (their
# commits are all in the green testing). Other events (nightly schedule,
# manual dispatch) always run. Needs TOKEN (job token) and a checkout with
# history (fetch-depth: 0).
set -uo pipefail
ctx=$1
command -v jq >/dev/null || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; }
api="${GITHUB_SERVER_URL}/api/v1/repos/${GITHUB_REPOSITORY}"
passed() {
  curl -fsS -m 30 -H "Authorization: token ${TOKEN}" "$api/commits/$1/statuses?limit=50" \
    | jq -e --arg c "$ctx" 'any(.[]; (.context | startswith($c + " (")) and .status == "success")' >/dev/null
}
skip=false why="running $ctx"
if [[ ${GITHUB_EVENT_NAME:-} == push ]]; then
  if passed "$GITHUB_SHA"; then
    skip=true why="${GITHUB_SHA:0:8} already passed $ctx"
  elif git fetch -q origin testing 2>/dev/null; then
    t=$(git rev-parse FETCH_HEAD)
    if git merge-base --is-ancestor "$GITHUB_SHA" "$t" && passed "$t"; then
      skip=true why="${GITHUB_SHA:0:8} is in testing ${t:0:8}, which passed $ctx"
    fi
  fi
fi
echo "skip=$skip" >>"$GITHUB_OUTPUT"
echo "$why"
