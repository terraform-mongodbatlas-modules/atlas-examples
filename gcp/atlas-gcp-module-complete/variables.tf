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
  description = "Force destroy the backup export bucket. This is set to true for the example to make cleanup easier, but in production you should set this to false."
  default     = true
}

variable "service_account_email" {
  type        = string
  description = "Service account email to impersonate"
  default     = null
}
