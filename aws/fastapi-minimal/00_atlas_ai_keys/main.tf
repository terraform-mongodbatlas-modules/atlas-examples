resource "mongodbatlas_ai_model_api_key" "this" {
  project_id = var.project_id
  name       = var.key_name
  cloud      = "ANY"
  geography  = "ANY"
}

locals {
  voyage_base_url = "https://${mongodbatlas_ai_model_api_key.this.endpoint}/v1"
  voyage_handoff = {
    voyage_api_key  = mongodbatlas_ai_model_api_key.this.secret
    voyage_base_url = local.voyage_base_url
  }
}

resource "local_file" "voyage_handoff" {
  count = var.output_path != null ? 1 : 0

  filename = var.output_path
  content  = jsonencode(local.voyage_handoff)
}
