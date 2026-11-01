variable "vpc_id" { type = string }
variable "db_sg_id" { type = string } # unused now

# Rules live in their own resources, so the group itself depends on nothing
# from module.db. Only the rule needs the db group ID: no cycle.
resource "aws_security_group" "app" {
  name_prefix = "app-"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "Postgres"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  cidr_ipv4                    = "10.40.0.0/16"
}

output "sg_id" { value = aws_security_group.app.id }
