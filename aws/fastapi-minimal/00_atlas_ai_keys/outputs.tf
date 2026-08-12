output "ai_model_api_key_id" {
  description = "Atlas AI Model API key ID."
  value       = mongodbatlas_ai_model_api_key.this.api_key_id
}

output "ai_model_api_key_secret" {
  description = "Atlas AI Model API key secret (al-...). Null if the resource was imported."
  value       = mongodbatlas_ai_model_api_key.this.secret
  sensitive   = true
}

output "ai_model_api_key_endpoint" {
  description = "Server-computed Voyage endpoint hostname (prepend https:// and append /v1 for the client)."
  value       = mongodbatlas_ai_model_api_key.this.endpoint
}

output "voyage_base_url" {
  description = "MongoDB-hosted Voyage base URL for HybridRAG (VOYAGE_BASE_URL)."
  value       = local.voyage_base_url
}
