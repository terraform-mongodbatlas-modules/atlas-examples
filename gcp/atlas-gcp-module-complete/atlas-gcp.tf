module "atlas_gcp" {
  source  = "terraform-mongodbatlas-modules/atlas-gcp/mongodbatlas"
  version = "~> 0.2"

  project_id = module.atlas_project.id

  # ---------------------------------------------------------------------------
  # PrivateLink (BYO Endpoints)
  # ---------------------------------------------------------------------------
  # By default, this example lets the module create PSC forwarding rules.
  #
  # To use existing forwarding rules instead:
  #
  # Replace:
  #   privatelink_endpoints = local.privatelink_endpoints
  #
  # With (two-phase BYO Endpoint workflow):
  #   privatelink_endpoints = []
  #
  #   privatelink_byo_endpoint = { east = { region = "us-east4" } }
  #   # After first apply, use privatelink_service_info output to create
  #   # your own google_compute_address + google_compute_forwarding_rule,
  #   # then complete the connection:
  #   privatelink_byo_service = {
  #     east = {
  #       ip_address           = google_compute_address.psc.address
  #       forwarding_rule_name = google_compute_forwarding_rule.psc.name
  #     }
  #   }
  #
  # NOTE:
  # - Use module.atlas_gcp.privatelink_service_info outputs
  #   to connect your forwarding rule to Atlas PrivateLink service.
  # - Output map keys use lowercase GCP format (us-east4) in atlas-gcp v0.2.0.
  # ---------------------------------------------------------------------------
  privatelink_endpoints = local.privatelink_endpoints

  # ---------------------------------------------------------------------------
  # Backup Export (BYO GCS Bucket)
  # ---------------------------------------------------------------------------
  # By default, this example lets the module create a GCS bucket.
  #
  # To use an existing bucket instead:
  #
  # Replace:
  #   backup_export = local.backup_export_config
  #
  # With:
  #   backup_export = {
  #     enabled     = true
  #     bucket_name = "your-existing-bucket-name"
  #   }
  # ---------------------------------------------------------------------------
  backup_export = local.backup_export_config

  gcp_tags = var.tags

  depends_on = [module.atlas_project]
}
