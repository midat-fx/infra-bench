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
