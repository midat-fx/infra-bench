package main

import rego.v1

resources contains r if {
	some path, value
	walk(input.values.root_module, [path, value])
	some r in value.resources
}

# Data sources share type names with the resources they read, so
# data "aws_s3_bucket" next to the bucket is not a second bucket.
managed(t) := [r | some r in resources; r.type == t; object.get(r, "mode", "managed") == "managed"]

one(t) := r if {
	rs := managed(t)
	count(rs) == 1
	r := rs[0]
}

# Without exactly one of each, role, bucket or queue is undefined and every
# rule built on it silently stops firing, so this has to deny by itself.
deny contains msg if {
	some t in ["aws_iam_role", "aws_s3_bucket", "aws_sqs_queue"]
	n := count(managed(t))
	n != 1
	msg := sprintf("expected exactly one %s, found %d", [t, n])
}

role := one("aws_iam_role")
bucket := one("aws_s3_bucket")
queue := one("aws_sqs_queue")

as_list(x) := x if is_array(x)
as_list(x) := [x] if not is_array(x)

# State stores unset lists as null.
arr(x) := x if is_array(x)

arr(x) := [] if not is_array(x)

# Every way a managed policy's ARN ends up on the role.
attached_arns contains a.values.policy_arn if {
	some a in resources
	a.type == "aws_iam_role_policy_attachment"
	a.values.role == role.values.name
}

attached_arns contains a.values.policy_arn if {
	some a in resources
	a.type == "aws_iam_policy_attachment"
	role.values.name in arr(a.values.roles)
}

attached_arns contains arn if some arn in arr(role.values.managed_policy_arns)

defined_arns := {p.values.arn | some p in managed("aws_iam_policy")}

# An AWS-managed or pre-existing policy has no document in this state, so it
# cannot be checked, and AdministratorAccess next to a correct policy would pass.
deny contains msg if {
	some arn in attached_arns
	not arn in defined_arns
	msg := sprintf("role gets %s, a policy not defined in this configuration", [arn])
}

inline_docs contains json.unmarshal(p.values.policy) if {
	some p in resources
	p.type == "aws_iam_role_policy"
	p.values.role == role.values.name
}

inline_docs contains json.unmarshal(p.policy) if some p in arr(role.values.inline_policy)

# Statements of every managed or inline policy that ends up on the role.
attached_docs contains json.unmarshal(p.values.policy) if {
	some p in managed("aws_iam_policy")
	p.values.arn in attached_arns
}

attached_docs contains d if some d in inline_docs

statements contains s if {
	some d in attached_docs
	some s in as_list(d.Statement)
}

allows contains s if {
	some s in statements
	s.Effect == "Allow"
}

# Every policy in the configuration counts, attached or not: a wildcard
# policy waiting to be attached is still a finding.
all_statements contains s if {
	some p in resources
	p.type in {"aws_iam_policy", "aws_iam_role_policy"}
	some s in as_list(json.unmarshal(p.values.policy).Statement)
	s.Effect == "Allow"
}

all_statements contains s if {
	some d in inline_docs
	some s in as_list(d.Statement)
	s.Effect == "Allow"
}

deny contains msg if {
	some s in all_statements
	some a in as_list(object.get(s, "Action", []))
	contains(a, "*")
	msg := sprintf("wildcard action %q", [a])
}

deny contains msg if {
	some s in all_statements
	some r in as_list(object.get(s, "Resource", []))
	r != concat("", [bucket.values.arn, "/*"])
	contains(r, "*")
	msg := sprintf("wildcard resource %q", [r])
}

deny contains msg if {
	some s in all_statements
	some k in ["NotAction", "NotResource", "NotPrincipal"]
	object.get(s, k, null) != null
	msg := sprintf("Allow statement uses %s", [k])
}

# What the exporter needs must still be allowed, on the exact ARN.
needed := {
	["s3:GetObject", concat("", [bucket.values.arn, "/*"])],
	["s3:PutObject", concat("", [bucket.values.arn, "/*"])],
	["sqs:SendMessage", queue.values.arn],
}

granted(action, res) if {
	some s in allows
	action in as_list(object.get(s, "Action", []))
	res in as_list(object.get(s, "Resource", []))
}

deny contains msg if {
	some [a, r] in needed
	not granted(a, r)
	msg := sprintf("role is missing %s on %s", [a, r])
}

deny contains "trust policy changed: must allow only ecs-tasks.amazonaws.com" if {
	trust := json.unmarshal(role.values.assume_role_policy)
	{p | some s in as_list(trust.Statement); some p in as_list(s.Principal.Service)} != {"ecs-tasks.amazonaws.com"}
}
