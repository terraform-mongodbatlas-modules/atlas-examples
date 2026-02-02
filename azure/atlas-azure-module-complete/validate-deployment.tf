module "validation_vm" {
  source = "../modules/validation-vm"
  count  = var.enable_validation_vm ? 1 : 0

  resource_group_name  = var.azure_resource_group_name
  location             = var.regions[0].azure_location
  subnet_id            = var.regions[0].subnet_id
  admin_ssh_public_key = var.validation_vm_ssh_key
  name_prefix          = var.cluster_name
  tags                 = var.tags

  atlas_project_id = module.atlas_project.id

  # Use the first region's private endpoint SRV connection string
  # This works for both sharded clusters (where private_srv is empty) and replica sets
  atlas_connection_string = try(
    module.atlas_cluster.connection_strings.private_endpoint[0].srv_connection_string,
    module.atlas_cluster.connection_strings.private_srv
  )

  depends_on = [module.atlas_azure]
}
