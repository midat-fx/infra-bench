package main

import rego.v1

# Every resource in the applied state, root and child modules alike.
resources contains r if {
	some path, value
	walk(input.values.root_module, [path, value])
	some r in value.resources
}

buckets contains b if {
	some b in resources
	b.type == "aws_s3_bucket"
}

of_type(t, bucket) := [r | some r in resources; r.type == t; r.values.bucket == bucket]

sse_ok(rule) if {
	some d in rule.apply_server_side_encryption_by_default
	d.sse_algorithm in {"AES256", "aws:kms", "aws:kms:dsse"}
}

deny contains msg if {
	some b in buckets
	not any_sse(b.values.id)
	msg := sprintf("bucket %s (%s) has no default encryption configured", [b.address, b.values.id])
}

any_sse(id) if {
	some c in of_type("aws_s3_bucket_server_side_encryption_configuration", id)
	some rule in c.values.rule
	sse_ok(rule)
}

deny contains msg if {
	some b in buckets
	count(of_type("aws_s3_bucket_public_access_block", b.values.id)) == 0
	msg := sprintf("bucket %s has no public access block", [b.address])
}

deny contains msg if {
	some b in buckets
	some pab in of_type("aws_s3_bucket_public_access_block", b.values.id)
	some k in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]
	pab.values[k] != true
	msg := sprintf("bucket %s: %s is not true", [b.address, k])
}

# Versioning was a requirement before the audit; a fix must not drop it.
deny contains msg if {
	some b in buckets
	not versioned(b.values.id)
	msg := sprintf("bucket %s lost versioning", [b.address])
}

versioned(id) if {
	some v in of_type("aws_s3_bucket_versioning", id)
	v.values.versioning_configuration[0].status == "Enabled"
}
