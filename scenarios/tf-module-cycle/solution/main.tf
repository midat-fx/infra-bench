resource "aws_vpc" "main" {
  cidr_block = "10.40.0.0/16"
}

module "app" {
  source     = "./modules/app"
  vpc_id     = aws_vpc.main.id
  db_sg_id   = module.db.sg_id
}

module "db" {
  source    = "./modules/db"
  vpc_id    = aws_vpc.main.id
  app_sg_id = module.app.sg_id
}
