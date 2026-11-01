resource "aws_secretsmanager_secret" "orders_db" {
  name_prefix             = "orders-db-"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id
  secret_string = jsonencode({
    username = "orders"
    password = "r0tated-Orders-pw-Nov-2026-x9"
  })
}

output "orders_db_secret_arn" {
  value = aws_secretsmanager_secret.orders_db.arn
}
