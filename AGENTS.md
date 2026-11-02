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

Use Flutter **3.41.9** (its Dart is the formatter CI uses). From `commet/`:

```
flutter pub get
dart run scripts/codegen.dart
dart format -o none --show all --set-exit-if-changed .
dart analyze
flutter test unit_test
```

All five must pass, with no new analyzer warnings compared with your base. Run the whole unit
test suite, not just your tests. Check the PR merges cleanly into the stack:
`git merge-tree --write-tree origin/testing HEAD`.

**Re-check on the current base right before you mark a PR ready.** `testing` is regenerated on
every release, so a branch cut from yesterday's `testing` sits on commits that no longer exist.
Fetch, rebase onto the current `origin/testing` (or your `after:` topic's current tip), and run
codegen, analyze and the whole unit suite again *there*. A clean merge-tree isn't enough: code
that compiled on the old base can lose an import it relied on, and an import you add can now be
a duplicate.

**Your tests must fail without your change.** Before you open the PR, run each new test against
the base (stash or revert the code change) and say in the PR that it failed there. A test that
passes either way checks nothing. Common causes: a `Scaffold` that strips `viewInsets` from its
body, a fake that doesn't model what the real SDK does (local echoes, placeholders, ordering),
or asserting the property you just set instead of the behavior it causes.

Flutter builds are memory-hungry. Don't run two at once, and prefer letting CI build the apps.

## Code and UI conventions

- Visible text uses **American English** (favorite, canceled, gray, recognize).
- UI must work in **all three layout styles**: Discord, Telegram and Custom mix. Check phone and
  desktop sizes.
- **Visible UI change?** Show renders or mockups before building where you can, open the PR as a
  draft, and say which variant you recommend. The maintainer picks.
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
