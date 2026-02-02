# Required variables
# ----------------------------------------------------
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
}

variable "location" {
  description = "Azure region for the VM"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the VM will be deployed. Must be in the same VNet as Atlas Private Endpoint."
  type        = string
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM access. Optional - password auth is always enabled for Serial Console."
  type        = string
  default     = null
}

variable "atlas_project_id" {
  description = "MongoDB Atlas Project ID. Used to create temporary database user."
  type        = string
}

variable "atlas_connection_string" {
  description = "MongoDB Atlas private endpoint SRV connection string. For sharded clusters, use private_endpoint[0].srv_connection_string. Example: mongodb+srv://cluster-pl-0.xxxxx.mongodb.net"
  type        = string
}


# Optional variables
# ----------------------------------------------------
variable "name_prefix" {
  description = "Prefix for resource names. If empty, uses 'atlas-validation-vm'."
  type        = string
  default     = ""
}

variable "vm_size" {
  description = "Azure VM size. B1s is cost-effective for validation."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
