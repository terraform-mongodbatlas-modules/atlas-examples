terraform {
  required_version = ">= 1.9"

  required_providers {
    mongodbatlas = {
      source = "mongodb/mongodbatlas"
    }
    google = {
      source = "hashicorp/google"
    }
  }
}

variable "gcp_project_id" {
  type = string
}

variable "atlas_org_id" {
  type = string
}

variable "atlas_project_name" {
  type = string
}

variable "atlas_cluster_name" {
  type = string
}

variable "enable_validation_vm" {
  type = bool
}

variable "regions" {
  type = any
}

resource "terraform_data" "subnetwork" {
  input = "https://www.googleapis.com/compute/v1/projects/test-project/regions/us-east4/subnetworks/default"
}

module "complete" {
  source = "../../.."

  gcp_project_id     = var.gcp_project_id
  atlas_org_id       = var.atlas_org_id
  atlas_project_name = var.atlas_project_name
  atlas_cluster_name = var.atlas_cluster_name

  regions = [
    {
      name       = "us-east4"
      subnetwork = terraform_data.subnetwork.output
    }
  ]

  enable_validation_vm           = var.enable_validation_vm
  validation_vm_enable_cloud_nat = true
}
