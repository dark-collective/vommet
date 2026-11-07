#!/usr/bin/env bash
# Vommet: prepare and check a PR's integration tree without a checkout or running PR code.
# Usage: pr-integration-tree.sh <head sha> <merge-base sha|-> <testing sha|->
# stdout: <tree sha> <testing sha, or '-' when the head's own tree is tested>.
# A head that carries the harness is tested as it is. A main-based head from before the
# integration topic is merged into the testing stack with its canonical merge base: the
# stack supplies the harness, and tests never run against older app code they weren't
# written for. Either way the tree must hold an executable runner and the entry point
# the workflow selects, or this fails (exit 1, reason on stderr) and nothing is enqueued.
# pr-github.yml runs its own commit's copy of this file with an empty environment (no tokens).
set -euo pipefail
head=$1 base=$2 testing=$3
runner=.vommet/it/run.sh
target=commet/integration_test/vommet_runner.dart
fail() { echo "$*" >&2; exit 1; }
commit() {
  [[ $1 =~ ^[0-9a-f]{40}$ ]] || fail 'invalid integration commit ID'
  git cat-file -e "$1^{commit}" 2>/dev/null || fail "commit ${1:0:12} not fetched"
}
check() {  # tree -> the harness is complete
  [[ $(git ls-tree "$1" "$runner") == '100755 blob '* ]] || {
    git cat-file -e "$1:$runner" 2>/dev/null && fail "$runner is not executable"
    fail "no $runner in the integration tree"; }
  [[ $(git cat-file -t "$1:$target" 2>/dev/null) == blob ]] || fail "no $target in the integration tree"
}
commit "$head"
if git cat-file -e "$head:$runner" 2>/dev/null; then
  tree=$(git rev-parse "$head^{tree}")
  check "$tree"
  printf '%s -\n' "$tree"
  exit 0
fi
[ "$base" != - ] && [ "$testing" != - ] || fail "head has no $runner and no main merge base to add it from"
commit "$base"; commit "$testing"
# A PR that deletes an existing runner must fail, not silently get it back.
! git cat-file -e "$base:$runner" 2>/dev/null || fail 'PR removed its integration runner'
# The explicit base lets the scheduler use depth-one fetches of all three commits.
# merge-tree writes objects only: no checkout, hooks, filters, build or PR code.
# Merge attributes come from testing's .gitattributes, as in the sync's own merges
# (VOMMET_CHANGES.md and experiment_entries.dart are merge=union), never from the PR;
# a fresh repo has no work tree to read them from (PR 1196 conflicted on 11-06 without).
rc=0; out=$(git --attr-source="$testing" merge-tree --write-tree --merge-base="$base" "$testing" "$head") || rc=$?
if [ "$rc" = 1 ]; then
  printf '%s\n' "$out" | sed -n '2,12p' >&2
  fail 'PR conflicts with the testing integration stack'
fi
[ "$rc" = 0 ] || fail "git merge-tree failed (exit $rc)"
tree=$(head -n1 <<<"$out")
check "$tree"
printf '%s %s\n' "$tree" "$testing"
