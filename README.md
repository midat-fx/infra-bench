# infra-bench

Thirteen broken Kubernetes and Terraform setups, each with a verifier that runs
the fix for real. Kubernetes scenarios run on a local [kind](https://kind.sigs.k8s.io)
cluster; Terraform scenarios apply against [LocalStack](https://github.com/localstack/localstack).
No cloud account, no credentials.

The point is the verifiers. Each scenario ships a reference fix, sometimes an
equivalent fix in another style, and two to five **plausible wrong fixes**:
the shortcuts a tired engineer or a coding agent takes (delete the probe, remove the memory limit, relax the namespace policy,
`ignore_changes` the drift away, `s3:*` instead of `*`). `make test` proves on
every run that each verifier rejects the broken setup, accepts the correct
fixes, and rejects every wrong fix *for the reason it was written to catch*:
13 scenarios, 77 verdicts.

```bash
make test
```

That creates one kind cluster and one LocalStack container, validates all
scenarios, and deletes both. Needs Docker (colima, Docker Desktop or Linux),
`python3`, `jq`, `curl`. kind is downloaded into `.bin/` with its checksum;
kubectl, Terraform and conftest run in containers, so nothing else is
installed.

## Scenarios

| Scenario | Broken | Wrong fixes the verifier must reject |
|---|---|---|
| `k8s-oom-crashloop` | memory limit below the app's start-up cache, `OOMKilled` loop | drop the limit · 2Gi limit (budget is 256Mi) · shrink the cache · raise requests only |
| `k8s-readiness-port` | readiness probe on port 80, app listens on 8080 | delete the probe · `exec: true` probe · rename containerPort to 80 |
| `k8s-networkpolicy` | allow rule selects a label no pod has, and the Service port instead of the pod port | allow the whole namespace · drop default-deny · right label, wrong port |
| `k8s-rbac-least-privilege` | log shipper bound to `cluster-admin` | Role on `resources: ["*"]` · ClusterRoleBinding · built-in `view` · no `pods/log` |
| `k8s-pod-security` | Deployment rejected by PSA `restricted` | relabel namespace to `baseline` · `runAsNonRoot` only · `runAsNonRoot` on a root image |
| `k8s-startup-probe` | liveness probe kills an app that needs 20 s to start, restart loop | delete the liveness probe · `exec: true` liveness · `initialDelaySeconds: 30` instead of a startup probe · startup probe too short · remove the slow start |
| `k8s-service-selector` | Service selector pins `version: v1` after a v2 rollout | `app: shop` or `app: shop, version: v2` (both catch the admin pods) · pin the new version |
| `tf-s3-encryption` | bucket without default encryption or public access block | encrypt a different bucket · 3 of 4 block settings · `acl = private` |
| `tf-iam-least-privilege` | task role with `Action: *`, `Resource: *` | `s3:*` · right actions on `Resource: *` · forget `sqs:SendMessage` · `NotAction` · `Resource: *` through `aws_iam_policy_document` · AWS-managed `AdministratorAccess` attached next to a correct policy |
| `tf-state-drift` | console change to an SQS queue, plan wants to revert it | `terraform apply` the old code · `ignore_changes` · `terraform state rm` |
| `tf-module-cycle` | two modules need each other's security group ID: `Error: Cycle` | VPC CIDR rules instead of SG references · drop the egress rule |
| `tf-open-ssh` | SSH from `0.0.0.0/0` and `::/0` | close IPv4 only · `0-65535` rule that still covers 22 · drop HTTPS too · open SSH re-added as `aws_security_group_rule` |
| `tf-hardcoded-secret` | DB password literal in `main.tf` | move it to `terraform.tfvars` · 12-char `random_password` · a new literal |

Each scenario lives in `scenarios/<id>/`: `task.md` (what the fixer is told),
`workspace/` (broken files), `solution/`, `alt/*/` (other correct fixes, in
four scenarios), `wrong/*/`, `check.sh` (verifier) and, for Terraform,
`policy/*.rego`.

## How the verifiers work

Kubernetes: delete the namespace, apply the workspace, then check behaviour
(Deployment available, no restarts, endpoints, real HTTP between pods,
`kubectl auth can-i` as the ServiceAccount) and the task's constraints
(limit budget, probe type, PSA label, selector shape).

Terraform: `terraform apply` into fresh state on LocalStack, then
[conftest](https://www.conftest.dev) Rego over `terraform show -json`. The
policies read the applied state, where references are resolved, so "encryption
on some other bucket" is detectable. The drift scenario instead inspects the
live queue and runs `terraform plan -detailed-exitcode` on the prepared state.

The Rego policies also have their own unit tests (`policy/*_test.rego`), on
small hand-written state fixtures: one passing fix and the key rejections per
policy, including the null-list regression described below. `make policy-test`
runs them in seconds without a cluster, and `make test` runs them first.

[docs/DESIGN.md](docs/DESIGN.md) explains each choice: why kubectl runs inside
the kind node, why apply rather than plan, why a live encryption check would
pass the broken bucket, and what is deliberately left out.

## Results

### Verifier validation

| Run | Commit | Verdicts correct | Wall time | Raw |
|---|---|---|---|---|
| macOS arm64, colima 4 CPU / 6 GB shared with other jobs, `-j 3` | `0f5e81a` | 65/66 | 1290.4 s | `results/validate-20261101T080538Z/` |
| same machine, after the timeout fix | `04216b9` | **66/66** (15 must-pass, 51 must-fail) | 770.5 s | `results/validate-20261101T082833Z/` |
| GitHub Actions `ubuntu-24.04`, clean checkout | `04216b9` | 65/66 | 834.4 s | `results/ci-41288960042/` |
| GitHub Actions, after the OOM reason fix | `a36667b` | **66/66** | 808.9 s | `results/ci-41290109989/` |
| Mac, after the trace scrub and history rewrite | `e3e223f` | **66/66** | 610.4 s | `results/validate-20261101T090854Z/` |
| Mac, fresh clone, `aws_iam_policy_document` alt and wrong fix added | `672bde7` | **68/68** (16 must-pass, 52 must-fail) | 673.7 s | `results/validate-20261102T202206Z/` |
| Mac, fresh clone, policies attached from outside the configuration rejected | `bf804ec` | **69/69** (16 must-pass, 53 must-fail) | 1230.8 s | `results/validate-20261103T135631Z/` |
| GitHub Actions `ubuntu-24.04`, clean checkout, manual run | `65102c0` | **69/69** | 577.9 s | `results/ci-41817285110/` |
| GitHub Actions, clean checkout, `k8s-startup-probe` added | `db304d5` | **77/77** (18 must-pass, 59 must-fail) | 622.9 s | `results/ci-41819080771/` |
| GitHub Actions, busybox pinned by digest, early-fail on whole reasons only | `731d3d0` | **77/77** | 636.4 s | `results/ci-41820490314/` |
| GitHub Actions, after the drift regrade | `dde436b` | **77/77** | 646.3 s | `results/ci-41894667678/` |

History was rewritten twice: on 2026-11-01 to remove account rate-limit status
lines from the agent traces (code and results unchanged), and on 2026-11-02 to
change the author identity (trees identical). The table shows current hashes;
each `summary.json` keeps the hash recorded at run time, and
`results/commit-map.txt` maps one to the other.

The CI rows' `summary.json` say `-dirty`: the warm-up `terraform init` output
in `lib/tf-warm/` had been committed by mistake, and on the amd64 runner init
added files next to it. No scenario, library or runner file differed; the
files are untracked since.

The 65/66 local run was an environment failure, not a verifier one: under heavy
load a namespace took longer than the then 120 s delete timeout, and the
attempt ended with no verdict. Since then the timeout is 300 s, an attempt
with no verdict (or a `FAIL: infra:` one) is retried once, and an infra
failure never counts as a correct rejection. Median verifier time per attempt
in the 66/66 run: 14.25 s Kubernetes, 27.0 s Terraform (`verify_seconds` in
`summary.json`).

The first CI run's miss was a reason mismatch, not a false verdict:
`k8s-oom-crashloop/wrong/requests-only` was rejected, but by the restart
counter instead of with the expected `OOMKilled`. Between crashes both pods
can look Ready for a moment, so the early OOM check is racy. The restart check
now names the last termination reason.

### Agent runs

36 runs of `claude -p` (Claude Code 2.1.220), one per model and scenario,
max 40 turns, the broken system live, verified with the same `check.sh`:

| Model | Solved as graded | After regrade | Median turns | Median agent time | Total cost |
|---|---|---|---|---|---|
| `claude-haiku-4-5-20251001` | 11/12 | 11/12 | 8 | 28.3 s | $0.76 |
| `claude-haiku-5-5` | 11/12 | **12/12** | 7 | 29.25 s | $3.58 |
| `claude-sonnet-5-5` | 12/12 | 12/12 | 6 | 23.3 s | $1.25 |

Raw: `results/agent-20261101T064108Z/` (Haiku 4.5) and
`results/agent-20261101T071205Z/` (5.5 models): transcripts (`*.jsonl`), the
agent's diff, verifier logs, `summary.json`, `regrade-*.json`. Cost is the
CLI's `total_cost_usd`. No run touched `scenarios/` (`peeked: false` in every
row).

The two misses are the interesting part:

- **Haiku 4.5, `k8s-networkpolicy`**: fixed the pod label, left the policy
  port at the Service port (80, not the pod's 8080), and reported success
  without testing traffic. That is exactly `wrong/service-port`, written before
  any agent ran; the verifier rejected it with `frontend cannot reach api`.
- **Haiku 5.5, `tf-module-cycle`**: the agent was right and the verifier was
  wrong. It moved both rules to root-level `aws_security_group_rule`
  resources; the Rego dropped them because Terraform state stores unset lists
  as `null`. The same bug made `tf-open-ssh` *accept* SSH from `0.0.0.0/0`
  written in that style. Fixed, guarded by a new wrong fix and three `alt/`
  fixes, and `bench.py regrade` re-checked all 33 regradable agent answers
  with the fixed verifiers: this was the only verdict that changed. Details:
  `results/policy-null-bug-20261101/` and [docs/DESIGN.md](docs/DESIGN.md).

The three `tf-state-drift` answers were not in that count: their verdict
depends on live LocalStack state, and no run saved it. All three agents only
edited `main.tf` and read live state (`plan`, `aws ... get-*`), so `regrade`
now rebuilds that state as `setup.sh` plus the saved diff, and skips any run
whose trace has a writing command. Regraded on a clean CI runner (run
41893849505, commit `925d40d`, which is `5132a4e` with the workflow step
swapped for the regrade): all three still pass. Raw:
`regrade-20261104T*.json` and `tf-state-drift.regrade.log` in both run
directories.

On 2026-11-04 I ran both 5.5 models on the newer `k8s-startup-probe`
scenario: both solved it with a `startupProbe` (Haiku: 4 turns, 15.1 s,
$0.16; Sonnet: 6 turns, 61.8 s, $0.10). Raw: `results/agent-20261104T200617Z/`.
The same evening `bench.py regrade` re-checked all 36 earlier answers, drift
included, against the verifiers at `f174a1d` (IAM grant paths, the stricter
early-fail check, busybox by digest): no verdict changed beyond the
`tf-module-cycle` one above. Raw: `regrade-20261104T2014*.json` and
`regrade-20261104T2018*.json` in the two 11-01 run directories.

Twelve scenarios at one run per model is a smoke test of the harness, not a
model ranking.

## Adding a scenario

A scenario is a directory `scenarios/<id>/`. The runner finds it by its
`check.sh`, so the directory name is the ID.

| Path | What it is |
|---|---|
| `task.md` | What the fixer is told, and the only thing an agent sees besides the files. Every constraint the verifier enforces has to be written here; a check the task does not announce grades a guess. |
| `workspace/` | The broken files. Each attempt starts from a fresh copy. |
| `solution/` | My reference fix, copied over the workspace copy. Only changed files need to be there. |
| `alt/<name>/` | Optional: another correct fix in a different style. It must pass too. |
| `wrong/<name>/` | At least two plausible wrong fixes, each with an `_expect` file. |
| `wrong/<name>/_expect` | Text that must appear in the verifier's output. A wrong fix that fails for some other reason counts as a miss. |
| `<overlay>/_post.sh` | Optional, in `solution/`, `alt/` or `wrong/`: a command run in the workspace after copying, for fixes that are an action rather than a file (`terraform state rm`). `IB_ROOT` points at the repo. Files starting with `_` are never copied. |
| `setup.sh` | Optional: prepares live state before each attempt (the drift scenario changes the queue behind Terraform's back). |
| `check.sh` | The verifier. Gets the workspace path as `$1`; exit 0 accepts. |
| `policy/*.rego`, `policy/*_test.rego` | Terraform only: conftest policy over the applied state, and its unit tests in `package main_test`. |

`check.sh` sources `lib/k8s.sh` or `lib/tf.sh` and reports through `fail` and
`ok` from `lib/env.sh`, which gives the output contract the runner parses:

- `FAIL: <reason>` and a non-zero exit: rejected. The first `FAIL:` line is
  the reason recorded in `summary.json`, and `_expect` is matched against the
  whole output;
- `FAIL: infra: <reason>`, or a non-zero exit with no `FAIL:` line at all: the
  environment broke, not the fix (a namespace that would not delete). The
  attempt is retried once, and an infra failure never counts as a correct
  rejection;
- `ok: <what was proven>` and exit 0: accepted.

Check what the task forbids before checking behaviour where you can (probe
type, limit budget, wildcards), then behaviour. Wait on states with the
helpers (`k8s_wait_available` fails fast on crash loops instead of running out
the clock), and for Terraform apply into fresh state, then read
`terraform show -json`, where references are resolved.

How I prove a new verifier before I trust it:

1. **Broken fails, for the stated problem.** `broken` is always the first
   attempt; its reason in the run output should be the bug from `task.md`,
   not a typo in the manifests.
2. **The solution and every alt pass.** An alt in another style (a different
   resource type, a probe kind, a policy-writing style) is what catches a
   verifier that only recognises my own fix.
3. **Each wrong fix fails with its `_expect`.** Write the wrong fixes as the
   shortcuts someone would actually take, at least one that still behaves
   (breaks a written constraint) and one that still looks right (passes a
   static read, fails at runtime).
4. **Mutants turn tests red.** For Rego, `make policy-test` first, then delete
   or weaken each rule by hand and confirm that exactly the intended unit test
   fails (the results notes for the IAM fixes list the mutants I ran). A
   `check.sh` has no unit tests; its guard is the wrong fixes, so give every check
   a wrong fix that only that check rejects.
5. **The whole suite, then the numbers.** `make test KEEP=1 IDS=<id>` while
   iterating, then a full `make test` from a fresh clone. README counts come
   only from that run's `results/validate-*/summary.json`.

`make check` (no cluster) also runs `test_bench.py`, whose layout test fails
on a scenario without `task.md`, `workspace/`, `solution/` or `check.sh`, with
fewer than two wrong fixes, or with a wrong fix that has no `_expect`.

## Other targets

```bash
make check                  # no cluster: Rego tests, runner self-test, leak check
make policy-test            # Rego unit tests only, no cluster
make test KEEP=1            # leave the cluster up afterwards
make validate IDS="tf-open-ssh k8s-pod-security"   # against a running cluster
make list
make purge                  # also delete the pinned images
python3 bench.py agent -m claude-haiku-5-5 -m claude-sonnet-5-5   # agent runs, needs `claude`
```

## How it was built

The code, tests and this README were written by Claude Code, Anthropic's AI coding agent, working to Midat's problem statement: Midat chose the problem, set the requirements, reviewed the work and accepted it. Every number above comes from the files in this repository and the commands that produced them.
