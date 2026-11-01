package main_test

import data.main
import rego.v1

# Unit tests on hand-written state fixtures: `make policy-test`.

state(rs) := {"values": {"root_module": {"resources": rs}}}

bucket := {"address": "aws_s3_bucket.invoices", "type": "aws_s3_bucket", "values": {"id": "inv-1"}}

sse(b, alg) := {"type": "aws_s3_bucket_server_side_encryption_configuration", "values": {"bucket": b, "rule": [{"apply_server_side_encryption_by_default": [{"sse_algorithm": alg}]}]}}

pab(b, restrict) := {"type": "aws_s3_bucket_public_access_block", "values": {"bucket": b, "block_public_acls": true, "block_public_policy": true, "ignore_public_acls": true, "restrict_public_buckets": restrict}}

versioning(b) := {"type": "aws_s3_bucket_versioning", "values": {"bucket": b, "versioning_configuration": [{"status": "Enabled"}]}}

test_fixed_bucket_passes if {
	count(main.deny) == 0 with input as state([bucket, sse("inv-1", "aws:kms"), pab("inv-1", true), versioning("inv-1")])
}

test_encryption_on_other_bucket_is_denied if {
	some msg in main.deny with input as state([bucket, sse("other", "AES256"), pab("inv-1", true), versioning("inv-1")])
	contains(msg, "has no default encryption")
}

test_unknown_algorithm_is_denied if {
	some msg in main.deny with input as state([bucket, sse("inv-1", "none"), pab("inv-1", true), versioning("inv-1")])
	contains(msg, "has no default encryption")
}

test_partial_block_is_denied if {
	main.deny["bucket aws_s3_bucket.invoices: restrict_public_buckets is not true"] with input as state([bucket, sse("inv-1", "AES256"), pab("inv-1", false), versioning("inv-1")])
}

test_bucket_in_child_module_is_checked if {
	in_module := {"values": {"root_module": {"child_modules": [{"resources": [bucket]}]}}}
	some msg in main.deny with input as in_module
	contains(msg, "has no public access block")
}
