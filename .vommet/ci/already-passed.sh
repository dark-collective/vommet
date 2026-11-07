#!/usr/bin/env bash
# Skip a heavy CI job whose result we already have.
#
#   already-passed.sh "<workflow> / <job>"     (e.g. "build / linux")
#
# On a push, writes skip=true to $GITHUB_OUTPUT when this exact commit already
# passed that check, or when the commit is contained in the current testing
# and testing passed it. That covers testing/main right after a promote (the
# same commits passed as sync/*) and the topic branches a promote moves (their
# commits are all in the green testing), or when a recent first-parent ancestor
# with the same content (minus .vommet/topics and VOMMET_CHANGES.md) passed it.
# Other events (nightly schedule,
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
# The content that matters for a build: the whole tree minus files that only
# list topics or describe changes. Two commits with the same content hash
# build the same app.
content() {
  git ls-tree -r "$1" | grep -v -P '\t(\.vommet/topics|VOMMET_CHANGES\.md)$' | sha256sum | cut -c1-16
}
skip=false why="running $ctx"
if [[ ${GITHUB_EVENT_NAME:-} == push ]]; then
  if passed "$GITHUB_SHA"; then
    skip=true why="${GITHUB_SHA:0:8} already passed $ctx"
  elif git fetch -q origin testing 2>/dev/null && t=$(git rev-parse FETCH_HEAD) \
      && git merge-base --is-ancestor "$GITHUB_SHA" "$t" && passed "$t"; then
    skip=true why="${GITHUB_SHA:0:8} is in testing ${t:0:8}, which passed $ctx"
  else
    # Same content as a recent first-parent ancestor that passed (main after a
    # topics-only commit, a re-cut candidate): skip.
    mine=$(content "$GITHUB_SHA")
    for a in $(git rev-list --first-parent --max-count=30 "$GITHUB_SHA~1" 2>/dev/null); do
      [[ $(content "$a") == "$mine" ]] || break
      if passed "$a"; then skip=true why="${GITHUB_SHA:0:8} has the same content as ${a:0:8}, which passed $ctx"; break; fi
    done
  fi
fi
echo "skip=$skip" >>"$GITHUB_OUTPUT"
echo "$why"
