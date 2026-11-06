# PR integration snapshots (Vommet issue 1191)

`integration / pr (github)` runs the whole integration suite on a GitHub copy of an agent
PR's head (`pr-github.yml`, step 3b). The harness (`.vommet/it/run.sh`,
`commet/integration_test/vommet_runner.dart`) lives in the testing topic stack, not on
`main`, so a valid main-based PR doesn't carry it. Copying such a head as it was made the
gate fail before any test ran (`.vommet/it/run.sh: No such file or directory`, exit 2;
PR 1196 and PR 1212, 11-05/06).

## What the scheduler does

`.vommet/ci/pr-integration-tree.sh <head> <merge base|-> <testing|->` decides the tree:

| PR head | Tested tree | Snapshot message |
| --- | --- | --- |
| carries `.vommet/it/run.sh` (overlay and topic PRs) | the head's own tree | `... integration snapshot of <head>` |
| no runner, base `main` | `git --attr-source=testing merge-tree --merge-base=<PR merge base> testing <head>` (testing's `merge=union` attributes, never the PR's) | `... of <head> on testing <sha> (merge base <sha>)` |
| no runner, any other base; no merge base | none: failure status | - |

Either way the tree must hold an executable (100755) `run.sh` and the entry point
`vommet-integration.yml` selects, or nothing is enqueued and the head gets a failure
status that starts with `integration not started:` and says why (conflict with the
stack, runner deleted, not executable, entry point missing, no main merge base, a merge
base the server doesn't have). Failing to fetch `testing` leaves no status and is retried
on the next tick, with a warning in the log. If the helper itself can't be loaded, the
integration copies wait (no status) and the scheduler run fails with an error, after the
PR builds and gates went on as usual.
The pending and final statuses also say `on testing <sha>` for a merged tree, so a
result is never mistaken for one of the head alone. The pending status names the snapshot
commit, and the result mirrored later is that commit's GitHub run, never an older one. The PR branch and `testing` are never
changed: merge-tree only writes objects, from depth-one fetches of the three commits.

Security: the scheduler holds `GH_COPY_TOKEN` and `SYNC_TOKEN`. It runs the helper from
**its own commit** (`$GITHUB_SHA`: main when scheduled, a writer's branch when
dispatched), never a PR's copy, with an empty environment (`env -i`, so no token reaches
it), and never checks out or runs PR code. `.github/` in every snapshot is replaced by the
trusted workflow from `ci/windows-release`, as before.

## Automated checks

`python3 .vommet/ci/pr-integration-tree-test.py -v` (a few seconds; git, jq, python3) runs
the workflow's own shell, cut out of `pr-github.yml` between its `snapshot tree` markers,
plus the helper loading, the work-item jq, the retest guard and the result description,
against real repositories with depth-one fetches. It covers both PR kinds, conflicts,
deleted/non-executable runners, a missing entry point, a stack without the harness, a
missing or unfetchable merge base, source-head identity, the trusted `.github` replacement,
a PR-supplied helper, a workflow commit without the helper, that no token reaches the
helper, retest snapshots and run matching.

`vommet-pr.yml` (checks part, on ci/windows-release) runs it on every PR build whose tree
has it, so a PR that changes this scheduler is tested with its own changed copy, and a
tree whose `pr-github.yml` uses the helper but lacks the tests fails. Failed-on-base proof:
`WORKFLOW=<main's old pr-github.yml> python3 .vommet/ci/pr-integration-tree-test.py`
fails 19 of 23 (the main-based snapshot has no runner; invalid trees would be pushed).

## Deploying a CI repair (this file's procedure)

A broken PR gate cannot block its own repair: scheduler changes ship like any main
topic, through the sync inbox, whose pre-gate and cut run the integration suite on the
testing stack (which carries the harness), not through `integration / pr (github)`.

1. A maintainer session builds the fix on a `ci/*` topic off `origin/main`, runs this
   test file, and records the failed-on-base run.
2. Trial before it lands: push the topic branch, then dispatch `pr-github.yml` on that
   branch with `only=<PR>` (add `retest=yes` when that head already has a finished
   integration status). Only repo writers can dispatch; agent accounts can't. Check the
   copy's message and the real GitHub run.
3. File the topic in the inbox (`proof: internal`, with the test and trial links) and
   follow it with `await-release.sh`.
4. After it lands, check the schedule pin: Forgejo runs a scheduled workflow from the
   `commit_sha` stored for it, refreshed only by a main push that changes the workflow
   file. A helper-only change therefore needs a touch of `pr-github.yml` too. Then watch
   one scheduled tick take the new path.

`retest=yes` is for re-running a PR whose gate failed because of the CI itself, after
that is fixed. It is not a bypass: it only re-copies the same head (as a new snapshot
commit whose message ends `, retest <run id>`), the status comes from that new real run,
and it takes exactly one PR (`only`). Never post or clear an
`integration / pr (github)` status by hand, and never retest to wave through a test
failure in the PR's own code. Agents without write access ask the maintainer, or push a
new commit (AGENTS.md: one retry of the same tree for infrastructure failures).

This does not protect against network outages, flaky tests, GitHub capacity, or CI
changes outside this snapshot path.
