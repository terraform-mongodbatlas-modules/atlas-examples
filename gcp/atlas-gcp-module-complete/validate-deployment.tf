# ---------------------------------------------------------------------------
# Data source to fetch the cluster with fresh private endpoint strings.
# ---------------------------------------------------------------------------
# Private endpoint connection strings may not be available immediately after
# cluster creation. This dependency-ordered read occurs after both the cluster
# and GCP Private Service Connect endpoints have been created.
# ---------------------------------------------------------------------------
data "mongodbatlas_advanced_cluster" "validation" {
  count = local.validation_vm_enabled ? 1 : 0

  project_id = module.atlas_project.id
  name       = var.atlas_cluster_name

  depends_on = [module.atlas_cluster, module.atlas_gcp]
}

locals {
  # Match the first region's Atlas endpoint association by forwarding rule ID.
  # GCP private endpoint SRV hostnames do not reliably contain a region token.
  validation_vm_endpoint_service_id = local.validation_vm_enabled ? try(
    module.atlas_gcp.privatelink[local.validation_vm_region].atlas_endpoint_service_name,
    [
      for endpoint in values(module.atlas_gcp.privatelink) :
      endpoint.atlas_endpoint_service_name
      if lookup(var.atlas_to_gcp_region, endpoint.region, endpoint.region) == local.validation_vm_region
    ][0],
    null
  ) : null

  validation_vm_private_endpoints = local.validation_vm_enabled ? try(
    flatten([
      for connection_string in data.mongodbatlas_advanced_cluster.validation[0].connection_strings.private_endpoint :
      connection_string
    ]),
    []
  ) : []

  validation_vm_connection_strings = local.validation_vm_enabled ? [
    for private_endpoint in local.validation_vm_private_endpoints :
    private_endpoint.srv_connection_string
    if try(
      contains(
        [for endpoint in private_endpoint.endpoints : endpoint.endpoint_id],
        local.validation_vm_endpoint_service_id
      ),
      false
    )
  ] : []

  validation_vm_connection_string = local.validation_vm_enabled ? try(
    local.validation_vm_connection_strings[0],
    null
  ) : null
}

module "validation_vm" {
  source = "../modules/validation-vm"
  count  = local.validation_vm_enabled ? 1 : 0

  gcp_project_id = var.gcp_project_id
  subnetwork     = local.validation_vm_subnetwork
  zone           = var.validation_vm_zone
  machine_type   = var.validation_vm_machine_type

  create_iap_ssh_firewall = var.validation_vm_create_iap_ssh_firewall
  enable_cloud_nat        = var.validation_vm_enable_cloud_nat

  atlas_project_id        = module.atlas_project.id
  atlas_connection_string = local.validation_vm_connection_string

  depends_on = [module.atlas_gcp]
}
