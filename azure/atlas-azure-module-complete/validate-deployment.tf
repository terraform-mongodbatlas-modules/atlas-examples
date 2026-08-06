locals {
  connection_string = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )
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

  # Connection string falls back to private_endpoint → private_srv → standard_srv.
  # All types validate PrivateLink via DNS resolution tests for private IPs.
  atlas_connection_string = local.connection_string
}
