variable "orders_db_password" {
  type      = string
  sensitive = true
}

resource "aws_secretsmanager_secret" "orders_db" {
  name_prefix             = "orders-db-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id
  secret_string = jsonencode({
    username = "orders"
    password = var.orders_db_password
  })
}

output "orders_db_secret_arn" {
  value = aws_secretsmanager_secret.orders_db.arn
}
