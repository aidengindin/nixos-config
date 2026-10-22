import datetime
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/forgejo"))
import cooldown
import images
import tags
import update

NOW = datetime.datetime(2026, 10, 22, tzinfo=datetime.timezone.utc)
DAY = 86400
TS = NOW.timestamp()


def node(owner="someone", repo="thing", ref=None, age=1, rev="n" * 40, **original):
    return {"locked": {"type": "github", "owner": owner, "repo": repo, "rev": rev, "narHash": "sha256-new",
                "lastModified": int(TS - age * DAY)},
            "original": {"type": "github", "owner": owner, "repo": repo, **({"ref": ref} if ref else {}), **original}}


class FakeGitHub:
    def __init__(self, commits=None, releases=None):
        self.commits, self.releases, self.prefetched = commits or {}, releases or {}, []

    def commit_before(self, owner, repo, ref, until):
        found = [(rev, ts) for rev, ts in self.commits.get((owner, repo), []) if ts <= until.timestamp()]
        return max(found, key=lambda c: c[1]) if found else None

    def prefetch(self, owner, repo, rev):
        self.prefetched.append(rev)
        return {"rev": rev, "narHash": "sha256-prefetched", "lastModified": dict(self.commits[(owner, repo)])[rev]}

    def get(self, path):
        return self.releases[path.split("/releases")[0].split("repos/")[1]]


def lock(**nodes):
    return {"nodes": {"root": {"inputs": {}}, **nodes}, "root": "root", "version": 7}


class ExemptionTests(unittest.TestCase):
    def test_exempt_inputs(self):
        for original in (
            {"type": "github", "owner": "nixos", "repo": "nixpkgs", "ref": "nixos-26.05"},
            {"type": "github", "owner": "NixOS", "repo": "nixpkgs", "ref": "nixpkgs-unstable"},
            {"type": "github", "owner": "nix-community", "repo": "home-manager", "ref": "release-26.05"},
            {"type": "github", "owner": "nix-community", "repo": "home-manager"},
            {"type": "github", "owner": "aidengindin", "repo": "anything"},
            {"type": "git", "url": "https://git.gindin.xyz/aidengindin/job-scraper.git"},
            {"type": "tarball", "url": "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz"},
        ):
            self.assertTrue(cooldown.exempt(original), original)

    def test_non_exempt_inputs(self):
        for original in (
            {"type": "github", "owner": "nixos", "repo": "nixpkgs", "ref": "master"},
            {"type": "github", "owner": "nixos", "repo": "nixos-hardware", "ref": "master"},
            {"type": "github", "owner": "nix-community", "repo": "disko"},
            {"type": "git", "url": "https://example.com/aidengindin/x.git"},
            {"type": "tarball", "url": "https://example.com/nixexprs.tar.xz"},
        ):
            self.assertFalse(cooldown.exempt(original), original)


class CooldownTests(unittest.TestCase):
    def run_cooldown(self, nodes, baseline=None, github=None):
        return cooldown.apply_cooldown(lock(**nodes), baseline, NOW, github or FakeGitHub())

    def test_old_nodes_are_untouched(self):
        new, _, held, _ = self.run_cooldown({"a": node(age=30)})
        self.assertEqual(new["nodes"]["a"], node(age=30))
        self.assertEqual(held, [])

    def test_young_node_is_repinned_and_original_is_untouched(self):
        github = FakeGitHub({("someone", "thing"): [("e" * 40, int(TS - 10 * DAY)), ("f" * 40, int(TS - 2 * DAY))]})
        original = node(ref="main", age=2)
        new, _, held, _ = self.run_cooldown({"a": original}, github=github)
        self.assertEqual(new["nodes"]["a"]["locked"]["rev"], "e" * 40)
        self.assertEqual(new["nodes"]["a"]["locked"]["narHash"], "sha256-prefetched")
        self.assertEqual(new["nodes"]["a"]["locked"]["lastModified"], int(TS - 10 * DAY))
        self.assertEqual(new["nodes"]["a"]["locked"]["owner"], "someone")
        self.assertEqual(new["nodes"]["a"]["original"], original["original"])
        self.assertEqual(held[0]["name"], "a")
        self.assertEqual(held[0]["upstream_head_age_days"], 2.0)
        self.assertEqual(held[0]["pinned_age_days"], 10.0)

    def test_baseline_that_equals_newest_eligible_is_kept_verbatim(self):
        base = node(age=12, rev="b" * 40)
        base["locked"]["narHash"] = "sha256-baseline"
        github = FakeGitHub({("someone", "thing"): [("b" * 40, int(TS - 12 * DAY))]})
        new, _, _, _ = self.run_cooldown({"a": node(age=1)}, baseline=lock(a=base), github=github)
        self.assertEqual(new["nodes"]["a"]["locked"], base["locked"])
        self.assertEqual(github.prefetched, [])

    def test_baseline_is_never_downgraded(self):
        base = node(age=3, rev="b" * 40)
        github = FakeGitHub({("someone", "thing"): [("c" * 40, int(TS - 9 * DAY))]})
        new, _, _, _ = self.run_cooldown({"a": node(age=1)}, baseline=lock(a=base), github=github)
        self.assertEqual(new["nodes"]["a"]["locked"]["rev"], "b" * 40)
        self.assertEqual(github.prefetched, [])

    def test_baseline_for_a_different_original_is_ignored(self):
        base = node(ref="old", age=12, rev="b" * 40)
        github = FakeGitHub({("someone", "thing"): [("c" * 40, int(TS - 9 * DAY))]})
        new, _, _, _ = self.run_cooldown({"a": node(ref="main", age=1)}, baseline=lock(a=base), github=github)
        self.assertEqual(new["nodes"]["a"]["locked"]["rev"], "c" * 40)

    def test_no_eligible_commit_leaves_node_and_reports_it(self):
        github = FakeGitHub({("someone", "thing"): [("f" * 40, int(TS - 2 * DAY))]})
        new, _, held, _ = self.run_cooldown({"a": node(age=2)}, github=github)
        self.assertEqual(new["nodes"]["a"]["locked"]["rev"], "n" * 40)
        self.assertEqual(len(held), 1)

    def test_exempt_and_immutable_nodes_are_skipped(self):
        nodes = {"own": node(owner="aidengindin", age=1), "hm": node(owner="nix-community", repo="home-manager", age=1),
            "tag": node(ref="v1.2.3", age=1), "rev": node(age=1, rev="a" * 40)}
        nodes["rev"]["original"]["rev"] = "a" * 40
        new, _, held, unhandled = self.run_cooldown(nodes)
        self.assertEqual(new, lock(**nodes))
        self.assertEqual((held, unhandled), ([], []))

    def test_young_non_github_node_is_reported(self):
        nodes = {"x": {"locked": {"type": "git", "url": "https://example.com/x.git", "rev": "a" * 40,
            "lastModified": int(TS - DAY)}, "original": {"type": "git", "url": "https://example.com/x.git"}}}
        new, _, _, unhandled = self.run_cooldown(nodes)
        self.assertEqual(new, lock(**nodes))
        self.assertEqual(len(unhandled), 1)
        self.assertIn("`x`", unhandled[0])

    def test_input_lock_is_not_mutated(self):
        github = FakeGitHub({("someone", "thing"): [("e" * 40, int(TS - 10 * DAY))]})
        source = lock(a=node(age=1))
        cooldown.apply_cooldown(source, None, NOW, github)
        self.assertEqual(source, lock(a=node(age=1)))


class TagOrderingTests(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(images.parse_tag("0.8.7-pg18"), ("", (0, 8, 7), "-pg18"))
        self.assertEqual(images.parse_tag("v1.2.3"), ("v", (1, 2, 3), ""))
        self.assertIsNone(images.parse_tag("pg18"))
        self.assertIsNone(images.parse_tag("latest"))

    def test_semver_ordering_is_numeric_not_lexical(self):
        self.assertEqual(images.candidates("3.4.0", ["3.5.0", "3.10.0", "3.9.0", "3.4.0"]), ["3.10.0", "3.9.0", "3.5.0", "3.4.0"])

    def test_same_major_only(self):
        self.assertEqual(images.candidates("3.4.0", ["2.9.0", "3.5.0", "4.0.0"]), ["3.5.0"])

    def test_zero_major_tracks_minor(self):
        self.assertEqual(images.candidates("0.17.1", ["0.17.2", "0.18.0", "0.16.4", "0.17.0"]), ["0.17.2"])

    def test_never_older_than_current(self):
        self.assertEqual(images.candidates("1.5.0", ["1.4.0", "1.5.0"]), ["1.5.0"])

    def test_suffix_must_match(self):
        tags_ = ["0.8.8-pg18", "0.8.8-pg17", "0.8.8-pg18-trixie", "0.8.9"]
        self.assertEqual(images.candidates("0.8.7-pg18", tags_), ["0.8.8-pg18"])

    def test_prereleases_are_ignored(self):
        tags_ = ["1.1.0-rc1", "1.1.0-beta2", "1.1.0-dev", "1.1.0-nightly", "1.1.0-alpha1", "1.0.1"]
        self.assertEqual(images.candidates("1.0.0", tags_), ["1.0.1"])

    def test_component_count_must_match(self):
        self.assertEqual(images.candidates("0.9.936", ["0.9", "0.9.958", "0.9.965"]), ["0.9.965", "0.9.958"])


class FakeRegistry:
    def __init__(self, tags_, created):
        self._tags, self._created = tags_, created

    def tags(self, repository):
        return self._tags

    def created(self, repository, tag):
        return NOW - datetime.timedelta(days=self._created[tag])

    def digest(self, repository, tag):
        return "sha256:" + tag.replace(".", "").ljust(64, "0")


class ImageUpdateTests(unittest.TestCase):
    DIGEST = "sha256:" + "a" * 64

    def test_newest_old_enough_tag_wins(self):
        registry = FakeRegistry(["1.0.0", "1.1.0", "1.2.0", "1.3.0"], {"1.1.0": 30, "1.2.0": 8, "1.3.0": 2})
        self.assertEqual(images.decide("r/x", "1.0.0", registry, NOW)[0], "1.2.0")

    def test_exactly_seven_days_is_eligible_and_just_under_is_not(self):
        registry = FakeRegistry(["1.0.0", "1.1.0"], {"1.1.0": 7})
        self.assertEqual(images.decide("r/x", "1.0.0", registry, NOW)[0], "1.1.0")
        registry._created["1.1.0"] = 6.99
        new, note = images.decide("r/x", "1.0.0", registry, NOW)
        self.assertEqual(new, "1.0.0")
        self.assertIn("1.1.0", note)

    def test_only_young_candidates_keeps_current(self):
        registry = FakeRegistry(["1.0.0", "1.0.1"], {"1.0.1": 1})
        self.assertEqual(images.decide("r/x", "1.0.0", registry, NOW)[0], "1.0.0")

    def test_text_rewrite_updates_tag_and_digest(self):
        registry = FakeRegistry(["1.0.0", "1.1.0"], {"1.1.0": 20})
        text = f'default = "ghcr.io/o/x:1.0.0@{self.DIGEST}";\nother = "ghcr.io/o/y:latest";'
        new, notes = images.update_text(text, registry, NOW, lambda line: None)
        self.assertEqual(new, f'default = "ghcr.io/o/x:1.1.0@{registry.digest("", "1.1.0")}";\nother = "ghcr.io/o/y:latest";')
        self.assertEqual(notes, [])

    def test_unchanged_tag_keeps_digest(self):
        registry = FakeRegistry(["1.0.0"], {})
        text = f'"ghcr.io/o/x:1.0.0@{self.DIGEST}"'
        self.assertEqual(images.update_text(text, registry, NOW, lambda line: None)[0], text)

    def test_registry_failure_leaves_text_alone(self):
        class Broken(FakeRegistry):
            def tags(self, repository):
                raise OSError("offline")
        text = f'"ghcr.io/o/x:1.0.0@{self.DIGEST}"'
        new, notes = images.update_text(text, Broken([], {}), NOW, lambda line: None)
        self.assertEqual(new, text)
        self.assertIn("lookup failed", notes[0])

    def test_unpinned_detection(self):
        self.assertEqual(images.unpinned('image = "ghcr.io/o/x:latest";'), ["ghcr.io/o/x:latest"])
        self.assertEqual(images.unpinned(f'image = "ghcr.io/o/x:1.0.0@{self.DIGEST}";'), [])
        self.assertEqual(images.unpinned("image = cfg.dbImage;"), [])

    def test_repository_images_are_pinned(self):
        for path in sorted(Path(images.ROOT, "services").glob("*.nix")):
            self.assertEqual(images.unpinned(path.read_text()), [], path.name)


class TagBumpTests(unittest.TestCase):
    @staticmethod
    def release(tag, age, **extra):
        return {"tag_name": tag, "published_at": (NOW - datetime.timedelta(days=age)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "draft": False, "prerelease": False, **extra}

    def test_newest_release_old_enough(self):
        releases = [self.release("v3", 1), self.release("v2", 9), self.release("v1", 30)]
        self.assertEqual(tags.choose(releases, "v1", NOW)[0], "v2")

    def test_cooldown_is_respected(self):
        new, held, _ = tags.choose([self.release("v2.1", 3), self.release("v2.0", 6.9), self.release("v1.0", 30)], "v1.0", NOW)
        self.assertEqual(new, "v1.0")
        self.assertIn("v2.1", held)

    def test_prereleases_and_drafts_are_ignored(self):
        releases = [self.release("v3", 20, prerelease=True), self.release("v4", 20, draft=True), self.release("v2", 30), self.release("v1", 40)]
        self.assertEqual(tags.choose(releases, "v1", NOW)[0], "v2")

    def test_older_line_backport_published_later_is_ignored(self):
        releases = [self.release("v1.4.1", 10), self.release("v2.0.0", 20), self.release("v1.4.0", 40)]
        self.assertEqual(tags.choose(releases, "v2.0.0", NOW)[0], "v2.0.0")

    def test_never_downgrades(self):
        self.assertEqual(tags.choose([self.release("v1.0.0", 30)], "v2.0.0", NOW)[0], "v2.0.0")
        self.assertEqual(tags.choose([self.release("v2026.1.1", 30)], "v2026.8.3", NOW)[0], "v2026.8.3")

    def test_scheme_change_is_reported_not_applied(self):
        releases = [self.release("v0.22.2", 8), self.release("v0.22.4", 1), self.release("v2026.9.24", 28), self.release("v2026.8.3", 60)]
        new, _, note = tags.choose(releases, "v2026.8.3", NOW)
        self.assertEqual(new, "v2026.9.24")
        self.assertEqual(note, "upstream changed version scheme (latest v0.22.x); migrate manually")
        new, _, note = tags.choose(releases[:1] + releases[3:], "v2026.8.3", NOW)
        self.assertEqual(new, "v2026.8.3")
        self.assertIn("v0.22.x", note)

    def test_scheme_change_note_reaches_the_report_and_pin_is_unchanged(self):
        text = 'h.url = "github:o/r/v2026.8.3";'
        github = FakeGitHub(releases={"o/r": [self.release("v0.22.2", 8), self.release("v2026.8.3", 60)]})
        new, changed, notes = tags.update_text(text, github, NOW, lambda line: None)
        self.assertEqual((new, changed), (text, []))
        self.assertEqual(notes, ["h: upstream changed version scheme (latest v0.22.x); migrate manually"])

    def test_flake_url_is_rewritten(self):
        text = 'a.url = "github:o/r/v1";\n    b.url = "github:o/b";\n    c.url = "github:o/c/v1";'
        github = FakeGitHub(releases={"o/r": [self.release("v2", 20), self.release("v1", 40)],
            "o/c": [self.release("v1", 40)]})
        new, changed, _ = tags.update_text(text, github, NOW, lambda line: None)
        self.assertEqual(new, 'a.url = "github:o/r/v2";\n    b.url = "github:o/b";\n    c.url = "github:o/c/v1";')
        self.assertEqual(changed, [("a", "v2")])

    def test_exempt_owner_is_not_bumped(self):
        text = 'a.url = "github:aidengindin/r/v1";'
        self.assertEqual(tags.update_text(text, FakeGitHub(), NOW, lambda line: None)[0], text)


class ReportTests(unittest.TestCase):
    def test_pr_section_lists_held_back_inputs(self):
        reports = {"cooldown": {"held": [{"name": "foo", "repo": "o/foo", "upstream_head_age_days": 2.0,
            "pinned_age_days": 9.5, "pinned_rev": "a" * 40}], "unhandled": ["`bar` (git)"]},
            "tags": {"held": ["`h`: held back newer v2"]}, "images": {"held": ["`i`: x"], "problems": ["p"]}}
        section = update.cooldown_section(reports)
        for fragment in ("| `foo` | o/foo | 2.0d | 9.5d |", "`bar` (git)", "held back newer v2", "`i`: x", "- p"):
            self.assertIn(fragment, section)

    def test_second_cooldown_pass_is_merged_without_duplicates(self):
        import json
        import tempfile
        held = lambda name: {"name": name, "repo": "o/" + name, "upstream_head_age_days": 1, "pinned_age_days": 8, "pinned_rev": "a" * 40}
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "cooldown.json").write_text(json.dumps({"held": [held("a")]}))
            Path(directory, "cooldown-tags.json").write_text(json.dumps({"held": [held("a"), held("b")]}))
            reports = update.read_reports(directory)
        self.assertEqual([h["name"] for h in reports["cooldown"]["held"]], ["a", "b"])
        self.assertEqual(reports["tags"], {})

    def test_empty_reports_produce_no_section(self):
        self.assertEqual(update.cooldown_section({"cooldown": {}, "tags": {}, "images": {}}), "")

    def test_commands_run_in_the_documented_order(self):
        names = [" ".join(c) for c in update.COMMANDS]
        order = [next(i for i, n in enumerate(names) if k in n) for k in ("flake update", "cooldown.py", "tags.py", "nix-update", "images.py")]
        self.assertEqual(order, sorted(order))
        self.assertTrue(all("--inputs-from" in n for n in names if "nix-update" in n))


if __name__ == "__main__":
    unittest.main()
