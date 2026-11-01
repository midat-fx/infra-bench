variable "vpc_id" { type = string }
variable "db_sg_id" { type = string }

# Rules live in their own resources, so the group itself depends on nothing
# from module.db. Only the rule needs the db group ID: no cycle.
resource "aws_security_group" "app" {
  name_prefix = "app-"
  vpc_id      = var.vpc_id
}

output "sg_id" { value = aws_security_group.app.id }
