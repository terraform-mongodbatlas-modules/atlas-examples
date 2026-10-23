terraform {
  required_version = ">= 1.9"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.11"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


provider "mongodbatlas" {}

provider "aws" {
  region = var.aws_region

  # Cloud Tag Policy tags for every AWS resource in this configuration, including the
  # ones the atlas-aws module and the validation VM module create.
  default_tags {
    tags = var.tags
  }
}
