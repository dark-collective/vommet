#!/usr/bin/env bash
# Keep one open "Upstream sync" issue per pending candidate.
#   report-issue.sh candidate   post sync-report.md (new issue, or a comment on the open one)
#   report-issue.sh promoted    comment and close the open one
# Needs API (…/api/v1/repos/<owner>/<repo>), TOKEN, RUN_URL; RC for candidate.
set -euo pipefail
TITLE_PREFIX='Upstream sync'
auth=(-H "Authorization: token $TOKEN" -H 'Content-Type: application/json')

open_issue=$(curl -fsS "${auth[@]}" "$API/issues?state=open&type=issues&limit=50&q=$(jq -rn --arg q "$TITLE_PREFIX" '$q|@uri')" \
  | jq -r --arg p "$TITLE_PREFIX" '[.[] | select(.title | startswith($p))][0].number // empty')

comment() { jq -n --arg b "$1" '{body:$b}' | curl -fsS "${auth[@]}" -X POST -d @- "$API/issues/$open_issue/comments" >/dev/null; }

case $1 in
  candidate)
    body="$(cat sync-report.md 2>/dev/null || echo 'No report (the sync script failed before writing one).')"$'\n\n'"Run: $RUN_URL"
    if [[ ${RC:-0} != 0 && ${RC:-0} != 2 ]]; then body="**The sync job failed (exit $RC).**"$'\n\n'"$body"; fi
    if [[ -n $open_issue ]]; then
      comment "$body"
      echo "commented on #$open_issue"
    else
      title="$TITLE_PREFIX $(date -u +%F)"
      [[ ${RC:-0} == 2 ]] && title="$title: conflict"
      label=$(curl -fsS "${auth[@]}" "$API/labels?limit=50" | jq '[.[] | select(.name=="infra") | .id]')
      jq -n --arg t "$title" --arg b "$body" --argjson l "$label" '{title:$t, body:$b, labels:$l}' \
        | curl -fsS "${auth[@]}" -X POST -d @- "$API/issues" | jq -r '"opened #\(.number)"'
    fi
    ;;
  promoted)
    [[ -n $open_issue ]] || { echo "no open sync issue"; exit 0; }
    comment "Promoted: main, the topics and testing now point at the candidates. Rollback tags: \`pre-sync/$STAMP/*\`."$'\n\n'"Run: $RUN_URL"
    curl -fsS "${auth[@]}" -X PATCH -d '{"state":"closed"}' "$API/issues/$open_issue" >/dev/null
    echo "closed #$open_issue"
    ;;
  *) echo "usage: $0 candidate|promoted" >&2; exit 1 ;;
esac
