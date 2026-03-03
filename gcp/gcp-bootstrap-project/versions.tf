terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

# Provider without default project - each resource specifies project explicitly
provider "google" {
  # project is set per-resource via local.project_id
}
