package main_test

import data.main
import rego.v1

# Unit tests on hand-written state fixtures: `make policy-test`.

groups := [
	{"type": "aws_security_group", "values": {"id": "sg-app", "name": "app-1", "ingress": [], "egress": []}},
	{"type": "aws_security_group", "values": {"id": "sg-db", "name": "db-1", "ingress": [], "egress": []}},
]

state(rules) := {"values": {"root_module": {"resources": array.concat(groups, rules)}}}

vpc_rule(dir, sg, peer, cidr) := {"type": concat("", ["aws_vpc_security_group_", dir, "_rule"]), "values": {"security_group_id": sg, "ip_protocol": "tcp", "from_port": 5432, "to_port": 5432, "referenced_security_group_id": peer, "cidr_ipv4": cidr, "cidr_ipv6": null}}

# aws_security_group_rule as Terraform state stores it: unset lists are null.
legacy_rule(dir, sg, peer) := {"type": "aws_security_group_rule", "values": {"type": dir, "security_group_id": sg, "protocol": "tcp", "from_port": 5432, "to_port": 5432, "source_security_group_id": peer, "cidr_blocks": null, "ipv6_cidr_blocks": null}}

test_vpc_rules_pass if {
	count(main.deny) == 0 with input as state([vpc_rule("egress", "sg-app", "sg-db", null), vpc_rule("ingress", "sg-db", "sg-app", null)])
}

# Regression: the first sg.rego dropped these rules (array.concat on null).
test_legacy_rules_with_null_lists_pass if {
	count(main.deny) == 0 with input as state([legacy_rule("egress", "sg-app", "sg-db"), legacy_rule("ingress", "sg-db", "sg-app")])
}

test_inline_blocks_pass if {
	inline := {"values": {"root_module": {"resources": [
		{"type": "aws_security_group", "values": {"id": "sg-app", "name": "app-1", "ingress": [], "egress": [{"from_port": 5432, "to_port": 5432, "protocol": "tcp", "security_groups": ["sg-db"], "cidr_blocks": [], "ipv6_cidr_blocks": []}]}},
		{"type": "aws_security_group", "values": {"id": "sg-db", "name": "db-1", "egress": [], "ingress": [{"from_port": 5432, "to_port": 5432, "protocol": "tcp", "security_groups": ["sg-app"], "cidr_blocks": [], "ipv6_cidr_blocks": []}]}},
	]}}}
	count(main.deny) == 0 with input as inline
}

test_cidr_ingress_is_denied if {
	some msg in main.deny with input as state([vpc_rule("egress", "sg-app", "sg-db", null), vpc_rule("ingress", "sg-db", null, "10.40.0.0/16")])
	startswith(msg, "db accepts tcp/5432 from CIDR")
}

test_missing_egress_is_denied if {
	main.deny["app has no egress to the db group on 5432"] with input as state([vpc_rule("ingress", "sg-db", "sg-app", null)])
}
