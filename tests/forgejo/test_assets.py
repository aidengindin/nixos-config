import datetime
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/forgejo"))
import assets

NOW = datetime.datetime(2026, 10, 22, tzinfo=datetime.timezone.utc)


def release(tag, age, names, **extra):
    return {"tag_name": tag, "published_at": (NOW - datetime.timedelta(days=age)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "draft": False, "prerelease": False, "assets": [{"name": n} for n in names], **extra}


class FakeGitHub:
    def __init__(self, **releases):
        self.releases, self.calls = releases, []

    def get(self, path):
        self.calls.append(path)
        return self.releases[path.split("/releases")[0].split("repos/")[1]]


TEXT = """let
  chromiumWebStore = pkgs.fetchurl {
    url = "https://github.com/NeverDecaf/chromium-web-store/releases/download/v1.5.5.3/Chromium.Web.Store.crx";
    sha256 = "sha256-store";
  };

  uBlockOrigin = pkgs.fetchzip {
    url = "https://github.com/gorhill/uBlock/releases/download/1.75.0/uBlock0_1.75.0.chromium.zip";
    sha256 = "sha256-ublock";
  };
  other = pkgs.fetchurl {
    url = "https://example.com/x";
    sha256 = "sha256-other";
  };
in 1
"""


def ublock(*releases):
    return FakeGitHub(**{"gorhill/uBlock": list(releases), "NeverDecaf/chromium-web-store": [
        release("v1.5.5.3", 90, ["Chromium.Web.Store.crx"])]})


def run(github, text=TEXT):
    calls = []

    def hasher(url, unpack):
        calls.append((url, unpack))
        return "sha256-new"
    return (*assets.update_text(text, github, NOW, lambda line: None, hasher), calls)


class AssetTests(unittest.TestCase):
    def test_asset_name_substitutes_version_or_stays_fixed(self):
        self.assertEqual(assets.asset_name("uBlock0_1.75.0.chromium.zip", "1.75.0", "1.76.0"), "uBlock0_1.76.0.chromium.zip")
        self.assertEqual(assets.asset_name("Chromium.Web.Store.crx", "v1.5.5.3", "v1.6.0.0"), "Chromium.Web.Store.crx")

    def test_both_urls_discovered(self):
        github = ublock(release("1.75.0", 90, ["uBlock0_1.75.0.chromium.zip"]))
        new, changed, notes, problems, calls = run(github)
        self.assertEqual(sorted(github.calls), sorted([
            "repos/gorhill/uBlock/releases?per_page=30", "repos/NeverDecaf/chromium-web-store/releases?per_page=30"]))
        self.assertEqual((new, changed, notes, problems, calls), (TEXT, [], [], [], []))

    def test_bump_rewrites_zip_with_unpacked_hash_and_leaves_other_blocks(self):
        github = ublock(release("1.76.0", 10, ["uBlock0_1.76.0.chromium.zip"]), release("1.75.0", 90, ["uBlock0_1.75.0.chromium.zip"]))
        new, changed, _, problems, calls = run(github)
        self.assertEqual(calls, [("https://github.com/gorhill/uBlock/releases/download/1.76.0/uBlock0_1.76.0.chromium.zip", True)])
        self.assertEqual(problems, [])
        self.assertEqual(new, TEXT.replace("1.75.0/uBlock0_1.75.0", "1.76.0/uBlock0_1.76.0").replace("sha256-ublock", "sha256-new"))
        self.assertEqual(changed[0][1], "1.76.0")

    def test_fetchurl_uses_flat_hash_and_fixed_asset_name(self):
        github = FakeGitHub(**{"gorhill/uBlock": [release("1.75.0", 90, [])], "NeverDecaf/chromium-web-store": [
            release("v1.5.6.0", 9, ["Chromium.Web.Store.crx"]), release("v1.5.5.3", 90, [])]})
        new, _, _, problems, calls = run(github)
        self.assertEqual(calls, [("https://github.com/NeverDecaf/chromium-web-store/releases/download/v1.5.6.0/Chromium.Web.Store.crx", False)])
        self.assertIn("v1.5.6.0/Chromium.Web.Store.crx", new)
        self.assertIn('sha256 = "sha256-new"', new)
        self.assertIn("sha256-ublock", new)
        self.assertEqual(problems, [])

    def test_missing_asset_is_a_problem_and_pin_stays(self):
        github = ublock(release("1.76.0", 10, ["uBlock0_1.76.0.firefox.xpi"]), release("1.75.0", 90, []))
        new, changed, _, problems, calls = run(github)
        self.assertEqual((new, changed, calls), (TEXT, [], []))
        self.assertEqual(len(problems), 1)
        self.assertIn("uBlock0_1.76.0.chromium.zip", problems[0])

    def test_young_release_is_held_back(self):
        github = ublock(release("1.76.0", 3, ["uBlock0_1.76.0.chromium.zip"]), release("1.75.0", 90, ["uBlock0_1.75.0.chromium.zip"]))
        new, changed, notes, problems, calls = run(github)
        self.assertEqual((new, changed, problems, calls), (TEXT, [], [], []))
        self.assertEqual(len(notes), 1)
        self.assertIn("1.76.0 (3d old)", notes[0])

    def test_no_downgrade(self):
        github = ublock(release("1.74.0", 90, ["uBlock0_1.74.0.chromium.zip"]), release("1.75.0", 3, ["uBlock0_1.75.0.chromium.zip"]))
        new, changed, _, _, calls = run(github)
        self.assertEqual((new, changed, calls), (TEXT, [], []))

    def test_release_lookup_failure_leaves_pin(self):
        class Broken:
            def get(self, path):
                raise OSError("offline")
        new, changed, _, problems, _ = run(Broken())
        self.assertEqual((new, changed), (TEXT, []))
        self.assertEqual(len(problems), 2)

    def test_hash_failure_leaves_pin(self):
        github = ublock(release("1.76.0", 10, ["uBlock0_1.76.0.chromium.zip"]), release("1.75.0", 90, []))

        def hasher(url, unpack):
            raise OSError("download failed")
        new, changed, _, problems = assets.update_text(TEXT, github, NOW, lambda line: None, hasher)[:4]
        self.assertEqual((new, changed), (TEXT, []))
        self.assertEqual(len(problems), 1)


if __name__ == "__main__":
    unittest.main()
