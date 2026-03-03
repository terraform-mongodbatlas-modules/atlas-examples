terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

# Provider without default project - each resource specifies project explicitly
provider "google" {
  project                     = var.gcp_project_id
  impersonate_service_account = var.service_account_email
}
