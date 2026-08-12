resource "mongodbatlas_ai_model_api_key" "this" {
  project_id = var.project_id
  name       = var.key_name
  cloud      = "ANY"
  geography  = "ANY"
}

resource "aws_secretsmanager_secret" "this" {
  region = var.aws_region
  name   = var.secret_name
  tags   = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  region        = var.aws_region
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = mongodbatlas_ai_model_api_key.this.secret
}

locals {
  voyage_base_url = "https://${mongodbatlas_ai_model_api_key.this.endpoint}/v1"
}
