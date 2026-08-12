resource "random_password" "this" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "this" {
  region = var.aws_region
  name   = var.secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  region        = var.aws_region
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = random_password.this.result
}
