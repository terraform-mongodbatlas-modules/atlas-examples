output "https_url" {
  description = "CloudFront HTTPS URL for the UI. Null when http_edges is empty."
  value       = try(module.lz.aws.http_edges["main"].https_url, null)
}

output "ecr_repository_url" {
  description = "ECR repository URL for just build-push (no tag)."
  value       = module.lz.ecr_repositories["ui"]
}

output "app_secret_name" {
  description = "Secrets Manager secret name consumed by the app stack."
  value       = local.app_secret_name
}

output "chainlit_demo_username" {
  description = "Demo login username."
  value       = "demo"
}

output "chainlit_demo_password" {
  description = "Demo login password (also in the app secret)."
  value       = random_password.chainlit_demo.result
  sensitive   = true
}

output "connection_string_public" {
  description = "Public connection string for debugging with mongosh or local app."
  value       = module.lz.connection_string_public
  sensitive   = true
}
