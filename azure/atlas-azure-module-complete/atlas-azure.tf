module "atlas_azure" {
  # update to use source version once CLOUDP-365414 is done:
  source     = "terraform-mongodbatlas-modules/atlas-azure/mongodbatlas"
  version    = "~> 0.1.0"
  project_id = module.atlas_project.id

  # ---------------------------------------------------------------------------
  # Service Principal (BYO)
  # ---------------------------------------------------------------------------
  # To use an existing Azure Service Principal instead of letting the module create one:
  # Replace:
  #   create_service_principal = true
  #
  # With:
  #   create_service_principal = false
  #   service_principal_id     = "<existing-service-principal-object-id>"
  #
  # The service_principal_id must be the Azure AD Object ID.
  create_service_principal = true

  # ---------------------------------------------------------------------------
  # PrivateLink (BYO Private Endpoint)
  # ---------------------------------------------------------------------------
  # By default, this example lets the module create Azure Private Endpoints.
  #
  # To use existing Private Endpoints instead:
  #
  # Replace:
  #   privatelink_endpoints = local.privatelink_endpoints
  #
  # With:
  #   privatelink_byoe_locations = {
  #     eastus2 = "eastus2"
  #   }
  #
  #   privatelink_byoe = {
  #     eastus2 = {
  #       azure_private_endpoint_id         = "<existing-private-endpoint-id>"
  #       azure_private_endpoint_ip_address = "<private-ip>"
  #     }
  #   }
  #
  # NOTE:
  # - Use module.atlas_azure.privatelink_service_info outputs
  #   to connect your Private Endpoint to Atlas.
  privatelink_endpoints = local.privatelink_endpoints

  # ----------------------------------------------------------------------------------
  # BYO STORAGE ACCOUNT + CONTAINER
  # ----------------------------------------------------------------------------------
  # If your organization already has an approved Storage Account and container:
  #
  # Replace the `create_storage_account` block with:
  #
  # backup_export = {
  #   enabled            = true
  #   container_name     = "existing-container-name"
  #   storage_account_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<name>"
  #   create_container   = false
  # }
  #
  # Notes:
  # - `storage_account_id` must be the full Azure resource ID
  # - Set `create_container = true` only if the container does NOT exist
  # ----------------------------------------------------------------------------------
  backup_export = {
    enabled        = true
    container_name = "atlas-backups"

    create_storage_account = {
      enabled             = true
      name                = local.storage_account_name
      resource_group_name = var.azure_resource_group_name
      azure_location      = local.backup_azure_location
    }
  }

  depends_on = [module.atlas_project]
}
