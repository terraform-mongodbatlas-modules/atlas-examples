terraform {
  required_version = ">= 1.9"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.7"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "mongodbatlas" {}

provider "google" {
  project                     = var.gcp_project_id
  impersonate_service_account = var.service_account_email
}
