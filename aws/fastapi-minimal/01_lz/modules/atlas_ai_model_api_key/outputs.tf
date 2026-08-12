output "secret_arn" {
  description = "Secrets Manager ARN for the Voyage API key."
  value       = aws_secretsmanager_secret.this.arn
}

output "voyage_base_url" {
  description = "MongoDB-hosted Voyage OpenAI-compatible base URL."
  value       = local.voyage_base_url
}

output "api_key_id" {
  description = "Atlas AI Model API key ID."
  value       = mongodbatlas_ai_model_api_key.this.api_key_id
}
