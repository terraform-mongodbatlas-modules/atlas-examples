terraform {
  required_version = ">= 1.9"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = ">= 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.53"
    }
  }
}

provider "mongodbatlas" {}

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {}
}

provider "azuread" {}
