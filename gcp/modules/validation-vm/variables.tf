variable "gcp_project_id" {
  description = "GCP project ID where the validation VM is created."
  type        = string
}

variable "subnetwork" {
  description = "Self-link of the subnet where the private validation VM is created."
  type        = string
}

variable "atlas_project_id" {
  description = "MongoDB Atlas project ID used to create the temporary database user."
  type        = string
}

variable "atlas_connection_string" {
  description = "MongoDB Atlas private endpoint SRV connection string."
  type        = string
  nullable    = true
}

variable "zone" {
  description = "GCP zone for the VM. When null, the first available zone in the subnet region is selected."
  type        = string
  default     = null
}

variable "machine_type" {
  description = "Compute Engine machine type for the validation VM."
  type        = string
  default     = "e2-micro"
}

variable "create_iap_ssh_firewall" {
  description = "Create a VM-targeted firewall rule that permits SSH only from the IAP TCP forwarding range."
  type        = bool
  default     = true
}

variable "enable_cloud_nat" {
  description = "Create a dedicated Cloud Router and subnet-scoped Cloud NAT for validation VM package installation. Enable this when the subnet has no existing outbound internet access."
  type        = bool
  default     = false
}
