locals {
  # Match the first region's Atlas endpoint association by forwarding rule ID.
  # GCP private endpoint SRV hostnames do not reliably contain a region token.
  validation_vm_endpoint_service_id = try(
    module.atlas_gcp.privatelink[local.validation_vm_region].atlas_endpoint_service_name,
    [
      for endpoint in values(module.atlas_gcp.privatelink) :
      endpoint.atlas_endpoint_service_name
      if lookup(var.atlas_to_gcp_region, endpoint.region, endpoint.region) == local.validation_vm_region
    ][0],
    null
  )

  validation_vm_private_endpoints = coalesce(
    try(module.atlas_cluster.connection_strings.private_endpoint, null),
    []
  )

  validation_vm_connection_strings = [
    for private_endpoint in local.validation_vm_private_endpoints :
    private_endpoint.srv_connection_string
    if try(
      contains(
        [for endpoint in private_endpoint.endpoints : endpoint.endpoint_id],
        local.validation_vm_endpoint_service_id
      ),
      false
    )
  ]

  validation_vm_connection_string = try(
    local.validation_vm_connection_strings[0],
    null
  )

  connection_string = coalesce(
    local.validation_vm_connection_string,
    try(module.atlas_cluster.connection_strings.private_srv, ""),
    module.atlas_cluster.connection_strings.standard_srv
  )
}

module "validation_vm" {
  source = "../modules/validation-vm"
  count  = var.enable_validation_vm ? 1 : 0

  gcp_project_id = var.gcp_project_id
  subnetwork     = local.validation_vm_subnetwork
  zone           = var.validation_vm_zone
  machine_type   = var.validation_vm_machine_type

  create_iap_ssh_firewall = var.validation_vm_create_iap_ssh_firewall
  enable_cloud_nat        = var.validation_vm_enable_cloud_nat

  atlas_project_id        = module.atlas_project.id
  atlas_connection_string = local.validation_vm_connection_string
}
