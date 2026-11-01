package main

import rego.v1

resources contains r if {
	some path, value
	walk(input.values.root_module, [path, value])
	some r in value.resources
}

group(prefix) := g if {
	gs := [g | some g in resources; g.type == "aws_security_group"; startswith(g.values.name, prefix)]
	count(gs) == 1
	g := gs[0]
}

app := group("app-")
db := group("db-")

covers(from, to, proto) if {
	from <= 5432
	to >= 5432
	proto in {"tcp", "6", "-1"}
}

# One normalised rule list from the three ways the AWS provider can express
# a rule: inline blocks, aws_security_group_rule, aws_vpc_security_group_*_rule.
rules contains {"sg": g.values.id, "dir": dir, "from": r.from_port, "to": r.to_port, "proto": r.protocol, "peer": peer, "cidrs": array.concat(r.cidr_blocks, r.ipv6_cidr_blocks)} if {
	some g in resources
	g.type == "aws_security_group"
	some dir in ["ingress", "egress"]
	some r in g.values[dir]
	some peer in array.concat(r.security_groups, ["none"])
}

rules contains {"sg": r.values.security_group_id, "dir": r.values.type, "from": r.values.from_port, "to": r.values.to_port, "proto": r.values.protocol, "peer": object.get(r.values, "source_security_group_id", null), "cidrs": array.concat(object.get(r.values, "cidr_blocks", []), object.get(r.values, "ipv6_cidr_blocks", []))} if {
	some r in resources
	r.type == "aws_security_group_rule"
}

rules contains {"sg": r.values.security_group_id, "dir": dir, "from": r.values.from_port, "to": r.values.to_port, "proto": r.values.ip_protocol, "peer": r.values.referenced_security_group_id, "cidrs": [c | some c in [r.values.cidr_ipv4, r.values.cidr_ipv6]; c != null; c != ""]} if {
	some r in resources
	some dir in ["ingress", "egress"]
	r.type == concat("", ["aws_vpc_security_group_", dir, "_rule"])
}

has(sg, dir, peer) if {
	some r in rules
	r.sg == sg
	r.dir == dir
	r.peer == peer
	covers(r.from, r.to, r.proto)
}

deny contains "db has no ingress from the app group on 5432" if not has(db.values.id, "ingress", app.values.id)

deny contains "app has no egress to the db group on 5432" if not has(app.values.id, "egress", db.values.id)

deny contains msg if {
	some r in rules
	r.sg == db.values.id
	r.dir == "ingress"
	covers(r.from, r.to, r.proto)
	count(r.cidrs) > 0
	msg := sprintf("db accepts tcp/5432 from CIDR %v", [r.cidrs])
}

deny contains "expected exactly one app-* and one db-* security group" if {
	not app
}

deny contains "expected exactly one app-* and one db-* security group" if {
	not db
}
