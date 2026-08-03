variable "gcp_project_id" {
  description = "GCP project ID for the provider"
  type        = string
}

variable "name_suffix" {
  description = "Unique suffix for resource names (e.g. the GitHub run ID)"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the subnetwork"
  type        = string
  default     = "us-east4"
}
