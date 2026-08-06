variable "gcp_project_id" {
  description = "GCP project ID for the provider"
  type        = string
}

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

variable "regions" {
  description = <<-EOT
    Region configurations with GCP networking for PrivateLink (PSC).
    The VPC network is derived from the subnetwork — no separate network input needed.

    - name: Region name in Atlas (e.g., "US_EAST_4") or GCP (e.g., "us-east4") format.
      Normalized to Atlas format for the cluster; the atlas-gcp module accepts either.
    - subnetwork: Subnetwork self_link for PSC endpoint placement
      (e.g., google_compute_subnetwork.atlas_psc.self_link).
    - node_count (optional): Override per-region electable node count.

    Example:
      regions = [
        {
          name       = "US_EAST_4"
          subnetwork = google_compute_subnetwork.atlas_psc.self_link
        }
      ]
  EOT

  type = list(object({
    name       = string
    subnetwork = string
    node_count = optional(number)
  }))

  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one region is required."
  }
}

variable "tags" {
  description = "Tags applied to Atlas resources and as labels to GCP resources"
  type        = map(string)
  default     = {}
}

variable "ip_access_list" {
  description = <<-EOT
    Optional IP access list entries for Atlas.
    By default, no public IP access is allowed (PrivateLink only).
    Private IP whitelisting is not necessary, shown for example purposes only.
  EOT

  type = list(object({
    source  = string
    comment = optional(string)
  }))

  default = []
}

variable "backup_export_force_destroy" {
  type        = bool
  description = "Force destroy the backup export bucket even when it contains exported snapshots. Disabled by default (safe); enable only for ephemeral/test deployments where cleanup matters more than retaining exports."
  default     = false
}

variable "service_account_email" {
  type        = string
  description = "Service account email to impersonate"
  default     = null
}

# Validation VM
# ----------------------------------------------------
variable "enable_validation_vm" {
  description = "Deploy a private validation VM and temporary Atlas database user."
  type        = bool
  default     = true
}

variable "validation_vm_zone" {
  description = "GCP zone for the validation VM. When null, the first sorted available zone in the first subnet's region is selected."
  type        = string
  default     = null
}

variable "validation_vm_machine_type" {
  description = "Compute Engine machine type for the validation VM."
  type        = string
  default     = "e2-micro"
}

variable "validation_vm_create_iap_ssh_firewall" {
  description = "Create a VM-targeted firewall rule that permits SSH only from the IAP TCP forwarding range."
  type        = bool
  default     = true
}

variable "validation_vm_enable_cloud_nat" {
  description = "Create a dedicated Cloud Router and subnet-scoped Cloud NAT for validation VM package installation. Enable this when the subnet has no existing outbound internet access."
  type        = bool
  default     = false
}
