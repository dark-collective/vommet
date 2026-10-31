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
- Before writing code, check for overlap: `.vommet/topics` and `git log origin/testing`,
  `VOMMET_CHANGES.md` on `testing`, open PRs on nether/vommet, and Commet upstream.

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
- New experiments go in `experiment_entries.dart` and nowhere else.
- Don't use `@visibleForTesting` (`unit_test/` isn't a recognized test dir, so it warns).
- Add a row to `VOMMET_CHANGES.md` for every change versus Commet, in your topic's own
  `## Section` at the **end** of the file, preceded by a blank line (the file uses union merge).
- Keep PRs small and single-purpose. One PR = one topic, linear history.

## Pull requests

Push to your fork and open the PR on `nether/vommet`. Use the description headings from the
agent brief, section 6: Summary, AI disclosure, Overlap check, Base, Changes, Tests, Gate,
Not fixed / not verified, Filing. Never mark a PR ready while CI is red or pending.
