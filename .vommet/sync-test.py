#!/usr/bin/env python3
"""Tests for .vommet/sync.sh: candidate pins, the shadow append and check-append (2026-11-07).

Builds throwaway repositories (an upstream, a bare origin, a work clone) and runs the real
sync.sh against them, as the upstream-sync and upstream-promote workflows do (SYNC_UNCHECKED=1
skips only the Forgejo status lookup). Needs git, bash and jq. A few seconds per test.

    python3 .vommet/sync-test.py -v
    SYNC_SH=<another sync.sh> python3 .vommet/sync-test.py -v   # e.g. main's old copy (fails-on-base check)
(Temporary repos go under $TMPDIR; point it at a disk-backed dir on hosts with a small /tmp.)
"""
import json, os, subprocess, tempfile, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SYNC = os.environ.get('SYNC_SH') or os.path.join(HERE, 'sync.sh')
ENV = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.invalid',
           GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@example.invalid',
           GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1', SYNC_UNCHECKED='1',
           SYNC_RETRY_SLEEP='0', FORGEJO_API='', FORGEJO_TOKEN='')
ENV.pop('GITHUB_OUTPUT', None)


class Repo:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sync-test-')
        d = self.tmp.name
        self.up, self.origin, self.w = d + '/up', d + '/origin.git', d + '/w'
        self.env = dict(ENV, UPSTREAM_URL=self.up, REPORT=d + '/report.md')
        self.sh('git', 'init', '-q', '-b', 'main', self.up)
        self.sh('git', 'init', '-q', '--bare', '-b', 'main', self.origin)
        self.write('app.txt', 'one\ntwo\nthree\n', cwd=self.up)
        self.commit('upstream: start', cwd=self.up)
        self.sh('git', 'clone', '-q', self.up, self.w)
        self.git('remote', 'rename', 'origin', 'upstream')
        self.git('remote', 'add', 'origin', self.origin)
        self.write('.gitattributes', 'VOMMET_CHANGES.md merge=union\n')
        self.write('VOMMET_CHANGES.md', '# Vommet changes\n')
        self.topics([('a', ''), ('b', 'after a'), ('c', '')])
        self.commit('fork: topics')
        self.git('push', '-q', 'origin', 'main')
        for name, base, f in (('a', 'main', 'a.txt'), ('b', 'a', 'b.txt'), ('c', 'main', 'c.txt')):
            self.git('checkout', '-q', '-B', name, 'origin/' + base if base != 'main' else 'main')
            self.write(f, name + '\n')
            self.commit('topic ' + name)
            self.git('push', '-q', 'origin', name)
            self.git('fetch', '-q', 'origin')
        self.git('checkout', '-q', 'main')
        self.git('push', '-q', 'origin', 'main:testing')   # a first published testing
        self.cycle()                                         # first canonical release

    # helpers
    def sh(self, *a, cwd=None, check=True):
        r = subprocess.run(a, cwd=cwd, env=self.env if hasattr(self, 'env') else ENV, capture_output=True, text=True)
        if check and r.returncode:
            raise AssertionError(f"{' '.join(a)} -> {r.returncode}\n{r.stdout}\n{r.stderr}")
        return r

    def git(self, *a, check=True):
        return self.sh('git', *a, cwd=self.w, check=check).stdout.strip()

    def write(self, path, text, cwd=None):
        with open(os.path.join(cwd or self.w, path), 'w') as f:
            f.write(text)

    def commit(self, msg, cwd=None):
        self.sh('git', 'add', '-A', cwd=cwd or self.w)
        self.sh('git', 'commit', '-q', '-m', msg, cwd=cwd or self.w)

    def topics(self, lines):
        self.write('.vommet/topics' if os.path.isdir(self.w + '/.vommet') else '.vommet-topics-tmp', '')
        os.makedirs(self.w + '/.vommet', exist_ok=True)
        if os.path.exists(self.w + '/.vommet-topics-tmp'):
            os.remove(self.w + '/.vommet-topics-tmp')
        self.write('.vommet/topics', ''.join(f'{n} {k}'.rstrip() + '\n' for n, k in lines))

    def edit_main(self, lines=None, extra=None):
        self.git('fetch', '-q', 'origin')
        self.git('checkout', '-q', '-B', 'main', 'origin/main')
        if lines is not None:
            self.topics(lines)
        if extra:
            self.write(*extra)
        self.commit('fork: main update')
        self.git('push', '-q', 'origin', 'main')

    def run(self, *a):
        if a[0] == 'promote':
            time.sleep(1.1)   # rollback tags are stamped to the second; two promotes must not share one
        return self.sh('bash', SYNC, *a, cwd=self.w, check=False)

    def cycle(self):
        r = self.run('candidate', '--force')
        assert r.returncode == 0, r.stderr
        r = self.run('promote')
        assert r.returncode == 0, r.stderr
        self.git('fetch', '-q', '--prune', 'origin')

    def state(self):
        self.git('fetch', '-q', 'origin')
        return dict(l.split('=', 1) for l in self.git('show', 'origin/sync/state:state').splitlines())

    def add_commit_on(self, ref, path, text, push_to):
        self.git('fetch', '-q', 'origin')
        self.git('checkout', '-q', '-B', 'tmp', ref)
        self.write(path, text)
        self.commit('change ' + path)
        self.git('push', '-q', '-f', 'origin', 'tmp:' + push_to)
        self.git('checkout', '-q', 'main')
        return self.git('rev-parse', 'tmp')


class Pins(unittest.TestCase):
    def setUp(self):
        self.r = Repo()

    def test_candidate_records_a_pin_per_topic(self):
        st = self.r.state() if self.r.run('candidate', '--force').returncode == 0 else {}
        for t in 'abc':
            self.assertEqual(st.get('cand:' + t), self.r.git('rev-parse', 'origin/sync/topic/' + t))

    def test_promote_refuses_a_moved_candidate_topic(self):
        self.assertEqual(self.r.run('candidate', '--force').returncode, 0)
        self.r.add_commit_on('origin/sync/topic/c', 'c.txt', 'sneaked in\n', 'sync/topic/c')
        r = self.r.run('promote')
        self.assertNotEqual(r.returncode, 0, 'promote accepted a sync/topic moved after the candidate')
        self.assertIn('sync/topic/c moved since the candidate was cut', r.stderr)
        self.r.git('fetch', '-q', 'origin')
        self.assertNotEqual(self.r.git('rev-parse', 'origin/c'), self.r.git('rev-parse', 'origin/sync/topic/c'))

    def test_promote_refuses_a_moved_published_ref(self):
        self.assertEqual(self.r.run('candidate', '--force').returncode, 0)
        self.r.add_commit_on('origin/testing', 'x.txt', 'x\n', 'testing')
        r = self.r.run('promote')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('testing was pushed to since the candidate was cut', r.stderr)

    def restate(self, drop):
        """Rewrite sync/state without the lines `drop` matches (an older sync.sh, or a hand edit)."""
        st = self.r.git('show', 'origin/sync/state:state')
        keep = ''.join(l + '\n' for l in st.splitlines() if not drop(l))
        p = subprocess.run(['git', 'hash-object', '-w', '--stdin'], cwd=self.r.w, env=self.r.env, input=keep, capture_output=True, text=True)
        tree = subprocess.run(['git', 'mktree'], cwd=self.r.w, env=self.r.env, input=f'100644 blob {p.stdout.strip()}\tstate\n',
                              capture_output=True, text=True).stdout.strip()
        c = self.r.git('commit-tree', tree, '-m', 'state')
        self.r.git('push', '-q', '-f', 'origin', c + ':refs/heads/sync/state')

    def test_state_without_pins_still_promotes(self):
        self.assertEqual(self.r.run('candidate', '--force').returncode, 0)
        self.restate(lambda l: l.startswith('cand:'))
        r = self.r.run('promote')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('no candidate pins', r.stderr + r.stdout)

    def test_state_missing_one_pin_refuses(self):
        self.assertEqual(self.r.run('candidate', '--force').returncode, 0)
        self.restate(lambda l: l.startswith('cand:b='))
        r = self.r.run('promote')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('sync/state has no pin for b', r.stderr)

    def test_promotion_record_without_a_git_identity(self):
        self.assertEqual(self.r.run('candidate', '--force').returncode, 0)
        time.sleep(1.1)
        env = {k: v for k, v in self.r.env.items() if not k.startswith('GIT_AUTHOR') and not k.startswith('GIT_COMMITTER') and k != 'EMAIL'}
        r = subprocess.run(['bash', SYNC, 'promote'], cwd=self.r.w, env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        refs = self.r.git('ls-remote', 'origin', 'refs/tags/pre-sync/*/_promotion').splitlines()
        self.assertEqual(len(refs), 2, r.stderr)

    def test_promotion_record(self):
        self.r.write('up.txt', 'new\n', cwd=self.r.up)   # upstream moves: every topic is replayed
        self.r.commit('upstream: more', cwd=self.r.up)
        old_testing = self.r.git('rev-parse', 'origin/testing')
        self.assertEqual(self.r.run('candidate', '--force').returncode, 0)
        st = self.r.state()
        self.assertEqual(self.r.run('promote').returncode, 0)
        refs = self.r.git('ls-remote', 'origin', 'refs/tags/pre-sync/*/_promotion').splitlines()
        self.assertEqual(len(refs), 2, refs)   # the setUp release and this one
        tag = sorted(l.split()[1] for l in refs)[-1]
        self.r.git('fetch', '-q', 'origin', f'+{tag}:{tag}')
        rec = json.loads(self.r.git('show', tag + ':promotion.json'))
        self.assertEqual(rec['old_testing'], old_testing)
        self.assertEqual(rec['new_testing'], st['sync_testing'])
        self.assertEqual(rec['mode'], 'canonical')
        self.assertEqual(rec['rewritten'], ['a', 'b', 'c'])
        self.assertTrue(rec['main_rebased'])
        self.assertEqual(rec['shadow_append'], 'ineligible: upstream moved (main rebased)')


class Shadow(unittest.TestCase):
    def setUp(self):
        self.r = Repo()

    def cand(self):
        r = self.r.run('candidate', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)   # the shadow never fails a candidate
        # ... and leaves the work tree as the canonical build left it
        self.assertEqual(self.r.git('symbolic-ref', '--short', 'HEAD'), 'sync/testing')
        self.assertEqual(self.r.git('status', '--porcelain', '--untracked-files=no'), '')
        for f in ('MERGE_HEAD', 'CHERRY_PICK_HEAD'):
            self.assertFalse(os.path.exists(os.path.join(self.r.w, '.git', f)), f)
        st = self.r.state()
        self.assertEqual(st['sync_testing'], self.r.git('rev-parse', 'origin/sync/testing'))
        return st['shadow_append']

    def add_overlay(self, name, path, text):
        self.r.add_commit_on('origin/testing', path, text, name)

    def test_new_overlay_appends_with_nothing_rewritten(self):
        self.add_overlay('o1', 'o1.txt', 'o1\n')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o1', 'overlay')])
        self.assertEqual(self.cand(), 'equal 0')

    def test_grown_topic_and_main_code_change(self):
        self.r.add_commit_on('origin/a', 'a.txt', 'a two\n', 'a')
        self.r.edit_main(extra=('main-only.txt', 'm\n'))
        self.assertEqual(self.cand(), 'equal 0')

    def test_two_new_overlays_on_the_published_testing_keep_their_heads(self):
        self.add_overlay('o1', 'o1.txt', 'o1\n')
        self.add_overlay('o2', 'o2.txt', 'o2\n')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o1', 'overlay'), ('o2', 'overlay')])
        self.assertEqual(self.cand(), 'equal 0')
        for o in ('o1', 'o2'):
            self.assertEqual(self.r.sh('git', 'merge-base', '--is-ancestor', 'origin/' + o, 'sync/shadow',
                                       cwd=self.r.w, check=False).returncode, 0)

    def test_overlay_on_a_rewritten_testing_is_replayed(self):
        self.add_overlay('o1', 'o1.txt', 'o1\n')            # built on the current testing ...
        self.r.write('up.txt', 'new\n', cwd=self.r.up)       # ... which an upstream sync then rewrites
        self.r.commit('upstream: more', cwd=self.r.up)
        self.r.cycle()
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o1', 'overlay')])
        self.assertEqual(self.cand(), 'equal 1')

    def test_empty_topic_is_not_missing(self):
        # a topic with no commits of its own ("Already up to date") leaves no merge commit in testing
        self.r.git('push', '-q', 'origin', 'origin/main:refs/heads/e')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('e', '')])
        self.r.cycle()
        self.add_overlay('o1', 'o1.txt', 'o1\n')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('e', ''), ('o1', 'overlay')])
        self.assertIn(self.cand(), ('equal 0', 'equal 1'))

    def test_upstream_moved(self):
        self.r.write('up.txt', 'new\n', cwd=self.r.up)
        self.r.commit('upstream: more', cwd=self.r.up)
        self.assertEqual(self.cand(), 'ineligible: upstream moved (main rebased)')

    def test_edited_topic(self):
        self.r.git('fetch', '-q', 'origin')
        self.r.git('checkout', '-q', '-B', 'tmp', 'origin/c')
        self.r.write('c.txt', 'c rewritten\n')
        self.r.sh('git', 'commit', '-q', '-a', '--amend', '-m', 'topic c v2', cwd=self.r.w)
        self.r.git('push', '-q', '-f', 'origin', 'tmp:c')
        self.r.git('checkout', '-q', 'main')
        self.assertEqual(self.cand(), 'ineligible: c edited (not a fast-forward of its published head)')

    def test_removed_topic(self):
        self.r.edit_main([('a', ''), ('b', 'after a')])
        self.assertEqual(self.cand(), 'ineligible: c removed (merged into main or dropped)')

    def test_reordered_topics(self):
        self.r.edit_main([('c', ''), ('a', ''), ('b', 'after a')])
        self.assertEqual(self.cand(), 'ineligible: regular topics reordered')

    def test_overlay_inserted_before_an_older_one(self):
        self.add_overlay('o1', 'o1.txt', 'o1\n')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o1', 'overlay')])
        self.r.cycle()
        self.add_overlay('o2', 'o2.txt', 'o2\n')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o2', 'overlay'), ('o1', 'overlay')])
        self.assertEqual(self.cand(), 'ineligible: overlays reordered or one inserted before an older one')

    def test_union_order_difference_is_permuted(self):
        # canonical: new regular d merges before the overlay; the append merges it after.
        self.add_overlay('o1', 'VOMMET_CHANGES.md', '# Vommet changes\n\n## o1\n')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o1', 'overlay')])
        self.r.cycle()
        self.r.git('fetch', '-q', 'origin')
        self.r.add_commit_on('origin/main', 'VOMMET_CHANGES.md', '# Vommet changes\n\n## d\n', 'd')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('d', ''), ('o1', 'overlay')])
        self.assertEqual(self.cand(), 'permuted 0')


class CheckAppend(unittest.TestCase):
    """The checks a live append would have to pass at promote time."""
    def setUp(self):
        self.r = Repo()
        self.r.add_commit_on('origin/a', 'a.txt', 'a two\n', 'a')
        self.r.add_commit_on('origin/testing', 'o1.txt', 'o1\n', 'o1')
        self.r.edit_main([('a', ''), ('b', 'after a'), ('c', ''), ('o1', 'overlay')])
        r = self.r.run('candidate', '--force')
        assert r.returncode == 0, r.stderr
        self.st = self.r.state()
        self.tree = self.r.git('rev-parse', self.st['sync_testing'] + '^{tree}')

    def check(self, c):
        return self.r.run('check-append', c)

    def test_the_shadow_build_passes(self):
        r = self.check('sync/shadow')
        self.assertEqual((r.returncode, r.stdout.strip()), (0, 'ok equal'), r.stderr)

    def test_same_tree_without_old_testing(self):
        c = self.r.git('commit-tree', self.tree, '-p', self.st['main'], '-m', 'forged')
        r = self.check(c)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('old testing', r.stdout)

    def test_same_tree_with_a_topic_head_rewritten(self):
        c = self.r.git('commit-tree', self.tree, '-p', self.st['testing'], '-p', self.st['main'], '-m', 'forged')
        r = self.check(c)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("a's published head", r.stdout)

    def test_right_parents_wrong_tree(self):
        shadow = self.r.git('rev-parse', 'sync/shadow')
        self.r.git('checkout', '-q', '-B', 'tmp', shadow)
        self.r.write('extra.txt', 'not in canonical\n')
        self.r.commit('extra')
        r = self.check('tmp')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('tree differs from the canonical rebuild in extra.txt', r.stdout)

    def test_changes_file_not_a_permutation(self):
        self.r.git('checkout', '-q', '-B', 'tmp', 'sync/shadow')
        with open(os.path.join(self.r.w, 'VOMMET_CHANGES.md'), 'a') as f:
            f.write('- an extra row\n')
        self.r.commit('extra row')
        r = self.check('tmp')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('VOMMET_CHANGES.md', r.stdout)


if __name__ == '__main__':
    unittest.main()
