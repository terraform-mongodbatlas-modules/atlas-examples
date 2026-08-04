terraform {
  required_version = ">= 1.10"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.15"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  provider_meta "mongodbatlas" {
    user_agent_extra = {
      example = "aws-fastapi-minimal"
    }
  }
}

provider "mongodbatlas" {}

provider "aws" {
  region = local.aws_region

  default_tags {
    tags = var.tags
  }
}
