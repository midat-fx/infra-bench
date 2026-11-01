variable "vpc_id" { type = string }

resource "aws_security_group" "app" {
  name_prefix = "app-"
  vpc_id      = var.vpc_id
}

output "sg_id" { value = aws_security_group.app.id }
