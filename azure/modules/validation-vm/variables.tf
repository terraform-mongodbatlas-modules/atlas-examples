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
  description = <<-EOT
    SSH public key for VM access via Azure Bastion.
    
    When provided (non-empty): Creates Azure Bastion with SSH key authentication.
    When empty/null (default): Uses Serial Console with password authentication.
  EOT
  type        = string
  default     = ""
}

variable "atlas_project_id" {
  description = "MongoDB Atlas Project ID. Used to create temporary database user."
  type        = string
}

variable "atlas_connection_string" {
  description = <<-EOT
    MongoDB Atlas private endpoint connection string. Supports both formats:
    
    - SRV format: mongodb+srv://<host> (with or without credentials)
    - Standard format: mongodb://<host1>:<port>,<host2>:<port>,<host3>:<port>/?replicaSet=...
    
    The validation scripts will enumerate all hosts (via SRV lookup or comma-split)
    and verify each resolves to a private IP address.
  EOT
  type        = string
}

variable "bastion_subnet_cidr" {
  description = "CIDR range for the Azure Bastion subnet (must be /26 or larger)."
  type        = string
  default     = "10.0.255.0/26"
}
