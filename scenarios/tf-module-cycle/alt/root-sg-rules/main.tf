# Found in an agent run (claude-haiku-5-5, results/agent-20261101T071205Z): a
# correct fix the first version of policy/sg.rego wrongly rejected.
resource "aws_vpc" "main" {
  cidr_block = "10.40.0.0/16"
}

module "app" {
  source = "./modules/app"
  vpc_id = aws_vpc.main.id
}

module "db" {
  source = "./modules/db"
  vpc_id = aws_vpc.main.id
}

# Rules live at the root so each group is created before either rule references the other.
resource "aws_security_group_rule" "app_to_db_postgres" {
  type                     = "egress"
  description              = "Postgres"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.app.sg_id
  source_security_group_id = module.db.sg_id
}

resource "aws_security_group_rule" "db_from_app_postgres" {
  type                     = "ingress"
  description              = "Postgres from app"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.db.sg_id
  source_security_group_id = module.app.sg_id
}
