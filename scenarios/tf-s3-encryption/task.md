# invoices bucket fails the storage audit

The security review flagged the `invoices` bucket defined in `main.tf`:

1. no default server-side encryption is configured on the bucket;
2. S3 Block Public Access is not enabled for it.

Fix the Terraform so the bucket has explicit default encryption (SSE-S3 or
SSE-KMS) and all four Block Public Access settings turned on. Keep versioning.

The verifier runs `terraform init` and `terraform apply` against LocalStack in
a fresh state, then evaluates policy over `terraform show -json`.
