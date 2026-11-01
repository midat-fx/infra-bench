variable "vpc_id" { type = string }

resource "aws_security_group" "db" {
  name_prefix = "db-"
  vpc_id      = var.vpc_id
}

output "sg_id" { value = aws_security_group.db.id }
