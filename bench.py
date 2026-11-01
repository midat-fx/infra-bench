#!/usr/bin/env python3
"""infra-bench runner.

  bench.py validate [ids...]   prove every verifier: broken fails, solution
                               passes, each wrong fix fails for its reason
  bench.py agent MODEL [ids]   let `claude -p` fix scenarios, then verify
  bench.py list

A scenario is a directory under scenarios/:
  task.md      what the engineer (or agent) is told
  workspace/   the broken files
  solution/    reference fix, copied over workspace/
  wrong/<n>/   plausible bad fixes; `_expect` holds text the verifier's
               output must contain, so a wrong fix is rejected for the
               intended reason, not by accident
  setup.sh     optional: prepares live state (drift scenarios)
  check.sh     the verifier: exit 0 = accepted

Overlay dirs may hold `_delete` (paths to remove) and `_post.sh` (run in the
workspace after copying, e.g. a `terraform apply` the fixer would run).
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCEN = ROOT / "scenarios"
WORK = ROOT / ".work"


def sh(cmd, cwd=None, timeout=600, env=None):
    """Run a command; return (rc, combined output)."""
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=timeout)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, f"FAIL: timed out after {timeout}s"


def overlay(src: Path, ws: Path):
    for f in src.rglob("*"):
        rel = f.relative_to(src)
        if f.is_dir() or rel.name.startswith("_"):
            continue
        (ws / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, ws / rel)
    if (src / "_delete").exists():
        for line in (src / "_delete").read_text().split():
            p = ws / line
            shutil.rmtree(p) if p.is_dir() else p.unlink(missing_ok=True)


def prepare(sid: str, ws: Path, log: list):
    scen = SCEN / sid
    if ws.exists():
        shutil.rmtree(ws)
    shutil.copytree(scen / "workspace", ws)
    if (scen / "setup.sh").exists():
        rc, out = sh(["bash", str(scen / "setup.sh"), str(ws)])
        log.append(f"$ setup.sh\n{out}")
        if rc:
            raise RuntimeError(f"setup failed:\n{out}")


def verify(sid: str, ws: Path, log: list):
    t0 = time.monotonic()
    rc, out = sh(["bash", str(SCEN / sid / "check.sh"), str(ws)])
    log.append(f"$ check.sh\n{out}")
    return rc == 0, out, round(time.monotonic() - t0, 1)


def attempts(sid: str):
    scen = SCEN / sid
    yield "broken", None
    yield "solution", scen / "solution"
    for w in sorted((scen / "wrong").iterdir()) if (scen / "wrong").exists() else []:
        yield f"wrong/{w.name}", w


def validate_one(sid: str, run_dir: Path):
    rows = []
    for name, src in attempts(sid):
        ws = WORK / run_dir.name / sid / name.replace("/", "-")
        log = []
        want_pass = name == "solution"
        expect = (src / "_expect").read_text().strip() if src and (src / "_expect").exists() else None
        try:
            prepare(sid, ws, log)
            if src:
                overlay(src, ws)
                if (src / "_post.sh").exists():
                    rc, out = sh(["bash", str(src / "_post.sh")], cwd=ws,
                                 env={**os.environ, "IB_ROOT": str(ROOT)})
                    log.append(f"$ _post.sh\n{out}")
            passed, out, secs = verify(sid, ws, log)
            fail_lines = [l for l in out.splitlines() if l.startswith("FAIL:")]
            hit = [l for l in fail_lines if expect and expect in l]
            reason = (hit or fail_lines or [""])[0]
            good = passed == want_pass and (expect is None or expect in out)
        except RuntimeError as e:
            passed, reason, secs, good = False, str(e).splitlines()[0], 0.0, False
        (run_dir / sid).mkdir(parents=True, exist_ok=True)
        (run_dir / sid / f"{name.replace('/', '-')}.log").write_text("\n".join(log))
        row = dict(scenario=sid, attempt=name, expected="pass" if want_pass else "fail",
                   got="pass" if passed else "fail", reason=reason, expect=expect,
                   ok=good, verify_seconds=secs)
        rows.append(row)
        print(f"{'ok ' if good else 'BAD'} {sid:28} {name:28} {row['got']:4} {secs:5.1f}s {reason}", flush=True)
        shutil.rmtree(ws, ignore_errors=True)
    return rows


def scenario_ids(ids):
    all_ids = sorted(p.name for p in SCEN.iterdir() if (p / "check.sh").exists())
    if not ids:
        return all_ids
    bad = set(ids) - set(all_ids)
    if bad:
        sys.exit(f"unknown scenarios: {', '.join(sorted(bad))}")
    return ids


def stamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def git_rev():
    rc, out = sh(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"])
    dirty = sh(["git", "-C", str(ROOT), "status", "--porcelain", "--", "scenarios", "lib", "bench.py"])[1].strip()
    return (out.strip() if rc == 0 else "none") + ("-dirty" if dirty else "")


def cmd_validate(a):
    ids = scenario_ids(a.ids)
    run_dir = ROOT / "results" / f"validate-{stamp()}"
    run_dir.mkdir(parents=True)
    t0 = time.monotonic()
    with ThreadPoolExecutor(a.jobs) as ex:
        rows = [r for rs in ex.map(lambda s: validate_one(s, run_dir), ids) for r in rs]
    summary = dict(kind="validate", commit=git_rev(), started=run_dir.name.split("-", 1)[1],
                   jobs=a.jobs, wall_seconds=round(time.monotonic() - t0, 1),
                   scenarios=len(ids), attempts=len(rows),
                   correct=sum(r["ok"] for r in rows), rows=rows)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    bad = [r for r in rows if not r["ok"]]
    print(f"\n{summary['correct']}/{len(rows)} verdicts correct across {len(ids)} scenarios "
          f"in {summary['wall_seconds']}s -> {run_dir.relative_to(ROOT)}")
    return 1 if bad else 0


def cmd_list(a):
    for sid in scenario_ids([]):
        wrong = len(list((SCEN / sid / "wrong").iterdir())) if (SCEN / sid / "wrong").exists() else 0
        title = (SCEN / sid / "task.md").read_text().splitlines()[0].lstrip("# ")
        print(f"{sid:28} {wrong} wrong fixes  {title}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validate")
    v.add_argument("ids", nargs="*")
    v.add_argument("-j", "--jobs", type=int, default=int(os.environ.get("JOBS", 3)))
    v.set_defaults(fn=cmd_validate)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    a = ap.parse_args()
    sys.exit(a.fn(a))


if __name__ == "__main__":
    main()
