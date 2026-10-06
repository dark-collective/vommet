#!/usr/bin/env bash
# Vommet upstream sync: rebase the fork's patch stack onto Commet's main.
#
#   sync.sh candidate [--force]   cut candidates under sync/* (no published branch moves)
#   sync.sh promote               move main, the topics and testing to the candidates
#
# Layout this keeps (see .vommet/README.md):
#   main     = upstream main + a linear stack of accepted fork commits
#   topics   = linear branches listed in .vommet/topics, each on main or on the
#              topic named after "after"
#   testing  = generated: main + a --no-ff merge of every topic, in file order
#
# candidate pushes sync/main, sync/topic/<topic>, sync/testing and sync/state
# (the old tips, used as leases by promote). Nothing published moves until
# promote, which refuses unless CI passed on the candidate heads and nobody
# pushed to the published branches in the meantime.
#
# Exit codes: 0 = done or nothing to do, 2 = conflict (see the report), 1 = error.
set -euo pipefail

# The script checks out other branches (where this file may not exist) while
# bash is still reading it, so run from a private copy.
if [[ -z ${VOMMET_SYNC_RELOCATED:-} ]]; then
  copy=$(mktemp)
  cp "$0" "$copy"
  VOMMET_SYNC_RELOCATED=1 exec bash "$copy" "$@"
fi

ORIGIN=${ORIGIN:-origin}
UPSTREAM=${UPSTREAM:-upstream}
UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/commetchat/commet.git}
UPSTREAM_BRANCH=${UPSTREAM_BRANCH:-main}
REPORT=${REPORT:-sync-report.md}
# promote only: checks CI on the candidate heads through the Forgejo API.
FORGEJO_API=${FORGEJO_API:-}   # e.g. https://nether.codes/api/v1/repos/robocub/vommet
FORGEJO_TOKEN=${FORGEJO_TOKEN:-}
# Workflows whose status must be green on each candidate head (comma-separated
# context prefixes as Forgejo reports them, e.g. "build / linux (push)").
REQUIRED_CHECKS_MAIN=${REQUIRED_CHECKS_MAIN:-build}
REQUIRED_CHECKS_TESTING=${REQUIRED_CHECKS_TESTING:-build,android}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }
rev() { git rev-parse --verify --quiet "$1^{commit}"; }
report() { printf '%s\n' "$@" >>"$REPORT"; }

# --- topics -----------------------------------------------------------------

TOPICS=()        # branch names, file order
declare -A PARENT=()

read_topics() {  # $1 = commit whose .vommet/topics is authoritative
  local line name kw parent
  TOPICS=(); PARENT=()
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    read -r name kw parent _ <<<"$line" || true
    [[ -z ${name:-} ]] && continue
    if [[ -n ${kw:-} ]]; then
      [[ $kw == after && -n ${parent:-} ]] || die "bad .vommet/topics line: $line"
      [[ -n ${PARENT[$parent]+x} ]] || die "topic $name: parent $parent must be listed before it"
    else
      parent=main
    fi
    TOPICS+=("$name"); PARENT[$name]=$parent
  done < <(git show "$1:.vommet/topics")
}

# --- candidate --------------------------------------------------------------

conflict() {  # $1 = what was being rebuilt
  local files commit
  files=$(git diff --name-only --diff-filter=U | sed 's/^/  - `/; s/$/`/')
  commit=$(git log -1 --format='%h %s' REBASE_HEAD 2>/dev/null || git log -1 --format='%h %s' CHERRY_PICK_HEAD 2>/dev/null || git log -1 --format='%h %s' MERGE_HEAD 2>/dev/null || echo '?')
  report "" "## ❌ Conflict while rebuilding \`$1\`" "" "At commit: \`$commit\`" "" "Conflicting files:" "$files" ""
  report "Resolve it by hand (rebase the branch onto its new parent, fix, push) and run the sync again."
  git rebase --abort 2>/dev/null || git cherry-pick --abort 2>/dev/null || git merge --abort 2>/dev/null || true
  log "conflict in $1"
  exit 2
}

replay() {  # $1 = name for reports, rest = commits to cherry-pick onto HEAD
  local name=$1 c; shift
  for c in "$@"; do
    if ! git cherry-pick --allow-empty-message "$c" >/dev/null 2>&1; then
      # Already applied on the new base (no change left, no conflict): drop it.
      # Works with the old git (2.34) on the CI image, which lacks --empty=drop.
      if [[ -z $(git diff --name-only --diff-filter=U) ]] && git diff --cached --quiet; then
        git cherry-pick --skip >/dev/null 2>&1 || git reset --quiet --merge
      else
        conflict "$name"
      fi
    fi
  done
}

candidate() {
  local force=${1:-}
  : >"$REPORT"
  git remote get-url "$UPSTREAM" >/dev/null 2>&1 || git remote add "$UPSTREAM" "$UPSTREAM_URL"
  git fetch --quiet --prune "$ORIGIN" '+refs/heads/*:refs/remotes/'"$ORIGIN"'/*'
  git fetch --quiet "$UPSTREAM" "+refs/heads/$UPSTREAM_BRANCH:refs/remotes/$UPSTREAM/$UPSTREAM_BRANCH"

  local up old_main base
  up=$(rev "$UPSTREAM/$UPSTREAM_BRANCH") || die "no $UPSTREAM/$UPSTREAM_BRANCH"
  old_main=$(rev "$ORIGIN/main") || die "no $ORIGIN/main"
  if git merge-base --is-ancestor "$up" "$old_main" && [[ $force != --force ]]; then
    log "main already contains $UPSTREAM/$UPSTREAM_BRANCH ($(git log -1 --format=%h "$up")); nothing to do"
    echo "changed=false" >>"${GITHUB_OUTPUT:-/dev/null}"
    return 0
  fi
  base=$(git merge-base "$old_main" "$up")
  read_topics "$old_main"

  local n_up
  n_up=$(git rev-list --count "$base..$up")
  report "# Upstream sync: $n_up new upstream commit(s)" ""
  report "Upstream \`$UPSTREAM_BRANCH\` $(git log -1 --format='%h' "$base") → $(git log -1 --format='%h (%cs)' "$up")" ""
  if (( n_up > 0 )); then
    report "<details><summary>Upstream commits</summary>" ""
    git log --reverse --format='- %h %s' "$base..$up" >>"$REPORT"
    report "" "</details>" ""
  fi

  # Fork commits whose change upstream now carries: rebase drops them.
  local dropped
  dropped=$(git cherry -v "$up" "$old_main" "$base" | sed -n 's/^- \(.\{10\}\)[0-9a-f]* /\1 /p' || true)

  local state=()
  state+=("upstream=$up" "main=$old_main")

  # 1. main
  git checkout --quiet -B sync/main "$old_main"
  git rebase --quiet "$up" >/dev/null 2>&1 || conflict main
  local now_empty
  now_empty=$(comm -23 <(git log --format=%s "$base..$old_main" | LC_ALL=C sort) \
                       <(git log --format=%s "$up..sync/main" | LC_ALL=C sort) || true)

  # 2. topics, in file order, each onto its rebuilt parent
  local t p old_t new_p a excl
  declare -A NEW=([main]=sync/main)
  report "## Branches" "" "| branch | commits | |" "|---|---|---|"
  report "| main | $(git rev-list --count "$up..sync/main") | rebased onto upstream |"
  for t in "${TOPICS[@]}"; do
    p=${PARENT[$t]}
    old_t=$(rev "$ORIGIN/$t") || die "topic $t listed in .vommet/topics but $ORIGIN/$t does not exist"
    new_p=${NEW[$p]}
    # The topic's own commits: everything not on old main or on the old tip of
    # any topic it is stacked on. (Not merge-base based: a topic that once
    # merged main in would otherwise replay main's commits.)
    excl=("^$old_main"); a=$p
    while [[ $a != main ]]; do excl+=("^$(rev "$ORIGIN/$a")"); a=${PARENT[$a]}; done
    git checkout --quiet -B "sync/topic/$t" "$new_p"
    replay "$t" $(git rev-list --reverse --no-merges "$old_t" "${excl[@]}")
    NEW[$t]="sync/topic/$t"
    state+=("topic:$t=$old_t")
    report "| $t | $(git rev-list --count "$new_p..sync/topic/$t") | on ${p} |"
  done
  report ""

  # 3. testing
  local old_testing
  old_testing=$(rev "$ORIGIN/testing" || true)
  state+=("testing=${old_testing:-}")
  git checkout --quiet -B sync/testing sync/main
  for t in "${TOPICS[@]}"; do
    git merge --quiet --no-ff --no-edit -m "testing: merge $t" "sync/topic/$t" >/dev/null 2>&1 \
      || conflict "testing (merging $t)"
  done

  if [[ -n $dropped || -n $now_empty ]]; then
    report "## Fork commits now upstream (dropped by the rebase)" ""
    {
      printf '%s\n' "$dropped"
      # Became empty without a patch-id match (upstream fixed it differently).
      while IFS= read -r subj; do
        if [[ -n $subj ]] && ! grep -qF -- " $subj" <<<"$dropped"; then printf '(emptied) %s\n' "$subj"; fi
      done <<<"$now_empty"
    } | sed '/^$/d' | sed 's/^/- /' >>"$REPORT"
    report "" "Close their issues and update VOMMET_CHANGES.md when promoting."
    report ""
  fi
  report "Candidates: \`sync/main\` $(git log -1 --format=%h sync/main), \`sync/testing\` $(git log -1 --format=%h sync/testing)."
  report "Promote with the **upstream-promote** workflow once CI is green on both."

  # 4. state (leases for promote), as a parentless commit on sync/state
  local blob tree commit
  blob=$(printf '%s\n' "${state[@]}" "sync_main=$(rev sync/main)" "sync_testing=$(rev sync/testing)" | git hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tstate\n' "$blob" | git mktree)
  commit=$(git commit-tree "$tree" -m "sync state $(date -u +%FT%TZ)")
  git branch --force sync/state "$commit"

  local refs=(sync/main sync/testing sync/state)
  for t in "${TOPICS[@]}"; do refs+=("sync/topic/$t"); done
  if [[ ${SYNC_DRY_RUN:-} == 1 ]]; then
    log "dry run: not pushing ${refs[*]}"
  else
    # Topic candidates first: CI ignores sync/topic/** and sync/state, so the
    # two pushes that do build (sync/main, sync/testing) see consistent refs.
    git push --quiet --force "$ORIGIN" $(for r in "${refs[@]:2}"; do printf '%s:refs/heads/%s ' "$r" "$r"; done)
    git push --quiet --force "$ORIGIN" sync/main:refs/heads/sync/main sync/testing:refs/heads/sync/testing
  fi
  echo "changed=true" >>"${GITHUB_OUTPUT:-/dev/null}"
  log "candidates ready; report in $REPORT"
}

# --- promote ----------------------------------------------------------------

checks_green() {  # $1 = sha, $2 = comma-separated required context prefixes
  if [[ ${SYNC_UNCHECKED:-} == 1 ]]; then log "SYNC_UNCHECKED=1: skipping the CI check (local testing only)"; return 0; fi
  [[ -n $FORGEJO_API && -n $FORGEJO_TOKEN ]] || die "promote needs FORGEJO_API and FORGEJO_TOKEN"
  local json want
  json=$(curl -fsS -H "Authorization: token $FORGEJO_TOKEN" "$FORGEJO_API/commits/$1/statuses?limit=50")
  IFS=, read -ra want <<<"$2"
  local w
  for w in "${want[@]}"; do
    # Latest status per context; every context starting with "$w /" must be success, and one must exist.
    jq -e --arg w "$w" '
      [ group_by(.context)[] | max_by(.id) | select(.context | startswith($w + " /")) ] as $s
      | ($s | length > 0) and all($s[]; .status == "success")' <<<"$json" >/dev/null \
      || { log "CI not green for '$w' on ${1:0:10}"; return 1; }
  done
}

promote() {
  git fetch --quiet --prune "$ORIGIN" '+refs/heads/*:refs/remotes/'"$ORIGIN"'/*'
  rev "$ORIGIN/sync/state" >/dev/null || die "no candidate (run candidate first)"
  declare -A S=()
  local k v
  while IFS='=' read -r k v; do S[$k]=$v; done < <(git show "$ORIGIN/sync/state:state")

  [[ $(rev "$ORIGIN/sync/main") == "${S[sync_main]}" ]] || die "sync/main moved since the candidate was cut"
  [[ $(rev "$ORIGIN/sync/testing") == "${S[sync_testing]}" ]] || die "sync/testing moved since the candidate was cut"
  checks_green "${S[sync_main]}" "$REQUIRED_CHECKS_MAIN" || exit 1
  checks_green "${S[sync_testing]}" "$REQUIRED_CHECKS_TESTING" || exit 1

  local stamp leases=() moves=() tags=() name
  stamp=$(date -u +%Y%m%d-%H%M%S)
  for k in "${!S[@]}"; do
    case $k in
      main|testing) name=$k ;;
      topic:*) name=${k#topic:} ;;
      *) continue ;;
    esac
    v=${S[$k]}
    if [[ -n $v ]]; then
      [[ $(rev "$ORIGIN/$name" || true) == "$v" ]] || die "$name was pushed to since the candidate was cut; run the sync again"
      leases+=("--force-with-lease=refs/heads/$name:$v")
      tags+=("$v:refs/tags/pre-sync/$stamp/$name")
    else
      leases+=("--force-with-lease=refs/heads/$name:")
    fi
    case $k in
      main) moves+=("${S[sync_main]}:refs/heads/main") ;;
      testing) moves+=("${S[sync_testing]}:refs/heads/testing") ;;
      topic:*) moves+=("$(rev "$ORIGIN/sync/topic/$name"):refs/heads/$name") ;;
    esac
  done

  # Rollback points first, then every branch in one atomic push.
  git push --quiet "$ORIGIN" "${tags[@]}"
  git push --quiet --atomic "${leases[@]}" "$ORIGIN" "${moves[@]}"
  local del=(sync/main sync/testing sync/state)
  for k in "${!S[@]}"; do [[ $k == topic:* ]] && del+=("sync/topic/${k#topic:}"); done
  git push --quiet "$ORIGIN" $(printf ':refs/heads/%s ' "${del[@]}") || log "warning: could not delete sync/* refs"
  log "promoted; rollback tags under pre-sync/$stamp/"
  echo "stamp=$stamp" >>"${GITHUB_OUTPUT:-/dev/null}"
}

case ${1:-} in
  candidate) candidate "${2:-}" ;;
  promote) promote ;;
  *) die "usage: $0 candidate [--force] | promote" ;;
esac
