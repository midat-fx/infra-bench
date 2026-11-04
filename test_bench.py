"""Self-test for bench.py's pure logic: python3 -m unittest test_bench.

No Docker, no cluster. The scenario-layout checks keep every scenario in the
shape the runner expects, so a missing `_expect` fails here, not 10 minutes
into `make test`.
"""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import bench


class Traces(unittest.TestCase):
    def test_account_events_are_dropped(self):
        stream = "\n".join([
            json.dumps({"type": "system", "subtype": "init"}),
            json.dumps({"type": bench.ACCOUNT_EVENT_PREFIX + "_event", "info": {}}),
            "not json",
            "[1, 2]",
        ])
        out = bench.drop_account_events(stream)
        self.assertNotIn("rate_limit", out)
        for kept in ('"init"', "not json", "[1, 2]"):
            self.assertIn(kept, out)

    def test_scrub_removes_machine_paths_and_user(self):
        home = str(Path.home())
        text = f"{bench.ROOT}/x {home}/y {home.replace('/', '-')}-z by {bench.getpass.getuser()}"
        out = bench.scrub(text)
        self.assertEqual(out, "<repo>/x ~/y -HOME-z by user")


class Overlay(unittest.TestCase):
    def test_copies_files_but_not_control_files(self):
        with tempfile.TemporaryDirectory() as t:
            src, ws = Path(t, "src"), Path(t, "ws")
            (src / "modules/app").mkdir(parents=True)
            (src / "modules/app/main.tf").write_text("new")
            (src / "_expect").write_text("reason")
            (src / "_post.sh").write_text("exit 1")
            ws.mkdir()
            (ws / "keep.tf").write_text("old")
            bench.overlay(src, ws)
            self.assertEqual((ws / "modules/app/main.tf").read_text(), "new")
            self.assertEqual((ws / "keep.tf").read_text(), "old")
            self.assertFalse((ws / "_expect").exists() or (ws / "_post.sh").exists())


class Regrade(unittest.TestCase):
    def test_saved_agent_diff_rebuilds_the_agent_workspace(self):
        # alt/root-sg-rules was taken from this very agent answer.
        sid = "tf-module-cycle"
        saved = bench.ROOT / "results/agent-20261101T071205Z/claude-haiku-5-5" / f"{sid}.diff"
        alt = bench.SCEN / sid / "alt/root-sg-rules"
        with tempfile.TemporaryDirectory() as t:
            ws = Path(t, "ws")
            shutil.copytree(bench.SCEN / sid / "workspace", ws)
            patch = bench.workspace_patch(saved.read_text(), sid)
            # Both header sides must be workspace-relative: `patch` silently
            # falls back to whichever name exists, which would hide a bad side.
            headers = {l.split()[1] for l in patch.splitlines() if l.startswith(("--- ", "+++ "))}
            self.assertEqual(headers, {"main.tf", "modules/app/main.tf", "modules/db/main.tf"})
            p = subprocess.run(["patch", "-p0", "-s"], cwd=ws, input=patch, text=True, capture_output=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            for f in ["modules/app/main.tf", "modules/db/main.tf"]:
                self.assertEqual((ws / f).read_text(), (alt / f).read_text(), f)
            # The alt copy only adds a two-line provenance comment on top.
            alt_main = (alt / "main.tf").read_text().split("\n", 2)[2]
            self.assertEqual((ws / "main.tf").read_text(), alt_main)


class ScenarioLayout(unittest.TestCase):
    def test_every_saved_agent_diff_still_applies(self):
        # regrade rebuilds workspaces from these; a workspace edit must not
        # silently strand them.
        for run in sorted((bench.ROOT / "results").glob("agent-*")):
            for diff in sorted(run.glob("*/*.diff")):
                sid = diff.stem
                if (bench.SCEN / sid / "setup.sh").exists():
                    continue
                with self.subTest(diff=str(diff.relative_to(bench.ROOT))), tempfile.TemporaryDirectory() as t:
                    ws = Path(t) / "ws"
                    bench.prepare(sid, ws, [])
                    p = subprocess.run(["patch", "-p0", "-s", "--dry-run"], cwd=ws, text=True,
                                       input=bench.workspace_patch(diff.read_text(), sid),
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    self.assertEqual(p.returncode, 0, p.stdout)

    def test_every_scenario_is_complete(self):
        ids = bench.scenario_ids([])
        self.assertGreater(len(ids), 0)
        for sid in ids:
            d = bench.SCEN / sid
            with self.subTest(sid):
                for need in ["task.md", "workspace", "solution", "check.sh"]:
                    self.assertTrue((d / need).exists(), need)
                wrong = sorted((d / "wrong").iterdir())
                self.assertGreaterEqual(len(wrong), 2)
                for w in wrong:
                    expect = (w / "_expect").read_text().strip() if (w / "_expect").exists() else ""
                    self.assertTrue(expect, f"{w.name} has no _expect")

    def test_attempt_order_and_expectations(self):
        names = [n for n, _ in bench.attempts("tf-open-ssh")]
        self.assertEqual(names[:3], ["broken", "solution", "alt/inline-blocks"])
        self.assertTrue(all(n.startswith("wrong/") for n in names[3:]))


if __name__ == "__main__":
    unittest.main()
