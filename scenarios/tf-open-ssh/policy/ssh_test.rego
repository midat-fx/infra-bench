package main_test

import data.main
import rego.v1

# Unit tests on hand-written state fixtures: `make policy-test`.

web := {"type": "aws_security_group", "values": {"id": "sg-web", "name": "web-1", "ingress": [], "egress": []}}

rule(port_from, port_to, v4, v6) := {"type": "aws_vpc_security_group_ingress_rule", "values": {"security_group_id": "sg-web", "ip_protocol": "tcp", "from_port": port_from, "to_port": port_to, "cidr_ipv4": v4, "cidr_ipv6": v6}}

fixed := [web, rule(443, 443, "0.0.0.0/0", null), rule(443, 443, null, "::/0"), rule(22, 22, "198.51.100.0/24", null)]

state(rs) := {"values": {"root_module": {"resources": rs}}}

test_office_only_ssh_passes if {
	count(main.deny) == 0 with input as state(fixed)
}

# Regression: the first ssh.rego let this through. ipv6_cidr_blocks is null in
# state, array.concat(null, ...) was undefined, and the rule vanished.
test_legacy_rule_open_to_world_is_denied if {
	legacy := {"type": "aws_security_group_rule", "values": {"type": "ingress", "security_group_id": "sg-web", "protocol": "tcp", "from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"], "ipv6_cidr_blocks": null}}
	main.deny["port 22 reachable via tcp/22-22 from 0.0.0.0/0"] with input as state(array.concat(fixed, [legacy]))
}

test_wide_range_is_denied if {
	main.deny["port 22 reachable via tcp/0-65535 from 0.0.0.0/0"] with input as state(array.concat(fixed, [rule(0, 65535, "0.0.0.0/0", null)]))
}

test_all_protocols_is_denied if {
	all_traffic := {"type": "aws_vpc_security_group_ingress_rule", "values": {"security_group_id": "sg-web", "ip_protocol": "-1", "cidr_ipv4": null, "cidr_ipv6": "::/0"}}
	some msg in main.deny with input as state(array.concat(fixed, [all_traffic]))
	contains(msg, "from ::/0")
}

test_dropped_https_is_denied if {
	main.deny["HTTPS is no longer open from ::/0"] with input as state([web, rule(443, 443, "0.0.0.0/0", null), rule(22, 22, "198.51.100.0/24", null)])
}

test_subnet_of_office_is_fine if {
	count(main.deny) == 0 with input as state(array.concat(fixed, [rule(22, 22, "198.51.100.128/25", null)]))
}
