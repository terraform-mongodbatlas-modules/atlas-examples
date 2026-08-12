terraform {
  required_version = ">= 1.10"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.15"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  provider_meta "mongodbatlas" {
    user_agent_extra = {
      example = "aws-fastapi-minimal"
    }
  }
}

provider "mongodbatlas" {}
