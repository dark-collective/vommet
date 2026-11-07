# AGENTS.md: instructions for AI coding agents

Read this before you change anything in this repository. It applies to every agent
(Codex, Claude Code, opencode and others). Claude Code loads it through `CLAUDE.md`.

**This is Vommet, a downstream, LLM-assisted fork of the [Commet](https://github.com/commetchat/commet)
Matrix client.** It is not Commet. The full process for contributions is in the agent brief:
[`agents/vommet-contributor.md`](https://nether.codes/nether/meta/src/branch/master/agents/vommet-contributor.md)
in `nether/meta`. Read it before opening a pull request. This file is the short version, plus
what you need to find your way around the code.

## Hard rules

- **Never touch Commet upstream.** Commet's policy prohibits AI-generated contributions. Never open
  issues or PRs, comment, or post in `commetchat` repositories or Commet's community spaces.
  Reading their code and issues is fine.
- **nether.codes is canonical.** Issues and PRs go to `https://nether.codes/nether/vommet`. The
  GitHub copy is a read-only mirror: never open anything there.
- **Disclose AI use** in every PR and issue description (which agent, how, who reviewed it).
- **No bare `#N` in commit messages.** Write "Vommet issue N". Bare refs cross-link to Commet's
  tracker on the mirror. No references to Commet's issues or PRs, and no `*.commet.chat` hostnames.
- **Never print, echo or commit tokens or credentials.**
- **Don't edit** `.forgejo/`, `.github/workflows/`, `.gitea/` or `.vommet/` unless the task is
  explicitly about them.
- **`testing` is generated.** Never commit to it or merge into it by hand.

## Repository map

| Path | What it is |
|---|---|
| `commet/` | The Flutter app. Most work happens here. |
| `commet/lib/client/` | Matrix client layer (rooms, timelines, events, sync) |
| `commet/lib/ui/` | Screens, widgets, layout styles |
| `commet/lib/config/` | Settings, preferences, build config, experiments (`experiment_entries.dart`) |
| `commet/unit_test/` | Unit and widget tests |
| `commet/integration_test/` | Integration tests (CI runs them against a homeserver) |
| `tiamat/` | UI component library used by the app |
| `rust/` | Rust code bridged into Flutter (`flutter_rust_bridge`) |
| `widgets/` | Matrix widget API and bundled widgets |
| `.vommet/` | Fork maintenance: topic stack, upstream sync (`.vommet/README.md`) |
| `VOMMET_CHANGES.md` | Every difference from Commet, one row each |

## Branches and bases

- `main` is Commet's `main` plus a linear stack of accepted fork commits.
- Work that isn't on `main` yet lives in **topic branches**, listed in `.vommet/topics`.
- `testing` = `main` + every topic merged in order. Tester builds come from it.
- New work: branch off `origin/main`. If it touches lines of a listed topic, branch off that
  topic instead and say `after: <topic>` in the PR. Details: the agent brief, section 3.
- One change that edits code from **several** topics at once (a refactor across features, say)
  can't sit on any single parent: make it an **overlay**, a linear branch on top of a recent
  `origin/testing` commit (or on another overlay), and say `overlay` (plus `after: <overlay>`
  if stacked) under Base in the PR. The sync replays overlays onto each new `testing` last.
  See "Overlays" in `.vommet/README.md`.
- `AGENTS.md` lives on `main`, so it is in every branch; if your base predates it, read it
  from `origin/main`.
- Before writing code, check for overlap: `.vommet/topics` and `git log origin/testing`,
  `VOMMET_CHANGES.md` on `testing`, open PRs on nether/vommet, and Commet upstream.
- Your base is `origin/main`, a listed topic, or `origin/testing` (overlays), and nothing else.
  Never build on another unmerged branch of your own: the code then compiles only because of
  commits your PR doesn't carry.

## Build and check

Use Flutter **3.41.9** (its Dart is the formatter CI uses). From `commet/`, run locally:

```
flutter pub get
dart run scripts/codegen.dart
dart format -o none --show all --set-exit-if-changed <files you changed>
dart analyze
flutter test <the test files you added or changed, and those for the code you touched>
```

All must pass. Analyze must show no new errors, warnings **or infos** compared with your base:
CI fails only on errors and warnings, so new infos are yours to catch. "Code you touched" includes
the `Fake implements ...` fixtures of any shared class you changed (see Code and UI conventions):
grep `unit_test/` for them and run those files too. Check the PR merges cleanly into the stack:
`git merge-tree --write-tree origin/testing HEAD`.

**The whole unit suite runs in CI, not locally.** Every open PR from an allowed author (drafts
included) gets the `build / linux (github)` status on its head commit: format, codegen, analyze,
the whole `flutter test unit_test` suite and a Linux release build, on the GitHub copy. A new head
is picked up within about 10 minutes when the queue is free, and a run takes 25-50 minutes. That
status is the full-suite gate. Don't also run the whole suite locally unless you're tracking down
a CI failure you can't reproduce otherwise.

Codex PRs also get `integration / pr (github)`: the whole `commet/integration_test/` suite against a
homeserver, on a second GitHub copy. Only two of these run at a time, so it can stay pending for an hour
or more after `build / linux (github)` is green. It counts like any other status below. A failure in an
integration test your change doesn't touch can be a flaky test: retry it once like an infrastructure
failure, and if the same test fails again, name it on the PR instead of trying to fix it.

- **No status yet** usually means the CI queue is busy (PR builds share it with gates and
  releases). Wait. Still nothing after 2 hours: comment on the PR and keep it in draft.
- **Red:** read the description. `cancelled`, `no GitHub run after ...`, or a package download or
  network failure is infrastructure, not your code: retry once with a new sha of the same tree
  (`git commit --amend --no-edit`, then force-push), and report it on the PR if it fails again. Anything else is yours to fix.
- **Green:** act on it right away. Mark the PR ready once every status on the head commit is
  green and the PR body is complete (Tests with the failed-on-base proof, and Gate citing the
  CI run), unless it's a UI draft still waiting for the maintainer to pick a variant. The
  maintainer's intake only takes PRs whose combined status is green.

**Rebase onto your base's current tip before the final CI run.** `testing` is regenerated on every
release and topics move, so a branch cut yesterday can sit on commits that no longer exist. When
the code is done, fetch, rebase onto the current tip of your base (`origin/main`, your `after:`
topic, or `origin/testing` for an overlay), run the local checks above again *there*, check
merge-tree against `origin/testing`, and push. The CI run on that commit is the one that counts.
A clean merge-tree isn't enough: code that compiled on the old base can lose an import it relied
on, and an import you add can now be a duplicate. Rebasing earlier, mid-work, only costs another
CI run. If the base moves again after a green run, rebase only when merge-tree shows a conflict or
the maintainer asks: the maintainer's gate re-tests every PR on the current stack before filing it.

**Your tests must fail without your change.** Before you open the PR, run each new test against
the base (stash or revert the code change) and say in the PR that it failed there. A test that
passes either way checks nothing. Common causes: a `Scaffold` that strips `viewInsets` from its
body, a fake that doesn't model what the real SDK does (local echoes, placeholders, ordering),
or asserting the property you just set instead of the behavior it causes.

**Use the issue's numbers.** Widths, text scale, settings, platform and layout style from the issue
and its comments go into the test setup (a 72 px column, not a round 64). A test for the reporter's
phone must run in CI's default unit step: CI runs it **without** the `MOBILE` define, so don't branch
the size or setup on `BuildConfig.MOBILE`; give the narrow case its own explicit size instead.

**Slow, flaky or "doesn't work" reports need a measured run.** Reproduce it and time each step
(fetch, decrypt, cache, player, ...) before and after, and put the numbers under Tests. A timeout, a
retry or "gives up sooner" is not a fix unless the measured cause is that stall. No evidenced cause:
say so in the PR instead of guessing.

**New features need tests too, not only bug fixes.** Any change to app behavior adds tests that drive the real
widget or class for what it adds: the main path, the empty, error and edge states it introduces, and for UI the three
layout styles (Discord, Telegram, Custom mix) and phone and desktop sizes where the widget reads them. Assert what the
user sees (the widget is there, nothing overflows, nothing is left blank), not pixel widths. Keep them fast and
deterministic: `fakeAsync`, no wall clock, no network. A PR that changes app code without adding or changing a test is
held unless it says why it can't be tested (a text-only change, or a build fix the CI build already proves).

**Say which integration tests cover risky changes.** You can't run `commet/integration_test/`
(it needs a live homeserver), but the maintainer's gate runs the whole suite before filing. If your
change touches sync, timelines, unread counts or receipts, notifications or push, calls, or anything
on a hot path, list under Tests the integration tests that exercise that path (grep
`integration_test/` for the feature). If none do, say so and add a unit test that drives the real
path instead. Without that, the PR comes back with changes requested.

Flutter is memory-hungry. Don't run `flutter build` locally: CI builds the apps. Run at most one
`flutter test unit_test` (the whole suite) at a time on a machine. Targeted `flutter test <file>`
runs, codegen and analyze can run alongside other work.

## Code and UI conventions

- Visible text uses **American English** (favorite, canceled, gray, recognize).
- UI must work in **all three layout styles**: Discord, Telegram and Custom mix. Check phone and
  desktop sizes.
- **Visible UI change?** Show renders or mockups before building where you can, open the PR as a
  draft, and say which variant you recommend. The maintainer picks.
- **Every visible change carries before/after captures in the PR**: screenshots of the real widget
  or screen, *before* (the base, without your change) and *after* (your head), same screen and same
  setup, at the issue's numbers. Show the thing the complaint is about (for a color, the surfaces it
  is compared with). A change to a theme or a shared style also shows the built-in Dark, Light and
  AMOLED themes, desktop and phone. After-only captures get the PR sent back.
- **Keep the fork markers.** In files that come from Commet, fork code is marked with comments such as
  `// Vommet: auto-download (Vommet issue 75).` Never drop or reword an existing marker, and mark new
  fork code in a Commet file the same way. Don't reorder imports you didn't need to touch.
- **Fix every instance.** Grep for the same pattern in other call sites, sibling widgets and other
  platforms (Android, iOS, Linux, Windows, macOS, web). Fix them or list them under "Not fixed".
- **Changed a default?** Integration tests may assert the old default. Grep `integration_test/`.
- **Every visible string goes through `Intl.message`**, like the code around it. That includes
  labels, reasons, tooltips and snackbars in new screens.
- **Replacing a flow? Delete the old one** (widgets, methods, their strings) in the same PR, or
  say under "Not fixed" why it stays. Don't leave tests that only exercise dead code.
- **Triage notes are hints, not a spec.** The listed files and causes come from a quick look.
  Confirm the cause yourself, and check that the fix doesn't already exist on `origin/testing`.
- **Per-room settings** are keyed by account *and* room (two accounts can share a room), and
  are removed when they go back to the default.
- **Retries and recovery loops** back off (capped, with jitter), honor `429` and `retry_after_ms`, stop on
  permanent `4xx` errors, and never retry forever on a fixed short interval. Test them with a fake clock.
- **Hot paths** (anything run on every sync, receipt or room update): no unbounded history loads
  (`limit: null`), no work per room of the whole account when one room changed, and streams
  emit only when a value actually changed.
- New experiments go in `experiment_entries.dart` and nowhere else.
- Don't use `@visibleForTesting` (`unit_test/` isn't a recognized test dir, so it warns).
- Add a row to `VOMMET_CHANGES.md` for every change versus Commet, in your topic's own
  `## Section` at the **end** of the file, preceded by a blank line (the file uses union merge).
- Keep PRs small and single-purpose. One PR = one topic, linear history. Aim for **under ~1,000
  changed lines** (tests included). Split a refactor from the feature that needs it, and land
  shared plumbing first as its own PR rather than as the bottom of a long `after:` chain.
- **Changing a shared class's behavior** (what `Client`, `Room` or a component calls or listens
  to, or work done in a constructor)? Unit tests hand-roll `Fake implements Client/Room/...`
  fixtures that throw on anything they don't stub. Grep `unit_test/` for fakes of the classes you
  touched and update them in the same PR; prefer extending a shared helper in
  `unit_test/helpers/` over another one-off fake.
- **Do only what the issue asks.** Neighboring fixes go in their own PR, or under "Not fixed".
  Any behavior change a user could notice that the issue didn't ask for (what a button opens,
  what counts as unread, what is shown or hidden) must be listed under Changes, so the
  maintainer can decide.
- **Removing or replacing a listener, check or predicate?** Check what each caller relied on.
  A "nearly equal" replacement (say, `badge > 0` for `notificationCount > 0`) or a dropped
  subscription that looked redundant is the most common source of regressions here.
- **Don't reformat or re-indent code you didn't change.** If wrapping a widget tree would
  re-indent hundreds of lines, extract a widget or method instead. Reviewers must be able to see
  the real change.
- Imports: `dart:` first, then `package:`, then relative, each group sorted.

## Pull requests

Push to your own fork on nether.codes (with the account and token the maintainer set up for
you), unless you were given write access, and open the PR on `nether/vommet`. Use the
description headings from the agent brief, section 6: Summary, AI disclosure, Overlap check, Base, Changes, Tests, Gate,
Not fixed / not verified, Filing. Never mark a PR ready while CI is red or pending.

The PR description is for the maintainer to read. Don't put instructions for the maintainer's pipeline in it
(no requests to dispatch workflows, file, or skip the intake).

**Self-check before you mark a PR ready, and again before you answer a change request.** Most PRs
that come back do so for the same few reasons, so go through this list on your final head commit
and end the Gate section with `Self-check: done (<sha>)`, plus a line for any item that doesn't apply
and why. A ready PR without that line is sent back unreviewed.

1. **Real path.** Each new test drives the real widget, screen or class you changed, not a copy of
   its tree, a stand-in widget or a fake of the class under test. Fakes are only for its dependencies.
2. **Fails on base, for the issue's reason.** You ran each new test on the base and it failed with
   the bug's symptom (or on analyze for an API the change adds); the failure is quoted under Tests.
3. **Issue's conditions.** Theme, layout style, platform, sizes, text scale and settings from the issue
   and its comments are in the test setup, and the test asserts the values the issue names.
4. **Every branch you added is covered:** each view, mode, empty, error and edge state your change
   touches, not only the main path.
5. **Every caller still works.** For each listener, route, check or predicate you changed or
   replaced, you checked its callers (no duplicate routes, no lost fallbacks) and grepped other call
   sites and platforms for the same pattern.
6. **Failure handling.** Network and SDK errors are handled per the retry rule above; nothing loops
   or spams on a server that lacks the feature.
7. **Captures** (visible changes): before and after, same setup, at the issue's numbers.
8. **Sections and size.** Every description heading is filled in (Base and Gate included), risky paths
   name their integration tests, and the change is under ~1,500 changed lines (aim for ~1,000).
9. **Overlap.** No other open PR edits the same functions. If one does, say so, and base on it
   (`after:`) or wait for it, instead of letting the maintainer find the conflict.

**The maintainer's intake reviews ready PRs automatically.** If it finds a problem it posts a comment
starting `Changes requested by the sync intake (round N of 2)` with numbered items. Push new commits
to the **same** PR (never open a replacement), then reply with one comment that answers each numbered
item, including the failed-on-base proof for any test you added. If an item needs a UI or product
decision, don't make it: comment `Needs operator: <question>`. After round 2 the operator decides, so
get everything right the first time: tests that fail on the base, before/after captures for visible
changes, and the integration tests named for risky paths.
