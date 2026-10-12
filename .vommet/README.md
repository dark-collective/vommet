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
   was cut. It then tags the old tips `pre-sync/<stamp>/<branch>` and moves all
   branches in one atomic, lease-protected push. Finally it closes the issue.

Run **upstream-sync with `force`** to restack without an upstream change, e.g.
after editing a topic, to regenerate `testing`.

### On a conflict

The job stops at the first conflict and the issue names the branch, commit and
files. Rebase that branch by hand onto its new parent (`main` = upstream main
for `main` itself), resolve, push, and run the sync again.

### When upstream fixes something we patched

The rebase drops our commit automatically if upstream's change is identical.
Otherwise we get a conflict, or the commit becomes empty; the report lists it
either way. Then close the fork issue and update `VOMMET_CHANGES.md`.

### Rolling back a promotion

Every promoted branch has a `pre-sync/<stamp>/<branch>` tag at its old tip:
`git push --force origin pre-sync/<stamp>/main:refs/heads/main` (and the same
for each topic and `testing`).

## Secrets

`SYNC_TOKEN`: a nether.codes token with write access to this repo. Pushes made
with the job's own token don't trigger CI, and the candidates must run CI.

## Where fork code goes

Fork code lives in its own files; an upstream file gets at most a thin hook (an
import, a `with` clause, one call). Every line we change in an upstream file is
a line that can conflict when `main` is rebased onto Commet or a topic is
restacked, and `commet/lib/config/preferences.dart` showed why: 105 of 127
topics touched it.

- **Preferences:** Vommet-only preferences go in
  `commet/lib/config/vommet_preferences.dart` (`mixin VommetPreferences`, mixed
  into upstream's `Preferences`, so `preferences.x` is unchanged for callers).
  Preferences already added to `preferences.dart` by in-flight topics move there
  as those topics land on `main`, each a pure relocation.
- **Experiments:** metadata stays in `experiment_entries.dart` (union-merged);
  the preference backing an experiment goes in the mixin.
- **Other hotspots** (`main_page.dart`, `chat.dart`, `matrix_client.dart`, the
  LiveKit session) get the same treatment case by case: an extension, mixin or
  helper in a `vommet_*` file plus one hook line.
