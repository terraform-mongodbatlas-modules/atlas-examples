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
  name       = var.atlas_cluster_name

  depends_on = [module.atlas_cluster, module.atlas_aws]
}

locals {
  # VM is always deployed in the first region.
  # Atlas connection strings contain the region code with hyphens (e.g., "us-east-1").
  vm_region_key = lower(replace(local.regions_with_inferred_node_count[0].name, "_", "-"))

  # Find matching private endpoint connection string for the VM's region.
  matching_pe_connection_string = var.enable_validation_vm ? try(
    [
      for pe in data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_endpoint :
      pe.srv_connection_string
      if can(regex(local.vm_region_key, pe.srv_connection_string))
    ][0],
    ""
  ) : ""
}

module "validation_vm" {
  source = "../modules/validation-vm"
  count  = var.enable_validation_vm ? 1 : 0

  vpc_id    = local.validation_vm_vpc_id
  subnet_id = local.validation_vm_subnet_id

  # NAT Gateway: provide public subnet + route table only if private subnet lacks internet
  public_subnet_id       = var.validation_vm_public_subnet_id
  private_route_table_id = var.validation_vm_private_route_table_id

  create_ec2_instance_connect_endpoint = var.validation_vm_create_ec2_instance_connect_endpoint

  instance_type = "t3.micro"

  atlas_project_id   = module.atlas_project.id
  atlas_cluster_name = var.atlas_cluster_name

  # Connection string falls back to private_endpoint → private_srv → standard_srv
  atlas_connection_string = coalesce(
    local.matching_pe_connection_string,
    try(data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_endpoint[0].srv_connection_string, ""),
    try(data.mongodbatlas_advanced_cluster.this[0].connection_strings.private_srv, ""),
    data.mongodbatlas_advanced_cluster.this[0].connection_strings.standard_srv
  )

  depends_on = [module.atlas_aws]
}
