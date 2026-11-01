#!/usr/bin/env python3
"""infra-bench runner.

  bench.py validate [ids...]   prove every verifier: broken fails, solution
                               passes, each wrong fix fails for its reason
  bench.py agent [-m MODEL ...] [ids...]
                               let `claude -p` fix each scenario, then verify
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

An overlay dir may hold `_post.sh`, run in the workspace after copying: the
command a fixer would run, e.g. `terraform apply` or `terraform state rm`.
"""

import argparse
import getpass
import json
import os
import re
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
# Agents work outside the repo, so the reference fixes are not a `ls ..` away.
# It must still be under $HOME: colima only shares $HOME with containers.
AGENT_WORK = Path.home() / ".cache" / "infra-bench-agent"


def scrub(text: str) -> str:
    """Keep machine-specific paths and the local user name out of committed logs."""
    home = str(Path.home())
    text = text.replace(str(ROOT), "<repo>").replace(home, "~").replace(home.replace("/", "-"), "-HOME")
    return re.sub(rf"\b{re.escape(getpass.getuser())}\b", "user", text)


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
        (run_dir / sid / f"{name.replace('/', '-')}.log").write_text(scrub("\n".join(log)))
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


PROMPT = """You are the on-call infrastructure engineer. Fix the problem below by
editing the files in the current directory.

{task}
Environment:
- `kubectl` is connected to the live kind cluster{k8s_note}.
- `terraform` runs against LocalStack, a local AWS emulator; `aws` queries it.
- Work only inside the current directory. Stop when the fix is done; a
  verifier then checks the result.
"""

WRAPPERS = {
    # The cwd is mirrored into the node, so `kubectl apply -f file.yaml` works.
    "kubectl": 'source "{root}/lib/env.sh"\n'
               'docker exec "$NODE" mkdir -p "$PWD" && docker cp -q "$PWD/." "$NODE:$PWD"\n'
               'exec docker exec -i -w "$PWD" -e KUBECONFIG=/etc/kubernetes/admin.conf "$NODE" kubectl "$@"\n',
    "terraform": 'source "{root}/lib/tf.sh"\ntf "$PWD" "$@"\n',
    "aws": 'source "{root}/lib/env.sh"\nexec docker exec -i "$LOCALSTACK" awslocal "$@"\n',
}

ALLOWED = ("Read Edit Write Glob Grep Bash(kubectl:*) Bash(terraform:*) Bash(aws:*) "
           "Bash(ls:*) Bash(cat:*) Bash(grep:*) Bash(diff:*) Bash(echo:*)")


def agent_one(sid: str, model: str, run_dir: Path, max_turns: int):
    ws = AGENT_WORK / run_dir.name / model / sid
    bindir = AGENT_WORK / run_dir.name / model / f"{sid}.bin"
    log = []
    prepare(sid, ws, log)
    if sid.startswith("k8s-"):  # the broken state is live before the agent looks
        rc, out = sh(["bash", "-c", f'source "{ROOT}/lib/k8s.sh"; k8s_deploy {sid} "$1"', "_", str(ws)])
        log.append(f"$ k8s_deploy (broken)\n{out}")
    bindir.mkdir(parents=True, exist_ok=True)
    for name, body in WRAPPERS.items():
        (bindir / name).write_text("#!/usr/bin/env bash\n" + body.format(root=ROOT))
        (bindir / name).chmod(0o755)
    task = (SCEN / sid / "task.md").read_text()
    prompt = PROMPT.format(task=task, k8s_note=f"; the manifests here are deployed in namespace `{sid}`"
                           if sid.startswith("k8s-") else "")
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json", "--verbose",
           "--max-turns", str(max_turns), "--setting-sources", "project", "--strict-mcp-config",
           "--disable-slash-commands", "--no-session-persistence",
           "--tools", "Bash,Read,Edit,Write,Glob,Grep", "--allowedTools", ALLOWED]
    t0 = time.monotonic()
    rc, out = sh(cmd, cwd=ws, timeout=1200, env={**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}"})
    agent_secs = round(time.monotonic() - t0, 1)
    events = []
    for line in out.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    init = next((e for e in events if e.get("type") == "system" and e.get("subtype") == "init"), {})
    res = next((e for e in reversed(events) if e.get("type") == "result"), {})
    tool_inputs = json.dumps([c.get("input") for e in events if e.get("type") == "assistant"
                              for c in e.get("message", {}).get("content", []) if c.get("type") == "tool_use"])
    peeked = str(SCEN) in tool_inputs or "/scenarios/" in tool_inputs
    passed, vout, vsecs = verify(sid, ws, log)
    fail_lines = [l for l in vout.splitlines() if l.startswith("FAIL:")]
    out_dir = run_dir / model
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{sid}.jsonl").write_text(scrub(out))
    (out_dir / f"{sid}.verify.log").write_text(scrub("\n".join(log)))
    _, patch = sh(["diff", "-ruN", "-x", ".*", "-x", "terraform.tfstate*", str(SCEN / sid / "workspace"), str(ws)])
    (out_dir / f"{sid}.diff").write_text(scrub(patch))
    row = dict(scenario=sid, model=model, resolved_model=init.get("model"), passed=passed,
               reason=fail_lines[0] if fail_lines else "", turns=res.get("num_turns"),
               cost_usd=res.get("total_cost_usd"), agent_seconds=agent_secs, verify_seconds=vsecs,
               agent_error=res.get("subtype") if res.get("is_error") or rc else None, peeked=peeked)
    print(f"{'PASS' if passed else 'fail'} {model:8} {sid:28} turns={row['turns']} "
          f"${row['cost_usd'] or 0:.3f} {agent_secs:6.1f}s {row['reason']}", flush=True)
    shutil.rmtree(bindir, ignore_errors=True)
    shutil.rmtree(ws, ignore_errors=True)
    return row


def cmd_agent(a):
    a.models = a.models or ["claude-haiku-5-5"]
    ids = scenario_ids(a.ids)
    run_dir = ROOT / "results" / f"agent-{stamp()}"
    run_dir.mkdir(parents=True)
    jobs = [(m, s) for m in a.models for s in ids]
    with ThreadPoolExecutor(a.jobs) as ex:
        rows = list(ex.map(lambda ms: agent_one(ms[1], ms[0], run_dir, a.max_turns), jobs))
    summary = dict(kind="agent", commit=git_rev(), started=run_dir.name.split("-", 1)[1],
                   max_turns=a.max_turns, runs=len(rows), rows=rows)
    for m in a.models:
        mr = [r for r in rows if r["model"] == m]
        summary[f"pass_{m}"] = f"{sum(r['passed'] for r in mr)}/{len(mr)}"
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print({k: v for k, v in summary.items() if k.startswith("pass_")}, "->", run_dir.relative_to(ROOT))
    return 0


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
    g = sub.add_parser("agent")
    # Full model IDs: CLI aliases like "haiku" may resolve to an older model.
    g.add_argument("-m", "--model", dest="models", action="append",
                   help="repeatable; default claude-haiku-5-5")
    g.add_argument("ids", nargs="*")
    g.add_argument("-j", "--jobs", type=int, default=2)
    g.add_argument("--max-turns", type=int, default=40)
    g.set_defaults(fn=cmd_agent)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    a = ap.parse_args()
    sys.exit(a.fn(a))


if __name__ == "__main__":
    main()
