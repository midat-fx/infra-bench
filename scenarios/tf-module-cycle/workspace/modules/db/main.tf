variable "vpc_id" { type = string }
variable "app_sg_id" { type = string }

resource "aws_security_group" "db" {
  name_prefix = "db-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_sg_id]
  }
}

output "sg_id" { value = aws_security_group.db.id }
