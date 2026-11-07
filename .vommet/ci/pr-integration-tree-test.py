#!/usr/bin/env python3
"""Regression tests for the PR integration snapshots in pr-github.yml (Vommet issue 1191).

They run the workflow's own shell (cut out of .forgejo/workflows/pr-github.yml between its
"snapshot tree" markers, plus the helper loading, the work-item jq and the integration
cap) against real Git
repositories with depth-one fetches, so a later edit of the workflow is what gets tested.
No network, Flutter or homeserver; a few seconds. Run from the repository root:

    python3 .vommet/ci/pr-integration-tree-test.py -v

WORKFLOW=<file> tests another pr-github.yml (e.g. main's before this change, as the
failed-on-base proof). vommet-pr.yml runs this in the checks part of every PR build.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = Path(__file__).with_name("pr-integration-tree.sh")
WORKFLOW = Path(os.environ.get("WORKFLOW", ROOT / ".forgejo/workflows/pr-github.yml"))
RUNNER = ".vommet/it/run.sh"
TARGET = "commet/integration_test/vommet_runner.dart"
CTX = "integration / pr (github)"
SECRETS = {"GH_TOKEN_COPY": "ghs_fixture_copy_secret", "FJ_TOKEN": "fj_fixture_sync_secret",
           "GITHUB_TOKEN": "fixture_runner_token"}
TRUSTED_WF = "name: vommet-integration\n"


def cut(source, start, end, include_end=False):
    """The workflow text from the line holding start to the line holding end."""
    a = source.index(start)
    a = source.rindex("\n", 0, a) + 1
    b = source.index(end, a)
    b = source.index("\n", b) + 1 if include_end else source.rindex("\n", 0, b) + 1
    return source[a:b]


class Fixture(unittest.TestCase):
    """A canonical repository: main (with the helper), testing (main + harness), PR heads."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)
        self.repo = self.dir / "canonical"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.write("app.txt", "versionName=0.5.1\n")
        self.write("CHANGES.md", "# changes\n")
        self.write(".gitattributes", "CHANGES.md merge=union\n")
        self.write(".github/workflows/ours.yml", "name: canonical\n")
        self.base = self.commit("main before the PR")
        self.write(".vommet/ci/pr-integration-tree.sh", HELPER.read_text(), executable=True)
        self.main = self.commit("main: integration-tree helper")
        # testing = main + the integration topic (harness) + other topics
        self.git("checkout", "-qb", "testing", self.main)
        self.write(RUNNER, "#!/bin/sh\nexit 0\n", executable=True)
        self.write(TARGET, "// integration entry point\n")
        self.write("stack.txt", "existing stack features\n")
        self.write("CHANGES.md", "# changes\n| harness topic |\n")
        self.testing = self.commit("testing: harness topic")
        # A main-based PR (main has no harness); it also changes the helper and brings a
        # workflow, neither of which may be used.
        self.git("checkout", "-qb", "pull", self.main)
        self.write("app.txt", "versionName=testing-2026-11-05b\n")
        self.write("CHANGES.md", "# changes\n| android fix |\n")
        self.write(".github/workflows/untrusted.yml", "name: untrusted\n")
        self.write(".vommet/ci/pr-integration-tree.sh",
                   "#!/bin/sh\necho 0000000000000000000000000000000000000000 -\n", executable=True)
        self.head = self.commit("Android metadata fix")
        # An overlay PR on testing, which carries the harness itself.
        self.git("checkout", "-qb", "overlay-pr", self.testing)
        self.write("stack.txt", "existing stack features\noverlay change\n")
        self.write(".github/workflows/untrusted.yml", "name: untrusted\n")
        self.overlay = self.commit("overlay change")
        self.git("checkout", "-q", "main")

    def git(self, *args, check=True, cwd=None, input=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, input=input,
                              text=True, capture_output=True, check=check)

    def write(self, name, value, executable=False):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        path.chmod(0o755 if executable else 0o644)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)
        return self.git("rev-parse", "HEAD").stdout.strip()

    def branch_from(self, start, name):
        self.git("checkout", "-qB", name, start)

    def helper(self, head, base="-", testing="-"):
        return subprocess.run(["bash", str(HELPER), head, base, testing], cwd=self.repo,
                              text=True, capture_output=True, check=False)

    def scheduler(self, head, base_ref="main", merge_base=None, workflow_sha=None, spy=None, retest=""):
        """Run the workflow's helper loading + snapshot code for one prit item, like a tick."""
        source = WORKFLOW.read_text()
        self.git("update-ref", "refs/pull/1196/head", head)
        workflow_sha = workflow_sha or self.main
        if "# snapshot tree (begin" in source:
            load = cut(source, "# The integration-tree helper comes", "declare -A TRUSTED")
            snap = cut(source, "# snapshot tree (begin", "git push -q --force")
        else:  # main before this change (failed-on-base proof)
            load = ""
            snap = cut(source, "# The top-level tree minus its .github/", "git push -q --force")
        work = self.dir / "scheduler"
        shutil.rmtree(work, ignore_errors=True)
        self.git("init", "-q", str(work))
        for ref in ("refs/pull/1196/head:refs/item/ci-prit-1196", "refs/heads/main:refs/main"):
            self.git("fetch", "-q", "--depth=1", "--no-tags", self.repo.as_uri(), ref, cwd=work)
        row = {"kind": "prit", "base": merge_base if merge_base is not None else self.main,
               "base_ref": base_ref}
        script = f"""set -euo pipefail
declare -A GHDIR
post() {{ printf 'POST %s|%s|%s\\n' "$2" "$3" "$4"; }}
fjh=$(mktemp)
blob=$(printf '{TRUSTED_WF.strip()}\\n' | git hash-object -w --stdin)
wf=$(printf '100644 blob %s\\tvommet-integration.yml\\n' "$blob" | git mktree)
GHDIR[vommet-integration.yml]=$(printf '040000 tree %s\\tworkflows\\n' "$wf" | git mktree)
echo "TRUSTED ${{GHDIR[vommet-integration.yml]}}"
kind=prit key=1196 tag=ci-prit-1196 wfile=vommet-integration.yml ctx='{CTX}' what='prit 1196'
{load}
{'load_ithelper; cp ' + str(spy) + ' "$ithelper"' if spy else ''}
for once in 1; do
{snap}
printf 'RESULT %s %s\\n' "$tree" "$snap"
done
echo "BROKEN ${{it_broken:-}}"
"""
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        env.update(SECRETS, RETEST=retest, GITHUB_RUN_ID="4242", sha=head, row=json.dumps(row), SRC=self.repo.as_uri(), GITHUB_SHA=workflow_sha,
                   GIT_AUTHOR_NAME="Vommet snapshot", GIT_AUTHOR_EMAIL="snapshot@nether.codes",
                   GIT_COMMITTER_NAME="Vommet snapshot", GIT_COMMITTER_EMAIL="snapshot@nether.codes",
                   GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="protocol.file.allow", GIT_CONFIG_VALUE_0="always")
        result = subprocess.run(["bash", "-c", script], cwd=work, env=env, text=True, capture_output=True)
        result.work = work
        lines = result.stdout.splitlines()
        result.posts = [line[5:].split("|") for line in lines if line.startswith("POST ")]
        res = [line.split()[1:] for line in lines if line.startswith("RESULT ")]
        result.tree, result.snap = res[0] if res else (None, None)
        result.trusted = next((line.split()[1] for line in lines if line.startswith("TRUSTED ")), None)
        return result

    def show(self, result, path):
        return self.git("show", f"{result.tree}:{path}", cwd=result.work, check=False)

    def assert_enqueued(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.posts, [], "a failure status for a valid tree")
        self.assertIsNotNone(result.tree, "nothing would be pushed:\n" + result.stdout + result.stderr)
        ls = self.git("ls-tree", result.tree, RUNNER, cwd=result.work).stdout
        self.assertTrue(ls.startswith("100755 blob "), "snapshot without an executable runner: " + ls)
        self.assertEqual(self.git("cat-file", "-t", f"{result.tree}:{TARGET}", cwd=result.work).stdout.strip(),
                         "blob", "snapshot without the integration entry point")
        # Only the trusted workflow, never the PR's .github.
        self.assertEqual(self.git("rev-parse", f"{result.tree}:.github", cwd=result.work).stdout.strip(),
                         result.trusted)
        self.assertEqual(self.git("show", f"{result.tree}:.github/workflows/vommet-integration.yml",
                                  cwd=result.work).stdout, TRUSTED_WF)
        self.assertEqual(self.git("rev-list", "--count", result.snap, cwd=result.work).stdout.strip(), "1")

    def assert_refused(self, result, why):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIsNone(result.tree, "an invalid tree would be pushed")
        self.assertEqual(len(result.posts), 1, result.stdout + result.stderr)
        ctx, state, desc = result.posts[0]
        self.assertEqual((ctx, state), (CTX, "failure"))
        self.assertIn("integration not started", desc)
        self.assertIn(why, desc)


class SchedulerSnapshots(Fixture):
    def test_main_based_head_is_tested_on_the_testing_stack(self):
        r = self.scheduler(self.head)
        self.assert_enqueued(r)
        self.assertEqual(self.show(r, "app.txt").stdout, "versionName=testing-2026-11-05b\n", "PR change kept")
        self.assertEqual(self.show(r, "stack.txt").stdout, "existing stack features\n", "testing stack used")
        # The source head and the stack it was tested on are on record; the PR ref is untouched.
        msg = self.git("log", "-1", "--format=%B", r.snap, cwd=r.work).stdout.strip()
        self.assertEqual(msg, f"Vommet pull request 1196 integration snapshot of {self.head} "
                              f"on testing {self.testing} (merge base {self.main})")
        self.assertEqual(self.git("rev-parse", "refs/pull/1196/head").stdout.strip(), self.head)
        self.assertEqual(self.git("rev-parse", "refs/item/ci-prit-1196", cwd=r.work).stdout.strip(), self.head)
        self.assertEqual(self.git("rev-parse", "testing").stdout.strip(), self.testing)
        self.assertTrue((r.work / ".git/shallow").exists(), "depth-one fetches")

    def test_head_with_harness_is_tested_exactly(self):
        r = self.scheduler(self.overlay, base_ref="testing", merge_base=self.testing)
        self.assert_enqueued(r)
        head_tree = self.git("ls-tree", self.overlay).stdout.splitlines()
        snap_tree = self.git("ls-tree", r.tree, cwd=r.work).stdout.splitlines()
        self.assertEqual([l for l in head_tree if not l.endswith("\t.github")],
                         [l for l in snap_tree if not l.endswith("\t.github")])
        msg = self.git("log", "-1", "--format=%B", r.snap, cwd=r.work).stdout.strip()
        self.assertEqual(msg, f"Vommet pull request 1196 integration snapshot of {self.overlay}")

    def test_union_rows_from_testing_attributes_merge(self):
        # Both sides append to a merge=union file (VOMMET_CHANGES.md); a shallow repo has no
        # work tree, so without testing's attributes this conflicted (PR 1196, 11-06).
        r = self.scheduler(self.head)
        self.assert_enqueued(r)
        self.assertEqual(sorted(self.show(r, "CHANGES.md").stdout.splitlines()),
                         sorted(["# changes", "| harness topic |", "| android fix |"]))

    def test_pr_attributes_are_not_used(self):
        self.branch_from(self.head, "attrs")
        self.write(".gitattributes", "CHANGES.md merge=union\napp.txt merge=union\n")
        head = self.commit("PR makes app.txt union")
        self.branch_from(self.testing, "testing")
        self.write("app.txt", "conflicting stack value\n")
        self.commit("conflicting topic")
        self.git("checkout", "-q", "main")
        self.assert_refused(self.scheduler(head), "conflicts with the testing integration stack")

    def test_conflict_fails_and_pushes_nothing(self):
        self.branch_from(self.testing, "testing")
        self.write("app.txt", "conflicting stack value\n")
        self.commit("conflicting topic")
        self.git("checkout", "-q", "main")
        self.assert_refused(self.scheduler(self.head), "conflicts with the testing integration stack")

    def test_overlay_head_that_deleted_the_runner_fails(self):
        self.branch_from(self.testing, "removed")
        (self.repo / RUNNER).unlink()
        head = self.commit("delete runner")
        self.assert_refused(self.scheduler(head, base_ref="testing", merge_base=self.testing), "isn't based on main")

    def test_head_with_nonexecutable_runner_fails(self):
        self.branch_from(self.overlay, "mode")
        (self.repo / RUNNER).chmod(0o644)
        head = self.commit("runner mode")
        self.assert_refused(self.scheduler(head, base_ref="testing", merge_base=self.testing), "not executable")

    def test_head_without_entry_point_fails(self):
        self.branch_from(self.overlay, "no-entry")
        (self.repo / TARGET).unlink()
        head = self.commit("drop entry point")
        self.assert_refused(self.scheduler(head, base_ref="testing", merge_base=self.testing), TARGET)

    def test_testing_without_harness_fails(self):
        self.git("update-ref", "refs/heads/testing", self.main)
        self.assert_refused(self.scheduler(self.head), "no .vommet/it/run.sh")

    def test_missing_merge_base_fails(self):
        self.assert_refused(self.scheduler(self.head, merge_base=""), "isn't based on main")

    def test_helper_runs_from_the_workflow_commit_without_tokens(self):
        spy = self.dir / "spy.sh"
        dump = self.dir / "helper-env"
        spy.write_text(f"#!/bin/bash\nenv > {dump}\nexec bash {HELPER} \"$@\"\n")
        r = self.scheduler(self.head, spy=spy)
        self.assert_enqueued(r)
        seen = dump.read_text()
        for name, value in SECRETS.items():
            self.assertNotIn(value, seen, f"{name} reached the helper")

    def test_pr_supplied_helper_is_never_run(self):
        # The PR's own helper would print an all-zero tree; the workflow commit's helper is used.
        r = self.scheduler(self.head)
        self.assert_enqueued(r)
        self.assertNotEqual(r.tree, "0" * 40)

    def test_workflow_commit_without_helper_holds_integration_and_flags_the_job(self):
        r = self.scheduler(self.head, workflow_sha=self.base)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIsNone(r.tree, "copied without the helper")
        self.assertEqual(r.posts, [], "no status: it waits for a working scheduler")
        self.assertIn("::error::no .vommet/ci/pr-integration-tree.sh", r.stdout)
        self.assertIn("BROKEN no .vommet/ci/pr-integration-tree.sh", r.stdout)

    def test_retest_makes_a_new_snapshot_commit(self):
        first, again = self.scheduler(self.head), self.scheduler(self.head, retest="yes")
        self.assert_enqueued(again)
        self.assertEqual(first.tree, again.tree)
        self.assertNotEqual(first.snap, again.snap, "a byte-identical commit starts no GitHub run")
        msg = self.git("log", "-1", "--format=%B", again.snap, cwd=again.work).stdout.strip()
        self.assertTrue(msg.startswith(f"Vommet pull request 1196 integration snapshot of {self.head} on testing "), msg)
        self.assertTrue(msg.endswith(", retest 4242"), msg)

    def test_unfetchable_merge_base_fails_with_a_reason(self):
        r = self.scheduler(self.head, merge_base="f" * 40)
        self.assert_refused(r, "is not on the server")


class SchedulerPieces(unittest.TestCase):
    source = WORKFLOW.read_text()

    def test_work_item_carries_the_canonical_merge_base(self):
        start = "items=$(jq -c --argjson a \"$items\" '"
        a = self.source.index(start) + len(start)
        b = self.source.index("' --argjson itu", a)
        pr = {"number": 1196, "head": {"sha": "a" * 40, "repo": {"full_name": "codex/vommet", "owner": {"login": "codex"}}},
              "base": {"ref": "main", "repo": {"full_name": "nether/vommet"}}, "labels": [],
              "user": {"login": "codex"}, "merge_base": "b" * 40}
        out = subprocess.run(["jq", "-c", "--argjson", "a", "[]", "--argjson", "itu", '["codex"]', self.source[a:b]],
                             input=json.dumps([pr]), text=True, capture_output=True, check=True).stdout
        prit = next(i for i in json.loads(out) if i["kind"] == "prit")
        self.assertEqual((prit.get("base"), prit.get("base_ref"), prit["sha"]), ("b" * 40, "main", "a" * 40))

    def retest(self, retest, kind, state):
        block = cut(self.source, "# A writer's dispatch (retest=yes", "# retest (end)")
        script = f"RETEST='{retest}' kind={kind} state={state} what=x\n{block}\necho \"STATE $state\""
        return subprocess.run(["bash", "-c", script], text=True, capture_output=True, check=True).stdout.split()[-1]

    def test_retest_only_reruns_finished_integration(self):
        self.assertEqual(self.retest("yes", "prit", "failure"), "none")
        self.assertEqual(self.retest("yes", "prit", "pending"), "pending")
        self.assertEqual(self.retest("yes", "pr", "failure"), "failure")
        self.assertEqual(self.retest("", "prit", "failure"), "failure")

    def test_retest_needs_one_pr(self):
        line = next(l for l in self.source.splitlines() if "retest takes yes" in l)
        for retest, only, ok in (("yes", "1196", True), ("yes", "", False), ("1", "1196", False), ("", "", True)):
            rc = subprocess.run(["bash", "-c", f"RETEST='{retest}' ONLY='{only}'\n{line}"],
                                capture_output=True).returncode
            self.assertEqual(rc == 0, ok, (retest, only))

    def match(self, description, runs):
        block = cut(self.source, "snapsha=$(jq -r '.description", "<<<\"$runs\")", include_end=True)
        env = {**os.environ, "st": json.dumps({"description": description}), "runs": json.dumps(runs),
               "tag": "ci-prit-1", "sha": "a" * 40}
        out = subprocess.run(["bash", "-c", f"set -euo pipefail\n{block}\necho \"[${{r:-}}]\""], env=env,
                             text=True, capture_output=True, check=True).stdout.strip()[1:-1]
        return json.loads(out)["id"] if out else None

    def test_pending_result_is_the_named_snapshot_run(self):
        old = {"id": 1, "b": "ci-prit-1", "hs": "1" * 40, "status": "completed", "msg": "snapshot of " + "a" * 40}
        new = {"id": 2, "b": "ci-prit-1", "hs": "2" * 40, "status": "queued", "msg": "snapshot of " + "a" * 40 + ", retest 9"}
        desc = "running on the GitHub copy, snapshot " + "2" * 40
        self.assertEqual(self.match(desc, [old, new]), 2)
        self.assertIsNone(self.match(desc, [old]), "the old run's result is never mirrored for a retest")
        self.assertEqual(self.match("running on the GitHub copy", [old]), 1, "statuses from before 11-06")

    def test_result_names_the_testing_commit(self):
        line = next(l for l in self.source.splitlines() if "on=$(jq -r .msg" in l)
        msg = f"Vommet pull request 1 integration snapshot of {'a' * 40} on testing {'c' * 40} (merge base {'b' * 40})"
        for m, want in ((msg, f"[on testing {'c' * 12}]"), ("Vommet pull request 1 integration snapshot of x", "[]")):
            out = subprocess.run(["bash", "-c", f"set -euo pipefail\n{line}\necho \"[$on]\""],
                                 env={**os.environ, "r": json.dumps({"msg": m})},
                                 text=True, capture_output=True, check=True).stdout.strip()
            self.assertEqual(out, want)


class Capacity(unittest.TestCase):
    """The integration cap (11-06): 4 PR integration runs while GitHub has no cut, pre-gate or
    intake integration run, the old 2 while it has one, and never more jobs than MAX_ACTIVE."""
    source = WORKFLOW.read_text()

    def env(self):
        start = self.source.index("\nenv:\n")
        out = {}
        for line in self.source[start:self.source.index("\njobs:\n", start)].splitlines():
            k, _, v = line.strip().partition(": ")
            if k.isupper() and v.isdigit():
                out[k] = v
        return out

    def decide(self, runs, copies_it=0, release=()):
        """(it_cap, whether one more PR integration copy may start) for these GitHub runs."""
        accounting = cut(self.source, "# capacity accounting (begin", "# capacity accounting (end)")
        cap = cut(self.source, "# integration cap (begin", "# integration cap (end)")
        script = (f"set -euo pipefail\ncopies_it={copies_it} what=x\n{accounting}\n"
                  f"go=no; for _ in 1; do\n{cap}\ngo=yes; done\necho \"$it_cap $go\"")
        out = subprocess.run(["bash", "-c", script], env={**os.environ, **self.env(), "runs": json.dumps(runs),
                                                          "release_runs": json.dumps(list(release))},
                             text=True, capture_output=True, check=True).stdout.split()
        return int(out[-2]), out[-1] == "yes"

    @staticmethod
    def gh(branch, name="vommet-integration", status="in_progress"):
        return {"name": name, "b": branch, "status": status}

    def test_idle_github_takes_four_pr_integration_runs(self):
        prit = [self.gh(f"ci-prit-{n}") for n in range(3)]
        self.assertEqual(self.decide(prit), (4, True))
        self.assertEqual(self.decide(prit, copies_it=1), (4, False), "copies made this tick count")
        self.assertEqual(self.decide(prit + [self.gh("ci-prit-9")]), (4, False))
        done = [self.gh(f"ci-prit-{n}", status="completed") for n in range(5)]
        self.assertEqual(self.decide(done + [self.gh("ci-pr-1", "vommet-pr")]), (4, True))

    def test_cut_pregate_or_intake_integration_keeps_the_old_cap(self):
        for other in ("ci/windows-testing", "ci/windows-it-pre-11061548-w1-0", "ci/windows-it-intake-20261106t0950z-b1"):
            self.assertEqual(self.decide([self.gh(other)]), (2, True), other)
            self.assertEqual(self.decide([self.gh(other), self.gh("ci-prit-1")]), (2, False), other)
            self.assertEqual(self.decide([self.gh(other, status="queued")]), (2, True), other)

    def test_release_builds_keep_the_old_cap(self):
        prit = [self.gh("ci-prit-1"), self.gh("ci-prit-2")]
        self.assertEqual(self.decide(prit, release=[{"name": "vommet-web-e2e", "b": "ci/windows-testing"}]), (2, False))
        self.assertEqual(self.decide(prit[:1], release=[{"name": "vommet-smoke", "b": "testing"}]), (2, True))
        self.assertEqual(self.decide(prit), (4, True))

    def test_release_list_holds_only_unfinished_other_workflows(self):
        line = cut(self.source, "release_runs=$(jq", "<<<\"$all_runs\"", include_end=True)
        api = {"workflow_runs": [{"name": n, "status": st, "head_branch": "x"} for n, st in (
            ("vommet-linux", "in_progress"), ("vommet-web-e2e", "queued"), ("vommet-native", "completed"),
            ("vommet-pr", "in_progress"), ("vommet-gate", "queued"), ("vommet-integration", "in_progress"))]}
        out = subprocess.run(["bash", "-c", f"set -euo pipefail\n{line}\necho \"$release_runs\""],
                             env={**os.environ, "all_runs": json.dumps(api)}, text=True, capture_output=True, check=True).stdout
        self.assertEqual([r["name"] for r in json.loads(out)], ["vommet-linux", "vommet-web-e2e"])
        out = subprocess.run(["bash", "-c", f"set -euo pipefail\n{line}\necho \"$release_runs\""],
                             env={**os.environ, "all_runs": "null"}, text=True, capture_output=True, check=True).stdout
        self.assertEqual(json.loads(out), [])

    def test_job_budget_is_unchanged(self):
        e = {k: int(v) for k, v in self.env().items()}
        self.assertEqual(e["MAX_ACTIVE"], 12, "the cut shares the account's 20 jobs; raise this only on purpose")
        self.assertLessEqual(e["MAX_ACTIVE_IT_BUSY"], 2)
        self.assertLessEqual(e["MAX_ACTIVE_IT_BUSY"], e["MAX_ACTIVE_IT"])
        self.assertLessEqual(e["MAX_ACTIVE_IT"] * e["JOBS_PRIT"], e["MAX_ACTIVE"])
        line = next(l for l in self.source.splitlines() if '"$((active + copies + w))" -gt "$MAX_ACTIVE"' in l)
        self.assertIn("if", line, "every copy, PR integration included, stays inside MAX_ACTIVE")


class Helper(Fixture):
    def test_main_head_that_deleted_a_runner_on_its_base_fails(self):
        r = self.helper(self.head, self.testing, self.testing)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("removed its integration runner", r.stderr)

    def test_invalid_commit_id_is_rejected(self):
        r = self.helper(self.head, "--help", self.testing)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("invalid integration commit ID", r.stderr)

    def test_merge_does_not_touch_the_checkout(self):
        before = self.git("status", "--porcelain").stdout, self.git("rev-parse", "HEAD").stdout
        self.assertEqual(self.helper(self.head, self.main, self.testing).returncode, 0)
        self.assertEqual(before, (self.git("status", "--porcelain").stdout, self.git("rev-parse", "HEAD").stdout))


if __name__ == "__main__":
    unittest.main()
