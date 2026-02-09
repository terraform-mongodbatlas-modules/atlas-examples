# ---------------------------------------------------------------------------
# Data source to fetch cluster with fresh connection strings
# ---------------------------------------------------------------------------
# Private endpoint connection strings may not be available immediately after
# cluster creation. Using a data source with depends_on forces Terraform to
# re-read the cluster after private endpoints are established.
# ---------------------------------------------------------------------------
data "mongodbatlas_advanced_cluster" "this" {
  count = var.enable_validation_vm ? 1 : 0

  project_id = module.atlas_project.id
  name       = var.cluster_name

  depends_on = [module.atlas_cluster, module.atlas_azure]
}

module "validation_vm" {
  source = "../modules/validation-vm"
  count  = var.enable_validation_vm ? 1 : 0

  resource_group_name = var.azure_resource_group_name
  location            = var.regions[0].azure_location
  subnet_id           = var.regions[0].subnet_id

  # Optional: provide SSH public key to enable Bastion access
  # If empty/null (default), VM uses Serial Console with password auth
  admin_ssh_public_key = var.validation_vm_ssh_key

  atlas_project_id = module.atlas_project.id

  # Connection string falls back to private_endpoint → private_srv → standard_srv
  # All types validate PrivateLink via DNS resolution test (private IPs)
  atlas_connection_string = coalesce(
    try(data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_srv, ""),
    data.mongodbatlas_advanced_cluster.this[0].connection_strings.standard_srv
  )

  depends_on = [module.atlas_azure]
}
