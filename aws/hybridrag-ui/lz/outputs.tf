output "https_url" {
  description = "CloudFront HTTPS URL for the UI."
  value       = module.lz.aws.http_edges["main"].https_url
}

output "ecr_repository_url" {
  description = "ECR repository URL for just build-push (no tag)."
  value       = module.lz.ecr_repositories["ui"]
}

output "handoff_secret_name" {
  description = "Secrets Manager secret name consumed by the app stack."
  value       = local.handoff_secret_name
}

output "chainlit_demo_username" {
  description = "Demo login username."
  value       = "demo"
}

output "chainlit_demo_password" {
  description = "Demo login password (also in the handoff secret)."
  value       = random_password.chainlit_demo.result
  sensitive   = true
}
