# `one()` in iam.rego failed open, found while adding the policy-document alt

Real `terraform apply` on LocalStack and `tf_policy`, 2026-11-02. Workspace:
`tf-iam-least-privilege/wrong/resource-star` plus a second `aws_s3_bucket`.

    == policy before the fix
    ok: policy
    == policy after the fix
    FAIL: expected exactly one aws_s3_bucket, found 2

Before the fix the second bucket left `bucket` undefined, so the
wildcard-resource and required-permission rules produced nothing. Unit test:
`test_second_bucket_is_denied_not_ignored`, red before the fix. Mutants: dropping
the `n != 1` check or the data-source filter each turn exactly one test red.

Regrade of the recorded agent answers with the fixed policy changed nothing:
`regrade-20261102T201227Z.json` in `results/agent-20261101T064108Z/`,
`regrade-20261102T201343Z.json` in `results/agent-20261101T071205Z/`.

Still open, same run: the solution plus an `aws_iam_role_policy_attachment` to
`arn:aws:iam::aws:policy/AdministratorAccess` gets `ok: policy`. The policy only
reads policies defined in the configuration.
