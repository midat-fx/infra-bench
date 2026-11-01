package main

import rego.v1

resources contains r if {
	some path, value
	walk(input.values.root_module, [path, value])
	some r in value.resources
}

web := g if {
	some g in resources
	g.type == "aws_security_group"
	startswith(g.values.name, "web-")
}

# Ingress rules on the web group, flattened to one CIDR per entry, from inline
# blocks, aws_security_group_rule and aws_vpc_security_group_ingress_rule.
ingress contains {"from": r.from_port, "to": r.to_port, "proto": r.protocol, "cidr": c} if {
	some r in web.values.ingress
	some c in array.concat(r.cidr_blocks, r.ipv6_cidr_blocks)
}

ingress contains {"from": r.values.from_port, "to": r.values.to_port, "proto": r.values.protocol, "cidr": c} if {
	some r in resources
	r.type == "aws_security_group_rule"
	r.values.type == "ingress"
	r.values.security_group_id == web.values.id
	some c in array.concat(object.get(r.values, "cidr_blocks", []), object.get(r.values, "ipv6_cidr_blocks", []))
}

ingress contains {"from": object.get(r.values, "from_port", -1), "to": object.get(r.values, "to_port", -1), "proto": r.values.ip_protocol, "cidr": c} if {
	some r in resources
	r.type == "aws_vpc_security_group_ingress_rule"
	r.values.security_group_id == web.values.id
	some c in [r.values.cidr_ipv4, r.values.cidr_ipv6]
	c != null
	c != ""
}

# ip_protocol "-1" means all traffic regardless of ports.
reaches(r, port) if r.proto in {"-1", "all"}

reaches(r, port) if {
	r.proto in {"tcp", "6"}
	r.from <= port
	r.to >= port
}

office := "198.51.100.0/24"

deny contains msg if {
	some r in ingress
	reaches(r, 22)
	not net.cidr_contains(office, r.cidr)
	msg := sprintf("port 22 reachable via %s/%v-%v from %s", [r.proto, r.from, r.to, r.cidr])
}

deny contains "SSH from the office network is not allowed" if {
	not any_reach(22, office)
}

deny contains msg if {
	some cidr in ["0.0.0.0/0", "::/0"]
	not any_reach(443, cidr)
	msg := sprintf("HTTPS is no longer open from %s", [cidr])
}

any_reach(port, cidr) if {
	some r in ingress
	reaches(r, port)
	net.cidr_contains(r.cidr, cidr)
}
