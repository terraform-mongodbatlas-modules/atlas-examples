output "secret_arn" {
  description = "Secrets Manager ARN for the API key."
  value       = aws_secretsmanager_secret.this.arn
}
