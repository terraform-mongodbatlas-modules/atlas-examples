terraform {
  required_version = ">= 1.9"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.16"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  provider_meta "mongodbatlas" {
    user_agent_extra = {
      example = "aws-hybridrag-ui"
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
