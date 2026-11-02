# Rego null-list bug, found by an agent run

`claude-haiku-5-5` fixed `tf-module-cycle` with root-level
`aws_security_group_rule` resources (results/agent-20261101T071205Z). The
verifier rejected it: in Terraform state those resources carry
`cidr_blocks: null`, and `array.concat(null, ...)` is undefined in Rego, so
the rule never entered the normalised rule set. The same pattern in
`tf-open-ssh/policy/ssh.rego` was a false *accept*. Reproduction on
2026-11-01T07:46Z, state from `tf-open-ssh/wrong/legacy-rule` (SSH
from 0.0.0.0/0 via `aws_security_group_rule`), policy before and after commit
"Fix Rego null lists":

    == old policy (ssh.rego at d0b4202, recorded then as a9240c1)
    ok: policy
    == new policy
    FAIL: port 22 reachable via tcp/22-22 from 0.0.0.0/0

Fix: `arr()` helper that maps null to []. Regression guards:
`tf-open-ssh/wrong/legacy-rule` (must fail), `tf-module-cycle/alt/root-sg-rules`,
`tf-open-ssh/alt/inline-blocks`, `tf-iam-least-privilege/alt/inline-role-policy`
(must pass).
