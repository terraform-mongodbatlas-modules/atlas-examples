variable "gcp_project_id" {
  type        = string
  description = "Existing GCP project ID. If empty, a new project will be created."
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
