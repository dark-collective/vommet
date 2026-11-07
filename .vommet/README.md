# Fork maintenance (`.vommet/`)

Vommet is a soft fork: Commet's `main` plus a stack of our own commits, rebased
onto upstream continuously so we take Commet's changes in small steps and can
drop our patches as upstream lands equivalent fixes. Fork-only tooling lives in
this directory so it never collides with upstream paths.

## Branch layout

| Branch | What it is |
|---|---|
| `main` | upstream `main` + a **linear** stack of accepted fork commits (no merges) |
| topic branches | work not on `main` yet, listed in [`topics`](topics); each is linear, based on `main` or on another topic (`after`) |
| `testing` | **generated**: `main` + a `--no-ff` merge of every topic in `topics` order. Tester builds come from here. Don't commit to it directly; change a topic and restack |
| `sync/*` | candidates cut by the sync job; deleted on promotion |

**VOMMET_CHANGES.md:** give each topic its own section at the end of the file,
starting with a blank line. The file uses git's union merge (`.gitattributes`),
so sections that topics append at the same spot are kept side by side.

When two topics touch the same lines, stack one on the other (`after`) and
resolve the conflict once, inside the child branch. Otherwise the merge into
`testing` conflicts on every restack.

**Overlays** (`<branch> overlay` in `topics`) are for one change that edits
code from many topics at once, which no single parent could hold (e.g. making
Vommet's own strings translatable). The branch is linear on top of a
`testing` commit. The sync replays its commits onto the regenerated `testing`
after all regular topics and merges it in last. On a conflict, rebase the
overlay onto the current `testing` by hand (for l10n: redo the conflicting
strings and re-extract `intl_en.arb`).

## Upstream sync

1. **`upstream-sync`** (daily 05:17 UTC, or run it by hand): `sync.sh candidate`
   fetches Commet's `main`; if it moved, it rebases `main` onto it, replays every
   topic onto its rebuilt parent, regenerates `testing`, and pushes everything as
   `sync/main`, `sync/topic/<topic>`, `sync/testing`, plus `sync/state` (the old
   tips). Nothing published moves. It posts the report (upstream commits pulled
   in, fork commits that upstream now carries, per-branch status) on an open
   **Upstream sync** issue, creating one if none is open.
2. CI runs on `sync/main` and `sync/testing` like on any push.
3. **`upstream-promote`** (by hand): `sync.sh promote` checks that CI is green
   on both candidate heads (`build` on main; `build` and `android` on testing)
   and that nobody pushed to `main`, a topic or `testing` since the candidate
   was cut, and that no `sync/topic/<topic>` moved after it (the candidate heads
   are pinned as `cand:<topic>=` lines in `sync/state` since 2026-11-07). It then
   tags the old tips `pre-sync/<stamp>/<branch>`, moves the branches in leased
   batches (main and testing last), and pushes the promotion record (below).
   Finally it closes the issue.

Run **upstream-sync with `force`** to restack without an upstream change, e.g.
after editing a topic, to regenerate `testing`.

### On a conflict

The job stops at the first conflict and the issue names the branch, commit and
files. Rebase that branch by hand onto its new parent (`main` = upstream main
for `main` itself), resolve, push, and run the sync again.

### When upstream changes CI files (held for review)

Upstream commits that touch `.forgejo`, `.gitea`, `.github/workflows`,
`.github/actions` or `.vommet` would run with the fork's secrets as soon as a
candidate is pushed. So the sync takes upstream only up to the last commit
whose CI changes someone reviewed, recorded as one sha in
`.vommet/upstream-ci-reviewed` on main. Newer upstream commits that change those
paths are held: the candidate is cut on the older upstream commit (topics still
restack and ship), the report gets a **⏸ Upstream CI changes held for review**
section with the files, and `sync/state` gets an `upstream_held=<sha>` line. A
run without `force` that has nothing else to do exits 2, so the hold is posted
on the sync issue like a conflict.

Only upstream's own changes count (merge base to upstream tip), so the fork's
CI files and the GitHub workflows `winbranch.sh` adds never trigger it. To
accept: read the `git diff` the report prints, then commit the held sha as the
only line of `.vommet/upstream-ci-reviewed` on main (not while a candidate is
in CI). Only a person does this, never an unattended run.

### When upstream fixes something we patched

The rebase drops our commit automatically if upstream's change is identical.
Otherwise we get a conflict, or the commit becomes empty; the report lists it
either way. Then close the fork issue and update `VOMMET_CHANGES.md`.

### Promotion record

Each promote pushes `pre-sync/<stamp>/_promotion`, a commit holding `promotion.json`:
`mode`, `reason`, `old_testing`/`new_testing`, `old_main`/`new_main`, `main_rebased`,
`shadow_append`, `rewritten` (every topic whose published head this promote replaced),
`unchanged_topics` and `rollback_prefix`. PR tooling uses it to tell which PR bases a
promote replaced, without guessing from the branch list:

```
git ls-remote origin 'refs/tags/pre-sync/*/_promotion'
git fetch origin tag pre-sync/<stamp>/_promotion && git show pre-sync/<stamp>/_promotion:promotion.json
```

It is pruned with the rollback tags.

### Append promotion (shadow)

Every promote today is a full rebuild: each topic is replayed onto `main` and `testing`
is regenerated, so every topic head and `testing` get new commits even when the cut
only added an overlay. A PR built on the old `testing` then fails Forgejo's merge check
and its CI restarts. An *append* would keep history instead: old `testing` + a merge of
`main` (when it moved) + a merge of each new or grown topic, in file order, with nothing
rewritten. A new overlay whose base `testing` is already in the append is merged as it
is (its head, e.g. a PR's, stays); one built on a `testing` that was rewritten since is
replayed.

`sync.sh candidate` builds that append locally (`sync/shadow`, never pushed) and records
the result as `shadow_append=` in `sync/state` and in the report:

| Verdict | Meaning |
| --- | --- |
| `equal <n>` | same tree as the canonical rebuild; `<n>` topic heads would be rewritten (replayed overlays) |
| `permuted <n>` | same, except `VOMMET_CHANGES.md` lines in another order (its `merge=union` places a section by merge order) |
| `ineligible: <why>` | upstream moved, `main` rewritten, a topic removed, reordered or edited (not a fast-forward), an overlay inserted before an older one |
| `conflict: <name>` / `reject: <why>` | the append doesn't merge, or fails `check-append` |

Any upstream move makes the run ineligible (an append can never keep ancestry across a rebased `main`), so only topic-only `--force` runs are measured. An empty topic (no commits of its own) counts as merged when its head is already in the old testing.

It is measuring only: CI runs on, and promote moves, the canonical candidate. A replay of
the releases from 2026-11-01 to 11-07 found 31 of 33 eligible, 20 equal and 11 permuted.
`sync.sh check-append <commit>` is the read-only check a live append would have to pass at
promote time: old `testing` and `main` are ancestors, every listed topic's published head
is an ancestor (except an overlay old `testing` never merged), and the tree equals the
canonical one (or is `permuted`). Tests: `python3 .vommet/sync-test.py -v` (toy repositories,
the real `sync.sh`; `SYNC_SH=<other copy>` runs them against another version).

### Rolling back a promotion

Every promoted branch has a `pre-sync/<stamp>/<branch>` tag at its old tip:
`git push --force origin pre-sync/<stamp>/main:refs/heads/main` (and the same
for each topic and `testing`).
Tags older than 3 days (`PRE_SYNC_KEEP_DAYS` in upstream-promote.yml; default 7) are deleted after each promotion;
older ones up to 2026-10-27 are in a git bundle on the forgejo host
(`/var/lib/forgejo/archive/`).

## Secrets

`SYNC_TOKEN`: a nether.codes token with write access to this repo. Pushes made
with the job's own token don't trigger CI, and the candidates must run CI.
