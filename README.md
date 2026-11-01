# infra-bench

Twelve broken Kubernetes and Terraform setups, each with a verifier that runs
the fix for real. Kubernetes scenarios run on a local [kind](https://kind.sigs.k8s.io)
cluster; Terraform scenarios apply against [LocalStack](https://github.com/localstack/localstack).
No cloud account, no credentials.

The point is the verifiers. Each scenario ships a reference fix and two to four
**plausible wrong fixes**: the shortcuts a tired engineer or a coding agent
takes (delete the probe, remove the memory limit, relax the namespace policy,
`ignore_changes` the drift away, `s3:*` instead of `*`). `make test` proves on
every run that each verifier rejects the broken setup, accepts the reference
fix, and rejects every wrong fix *for the reason it was written to catch*.

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
| `k8s-service-selector` | Service selector pins `version: v1` after a v2 rollout | `app: shop` (catches admin pods) · `version: v2` · pin the new version |
| `tf-s3-encryption` | bucket without default encryption or public access block | encrypt a different bucket · 3 of 4 block settings · `acl = private` |
| `tf-iam-least-privilege` | task role with `Action: *`, `Resource: *` | `s3:*` · right actions on `Resource: *` · forget `sqs:SendMessage` · `NotAction` |
| `tf-state-drift` | console change to an SQS queue, plan wants to revert it | `terraform apply` the old code · `ignore_changes` · `terraform state rm` |
| `tf-module-cycle` | two modules need each other's security group ID: `Error: Cycle` | VPC CIDR rules instead of SG references · drop the egress rule |
| `tf-open-ssh` | SSH from `0.0.0.0/0` and `::/0` | close IPv4 only · `0-65535` rule that still covers 22 · drop HTTPS too |
| `tf-hardcoded-secret` | DB password literal in `main.tf` | move it to `terraform.tfvars` · 12-char `random_password` · a new literal |

Each scenario lives in `scenarios/<id>/`: `task.md` (what the fixer is told),
`workspace/` (broken files), `solution/`, `wrong/*/`, `check.sh` (verifier)
and, for Terraform, `policy/*.rego`.

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

[docs/DESIGN.md](docs/DESIGN.md) explains each choice: why kubectl runs inside
the kind node, why apply rather than plan, why a live encryption check would
pass the broken bucket, and what is deliberately left out.

## Results

RESULTS_PLACEHOLDER

## Other targets

```bash
make test KEEP=1            # leave the cluster up afterwards
make validate IDS="tf-open-ssh k8s-pod-security"   # against a running cluster
make list
make purge                  # also delete the pinned images (~3 GB)
python3 bench.py agent -m claude-haiku-5-5 -m claude-sonnet-5-5   # agent runs, needs `claude`
```
