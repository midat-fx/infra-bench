# exporter role allows everything

`main.tf` defines the `exporter` task role. Its policy is `Action: "*"`,
`Resource: "*"`, left over from an incident. The exporter does exactly two
things:

- reads and writes objects in the `exports` bucket (`s3:GetObject`,
  `s3:PutObject` on the objects of that bucket);
- sends a message to the `export_done` queue (`sqs:SendMessage`).

Rewrite the IAM policy to least privilege: only those actions, only on those
resources, no wildcards in actions or resources (object keys under the bucket,
`<bucket-arn>/*`, are the one exception). Keep the role and its trust policy.

The verifier applies the Terraform against LocalStack from fresh state and
evaluates policy over `terraform show -json`.
