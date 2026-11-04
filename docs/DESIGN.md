# Design notes

Why infra-bench is built the way it is. Each section is a decision and the
alternative that was turned down.

## What a scenario is

A directory with the broken files (`workspace/`), the task text (`task.md`), a
reference fix (`solution/`), several plausible wrong fixes (`wrong/*/`) and a
verifier (`check.sh`). The runner proves every verifier on every run:

- the broken workspace must be **rejected**;
- the reference fix must be **accepted**, and so must every `alt/*/` fix: a
  correct fix written in another style (inline security group blocks instead
  of rule resources, an inline role policy instead of policy + attachment);
- every wrong fix must be **rejected, for the intended reason**: each wrong fix
  carries an `_expect` string that has to show up in the verifier output.

The last rule is the important one. Without it, a wrong fix that fails because
of a typo in the overlay (a YAML indentation error, a Terraform syntax error)
would count as "the verifier caught it", and the suite would quietly turn into
a syntax checker. With it, `wrong/wildcard-resources` in the RBAC scenario has
to fail with `can get secrets`, not with anything else.

Fixes are overlays (whole files copied over the workspace), not patches. A
unified diff written by hand breaks on the first whitespace change; an overlay
is the file a reviewer would actually read. An overlay may add a `_post.sh` for
fixes that are an action rather than an edit: the drift scenario's wrong fixes
`terraform apply` the old code or `terraform state rm` the queue.

## Verifiers test behaviour, then policy

A verifier first makes the system run the candidate (kubectl apply into a fresh
namespace, terraform apply into fresh state against LocalStack), then checks
two kinds of things:

- **behaviour**: pods Ready, restart count, real HTTP traffic between pods,
  `kubectl auth can-i` as the ServiceAccount, `terraform plan
  -detailed-exitcode`, live SQS attributes;
- **policy**: the constraints in the task text that behaviour cannot show. A
  memory limit of 2Gi runs fine, but the task said at most 256Mi; a Service
  selector that pins `version: v2` routes correctly today and breaks on the
  next rollout.

Behaviour-only verifiers accept "delete the probe" and "remove the limit".
Policy-only verifiers (static linting of the YAML) accept manifests that never
start. Each scenario's wrong fixes include at least one of each kind.

Wrong fixes guard against false accepts; `alt/` fixes guard against false
rejects. A verifier that only recognises the reference fix's shape is as
broken as one that accepts anything, it just fails the other way.

## A verifier bug the agent runs found

The first Haiku 5.5 run "failed" `tf-module-cycle` with a fix that was
correct: it moved both rules to the root module as `aws_security_group_rule`
resources. The Rego dropped those rules. In Terraform state an unset list
attribute is `null`, not `[]`, and `array.concat(null, ...)` is undefined in
Rego, so the rule body silently produced nothing. The same pattern in
`tf-open-ssh` was worse: SSH from `0.0.0.0/0` written as an
`aws_security_group_rule` passed the policy. Both are fixed (an `arr()` helper
maps null to `[]`), and the cases that exposed them are now permanent:
`tf-open-ssh/wrong/legacy-rule` must fail, `tf-module-cycle/alt/root-sg-rules`
must pass. Reproduction and before/after output:
`results/policy-null-bug-20261101/`.

The full run catches a regression like this only after a minute of `terraform
apply`. So each policy also has `conftest verify` unit tests on hand-written
state fixtures that copy the shapes the provider really writes (`null` lists
included). They live in a separate `main_test` package, so their helper names
cannot collide with the policy's rules and `conftest test` never evaluates them.
I checked them with mutants: restoring the pre-fix `ssh.rego` or `sg.rego`,
deleting the `NotAction` rule, lowering the password minimum to 8, or skipping
the algorithm check each turns exactly the intended test red.

`bench.py regrade` re-runs today's verifiers over a past agent run, rebuilding
each workspace from the saved diff, so a verifier fix can be checked against
every recorded agent answer, not only the one that exposed it. The drift
scenario is not regradable: its verdict depends on live LocalStack state.

## Kubernetes: kubectl runs inside the kind node

`k()` in `lib/k8s.sh` is `docker exec <node> kubectl`. The kind node image
ships kubectl and an admin kubeconfig, so:

- the host needs neither kubectl nor a reachable API server port. On this
  machine colima's host port forwarding is broken (published ports never show
  up on macOS), and going through `docker exec` sidesteps it entirely;
- the client version always equals the server version.

Every attempt deletes the namespace (force-deleting pods first, so busybox's
ignored SIGTERM does not cost 30 seconds) and re-applies the workspace. The
files are the deliverable, not whatever was `kubectl edit`-ed live. Cluster-
scoped leftovers are cleaned too: ClusterRoles/Bindings labelled for the
scenario, and any ClusterRoleBinding whose subject lives in the scenario's
namespace, so an agent's stray `cluster-admin` binding cannot leak into the
next attempt.

`k8s_wait_available` fails fast on states that never heal by waiting
(`CrashLoopBackOff`, `OOMKilled`, `CreateContainerConfigError`, a
`ReplicaFailure` condition from admission). Rejecting a wrong fix then costs a
few seconds instead of the full timeout. A single non-zero exit (reason
`Error`) used to count too, which would have failed an app that legitimately
exits once and recovers; now only the reasons themselves, matched whole, do.

One workload image (`busybox`) serves every scenario: `httpd` for servers,
`wget` for traffic tests, `dd` to allocate memory. It is pulled into the node
once at `up`, so the first attempt is not timing the registry. It is pinned
by digest, like the kind node image, so a re-pushed tag cannot change what the
scenarios run.

kindnet, kind's default CNI, enforces NetworkPolicy in this release, so the
NetworkPolicy scenario tests real packets: `frontend -> api` must succeed and
`batch -> api` must time out. No Calico install is needed. The suite checks
this on every run: if the CNI stopped enforcing, `wrong/allow-namespace` and
the reference fix would both fail to block `batch`, and validation would go
red.

## Terraform: LocalStack, apply, then Rego over state

Terraform and conftest run in containers on kind's Docker network, where
LocalStack answers as `ib-localstack:4566`. Same reason as kubectl: no host
ports involved.

Why apply instead of only `terraform plan`:

- the policies check the **applied state** (`terraform show -json` after
  apply), where references are resolved. In a plan, `bucket =
  aws_s3_bucket.logs.id` is an unknown value; in state it is the bucket name,
  so "encryption configured on a different bucket" is decidable;
- apply proves the config is accepted by an AWS API, not just by the parser.

Why the policies require explicit resources instead of reading live settings:
LocalStack (like AWS since 2023) reports SSE-S3 default encryption on every
bucket, configured or not. A live `get-bucket-encryption` check passes the
broken workspace. The Rego requires an
`aws_s3_bucket_server_side_encryption_configuration` that targets the bucket.

The Rego normalises the several ways the AWS provider can express the same
thing (inline `ingress` blocks, `aws_security_group_rule`,
`aws_vpc_security_group_ingress_rule`; managed policy plus attachment, or an
inline role policy). A verifier that only understands the style of the
reference fix rejects correct alternatives, which is its own kind of false
result.

`aws_iam_policy_document` is the most common way to write IAM in Terraform, so
`tf-iam-least-privilege` has an alt in that style. The policy still reads
`aws_iam_policy.values.policy`: in applied state that is the rendered JSON, so
nothing depends on how it was written. I do not police the document's own
`statement` blocks. A document grants nothing until a policy resource uses it,
and at that point the rendered JSON is checked, while an `aws_iam_policy` with
a wildcard is a real IAM object even when unattached, so that one does count.
`wrong/document-resource-star` shows the rendered JSON really is what gets read.

Writing that alt exposed a false accept in the same policy. `one()` left
`bucket` undefined whenever the state did not hold exactly one bucket, and in
Rego an undefined value makes a rule body produce nothing rather than deny. So
a second bucket switched off the wildcard-resource and required-permission
rules, and `Resource: "*"` passed without a message. A separate rule now denies
when the count is not one, and `one()` ignores data sources, which share type
names with the resources they read.
Output: `results/iam-one-fail-open-20261102/`.

The policy did not read every way a policy reaches the role, either. An
attachment to AWS-managed `AdministratorAccess` by ARN, the same through
`aws_iam_policy_attachment` or `managed_policy_arns`, and an `inline_policy`
block on the role all passed next to a correct policy. Now every ARN that
reaches the role must belong to an `aws_iam_policy` in this configuration,
because a policy whose document is not in the state cannot be checked, and
inline blocks are policed like `aws_iam_role_policy`. Probes and state shapes:
`results/iam-grant-paths-20261103/`.

Resource names use `name_prefix` / `bucket_prefix`, so attempts never collide
on LocalStack and no attempt has to destroy what the previous one created.

The drift scenario is the exception to "fresh state": its `setup.sh` applies
the original code, then changes the queue behind Terraform's back with
`awslocal` (the console change during the incident). The verifier then runs on
that state: the live queue must still have the incident values, the queue must
still be in state, there must be no `ignore_changes`, and `plan
-detailed-exitcode` must exit 0. Each check rejects one of the shortcuts that
also make the plan clean.

## Pinned versions

| Component | Version | Why this one |
|---|---|---|
| kind | v0.33.0 | current release; downloaded with its published sha256 |
| node image | kindest/node v1.37.0, by digest | default for kind v0.33.0 |
| LocalStack | 4.14.0 | last community image that starts without an auth token |
| Terraform | 1.17.1 (image) | current |
| AWS provider | 5.100.0 | last 5.x |
| conftest | v0.71.1 | current |

The AWS provider polls `GetQueueAttributes` until the attributes read back
unchanged several times in a row; against LocalStack that is a fixed ~25 s per
SQS queue. It is the single largest cost in the Terraform half of the suite.
The drift scenario uses one queue, not a queue plus DLQ, for that reason.

## Agent runs

`bench.py agent` gives `claude -p` the task text and a copy of the broken
workspace, in a directory outside the repository (`~/.cache/infra-bench-agent`)
so the reference fixes are not one `ls ..` away. For Kubernetes scenarios the
broken manifests are deployed first, so the agent can debug a live failure.

The agent gets wrapper scripts on `PATH`: `kubectl` (mirrors the working
directory into the node, so `kubectl apply -f file.yaml` works), `terraform`
and `aws` (both against LocalStack). Allowed tools are file edits and those
commands; nothing else runs.

The wrappers reveal the repository path, so isolation is not airtight. Instead
of pretending otherwise, every run records `peeked`: whether any tool call
touched a `scenarios/` path. The transcript is kept in `results/` for audit.

User-level Claude Code settings, hooks, MCP servers and skills are switched
off for these runs (`--setting-sources project --strict-mcp-config
--disable-slash-commands`; the scratch directory has no project settings), and
the tool set is cut to `Bash,Read,Edit,Write,Glob,Grep`. Models are passed by
full ID: the CLI alias `haiku` resolved to Haiku 4.5, not 5.5, which is why the
first agent run in `results/` is labelled that way. The model actually used is
taken from the transcript's init event, not from the flag.

## CI and the leak check

Two workflows. `checks` runs on every push and pull request in about a minute:
`make check` (Rego unit tests, `bash -n`, the runner's self-test in
`test_bench.py`, the leak check) plus `shellcheck -S error`. `make test` needs
kind and LocalStack and takes ~15 minutes of runner time, so it runs weekly
and by hand, not on every push. The weekly run is there for drift outside the
repo: a provider release, a moved image, a LocalStack change. A manual run can
take an `ids` input to try one scenario on a clean runner; make pastes it into
a shell recipe, so the workflow accepts only scenario-ID characters. Both run with a read-only token and actions pinned to commit SHAs, so a
moved tag cannot change what runs.

`lib/leak-check.sh` exists because this repo commits agent transcripts, and a
transcript records more than the agent's work: home-directory paths, the local
user name, and once the Claude Code account's rate-limit status. The harness
scrubs those before writing, and the check is the second line. It greps every
commit, not just the tip (a leak in history is still public), decompresses
any `.gz` that ever existed (git grep skips binaries), and checks that every
commit has the same single author and committer identity and no attribution trailers. Its own patterns are split
(`'/Us''ers/'`) so that it never matches itself, and so the repository never
contains the literal strings it hunts for. I checked it on a throwaway clone
with one planted leak of each kind; each was reported.

## What is deliberately not here

- No Helm, operators or multi-node clusters: each adds minutes of start-up
  and gigabytes of images on a shared laptop, and none of the scenarios needs
  them.
- No metrics-server, so no HPA scenario.
- No real AWS. Some behaviour differs from LocalStack (IAM is not enforced in
  the community edition), which is why IAM is checked as policy over state, not
  by trying calls as the role.
