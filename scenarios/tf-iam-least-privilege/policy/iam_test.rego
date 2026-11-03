package main_test

import data.main
import rego.v1

# Unit tests on hand-written state fixtures: `make policy-test`.

bucket_arn := "arn:aws:s3:::exports-1"

queue_arn := "arn:aws:sqs:us-east-1:000000000000:done-1"

trust := json.marshal({"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "ecs-tasks.amazonaws.com"}, "Action": "sts:AssumeRole"}]})

good_statements := [
	{"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::exports-1/*"},
	{"Effect": "Allow", "Action": "sqs:SendMessage", "Resource": queue_arn},
]

state(statements) := {"values": {"root_module": {"resources": [
	{"type": "aws_s3_bucket", "values": {"arn": bucket_arn}},
	{"type": "aws_sqs_queue", "values": {"arn": queue_arn}},
	{"type": "aws_iam_role", "values": {"name": "exporter-1", "assume_role_policy": trust}},
	{"type": "aws_iam_policy", "values": {"arn": "arn:aws:iam::000000000000:policy/exporter-1", "policy": json.marshal({"Version": "2012-10-17", "Statement": statements})}},
	{"type": "aws_iam_role_policy_attachment", "values": {"role": "exporter-1", "policy_arn": "arn:aws:iam::000000000000:policy/exporter-1"}},
]}}}

test_least_privilege_passes if {
	count(main.deny) == 0 with input as state(good_statements)
}

test_service_wildcard_is_denied if {
	main.deny["wildcard action \"s3:*\""] with input as state([{"Effect": "Allow", "Action": "s3:*", "Resource": "arn:aws:s3:::exports-1/*"}, good_statements[1]])
}

test_prefix_wildcard_is_denied if {
	main.deny["wildcard action \"s3:Get*\""] with input as state(array.concat(good_statements, [{"Effect": "Allow", "Action": "s3:Get*", "Resource": "arn:aws:s3:::exports-1/*"}]))
}

test_resource_star_is_denied if {
	main.deny["wildcard resource \"*\""] with input as state([{"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "*"}, good_statements[1]])
}

test_not_action_is_denied if {
	main.deny["Allow statement uses NotAction"] with input as state(array.concat(good_statements, [{"Effect": "Allow", "NotAction": "iam:*", "Resource": queue_arn}]))
}

test_missing_permission_is_denied if {
	some msg in main.deny with input as state([good_statements[0]])
	startswith(msg, "role is missing sqs:SendMessage")
}

# A policy that is never attached grants nothing, so the role is still missing it.
test_unattached_policy_does_not_count if {
	unattached := {"values": {"root_module": {"resources": [r |
		some r in state(good_statements).values.root_module.resources
		r.type != "aws_iam_role_policy_attachment"
	]}}}
	some msg in main.deny with input as unattached
	startswith(msg, "role is missing")
}

# terraform show -json lists data sources in the same resources array.
document(id, statements) := {
	"mode": "data",
	"type": "aws_iam_policy_document",
	"name": id,
	"values": {
		"json": json.marshal({"Version": "2012-10-17", "Statement": statements}),
		"statement": statements,
	},
}

with_extra(extra) := {"values": {"root_module": {"resources": array.concat(state(good_statements).values.root_module.resources, extra)}}}

test_policy_document_rendered_json_passes if {
	count(main.deny) == 0 with input as with_extra([document("exporter", good_statements)])
}

# A document grants nothing until a policy resource uses it, and then the
# rendered JSON is read from that resource.
test_unused_policy_document_is_not_policed if {
	count(main.deny) == 0 with input as with_extra([document("draft", [{"Effect": "Allow", "Action": "*", "Resource": "*"}])])
}

# Data sources share type names with the resources they read.
test_data_source_of_same_type_is_not_a_second_bucket if {
	count(main.deny) == 0 with input as with_extra([{"mode": "data", "type": "aws_s3_bucket", "values": {"arn": bucket_arn}}])
}

# A second bucket used to leave `bucket` undefined, which switched off the
# rules built on it: Resource "*" passed with no message at all.
test_second_bucket_is_denied_not_ignored if {
	wide := {"values": {"root_module": {"resources": array.concat(state([{"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "*"}, good_statements[1]]).values.root_module.resources, [{"type": "aws_s3_bucket", "values": {"arn": "arn:aws:s3:::other"}}])}}}
	main.deny["expected exactly one aws_s3_bucket, found 2"] with input as wide
}

# Other ways a policy reaches the role. Shapes copied from applied state:
# results/iam-grant-paths-20261103/.
admin_arn := "arn:aws:iam::aws:policy/AdministratorAccess"

admin_denied(msgs) if msgs[sprintf("role gets %s, a policy not defined in this configuration", [admin_arn])]

test_attachment_of_undefined_policy_is_denied if {
	admin_denied(main.deny) with input as with_extra([{"mode": "managed", "type": "aws_iam_role_policy_attachment", "values": {"role": "exporter-1", "policy_arn": admin_arn}}])
}

test_policy_attachment_resource_is_denied if {
	admin_denied(main.deny) with input as with_extra([{"mode": "managed", "type": "aws_iam_policy_attachment", "values": {"roles": ["exporter-1"], "users": null, "groups": null, "policy_arn": admin_arn}}])
}

with_role_values(extra) := {"values": {"root_module": {"resources": [r |
	some r0 in state(good_statements).values.root_module.resources
	r := role_with(r0, extra)
]}}}

role_with(r, extra) := {"type": r.type, "values": object.union(r.values, extra)} if r.type == "aws_iam_role"

role_with(r, _) := r if r.type != "aws_iam_role"

test_managed_policy_arns_is_denied if {
	admin_denied(main.deny) with input as with_role_values({"managed_policy_arns": [admin_arn], "inline_policy": []})
}

test_inline_policy_block_is_policed if {
	inline := [{"name": "debug", "policy": json.marshal({"Version": "2012-10-17", "Statement": [{"Action": "*", "Effect": "Allow", "Resource": "*"}]})}]
	main.deny["wildcard action \"*\""] with input as with_role_values({"managed_policy_arns": [], "inline_policy": inline})
}

# What the provider writes when neither argument is set.
test_empty_role_lists_pass if {
	count(main.deny) == 0 with input as with_role_values({"managed_policy_arns": [], "inline_policy": []})
}
