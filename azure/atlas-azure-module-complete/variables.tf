# Required variables
# ----------------------------------------------------
variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "atlas_project_name" {
  description = "Name for the Atlas project"
  type        = string
}

variable "atlas_cluster_name" {
  description = "Name for the Atlas cluster"
  type        = string
}

variable "azure_resource_group_name" {
  description = "Azure Resource Group where Azure resources (Private Endpoints, Backup, Validation VM) are created."
  type        = string
}

variable "regions" {
  description = <<-EOT
    Region configurations with Azure networking for PrivateLink.
    Used to place Atlas nodes and wire Private Endpoint networking. The first
    region in the list is also used for deploying the validation VM and creating backup storage.
    
    Attributes:
    - name: Atlas region name (e.g., "US_EAST_2") for cluster placement.
    - subnet_id: Azure subnet ID where Private Endpoint networking is created.
      The validation VM is deployed in the first region's subnet.
    - azure_location: Azure region name (e.g., "eastus2") used for Azure
      resources such as Private Endpoints and backup storage (first region only).
    - node_count (optional): Overrides per-region node count when set.
    
    Example:
      regions = [
        {
          name           = "US_EAST_2"
          subnet_id      = "/subscriptions/.../subnets/atlas-pe-subnet"
          azure_location = "eastus2"
        },
        {
          name           = "US_WEST_2"
          subnet_id      = "/subscriptions/.../subnets/atlas-pe-subnet"
          azure_location = "westus2"
        }
      ]
  EOT
  type = list(object({
    name           = string
    subnet_id      = string
    azure_location = optional(string)
    node_count     = optional(number)
  }))

  validation {
    condition     = try(trimspace(var.regions[0].azure_location), "") != ""
    error_message = "The first region must include azure_location (used for backup storage and validation VM deployment)."
  }
}


# Optional variables
# ----------------------------------------------------
variable "azure_subscription_id" {
  description = "Azure Subscription ID. Used for PrivateLink and Backup Export to Azure Storage (uses the underlying subscription when null)."
  type        = string
  default     = null # allows to use underlying subscription
}

variable "tags" {
  description = "Tags applied to all Atlas resources"
  type        = map(string)
  default     = {}
}

variable "ip_access_list" {
  description = <<-EOT
    Optional IP access list entries for Atlas.
    By default, no public IP access is allowed (PrivateLink only).
    Private IP whitelisting is not necessary, shown for example purposes only
  EOT

  type = list(object({
    source  = string
    comment = optional(string)
  }))

  default = []
}

# Validation VM
# ----------------------------------------------------
variable "enable_validation_vm" {
  description = "Deploy a validation VM to test Atlas deployment over PrivateLink"
  type        = bool
  default     = true
}

variable "validation_vm_ssh_key" {
  description = <<-EOT
    SSH public key for validation VM access.
    
    - If provided: Creates Azure Bastion (Standard) for SSH access
    - If empty/null (default): Uses Serial Console with password authentication
    
    Serial Console (default) requires no additional Azure resources and works
    through the Azure Portal. Bastion requires a public IP and the Standard SKU
    for native SSH client support.
  EOT
  type        = string
  default     = null
}
