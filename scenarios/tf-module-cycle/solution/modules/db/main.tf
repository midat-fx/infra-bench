variable "vpc_id" { type = string }
variable "app_sg_id" { type = string }

resource "aws_security_group" "db" {
  name_prefix = "db-"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "Postgres from app"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.app_sg_id
}

output "sg_id" { value = aws_security_group.db.id }
