output "api_key" {
  description = "Atlas AI Model API key secret (inline into the handoff JSON)."
  value       = mongodbatlas_ai_model_api_key.this.secret
  sensitive   = true
}

output "voyage_base_url" {
  description = "MongoDB-hosted Voyage OpenAI-compatible base URL."
  value       = local.voyage_base_url
}

output "api_key_id" {
  description = "Atlas AI Model API key ID."
  value       = mongodbatlas_ai_model_api_key.this.api_key_id
}
