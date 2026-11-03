# Policies reaching the IAM role from outside the checked set

Real `terraform apply` on LocalStack 4.14.0 and `tf_policy`, 2026-11-03.
Each probe is `tf-iam-least-privilege/solution` plus one extra grant path:

| Probe | Extra grant | Policy before | Policy after |
|---|---|---|---|
| p0 | none | `ok: policy` | `ok: policy` |
| p1 | `aws_iam_role_policy_attachment` to `arn:aws:iam::aws:policy/AdministratorAccess` | `ok: policy` | `FAIL: role gets arn:aws:iam::aws:policy/AdministratorAccess, a policy not defined in this configuration` |
| p2 | `aws_iam_policy_attachment`, `roles = [role]`, same ARN | `ok: policy` | same FAIL |
| p3 | `managed_policy_arns = [same ARN]` on the role | `ok: policy` | same FAIL |
| p4 | `inline_policy` block on the role, `Action: "*"`, `Resource: "*"` | `ok: policy` | `FAIL: wildcard action "*"`, `FAIL: wildcard resource "*"` |

State shapes the unit tests copy, from `terraform show -json`:

- `aws_iam_role`: `managed_policy_arns` and `inline_policy` are `[]` when unset
  (p0), not a mirror of attachments made by other resources;
- p3: `managed_policy_arns: ["arn:aws:iam::aws:policy/AdministratorAccess"]`;
- p4: `inline_policy: [{"name": "debug", "policy": "<JSON string>"}]`;
- p2 `aws_iam_policy_attachment`: `roles: [<role name>]`, `users: null`, `groups: null`.

Unit tests: 4 new tests red before the fix, 16/16 after. Mutants: dropping the
undefined-policy deny, the `aws_iam_policy_attachment` path, the
`managed_policy_arns` path or the `inline_policy` path each turns its test red.
One mutant survives and is equivalent: `arr()` mapping null to `[null]`
instead of `[]` changes nothing, since no role name equals null.

p1 is now the permanent `wrong/managed-admin`. Regrade of the recorded agent
answers with the fixed policy changed nothing:
`results/agent-20261101T064108Z/regrade-20261103T135105Z.json`,
`results/agent-20261101T071205Z/regrade-20261103T135253Z.json`.
