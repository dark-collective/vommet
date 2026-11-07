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
#   overlays = topics marked "overlay": linear commits on top of testing itself,
#              for changes that span many topics (e.g. making strings
#              translatable). Listed after every regular topic.
#   testing  = generated: main + a --no-ff merge of every topic, in file order,
#              then a --no-ff merge of each overlay replayed onto that
#
# candidate pushes sync/main, sync/topic/<topic>, sync/testing and sync/state
# (the old tips, used as leases by promote, and the candidate heads CI saw, as
# pins). Nothing published moves until promote, which refuses unless CI passed
# on the candidate heads, no candidate ref moved, and nobody pushed to the
# published branches in the meantime.
#
# Shadow append (2026-11-07, measuring only): candidate also builds, locally and
# never pushed, the testing an append would give (old testing + main + what was
# added since, nothing rewritten) and records in sync/state whether it matches
# the canonical rebuild (shadow_append=...). Promote ignores it. See
# "Append promotion (shadow)" in .vommet/README.md.
#
#   sync.sh check-append <commit>   read-only: would <commit> be a valid append of
#                                   the current origin/sync/state? (exit 0 = yes)
#
# Exit codes: 0 = done or nothing to do, 2 = conflict, or upstream changed CI
# files and nothing else needs a candidate (see the report), 1 = error.
# Upstream CI changes are held for review, never pushed: see ci_review_gate.
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
REQUIRED_CHECKS_TESTING=${REQUIRED_CHECKS_TESTING:-build,android,integration}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }
rev() { git rev-parse --verify --quiet "$1^{commit}"; }
report() { printf '%s\n' "$@" >>"$REPORT"; }

# --- topics -----------------------------------------------------------------

TOPICS=()        # branch names, file order
declare -A PARENT=()
OVERLAYS=()      # overlay branch names, file order (based on testing)

read_topics() {  # $1 = commit whose .vommet/topics is authoritative
  local line name kw parent
  TOPICS=(); PARENT=(); OVERLAYS=()
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    read -r name kw parent _ <<<"$line" || true
    [[ -z ${name:-} ]] && continue
    if [[ ${kw:-} == overlay ]]; then
      OVERLAYS+=("$name")
      continue
    fi
    (( ${#OVERLAYS[@]} == 0 )) || die "topic $name: regular topics must be listed before every overlay"
    if [[ -n ${kw:-} ]]; then
      [[ $kw == after && -n ${parent:-} ]] || die "bad .vommet/topics line: $line"
      [[ -n ${PARENT[$parent]+x} ]] || die "topic $name: parent $parent must be listed before it"
    else
      parent=main
    fi
    TOPICS+=("$name"); PARENT[$name]=$parent
  done < <(git show "$1:.vommet/topics")
}

# An overlay's own commits: its tip and the single-parent commits below it,
# down to the first merge (the testing it was built on), oldest first.
overlay_commits() {  # $1 = overlay tip
  local c=$1 out=()
  while [[ $(git rev-list --no-walk --parents "$c" | wc -w) == 2 ]]; do
    out=("$c" "${out[@]}"); c=$(rev "$c^")
  done
  (( ${#out[@]} > 0 )) || die "overlay at ${1:0:10} has no commits of its own on top of testing"
  printf '%s\n' "${out[@]}"
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

# Names under dependency_overrides in commet/pubspec.yaml at commit $1.
overridden_packages() {
  { git show "$1:commet/pubspec.yaml" 2>/dev/null || true; } | awk '
    /^dependency_overrides:/ { in_o = 1; next }
    in_o && /^[^ #]/ { in_o = 0 }
    in_o && match($0, /^  [A-Za-z0-9_]+:/) { print substr($0, 3, RLENGTH - 3) }
  '
}

# The lines declaring package $2 outside dependency_overrides in
# commet/pubspec.yaml at commit $1 (its key plus the indented lines under it).
dependency_block() {
  { git show "$1:commet/pubspec.yaml" 2>/dev/null || true; } | awk -v pkg="$2" '
    /^[^ #]/ { section = $1 }
    section == "dependency_overrides:" { next }
    /^  [^ ]/ { inside = ($0 ~ "^  " pkg ":") }
    inside { print section " " $0 }
  '
}

# Report (never fail) when upstream changed its dependencies, calling out
# packages that main or a topic overrides: the override silently wins.
dependency_report() {  # $1 = base, $2 = upstream tip, $3 = old main
  local base=$1 up=$2 old_main=$3
  [[ -n $(git diff --name-only "$base..$up" -- commet/pubspec.yaml pubspec.lock) ]] || return 0
  report "## ⚠️ Upstream changed dependencies" ""
  local changed pkg t tip overridden=()
  changed=$(git diff "$base..$up" -- commet/pubspec.yaml)
  {
    overridden_packages "$old_main"
    for t in "${TOPICS[@]}"; do
      if tip=$(rev "$ORIGIN/$t"); then overridden_packages "$tip"; fi
    done
  } | sort -u >"$REPORT.overrides"
  while read -r pkg; do
    [[ -n $pkg ]] || continue
    if [[ $(dependency_block "$base" "$pkg") != "$(dependency_block "$up" "$pkg")" ]]; then
      overridden+=("$pkg")
    fi
  done <"$REPORT.overrides"
  rm -f "$REPORT.overrides"
  if (( ${#overridden[@]} > 0 )); then
    report "**Upstream changed packages we override in \`dependency_overrides\`:** ${overridden[*]}." \
      "Our override wins, so check whether ours needs to follow (e.g. rebase our SDK fork onto upstream's new ref)." ""
  fi
  if [[ -n $changed ]]; then
    report "<details><summary>commet/pubspec.yaml diff</summary>" "" '```diff'
    printf '%s\n' "$changed" >>"$REPORT"
    report '```' "" "</details>" ""
  else
    report "Only \`pubspec.lock\` changed." ""
  fi
}

# Upstream changes to CI or to this tooling would run with the fork's secrets as
# soon as a candidate is pushed (Forgejo hands every repo secret to any workflow
# in the pushed tree; the GitHub copy builds and signs the candidate). So the
# sync takes upstream only as far as someone has reviewed such changes:
# $CI_REVIEWED on main holds the newest upstream sha whose CI changes were read
# and accepted. If upstream changed CI_PATHS after that point (or after the
# merge base, whichever is newer), the candidate is cut on that older upstream
# commit instead: topics still restack and ship, and the new upstream commits
# wait for the review. Only upstream's own changes count (merge base ->
# upstream tip), never the fork's CI files on main or the GitHub workflows
# winbranch.sh adds to ci/windows-testing.
CI_PATHS=(.forgejo .gitea .github/workflows .github/actions .vommet)
CI_REVIEWED=.vommet/upstream-ci-reviewed

# Prints the upstream commit the candidate may use: $2, or the reviewed point
# when upstream changed CI files after it. Writes the hold to the report.
ci_review_gate() {  # $1 = base, $2 = upstream tip, $3 = old main
  local base=$1 up=$2 from=$1 reviewed files
  reviewed=$({ git show "$3:$CI_REVIEWED" 2>/dev/null || true; } | grep -m1 -oE '^[0-9a-f]{40}' || true)
  if [[ -n $reviewed ]] && rev "$reviewed" >/dev/null \
      && git merge-base --is-ancestor "$base" "$reviewed" && git merge-base --is-ancestor "$reviewed" "$up"; then
    from=$reviewed
  fi
  # --no-renames lists both sides of a rename, so a file moved out of CI_PATHS shows too.
  files=$(git diff --no-renames --name-only "$from" "$up" -- "${CI_PATHS[@]}")
  if [[ -z $files ]]; then
    printf '%s\n' "$up"
    return 0
  fi
  report "## ⏸ Upstream CI changes held for review" ""
  report "Upstream changed files that run with the fork's secrets once pushed, so this candidate" \
    "takes upstream only up to $(git log -1 --format='%h (%cs)' "$from"). Topics restack as usual." ""
  printf '%s\n' "$files" | sed 's/^/- `/; s/$/`/' >>"$REPORT"
  report "" "Review \`git diff $from $up -- ${CI_PATHS[*]}\`." \
    "To accept, commit \`$up\` as the only line of \`$CI_REVIEWED\` on main (not while a" \
    "candidate is in CI). The next sync then takes upstream up to that commit." ""
  log "upstream changed CI files after ${from:0:10}; held for review"
  printf '%s\n' "$from"
}

# A promote of the current sync/state that died part-way (some published refs already at their
# candidate) must be finished (re-run the promote) before a new candidate overwrites sync/*: that
# would lose which refs still need moving (2026-11-05).
partial_promote_guard() {
  rev "$ORIGIN/sync/state" >/dev/null || return 0
  local k v n moved=0
  while IFS='=' read -r k v; do
    case $k in topic:*) n=${k#topic:} ;; *) continue ;; esac
    [[ -n $v && $(rev "$ORIGIN/$n" || true) != "$v" && $(rev "$ORIGIN/$n" || true) == "$(rev "$ORIGIN/sync/topic/$n" || true)" ]] && moved=$((moved + 1))
  done < <(git show "$ORIGIN/sync/state:state")
  ((moved == 0)) || die "a promote of the current candidate died part-way ($moved topic(s) already moved): re-run the promote first"
}

# --- append (shadow) ----------------------------------------------------------

# Names and kinds in a commit's .vommet/topics: "R <name>" or "O <name>", file order.
manifest_lines() {  # $1 = commit
  local line name kw
  { git show "$1:.vommet/topics" 2>/dev/null || true; } | while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    read -r name kw _ <<<"$line" || true
    [[ -z ${name:-} ]] && continue
    if [[ ${kw:-} == overlay ]]; then echo "O $name"; else echo "R $name"; fi
  done
}

# What a published testing was built from: walks its first-parent chain of
# "testing: merge <name>" merges and prints "<name> <merged head>", newest first
# (a name merged twice, as an append does for a grown topic, keeps its newest
# head), then "@base <commit>" for the commit the merges sit on. "main" merges
# (appends of a newer main) print as "main <commit>".
testing_merges() {  # $1 = testing commit
  git log --first-parent --format='%H%x09%P%x09%s' "$1" | awk -F'\t' '
    { n = split($2, p, " ")
      if (n == 2 && $3 ~ /^testing: merge [^ \t]+$/) {
        name = substr($3, 16)
        if (!(name in seen)) { seen[name] = 1; print name, p[2] }
        next
      }
      print "@base", $1; exit }' || true
}

# Is $1 an ancestor of $2? (no output)
is_anc() { git merge-base --is-ancestor "$1" "$2" 2>/dev/null; }

# check_append <candidate> <old testing> <main> <canonical testing> <manifest commit>
# The checks a promoted append must pass, apart from CI: the old testing and main
# are ancestors; every listed topic's published head is an ancestor, except an
# overlay that old testing never merged (its commits are replayed); the tree equals
# the canonical rebuild's (or differs only by a reordering of VOMMET_CHANGES.md
# lines, the union-merge order). Prints "ok <equal|permuted>" or "reject: <why>".
check_append() {
  local cand=$1 old_t=$2 main=$3 canon=$4 man=$5 kind name lease diff
  [[ -n $old_t ]] && is_anc "$old_t" "$cand" || { echo "reject: old testing ${old_t:0:10} is not an ancestor"; return 1; }
  is_anc "$main" "$cand" || { echo "reject: main ${main:0:10} is not an ancestor"; return 1; }
  declare -A merged=() anc=()
  while read -r name lease; do [[ $name == @base ]] || merged[$name]=1; done < <(testing_merges "$old_t")
  while read -r lease; do anc[$lease]=1; done < <(git for-each-ref --format='%(objectname)' --merged="$cand" "refs/remotes/$ORIGIN/")
  while read -r kind name; do
    lease=$(rev "$ORIGIN/$name") || { echo "reject: no $ORIGIN/$name"; return 1; }
    [[ -n ${anc[$lease]+x} ]] && continue
    if [[ $kind == O && -z ${merged[$name]+x} ]]; then continue; fi
    echo "reject: $name's published head ${lease:0:10} is not an ancestor (rewritten)"; return 1
  done < <(manifest_lines "$man")
  diff=$(git diff --name-only "$cand" "$canon")
  if [[ -z $diff ]]; then echo "ok equal"; return 0; fi
  if [[ $diff == VOMMET_CHANGES.md ]] \
     && cmp -s <(git show "$cand:VOMMET_CHANGES.md" | LC_ALL=C sort) <(git show "$canon:VOMMET_CHANGES.md" | LC_ALL=C sort); then
    echo "ok permuted"; return 0
  fi
  echo "reject: tree differs from the canonical rebuild in $(printf '%s' "$diff" | head -3 | paste -sd, -)"; return 1
}

# shadow_append <old testing> <old main>: builds sync/shadow locally (never pushed)
# and prints one verdict line: "equal <n>", "permuted <n>" (n = topic heads the
# append would rewrite), "ineligible: <why>", "conflict: <name>" or "reject: <why>".
# Never fails the candidate: every error becomes a verdict.
shadow_append() {
  local old_t=$1 old_main=$2 name head kind base prev_main cur c verdict
  [[ -n $old_t ]] || { echo "ineligible: no published testing"; return 0; }
  [[ $(rev sync/main) == "$old_main" ]] || { echo "ineligible: upstream moved (main rebased)"; return 0; }
  declare -A PREV=()
  while read -r name head; do
    case $name in @base) prev_main=$head ;; main) ;; *) PREV[$name]=$head ;; esac
  done < <(testing_merges "$old_t")
  # A testing that appended a newer main sits on an older base: its newest main is the newest "main" merge.
  head=$(testing_merges "$old_t" | awk '$1=="main"{print $2; exit}'); [[ -z $head ]] || prev_main=$head
  [[ -n ${prev_main:-} ]] && is_anc "$prev_main" "$old_main" || { echo "ineligible: main was rewritten"; return 0; }
  local pr=() po=() nr=() no=()
  while read -r kind name; do if [[ $kind == R ]]; then pr+=("$name"); else po+=("$name"); fi; done < <(manifest_lines "$prev_main")
  while read -r kind name; do if [[ $kind == R ]]; then nr+=("$name"); else no+=("$name"); fi; done < <(manifest_lines "$old_main")
  declare -A NEWSET=()
  for name in "${nr[@]}" "${no[@]}"; do NEWSET[$name]=1; done
  for name in "${pr[@]}" "${po[@]}"; do
    [[ -n ${NEWSET[$name]+x} ]] || { echo "ineligible: $name removed (merged into main or dropped)"; return 0; }
    if [[ -z ${PREV[$name]+x} ]]; then   # an empty topic ("Already up to date") leaves no merge commit
      head=$(rev "$ORIGIN/$name") && is_anc "$head" "$old_t" && PREV[$name]=$head \
        || { echo "ineligible: $name listed but not merged in old testing"; return 0; }
    fi
  done
  declare -A PRSET=(); for name in "${pr[@]}"; do PRSET[$name]=1; done
  local kept=(); for name in "${nr[@]}"; do [[ -z ${PRSET[$name]+x} ]] || kept+=("$name"); done
  [[ "${kept[*]}" == "${pr[*]}" ]] || { echo "ineligible: regular topics reordered"; return 0; }
  (( ${#po[@]} == 0 )) || [[ "${no[*]:0:${#po[@]}}" == "${po[*]}" ]] || { echo "ineligible: overlays reordered or one inserted before an older one"; return 0; }
  for name in "${nr[@]}" "${no[@]}"; do
    [[ -n ${PREV[$name]+x} ]] || continue
    head=$(rev "$ORIGIN/$name") || { echo "ineligible: no $ORIGIN/$name"; return 0; }
    [[ $head == "${PREV[$name]}" ]] || is_anc "${PREV[$name]}" "$head" || { echo "ineligible: $name edited (not a fast-forward of its published head)"; return 0; }
  done
  # Build: old testing, then main if it moved, then each new or grown topic in file order.
  local rewrites=0
  git checkout --quiet -B sync/shadow "$old_t" || { echo "reject: checkout failed"; return 0; }
  if [[ $prev_main != "$old_main" ]]; then
    git merge --quiet --no-ff --no-edit -m "testing: merge main" "$old_main" >/dev/null 2>&1 \
      || { git merge --abort 2>/dev/null; echo "conflict: main"; return 0; }
  fi
  for name in "${nr[@]}" "${no[@]}"; do
    head=$(rev "$ORIGIN/$name")
    [[ ${PREV[$name]:-} == "$head" ]] && continue
    if [[ -z ${PREV[$name]+x} && " ${no[*]} " == *" $name "* ]]; then
      # A new overlay: merge it as it is when the testing it was built on is already in this
      # append (the merge then brings only its own commits and keeps its head, e.g. a PR's);
      # replay its commits only when that testing was rewritten since.
      cur=$(rev HEAD)
      mapfile -t c < <(overlay_commits "$head" 2>/dev/null)
      (( ${#c[@]} > 0 )) || { echo "reject: overlay $name has no commits of its own"; return 0; }
      if ! is_anc "$(rev "${c[0]}^")" "$cur"; then
        git checkout --quiet -B sync/shadow-overlay "$cur"
        for base in "${c[@]}"; do
          git cherry-pick --allow-empty-message "$base" >/dev/null 2>&1 || { git cherry-pick --abort 2>/dev/null; git checkout --quiet sync/shadow; echo "conflict: $name"; return 0; }
        done
        head=$(rev HEAD); rewrites=$((rewrites + 1))
        git checkout --quiet sync/shadow
      fi
    fi
    git merge --quiet --no-ff --no-edit -m "testing: merge $name" "$head" >/dev/null 2>&1 \
      || { git merge --abort 2>/dev/null; echo "conflict: $name"; return 0; }
  done
  verdict=$(check_append "$(rev sync/shadow)" "$old_t" "$old_main" "$(rev sync/testing)" "$old_main") || { echo "$verdict"; return 0; }
  echo "${verdict#ok } $rewrites"
}

candidate() {
  local force=${1:-}
  : >"$REPORT"
  git remote get-url "$UPSTREAM" >/dev/null 2>&1 || git remote add "$UPSTREAM" "$UPSTREAM_URL"
  git fetch --quiet --prune "$ORIGIN" '+refs/heads/*:refs/remotes/'"$ORIGIN"'/*'
  git fetch --quiet "$UPSTREAM" "+refs/heads/$UPSTREAM_BRANCH:refs/remotes/$UPSTREAM/$UPSTREAM_BRANCH"

  partial_promote_guard

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
  local held= up_ok
  up_ok=$(ci_review_gate "$base" "$up" "$old_main")
  if [[ $up_ok != "$up" ]]; then
    held=$up; up=$up_ok
    if git merge-base --is-ancestor "$up" "$old_main" && [[ $force != --force ]]; then
      # Nothing else would change: no candidate, but exit 2 so the hold is reported.
      echo "changed=false" >>"${GITHUB_OUTPUT:-/dev/null}"
      exit 2
    fi
  fi
  dependency_report "$base" "$up" "$old_main"

  # Fork commits whose change upstream now carries: rebase drops them.
  local dropped
  dropped=$(git cherry -v "$up" "$old_main" "$base" | sed -n 's/^- \(.\{10\}\)[0-9a-f]* /\1 /p' || true)

  local state=()
  state+=("upstream=$up" "main=$old_main")
  [[ -z $held ]] || state+=("upstream_held=$held")

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

  # 4. overlays, each replayed onto testing so far, then merged into it
  for t in "${OVERLAYS[@]}"; do
    old_t=$(rev "$ORIGIN/$t") || die "overlay $t listed in .vommet/topics but $ORIGIN/$t does not exist"
    git checkout --quiet -B "sync/topic/$t" sync/testing
    replay "$t" $(overlay_commits "$old_t")
    state+=("topic:$t=$old_t")
    report "| $t | $(git rev-list --count "sync/testing..sync/topic/$t") | overlay on testing |"
    git checkout --quiet sync/testing
    git merge --quiet --no-ff --no-edit -m "testing: merge $t" "sync/topic/$t" >/dev/null 2>&1 \
      || conflict "testing (merging $t)"
  done

  # Pins: the candidate head of every topic, exactly as CI will see it. promote
  # refuses a sync/topic/* that moved after this (2026-11-07).
  for t in "${TOPICS[@]}" "${OVERLAYS[@]}"; do state+=("cand:$t=$(rev "sync/topic/$t")"); done

  # Shadow append (measuring only, never pushed, never promoted).
  local shadow
  shadow=$(shadow_append "${old_testing:-}" "$old_main" 2>/dev/null) || shadow="reject: shadow build error"
  git checkout --quiet sync/testing 2>/dev/null || true
  [[ -n $shadow ]] || shadow="reject: no verdict"
  state+=("shadow_append=$shadow")
  report "## Append promotion (shadow)" "" "\`$shadow\` (canonical rewrites $(( ${#TOPICS[@]} + ${#OVERLAYS[@]} )) topic heads). Measuring only: the canonical candidate is the one tested and promoted." ""

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

  # 5. state (leases for promote), as a parentless commit on sync/state
  local blob tree commit
  blob=$(printf '%s\n' "${state[@]}" "sync_main=$(rev sync/main)" "sync_testing=$(rev sync/testing)" | git hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tstate\n' "$blob" | git mktree)
  commit=$(git commit-tree "$tree" -m "sync state $(date -u +%FT%TZ)")
  git branch --force sync/state "$commit"

  local refs=(sync/main sync/testing sync/state)
  for t in "${TOPICS[@]}" "${OVERLAYS[@]}"; do refs+=("sync/topic/$t"); done
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
  # The token goes in through a file descriptor, not argv (argv shows in ps on the runner host).
  json=$(curl -fsS -H @<(printf 'Authorization: token %s\n' "$FORGEJO_TOKEN") "$FORGEJO_API/commits/$1/statuses?limit=50")
  IFS=, read -ra want <<<"$2"
  local w
  for w in "${want[@]}"; do
    # Every context starting with "$w /" must have passed on this exact commit
    # at least once. Not "latest status": a cancelled duplicate run (e.g. a
    # promote's own branch pushes) is recorded as failure and would mask the
    # pass. Same commit, same tree, so one pass is the evidence we need. The
    # trailing " (push)" / " (workflow_dispatch)" is ignored, so a manual
    # re-run of one failed job counts. "skipped" counts too: a job is skipped
    # only when its workflow's own check job decided the same content already
    # passed, and that check job is a separate context that must succeed.
    jq -e --arg w "$w" '
      [ map(.context |= sub(" \\([^)]*\\)$"; "")) | group_by(.context)[]
        | select(.[0].context | startswith($w + " /")) ] as $s
      | ($s | length > 0) and all($s[]; any(.[]; .status == "success" or .status == "skipped"))' <<<"$json" >/dev/null \
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

  # Every entry: its lease (the published tip when the candidate was cut) and its candidate. A ref
  # already at its candidate was moved by an earlier promote of THIS candidate that died part-way:
  # one --atomic push of ~1000 refs through Cloudflare hit its 100 s limit (HTTP 524) and the server
  # still applied 255 of them (cut 05b, 2026-11-05). So the moves go in leased batches, a re-run
  # resumes, and main and testing go last (testing at the candidate is what "promoted" means).
  local stamp name cand cur todo=() done_n=0 tags=() pinned=0
  declare -A LEASE=() CAND=()
  stamp=$(date -u +%Y%m%d-%H%M%S)
  # Candidates cut before 2026-11-07 have no cand: pins; those keep the old check.
  for k in "${!S[@]}"; do [[ $k == cand:* ]] && { pinned=1; break; }; done
  ((pinned)) || log "warning: sync/state has no candidate pins (cut by an older sync.sh); checking leases only"
  for k in "${!S[@]}"; do
    case $k in
      main) name=main; cand=${S[sync_main]} ;;
      testing) name=testing; cand=${S[sync_testing]} ;;
      topic:*) name=${k#topic:}; cand=$(rev "$ORIGIN/sync/topic/$name") || die "no sync/topic/$name"
               if ((pinned)); then
                 [[ -n ${S[cand:$name]:-} ]] || die "sync/state has no pin for $name"
                 [[ $cand == "${S[cand:$name]}" ]] || die "sync/topic/$name moved since the candidate was cut (pinned ${S[cand:$name]:0:10}, now ${cand:0:10})"
               fi ;;
      *) continue ;;
    esac
    v=${S[$k]}
    [[ -n $v ]] || die "$name has no lease in sync/state"
    LEASE[$name]=$v; CAND[$name]=$cand; tags+=("$v:refs/tags/pre-sync/$stamp/$name")
    cur=$(rev "$ORIGIN/$name" || true)
    if [[ $cur == "$cand" ]]; then
      [[ $v == "$cand" ]] || done_n=$((done_n + 1))
    elif [[ $cur == "$v" ]]; then
      todo+=("$name")
    else
      die "$name was pushed to since the candidate was cut; run the sync again"
    fi
  done
  ((done_n == 0)) || log "resuming a promote that died part-way: $done_n ref(s) already at their candidate"

  # Rollback points first (new tags overwrite nothing), then the moves: topics, main, testing.
  local i
  for ((i = 0; i < ${#tags[@]}; i += 200)); do git push --quiet "$ORIGIN" "${tags[@]:i:200}"; done
  local topics=() last=()
  for name in "${todo[@]}"; do case $name in main|testing) ;; *) topics+=("$name") ;; esac; done
  for name in main testing; do [[ " ${todo[*]} " == *" $name "* ]] && last+=("$name"); done
  push_moves "${topics[@]}"
  for name in "${last[@]}"; do push_moves "$name"; done

  local del=() r
  for r in sync/main sync/testing $(for k in "${!S[@]}"; do [[ $k == topic:* ]] && echo "sync/topic/${k#topic:}"; done); do
    del+=("--force-with-lease=refs/heads/$r:$(rev "$ORIGIN/$r" || true)" ":refs/heads/$r")
  done
  for ((i = 0; i < ${#del[@]}; i += 400)); do
    git push --quiet --atomic "$ORIGIN" "${del[@]:i:400}" || log "warning: could not delete some sync/* refs"
  done
  # sync/state last, and only once the rest is gone: a leftover sync/state makes the next cut's
  # candidate wait accept this (old) candidate.
  git fetch --quiet --prune "$ORIGIN" '+refs/heads/sync/*:refs/remotes/'"$ORIGIN"'/sync/*'
  if [[ -z $(git for-each-ref --format=x "refs/remotes/$ORIGIN/sync/topic" "refs/remotes/$ORIGIN/sync/main" "refs/remotes/$ORIGIN/sync/testing") ]]; then
    git push --quiet "$ORIGIN" ":refs/heads/sync/state" || log "warning: could not delete sync/state"
  else log "warning: sync/* refs left; sync/state kept (re-run the promote to clean up)"; fi
  promotion_record "$stamp" || log "warning: could not push the promotion record"
  log "promoted; rollback tags under pre-sync/$stamp/"
  echo "stamp=$stamp" >>"${GITHUB_OUTPUT:-/dev/null}"
}

# promotion_record <stamp>: one JSON file, promotion.json, in a parentless commit tagged
# pre-sync/<stamp>/_promotion (pruned with the rollback tags). PR tooling reads it to learn
# which published heads this promote replaced (2026-11-07). Uses S, LEASE and CAND.
promotion_record() {
  local stamp=$1 n rewritten=() kept=0 json blob tree commit
  for n in "${!LEASE[@]}"; do
    case $n in main|testing) continue ;; esac
    if [[ ${LEASE[$n]} != "${CAND[$n]}" ]]; then rewritten+=("$n"); else kept=$((kept + 1)); fi
  done
  json=$(jq -n --arg stamp "$stamp" --arg mode canonical \
    --arg old_testing "${S[testing]}" --arg new_testing "${S[sync_testing]}" \
    --arg old_main "${S[main]}" --arg new_main "${S[sync_main]}" \
    --arg upstream "${S[upstream]:-}" --arg shadow "${S[shadow_append]:-}" --argjson kept "$kept" \
    --arg reason "full rebuild: every topic is replayed onto main" \
    '{stamp:$stamp, mode:$mode, reason:$reason, old_testing:$old_testing, new_testing:$new_testing,
      old_main:$old_main, new_main:$new_main, main_rebased:($old_main != $new_main), upstream:$upstream,
      shadow_append:$shadow, unchanged_topics:$kept, rollback_prefix:("pre-sync/" + $stamp + "/"),
      rewritten:($ARGS.positional | sort)}' --args "${rewritten[@]}") || return 1
  blob=$(printf '%s\n' "$json" | git hash-object -w --stdin) || return 1
  tree=$(printf '100644 blob %s\tpromotion.json\n' "$blob" | git mktree) || return 1
  # the promote job's runner has no git identity configured; this commit isn't anyone's work
  commit=$(GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-$(git config user.name || echo vommet-sync)} \
           GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-$(git config user.email || echo vommet-sync@localhost)} \
           GIT_COMMITTER_NAME=${GIT_COMMITTER_NAME:-$(git config user.name || echo vommet-sync)} \
           GIT_COMMITTER_EMAIL=${GIT_COMMITTER_EMAIL:-$(git config user.email || echo vommet-sync@localhost)} \
           git commit-tree "$tree" -m "promotion $stamp") || return 1
  git push --quiet "$ORIGIN" "$commit:refs/tags/pre-sync/$stamp/_promotion"
}

# push_moves <name>...: move each to CAND[name] with a lease on LEASE[name], ~100 per atomic push.
# A push that fails (a proxy timeout) may still have been applied, so re-read the remote and retry
# only what is still at its lease; a ref at neither lease nor candidate stops the promote.
push_moves() {
  local names=("$@") i try n batch args specs cur left
  for ((i = 0; i < ${#names[@]}; i += 100)); do
    batch=("${names[@]:i:100}")
    for try in 1 2 3; do
      args=(); specs=()
      for n in "${batch[@]}"; do args+=("--force-with-lease=refs/heads/$n:${LEASE[$n]}"); specs+=("${CAND[$n]}:refs/heads/$n"); done
      git push --quiet --atomic "${args[@]}" "$ORIGIN" "${specs[@]}" && break
      log "push of ${#batch[@]} ref(s) failed (try $try); re-reading the remote"
      sleep "${SYNC_RETRY_SLEEP:-60}"
      git fetch --quiet --prune "$ORIGIN" '+refs/heads/*:refs/remotes/'"$ORIGIN"'/*'
      left=()
      for n in "${batch[@]}"; do
        cur=$(rev "$ORIGIN/$n" || true)
        if [[ $cur == "${LEASE[$n]}" ]]; then left+=("$n")
        elif [[ $cur != "${CAND[$n]}" ]]; then die "$n moved during the promote"; fi
      done
      batch=("${left[@]}"); ((${#batch[@]})) || break
      ((try < 3)) || die "promote push failed 3 times; re-run the promote to resume"
    done
  done
}

# Rollback tags older than PRE_SYNC_KEEP_DAYS (default 7) go: each promote adds ~1,000, and by
# 2026-11 the 97k of them made every tag listing on nether.codes slow and gave crawlers an endless
# /src/tag/ URL space. Older ones were archived to a bundle on the forgejo host (2026-11-04).
prune_rollback_tags() {
  local cut old=()
  cut=$(date -u -d "${PRE_SYNC_KEEP_DAYS:-7} days ago" +%Y%m%d)
  mapfile -t old < <(git ls-remote --refs "$ORIGIN" 'refs/tags/pre-sync/*' \
    | awk -v c="$cut" '{ split($2, p, "/"); if (substr(p[4], 1, 8) < c) print ":" $2 }')
  ((${#old[@]})) || return 0
  local i
  for ((i = 0; i < ${#old[@]}; i += 500)); do
    git push --quiet "$ORIGIN" "${old[@]:i:500}" || { log "warning: could not prune old rollback tags"; return 0; }
  done
  log "pruned ${#old[@]} rollback tags older than $cut"
}

# check-append <commit>: read-only check of <commit> against the current candidate.
check_append_cmd() {
  [[ -n ${1:-} ]] || die "usage: $0 check-append <commit>"
  git fetch --quiet --prune "$ORIGIN" '+refs/heads/*:refs/remotes/'"$ORIGIN"'/*'
  rev "$ORIGIN/sync/state" >/dev/null || die "no candidate (run candidate first)"
  declare -A S=(); local k v c
  while IFS='=' read -r k v; do S[$k]=$v; done < <(git show "$ORIGIN/sync/state:state")
  c=$(rev "$1") || die "no commit $1"
  # the candidate must contain the NEW main (sync_main): promote moves main there
  check_append "$c" "${S[testing]:-}" "${S[sync_main]}" "${S[sync_testing]}" "${S[sync_main]}"
}

case ${1:-} in
  candidate) candidate "${2:-}" ;;
  check-append) check_append_cmd "${2:-}" ;;
  promote) promote; prune_rollback_tags ;;
  *) die "usage: $0 candidate [--force] | promote | check-append <commit>" ;;
esac
