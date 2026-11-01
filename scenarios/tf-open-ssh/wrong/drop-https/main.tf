resource "aws_vpc" "edge" {
  cidr_block = "10.50.0.0/16"
}

resource "aws_security_group" "web" {
  name_prefix = "web-"
  vpc_id      = aws_vpc.edge.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh_v4" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "198.51.100.0/24"
  description       = "SSH from office"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
