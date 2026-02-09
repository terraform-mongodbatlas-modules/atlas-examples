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

  depends_on = [module.atlas_cluster, module.atlas_aws]
}

locals {
  # Find the private endpoint connection string that matches the VM's region.
  # The validation VM should use the endpoint in its own region for connectivity.
  #
  # Region resolution order:
  #   1. Explicit override via var.validation_vm_region
  #   2. Auto-detect by matching validation_vm_subnet_id against the regions list
  #   3. Default to the first configured region
  vm_region = coalesce(
    var.validation_vm_region,
    try(
      [for r in local.regions_with_inferred_node_count : r.aws_region
        if var.validation_vm_subnet_id != null && contains(r.subnet_ids, var.validation_vm_subnet_id)
      ][0],
      null
    ),
    local.regions_with_inferred_node_count[0].aws_region
  )

  # Find matching private endpoint connection string for the VM's region
  # Atlas returns endpoints keyed by region in the private_endpoint array
  # The connection string contains the region code without hyphens (e.g., "useast1")
  matching_pe_connection_string = var.enable_validation_vm ? try(
    [
      for pe in data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_endpoint :
      pe.srv_connection_string
      if can(regex(replace(local.vm_region, "-", ""), pe.srv_connection_string))
    ][0],
    ""
  ) : ""
}

module "validation_vm" {
  source = "../modules/validation-vm"
  count  = var.enable_validation_vm ? 1 : 0

  # ---------------------------------------------------------------------------
  # Networking - VM Placement
  # ---------------------------------------------------------------------------
  vpc_id    = local.validation_vm_vpc_id
  subnet_id = local.validation_vm_subnet_id

  # ---------------------------------------------------------------------------
  # Networking - Internet Access (for package installation)
  # ---------------------------------------------------------------------------
  create_nat_gateway      = var.validation_vm_create_nat_gateway
  public_subnet_id        = var.validation_vm_public_subnet_id
  create_internet_gateway = var.validation_vm_create_internet_gateway
  private_route_table_id  = var.validation_vm_private_route_table_id

  # ---------------------------------------------------------------------------
  # Networking - VM Access Methods
  # ---------------------------------------------------------------------------
  create_ec2_instance_connect_endpoint = var.validation_vm_create_ec2_instance_connect_endpoint
  create_ssm_vpc_endpoints             = var.validation_vm_create_ssm_vpc_endpoints

  # ---------------------------------------------------------------------------
  # Instance Configuration
  # ---------------------------------------------------------------------------
  instance_type        = var.validation_vm_instance_type
  admin_ssh_public_key = var.validation_vm_ssh_public_key

  # ---------------------------------------------------------------------------
  # Atlas Configuration
  # ---------------------------------------------------------------------------
  atlas_project_id   = module.atlas_project.id
  atlas_cluster_name = var.cluster_name

  # Connection string: prefer matching region's private endpoint, then fallbacks
  # This ensures the VM uses the PrivateLink endpoint in its own region
  atlas_connection_string = coalesce(
    local.matching_pe_connection_string,
    try(data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_srv, ""),
    data.mongodbatlas_advanced_cluster.this[0].connection_strings.standard_srv
  )

  depends_on = [module.atlas_aws]
}
