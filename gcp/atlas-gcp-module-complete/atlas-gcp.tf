module "atlas_gcp" {
  source  = "terraform-mongodbatlas-modules/atlas-gcp/mongodbatlas"
  version = "~> 0.1.0"

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
  # With (two-phase BYOE workflow):
  #   privatelink_byoe_regions = { east = "us-east4" }
  #   # After first apply, use privatelink_service_info output to create
  #   # your own google_compute_address + google_compute_forwarding_rule,
  #   # then complete the connection:
  #   privatelink_byoe = {
  #     east = {
  #       ip_address           = google_compute_address.psc.address
  #       forwarding_rule_name = google_compute_forwarding_rule.psc.name
  #     }
  #   }
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
