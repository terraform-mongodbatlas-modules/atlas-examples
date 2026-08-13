resource "mongodbatlas_ai_model_api_key" "this" {
  project_id = var.project_id
  name       = var.key_name
  cloud      = "ANY"
  geography  = "ANY"
}

locals {
  voyage_base_url = "https://${mongodbatlas_ai_model_api_key.this.endpoint}/v1"
}
