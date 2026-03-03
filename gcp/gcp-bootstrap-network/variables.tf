variable "gcp_project_id" {
  type        = string
  description = "GCP project ID where network resources are created."
}

variable "network_name" {
  type        = string
  default     = "atlas-vpc"
  description = "Name for the VPC network"
}

variable "service_account_email" {
  type        = string
  description = "Service account email to impersonate"
}
